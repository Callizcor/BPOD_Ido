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
BpodSystem.Data.TotalWaterDispensed = 0; % Track total water (mL)
BpodSystem.Data.LickHistory = []; % Store all licks with timestamps and states

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
            Motor_Move(str2double(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String')), motors_properties.Z_motor_num);
        end

        p = find(cellfun(@(x) strcmp(x,'Lx_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
        if ~isempty(p)
            set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Lx_Move});
            Motor_Move(str2double(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String')), motors_properties.Lx_motor_num);
        end

        p = find(cellfun(@(x) strcmp(x,'Ly_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
        if ~isempty(p)
            set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Ly_Move});
            Motor_Move(str2double(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String')), motors_properties.Ly_motor_num);
        end

        disp('Zaber motors initialized and moved to center positions');
        disp('You can manually adjust motor positions via GUI parameters during trials');

    catch ME
        warning('Failed to initialize Zaber motors: %s', ME.message);
        S.GUI.ZaberEnabled = 0;
    end
end

%% Nested motor movement functions (must be defined here to access motors_properties)
    function manual_Z_Move(hObject, ~)
        position = str2double(get(hObject, 'String'));
        Motor_Move(position, motors_properties.Z_motor_num);
    end

    function manual_Lx_Move(hObject, ~)
        position = str2double(get(hObject, 'String'));
        Motor_Move(position, motors_properties.Lx_motor_num);
    end

    function manual_Ly_Move(hObject, ~)
        position = str2double(get(hObject, 'String'));
        Motor_Move(position, motors_properties.Ly_motor_num);
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
BpodSystem.Data.TotalWaterDispensed = BpodSystem.Data.TotalWaterDispensed + S.GUI.InitRewardSize;

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
BpodSystem.Data.TotalWaterDispensed = BpodSystem.Data.TotalWaterDispensed + S.GUI.InitRewardSize;

fprintf('Session initialization complete. Initial water: %.3f mL\n', BpodSystem.Data.TotalWaterDispensed * 1000);

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
        'StateChangeConditions', {'Tup', 'DebouncePort1', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
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
        'StateChangeConditions', {'Tup', 'DebouncePort2', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
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

        % Calculate trial outcome and extract lick history
        [outcome, selectedPort, responseLicks, burstCount, lickHistory] = CalculateTrialOutcome(BpodSystem.Data.RawEvents.Trial{currentTrial}, currentTrial);

        BpodSystem.Data.Outcomes(currentTrial) = outcome;
        BpodSystem.Data.SelectedPort(currentTrial) = selectedPort;
        BpodSystem.Data.ResponseLickCount(currentTrial) = responseLicks;
        BpodSystem.Data.IncorrectLickBursts(currentTrial) = burstCount;
        BpodSystem.Data.DelayTimerResets(currentTrial) = burstCount;
        BpodSystem.Data.TrialEndTime(currentTrial) = now();

        % Update total water dispensed (rewards + initial water already counted)
        waterThisTrial = responseLicks * S.GUI.RewardSize;
        BpodSystem.Data.TotalWaterDispensed = BpodSystem.Data.TotalWaterDispensed + waterThisTrial;

        % Append lick history
        BpodSystem.Data.LickHistory = [BpodSystem.Data.LickHistory; lickHistory];

        % Update online plots
        UpdateOnlinePlot(BpodSystem.Data, currentTrial, S);

        % Save data
        SaveBpodSessionData;

        % Display trial information with delay progress and water
        fprintf('Trial %d: ', currentTrial);
        if outcome == 1
            fprintf('CORRECT | ');
        elseif outcome == 0
            fprintf('ERROR | ');
        else
            fprintf('IGNORE | ');
        end
        fprintf('Port %d | Rewards: %d | Delay resets: %d | Water: %.2f µL | Total: %.2f mL', ...
            selectedPort, responseLicks, burstCount, waterThisTrial * 1000000, BpodSystem.Data.TotalWaterDispensed * 1000);

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

function [outcome, selectedPort, responseLicks, burstCount, lickHistory] = CalculateTrialOutcome(RawEvents, currentTrial)
    % Calculate trial outcome based on terminal state
    % outcome: 1=correct, 0=error, -1=ignore
    % lickHistory: array with columns [timestamp, port, trialNum, stateNum, stateName]

    % Initialize lick history
    lickHistory = [];

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

    % Extract lick history (timestamp, port, trial, state)
    % Process all Port1Out and Port2Out events
    if isfield(RawEvents, 'Events')
        allLicks = [];

        % Collect Port 1 licks
        if isfield(RawEvents.Events, 'Port1Out') && ~isempty(RawEvents.Events.Port1Out)
            port1Licks = RawEvents.Events.Port1Out(:);
            for i = 1:length(port1Licks)
                allLicks = [allLicks; port1Licks(i), 1]; % [timestamp, port]
            end
        end

        % Collect Port 2 licks
        if isfield(RawEvents.Events, 'Port2Out') && ~isempty(RawEvents.Events.Port2Out)
            port2Licks = RawEvents.Events.Port2Out(:);
            for i = 1:length(port2Licks)
                allLicks = [allLicks; port2Licks(i), 2]; % [timestamp, port]
            end
        end

        % Sort licks by timestamp
        if ~isempty(allLicks)
            [~, sortIdx] = sort(allLicks(:, 1));
            allLicks = allLicks(sortIdx, :);

            % Determine state for each lick
            if isstruct(RawEvents.States)
                stateNames = fieldnames(RawEvents.States);
                for lickIdx = 1:size(allLicks, 1)
                    lickTime = allLicks(lickIdx, 1);
                    portNum = allLicks(lickIdx, 2);

                    % Find which state the lick occurred in
                    currentStateName = 'Unknown';
                    for stateIdx = 1:length(stateNames)
                        stateName = stateNames{stateIdx};
                        stateTimes = RawEvents.States.(stateName);

                        % Check each entry of this state
                        for entryIdx = 1:size(stateTimes, 1)
                            if ~isnan(stateTimes(entryIdx, 1)) && ~isnan(stateTimes(entryIdx, 2))
                                stateStart = stateTimes(entryIdx, 1);
                                stateEnd = stateTimes(entryIdx, 2);

                                if lickTime >= stateStart && lickTime <= stateEnd
                                    currentStateName = stateName;
                                    break;
                                end
                            end
                        end

                        if ~strcmp(currentStateName, 'Unknown')
                            break;
                        end
                    end

                    % Add to lick history: [timestamp, port, trial, stateName]
                    % Store as a cell array row: {timestamp, port, trial, stateName}
                    lickHistory = [lickHistory; {lickTime, portNum, currentTrial, currentStateName}];
                end
            end
        end
    end
end


function UpdateOnlinePlot(Data, currentTrial, S)
    % Update online visualization of trial outcomes and lick history

    global BpodSystem

    if currentTrial == 1
        % Initialize figure with larger size for additional plots
        BpodSystem.ProtocolFigures.OutcomePlot = figure('Name', 'Session Monitor', ...
            'NumberTitle', 'off', 'Position', [100 100 1400 900]);
    end

    figure(BpodSystem.ProtocolFigures.OutcomePlot);

    % Plot trial outcomes
    subplot(3,2,1);
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
    subplot(3,2,2);
    portSelection = Data.SelectedPort(1:currentTrial);
    histogram(portSelection, [0.5 1.5 2.5]);
    xlabel('Selected Port');
    ylabel('Count');
    title('Port Selection Distribution');
    xticks([1 2]);

    % Plot response licks
    subplot(3,2,3);
    responseLicks = Data.ResponseLickCount(1:currentTrial);
    plot(1:currentTrial, responseLicks, 'o-');
    xlabel('Trial Number');
    ylabel('Reward Count');
    title('Rewards per Trial');
    grid on;

    % Plot delay resets
    subplot(3,2,4);
    delayResets = Data.DelayTimerResets(1:currentTrial);
    plot(1:currentTrial, delayResets, 'o-');
    xlabel('Trial Number');
    ylabel('Reset Count');
    title('Delay Timer Resets per Trial');
    grid on;

    % Plot total water consumption over time
    subplot(3,2,5);
    totalWater_mL = Data.TotalWaterDispensed * 1000; % Convert to mL
    bar(1, totalWater_mL, 'FaceColor', [0.2 0.6 0.8]);
    ylabel('Water (mL)');
    title(sprintf('Total Water Dispensed: %.2f mL', totalWater_mL));
    xlim([0.5 1.5]);
    set(gca, 'XTick', []);
    grid on;

    % Plot lick burst history (last 20 seconds)
    subplot(3,2,6);
    cla; % Clear previous plot
    hold on;

    if ~isempty(Data.LickHistory)
        % Get current time (time of last lick or trial end)
        if iscell(Data.LickHistory)
            allTimes = cell2mat(Data.LickHistory(:, 1));
            currentTime = max(allTimes);
        else
            currentTime = 0;
        end

        % Define 20-second window
        timeWindow = 20; % seconds
        windowStart = max(0, currentTime - timeWindow);

        % Filter licks in the time window
        if iscell(Data.LickHistory)
            lickTimes = cell2mat(Data.LickHistory(:, 1));
            lickPorts = cell2mat(Data.LickHistory(:, 2));
            lickStates = Data.LickHistory(:, 4);

            % Find licks in window
            inWindow = lickTimes >= windowStart;
            windowTimes = lickTimes(inWindow);
            windowPorts = lickPorts(inWindow);
            windowStates = lickStates(inWindow);

            % Plot licks
            for i = 1:length(windowTimes)
                relTime = windowTimes(i) - windowStart; % Time relative to window start
                port = windowPorts(i);
                state = windowStates{i};

                % Determine color based on state
                if contains(state, 'Response') || contains(state, 'Reward')
                    color = [0.2 0.8 0.2]; % Green for response/reward
                elseif contains(state, 'Delay')
                    color = [0.8 0.2 0.2]; % Red for delay (incorrect)
                elseif contains(state, 'Burst')
                    color = [0.8 0.5 0.2]; % Orange for burst window
                else
                    color = [0.5 0.5 0.5]; % Gray for other
                end

                % Plot as vertical line at different heights for different ports
                yPos = port; % Port 1 at y=1, Port 2 at y=2
                plot([relTime relTime], [yPos-0.3 yPos+0.3], 'LineWidth', 2, 'Color', color);

                % Add state label for first few licks (avoid clutter)
                if i <= 5
                    text(relTime, yPos+0.4, strrep(state, '_', '\_'), ...
                        'FontSize', 6, 'Rotation', 45, 'Interpreter', 'tex');
                end
            end
        end

        ylim([0.5 2.5]);
        yticks([1 2]);
        yticklabels({'Port 1', 'Port 2'});
    end

    xlim([0 timeWindow]);
    xlabel('Time (s, last 20s)');
    ylabel('Lick Port');
    title('Lick Burst History (20s window)');
    grid on;
    hold off;

    drawnow;
end
