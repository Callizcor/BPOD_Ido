function FreeLicking_DynamicITI
% FREE LICKING PROTOCOL WITH DYNAMIC INTER-TRIAL INTERVALS
% Mice self-initiate trials by licking either port. Protocol delivers water
% rewards during 5-second response period, then requires 2-second delay
% without licking. Incorrect licks during delay reset the timer.
%
% Hardware:
%   - Lick ports: Port1Out/Port2Out (circuit closing)
%   - Valves: Valve1/Valve2 (string names)
%   - BNC1: 250Hz camera sync (2ms HIGH/2ms LOW)
%   - BNC2: 20-bit trial sync bitcode
%   - Zaber motors: Serial port COM18/COM6/COM11

global BpodSystem

%% Initialize Bpod System
MaxTrials = 1000; % Maximum number of trials

%% Task Parameters
S = BpodSystem.ProtocolSettings; % Load settings from GUI

if isempty(fieldnames(S))
    % Initialize default parameters if settings not loaded
    S.GUI.ResponseDuration = 5;        % Response period duration (seconds)
    S.GUI.DelayDuration = 2;           % Required delay without licking (seconds)
    S.GUI.BurstIgnoreDuration = 0.5;   % Duration to ignore licks after incorrect lick (seconds)
    S.GUI.DebounceDuration = 0.05;     % Debounce duration (seconds)
    S.GUI.RewardSize = 0.01;           % Valve duration for reward (seconds)
    S.GUI.InitRewardSize = 0.05;       % Initial water delivery (seconds)
    S.GUI.InitWaitDuration = 0.5;      % Wait after initial water (seconds)
    S.GUI.TrialTimeout = 3600;         % Ready state timeout (seconds)

    % Camera sync parameters
    S.GUI.CameraSyncEnabled = 1;       % Enable camera sync
    S.GUI.CameraPulseWidth = 0.002;    % 2ms HIGH pulse (250Hz = 4ms period)

    % Bitcode parameters
    S.GUI.BitcodeEnabled = 1;          % Enable trial sync bitcode

    % Zaber motor parameters
    S.GUI.ZaberEnabled = 0;            % Enable Zaber motors (set to 1 if available)
    S.GUI.ZaberPort = 'COM18';         % Serial port (COM18/COM6/COM11)
    S.GUI.ZaberMotorZ = 1;             % Z-axis motor number
    S.GUI.ZaberMotorLx = 3;            % Lx-axis motor number
    S.GUI.ZaberMotorLy = 2;            % Ly-axis motor number
    S.GUI.ZaberZ_Center = 210000;      % Z position for licking (microsteps)
    S.GUI.ZaberZ_Retract = 60000;      % Z position retracted (microsteps)
    S.GUI.ZaberLx_Center = 310000;     % Lx center position
    S.GUI.ZaberLy_Center = 310000;     % Ly center position
end

% Display parameters in GUI
BpodParameterGUI('init', S);

%% Initialize Data Storage
BpodSystem.Data.TrialTypes = [];
BpodSystem.Data.SelectedPort = [];
BpodSystem.Data.ResponseLickCount = [];
BpodSystem.Data.IncorrectLickBursts = [];
BpodSystem.Data.DelayTimerResets = [];
BpodSystem.Data.TrialStartTime = [];
BpodSystem.Data.TrialEndTime = [];
BpodSystem.Data.TrialRewardSize = [];
BpodSystem.Data.MotorPositions = [];
BpodSystem.Data.Bitcode = {};
BpodSystem.Data.Outcomes = []; % 1=correct, 0=error, -1=ignore

%% Initialize Zaber Motors (if enabled)
if S.GUI.ZaberEnabled
    try
        % Initialize Zaber controller
        global ZaberController;
        ZaberController = ZaberTCD1000(S.GUI.ZaberPort);

        % Move to center positions
        ZaberController.move(S.GUI.ZaberMotorZ, S.GUI.ZaberZ_Center);
        ZaberController.move(S.GUI.ZaberMotorLx, S.GUI.ZaberLx_Center);
        ZaberController.move(S.GUI.ZaberMotorLy, S.GUI.ZaberLy_Center);

        disp('Zaber motors initialized and moved to center positions');
    catch ME
        warning('Failed to initialize Zaber motors: %s', ME.message);
        S.GUI.ZaberEnabled = 0;
    end
end

%% Session Initialization - Deliver water to both ports
disp('=== SESSION INITIALIZATION ===');
disp('Delivering initial water rewards to both ports...');

