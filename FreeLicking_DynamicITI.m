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
    S.GUI.ZaberPort = 'COM6';          % Serial port (COM18/COM6/COM11)
    S.GUI.Z_motor_pos = 210000;        % Z position for licking (microsteps)
    S.GUI.Z_NonLickable = 60000;       % Z position retracted (microsteps)
    S.GUI.Lx_motor_pos = 310000;       % Lx center position
    S.GUI.Ly_motor_pos = 310000;       % Ly center position
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
global motors motors_properties

if S.GUI.ZaberEnabled
    try
        % Motor properties configuration
        motors_properties.PORT = S.GUI.ZaberPort;
        motors_properties.type = '@ZaberArseny';
        motors_properties.Z_motor_num = 2;   % COM6 setup
        motors_properties.Lx_motor_num = 1;  % COM6 setup
        motors_properties.Ly_motor_num = 4;  % COM6 setup

        % Set soft code handler for motor control
        BpodSystem.SoftCodeHandlerFunction = 'MySoftCodeHandler';

        % Open serial connection
        motors = ZaberTCD1000(motors_properties.PORT);
        serial_open(motors);

        % Setup manual motor control callbacks
        p = find(cellfun(@(x) strcmp(x,'Z_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
        if ~isempty(p)
            set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Z_Move});
            Z_Move(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String'));
        end

        p = find(cellfun(@(x) strcmp(x,'Lx_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
        if ~isempty(p)
            set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Lx_Move});
            Lx_Move(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String'));
        end

        p = find(cellfun(@(x) strcmp(x,'Ly_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
        if ~isempty(p)
            set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Ly_Move});
            Ly_Move(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String'));
        end

        disp('Zaber motors initialized and moved to center positions');
        disp('You can manually adjust motor positions via GUI parameters during trials');

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
            S.GUI.Z_motor_pos, S.GUI.Lx_motor_pos, S.GUI.Ly_motor_pos];
    else
        BpodSystem.Data.MotorPositions(currentTrial, :) = [0, 0, 0];
    end

    %% Build State Machine
    sma = NewStateMachine();

    % Configure GlobalTimer 1 for camera sync (250Hz continuous)
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

    % Configure GlobalTimer 2 for response period (5 seconds, one-shot)
    sma = SetGlobalTimer(sma, 'TimerID', 2, ...
        'Duration', S.GUI.ResponseDuration, ...
        'OnsetDelay', 0, ...
        'Channel', 'BNC2', ...
        'OnLevel', 0, ...  % Don't output on BNC2 (bitcode uses it)
        'OffLevel', 0, ...
        'Loop', 0, ...  % One-shot timer
        'SendGlobalTimerEvents', 1);  % Send GlobalTimer2_End event

    % ===== READY STATE: Wait for first lick =====
    if S.GUI.CameraSyncEnabled
        sma = AddState(sma, 'Name', 'ReadyForLick', ...
            'Timer', S.GUI.TrialTimeout, ...
            'StateChangeConditions', {'Port1Out', 'StartResponsePort1', 'Port2Out', 'StartResponsePort2', 'Tup', 'IgnoreTrial'}, ...
            'OutputActions', {'GlobalTimerTrig', 1});  % Start camera sync
    else
        sma = AddState(sma, 'Name', 'ReadyForLick', ...
            'Timer', S.GUI.TrialTimeout, ...
            'StateChangeConditions', {'Port1Out', 'StartResponsePort1', 'Port2Out', 'StartResponsePort2', 'Tup', 'IgnoreTrial'}, ...
            'OutputActions', {});
    end

    % ===== RESPONSE PERIOD: Port 1 Selected =====
    % Start response period and trigger GlobalTimer
    sma = AddState(sma, 'Name', 'StartResponsePort1', ...
        'Timer', 0, ...
        'StateChangeConditions', {'Tup', 'ResponsePort1'}, ...
        'OutputActions', {'GlobalTimerTrig', 2});  % Start response timer

    % Main response state - waits for GlobalTimer2_End or licks
    sma = AddState(sma, 'Name', 'ResponsePort1', ...
        'Timer', 1000, ...  % Safety timeout (won't be reached)
        'StateChangeConditions', {'GlobalTimer2_End', 'Delay_2_0s', 'Port1Out', 'RewardPort1'}, ...
        'OutputActions', {});

    % Reward delivery for Port 1
    sma = AddState(sma, 'Name', 'RewardPort1', ...
        'Timer', S.GUI.RewardSize, ...
        'StateChangeConditions', {'Tup', 'DebouncePort1'}, ...
        'OutputActions', {'Valve1', 1});

    % Debounce after Port 1 reward - returns to ResponsePort1
    sma = AddState(sma, 'Name', 'DebouncePort1', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort1', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {});

    % ===== RESPONSE PERIOD: Port 2 Selected =====
    % Start response period and trigger GlobalTimer
    sma = AddState(sma, 'Name', 'StartResponsePort2', ...
        'Timer', 0, ...
        'StateChangeConditions', {'Tup', 'ResponsePort2'}, ...
        'OutputActions', {'GlobalTimerTrig', 2});  % Start response timer

    % Main response state - waits for GlobalTimer2_End or licks
    sma = AddState(sma, 'Name', 'ResponsePort2', ...
        'Timer', 1000, ...  % Safety timeout (won't be reached)
        'StateChangeConditions', {'GlobalTimer2_End', 'Delay_2_0s', 'Port2Out', 'RewardPort2'}, ...
        'OutputActions', {});

    % Reward delivery for Port 2
    sma = AddState(sma, 'Name', 'RewardPort2', ...
        'Timer', S.GUI.RewardSize, ...
        'StateChangeConditions', {'Tup', 'DebouncePort2'}, ...
        'OutputActions', {'Valve2', 1});

    % Debounce after Port 2 reward - returns to ResponsePort2
    sma = AddState(sma, 'Name', 'DebouncePort2', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort2', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {});

    % ===== DELAY PERIOD: 2-second countdown (split into 0.5s segments for visibility) =====
    % Delay: 2.0s remaining
    sma = AddState(sma, 'Name', 'Delay_2_0s', ...
        'Timer', S.GUI.DelayDuration / 4, ...
        'StateChangeConditions', {'Tup', 'Delay_1_5s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Delay: 1.5s remaining
    sma = AddState(sma, 'Name', 'Delay_1_5s', ...
        'Timer', S.GUI.DelayDuration / 4, ...
        'StateChangeConditions', {'Tup', 'Delay_1_0s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Delay: 1.0s remaining
    sma = AddState(sma, 'Name', 'Delay_1_0s', ...
        'Timer', S.GUI.DelayDuration / 4, ...
        'StateChangeConditions', {'Tup', 'Delay_0_5s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Delay: 0.5s remaining - final segment
    sma = AddState(sma, 'Name', 'Delay_0_5s', ...
        'Timer', S.GUI.DelayDuration / 4, ...
        'StateChangeConditions', {'Tup', 'RewardConsumption', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Burst window: ignore licks for 0.5s then reset delay timer to beginning
    sma = AddState(sma, 'Name', 'BurstWindow', ...
        'Timer', S.GUI.BurstIgnoreDuration, ...
        'StateChangeConditions', {'Tup', 'Delay_2_0s'}, ...  % Return to start of delay (resets timer)
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

        % Display trial information with delay progress
        fprintf('Trial %d: ', currentTrial);
        if outcome == 1
            fprintf('CORRECT | ');
        elseif outcome == 0
            fprintf('ERROR | ');
        else
            fprintf('IGNORE | ');
        end
        fprintf('Port %d | Rewards: %d | Delay resets: %d', ...
            selectedPort, responseLicks, burstCount);

        % Show delay period progress
        if outcome == 1 && burstCount == 0
            fprintf(' | Delay: PERFECT (no licks)');
        elseif outcome == 1 && burstCount > 0
            fprintf(' | Delay: completed after %d reset(s)', burstCount);
        end
        fprintf('\n');
    end

    %% Handle Pause and Stop
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        break;
    end
end

%% Cleanup
global motors motors_properties

if S.GUI.ZaberEnabled && exist('motors', 'var') && ~isempty(motors)
    try
        % Retract motors
        Motor_Move(S.GUI.Z_NonLickable, motors_properties.Z_motor_num);

        % Close serial connection
        serial_close(motors);
        clear global motors motors_properties;
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

    % Check if States is a struct (sometimes it's just a number if no states entered)
    if currentTrial <= 3
        if isstruct(RawEvents.States)
            stateNames = fieldnames(RawEvents.States);
            fprintf('  DEBUG: States entered = %s\n', strjoin(stateNames, ', '));
        else
            fprintf('  DEBUG: States is not a struct! Type = %s, Value = %s\n', ...
                class(RawEvents.States), mat2str(RawEvents.States));
        end
    end

    % Determine which port was selected - check multiple possible states
    selectedPort = 0;

    % First, try to detect from StartResponse states
    if isstruct(RawEvents.States)
        if isfield(RawEvents.States, 'StartResponsePort1') && ~isnan(RawEvents.States.StartResponsePort1(1))
            selectedPort = 1;
        elseif isfield(RawEvents.States, 'StartResponsePort2') && ~isnan(RawEvents.States.StartResponsePort2(1))
            selectedPort = 2;
        end

        % Fallback: check ResponsePort states
        if selectedPort == 0
            if isfield(RawEvents.States, 'ResponsePort1') && ~isnan(RawEvents.States.ResponsePort1(1))
                selectedPort = 1;
            elseif isfield(RawEvents.States, 'ResponsePort2') && ~isnan(RawEvents.States.ResponsePort2(1))
                selectedPort = 2;
            end
        end
    end

    % Last resort: check from events (which port had licks)
    if selectedPort == 0 && isfield(RawEvents, 'Events')
        if isfield(RawEvents.Events, 'Port1Out') && ~isempty(RawEvents.Events.Port1Out)
            selectedPort = 1;
        elseif isfield(RawEvents.Events, 'Port2Out') && ~isempty(RawEvents.Events.Port2Out)
            selectedPort = 2;
        end
    end

    % Check terminal state for outcome
    outcome = 0; % Default to error
    if isstruct(RawEvents.States)
        if isfield(RawEvents.States, 'RewardConsumption') && ~isnan(RawEvents.States.RewardConsumption(1))
            outcome = 1; % Correct trial
        elseif isfield(RawEvents.States, 'IgnoreTrial') && ~isnan(RawEvents.States.IgnoreTrial(1))
            outcome = -1; % Ignored trial
        else
            % Debug output for first few trials
            if currentTrial <= 3
                fprintf('  DEBUG: No terminal state found. RewardConsumption exists: %d, IgnoreTrial exists: %d\n', ...
                    isfield(RawEvents.States, 'RewardConsumption'), ...
                    isfield(RawEvents.States, 'IgnoreTrial'));
            end
        end
    else
        if currentTrial <= 3
            fprintf('  DEBUG: States is not a struct - cannot check terminal states\n');
        end
    end

    % Count response licks (rewards delivered)
    responseLicks = 0;
    if isstruct(RawEvents.States)
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
    else
        burstCount = 0;
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


%% Motor movement helper functions

function manual_Z_Move(hObject, ~)
    global motors_properties;
    position = str2double(get(hObject, 'String'));
    Motor_Move(position, motors_properties.Z_motor_num);
end

function manual_Lx_Move(hObject, ~)
    global motors_properties;
    position = str2double(get(hObject, 'String'));
    Motor_Move(position, motors_properties.Lx_motor_num);
end

function manual_Ly_Move(hObject, ~)
    global motors_properties;
    position = str2double(get(hObject, 'String'));
    Motor_Move(position, motors_properties.Ly_motor_num);
end

function Z_Move(position)
    global motors_properties;
    if ischar(position) || isstring(position)
        position = str2double(position);
    end
    Motor_Move(position, motors_properties.Z_motor_num);
end

function Lx_Move(position)
    global motors_properties;
    if ischar(position) || isstring(position)
        position = str2double(position);
    end
    Motor_Move(position, motors_properties.Lx_motor_num);
end

function Ly_Move(position)
    global motors_properties;
    if ischar(position) || isstring(position)
        position = str2double(position);
    end
    Motor_Move(position, motors_properties.Ly_motor_num);
end