% Port 1 initialization
sma = NewStateMachine();
sma = AddState(sma, 'Name', 'DeliverWater1', ...
    'Timer', S.GUI.InitRewardSize, ...
    'StateChangeConditions', {'Tup', 'WaitPeriod1'}, ...
    'OutputActions', {'Valve1', 1});
sma = AddState(sma, 'Name', 'WaitPeriod1', ...
    'Timer', S.GUI.InitWaitDuration, ...
    'StateChangeConditions', {'Tup', 'exit'}, ...
    'OutputActions', {});
SendStateMachine(sma);
RawEvents = RunStateMachine();

% Port 2 initialization
sma = NewStateMachine();
sma = AddState(sma, 'Name', 'DeliverWater2', ...
    'Timer', S.GUI.InitRewardSize, ...
    'StateChangeConditions', {'Tup', 'WaitPeriod2'}, ...
    'OutputActions', {'Valve2', 1});
sma = AddState(sma, 'Name', 'WaitPeriod2', ...
    'Timer', S.GUI.InitWaitDuration, ...
    'StateChangeConditions', {'Tup', 'exit'}, ...
    'OutputActions', {});
SendStateMachine(sma);
RawEvents = RunStateMachine();

disp('Session initialization complete. Ready for trials.');

%% Main Trial Loop
for currentTrial = 1:MaxTrials

    S = BpodParameterGUI('sync', S); % Sync parameters with GUI

    % Generate trial-specific parameters
    TrialStartTime = now();
    BpodSystem.Data.TrialStartTime(currentTrial) = TrialStartTime;
    BpodSystem.Data.TrialRewardSize(currentTrial) = S.GUI.RewardSize;

    % Generate 20-bit random bitcode (0 to 1,048,575)
    if S.GUI.BitcodeEnabled
        bitcodeValue = randi([0, 2^20-1]);
        bitcodeString = dec2bin(bitcodeValue, 20);
        BpodSystem.Data.Bitcode{currentTrial} = bitcodeString;
    else
        BpodSystem.Data.Bitcode{currentTrial} = '';
    end

    % Store motor positions
    if S.GUI.ZaberEnabled
        BpodSystem.Data.MotorPositions(currentTrial, :) = [...
            S.GUI.ZaberZ_Center, S.GUI.ZaberLx_Center, S.GUI.ZaberLy_Center];
    else
        BpodSystem.Data.MotorPositions(currentTrial, :) = [0, 0, 0];
    end

    %% Build State Machine
    sma = NewStateMachine();

    % Configure GlobalTimer for camera sync (250Hz continuous)
    if S.GUI.CameraSyncEnabled
        sma = SetGlobalTimer(sma, 'TimerID', 1, ...
            'Duration', S.GUI.CameraPulseWidth, ...  % 2ms HIGH
            'OnsetDelay', 0, ...
            'Channel', 'BNC1', ...
            'OnLevel', 1, ...
            'OffLevel', 0, ...
            'Loop', 1, ...  % Continuous loop
            'SendGlobalTimerEvents', 0, ...
            'LoopInterval', S.GUI.CameraPulseWidth);  % 2ms LOW (total 4ms = 250Hz)
    end

    % ===== READY STATE: Wait for first lick =====
    if S.GUI.CameraSyncEnabled
        sma = AddState(sma, 'Name', 'ReadyForLick', ...
            'Timer', S.GUI.TrialTimeout, ...
            'StateChangeConditions', {'Port1Out', 'ResponsePort1', 'Port2Out', 'ResponsePort2', 'Tup', 'IgnoreTrial'}, ...
            'OutputActions', {'GlobalTimerTrig', 1});  % Start camera sync
    else
        sma = AddState(sma, 'Name', 'ReadyForLick', ...
            'Timer', S.GUI.TrialTimeout, ...
            'StateChangeConditions', {'Port1Out', 'ResponsePort1', 'Port2Out', 'ResponsePort2', 'Tup', 'IgnoreTrial'}, ...
            'OutputActions', {});
    end

    % ===== RESPONSE PERIOD: Port 1 Selected =====
    sma = AddState(sma, 'Name', 'ResponsePort1', ...
        'Timer', S.GUI.ResponseDuration, ...
        'StateChangeConditions', {'Tup', 'DelayPeriod', 'Port1Out', 'RewardPort1'}, ...
        'OutputActions', {});

    % Reward delivery for Port 1 with debounce
    sma = AddState(sma, 'Name', 'RewardPort1', ...
        'Timer', S.GUI.RewardSize, ...
        'StateChangeConditions', {'Tup', 'DebouncePort1'}, ...
        'OutputActions', {'Valve1', 1});

    % Debounce after Port 1 reward
    sma = AddState(sma, 'Name', 'DebouncePort1', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort1'}, ...
        'OutputActions', {});

    % ===== RESPONSE PERIOD: Port 2 Selected =====
    sma = AddState(sma, 'Name', 'ResponsePort2', ...
        'Timer', S.GUI.ResponseDuration, ...
        'StateChangeConditions', {'Tup', 'DelayPeriod', 'Port2Out', 'RewardPort2'}, ...
        'OutputActions', {});

    % Reward delivery for Port 2 with debounce
    sma = AddState(sma, 'Name', 'RewardPort2', ...
        'Timer', S.GUI.RewardSize, ...
        'StateChangeConditions', {'Tup', 'DebouncePort2'}, ...
        'OutputActions', {'Valve2', 1});

    % Debounce after Port 2 reward
    sma = AddState(sma, 'Name', 'DebouncePort2', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort2'}, ...
        'OutputActions', {});

    % ===== DELAY PERIOD: 2-second wait without licking =====
    sma = AddState(sma, 'Name', 'DelayPeriod', ...
        'Timer', S.GUI.DelayDuration, ...
        'StateChangeConditions', {'Tup', 'RewardConsumption', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Burst window: ignore licks for 0.5s then reset delay timer
    sma = AddState(sma, 'Name', 'BurstWindow', ...
        'Timer', S.GUI.BurstIgnoreDuration, ...
        'StateChangeConditions', {'Tup', 'DelayPeriod'}, ...  % Return to DelayPeriod (resets timer)
        'OutputActions', {});

    % ===== TERMINAL STATES =====
    % Successful trial completion
    if S.GUI.CameraSyncEnabled
        sma = AddState(sma, 'Name', 'RewardConsumption', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'exit'}, ...
            'OutputActions', {'GlobalTimerCancel', 1});  % Stop camera sync
    else
        sma = AddState(sma, 'Name', 'RewardConsumption', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'exit'}, ...
            'OutputActions', {});
    end

    % Trial ignored (timeout)
    if S.GUI.CameraSyncEnabled
        sma = AddState(sma, 'Name', 'IgnoreTrial', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'exit'}, ...
            'OutputActions', {'GlobalTimerCancel', 1});  % Stop camera sync
    else
        sma = AddState(sma, 'Name', 'IgnoreTrial', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'exit'}, ...
            'OutputActions', {});
    end

    %% Send State Machine and Run Trial
    SendStateMachine(sma);
    RawEvents = RunStateMachine();

    %% Process Trial Data
    if ~isempty(fieldnames(RawEvents))
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;

        % Calculate trial outcome
        [outcome, selectedPort, responseLicks, burstCount] = CalculateTrialOutcome(RawEvents, currentTrial);

        BpodSystem.Data.Outcomes(currentTrial) = outcome;
        BpodSystem.Data.SelectedPort(currentTrial) = selectedPort;
        BpodSystem.Data.ResponseLickCount(currentTrial) = responseLicks;
        BpodSystem.Data.IncorrectLickBursts(currentTrial) = burstCount;
        BpodSystem.Data.DelayTimerResets(currentTrial) = burstCount;
        BpodSystem.Data.TrialEndTime(currentTrial) = now();

        % Update online plots
        UpdateOnlinePlot(BpodSystem.Data, currentTrial);

        % Save data
        SaveBpodSessionData;

        % Display trial information
        fprintf('Trial %d: ', currentTrial);
        if outcome == 1
            fprintf('CORRECT | ');
        elseif outcome == 0
            fprintf('ERROR | ');
        else
            fprintf('IGNORE | ');
        end
        fprintf('Port %d | Rewards: %d | Bursts: %d\n', ...
            selectedPort, responseLicks, burstCount);
    end

    %% Handle Pause and Stop
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        break;
    end
end

%% Cleanup
if S.GUI.ZaberEnabled && exist('ZaberController', 'var')
    try
        % Retract motors
        ZaberController.move(S.GUI.ZaberMotorZ, S.GUI.ZaberZ_Retract);
        delete(ZaberController);
        clear global ZaberController;
        disp('Zaber motors retracted and connection closed');
    catch ME
        warning('Failed to cleanup Zaber motors: %s', ME.message);
    end
end

disp('Protocol completed successfully');

end % Main function


%% HELPER FUNCTIONS

function [outcome, selectedPort, responseLicks, burstCount] = CalculateTrialOutcome(RawEvents, currentTrial)
    % Calculate trial outcome based on terminal state
    % outcome: 1=correct, 0=error, -1=ignore

    % Determine which port was selected
    selectedPort = 0;
    if isfield(RawEvents.States, 'ResponsePort1') && ~isnan(RawEvents.States.ResponsePort1(1))
        selectedPort = 1;
    elseif isfield(RawEvents.States, 'ResponsePort2') && ~isnan(RawEvents.States.ResponsePort2(1))
        selectedPort = 2;
    end

    % Check terminal state for outcome
    if isfield(RawEvents.States, 'RewardConsumption') && ~isnan(RawEvents.States.RewardConsumption(1))
        outcome = 1; % Correct trial
    elseif isfield(RawEvents.States, 'IgnoreTrial') && ~isnan(RawEvents.States.IgnoreTrial(1))
        outcome = -1; % Ignored trial
    else
        outcome = 0; % Error trial
    end

    % Count response licks (rewards delivered)
    responseLicks = 0;
    if selectedPort == 1
        if isfield(RawEvents.States, 'RewardPort1')
            responseLicks = sum(~isnan(RawEvents.States.RewardPort1(:, 1)));
        end
    elseif selectedPort == 2
        if isfield(RawEvents.States, 'RewardPort2')
            responseLicks = sum(~isnan(RawEvents.States.RewardPort2(:, 1)));
        end
    end

    % Count burst windows (delay resets)
    burstCount = 0;
    if isfield(RawEvents.States, 'BurstWindow')
        burstCount = sum(~isnan(RawEvents.States.BurstWindow(:, 1)));
    end
end


function UpdateOnlinePlot(Data, currentTrial)
    % Update online visualization of trial outcomes

    global BpodSystem

    if currentTrial == 1
        % Initialize figure
        BpodSystem.ProtocolFigures.OutcomePlot = figure('Name', 'Trial Outcomes', 'NumberTitle', 'off');
    end

    figure(BpodSystem.ProtocolFigures.OutcomePlot);

    % Plot trial outcomes
    subplot(2,2,1);
    outcomes = Data.Outcomes(1:currentTrial);
    plot(1:currentTrial, outcomes, 'o-');
    xlabel('Trial Number');
    ylabel('Outcome');
    title('Trial Outcomes');
    ylim([-1.5 1.5]);
    yticks([-1 0 1]);
    yticklabels({'Ignore', 'Error', 'Correct'});
    grid on;

    % Plot port selection
    subplot(2,2,2);
    portSelection = Data.SelectedPort(1:currentTrial);
    histogram(portSelection, [0.5 1.5 2.5]);
    xlabel('Selected Port');
    ylabel('Count');
    title('Port Selection Distribution');
    xticks([1 2]);

    % Plot response licks
    subplot(2,2,3);
    responseLicks = Data.ResponseLickCount(1:currentTrial);
    plot(1:currentTrial, responseLicks, 'o-');
    xlabel('Trial Number');
    ylabel('Reward Count');
    title('Rewards per Trial');
    grid on;

    % Plot delay resets
    subplot(2,2,4);
    delayResets = Data.DelayTimerResets(1:currentTrial);
    plot(1:currentTrial, delayResets, 'o-');
    xlabel('Trial Number');
    ylabel('Reset Count');
    title('Delay Timer Resets per Trial');
    grid on;

    drawnow;
end


function SoftCodeHandler_PlayStimulus(code)
    % Handle soft codes for Zaber motor control
    global BpodSystem ZaberController

    S = BpodSystem.ProtocolSettings;

    if ~S.GUI.ZaberEnabled
        return;
    end

    try
        switch code
            case 1  % Move port IN (to lickable position)
                ZaberController.move(S.GUI.ZaberMotorZ, S.GUI.ZaberZ_Center);
            case 2  % Move port OUT (retracted)
                ZaberController.move(S.GUI.ZaberMotorZ, S.GUI.ZaberZ_Retract);
            otherwise
                warning('Unknown soft code: %d', code);
        end
    catch ME
        warning('Zaber motor control failed: %s', ME.message);
    end
end
