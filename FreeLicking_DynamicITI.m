function FreeLicking_DynamicITI
% FREE LICKING PROTOCOL WITH BLOCK-BASED DYNAMIC PARAMETERS
% Mice self-initiate trials by licking either port. Protocol delivers water
% rewards during 5-second response period, then requires delay without licking.
% Incorrect licks during delay reset the timer based on block parameters.
%
% BLOCKS: Each block has configurable:
%   - Reward sizes (left/right ports can differ)
%   - Delay duration
%   - Error penalty (where to reset delay timer on lick)
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
    S.GUI.BurstIgnoreDuration = 0.5;   % Duration to ignore licks after incorrect lick (seconds)
    S.GUI.DebounceDuration = 0.05;     % Debounce duration (seconds)
    S.GUI.InitRewardSize = 0.05;       % Initial water delivery (seconds)
    S.GUI.InitWaitDuration = 0.5;      % Wait after initial water (seconds)
    S.GUI.TrialTimeout = 3600;         % Ready state timeout (seconds)

    % Block design parameters
    S.GUI.BlocksEnabled = 1;           % Enable block-based design (0=single block mode)
    S.GUI.BlockSize = 40;              % Trials per block
    S.GUI.NumBlocks = 10;              % Number of blocks to generate

    % Block 1 parameters (easy: short delay, small reset penalty, equal rewards)
    S.GUI.Block1_DelayDuration = 2.0;      % Delay time (s)
    S.GUI.Block1_ErrorResetSegment = 1;    % 1=full reset, 2=75%, 3=50%, 4=25%
    S.GUI.Block1_RewardLeft = 0.01;        % Left port reward size (s)
    S.GUI.Block1_RewardRight = 0.01;       % Right port reward size (s)

    % Block 2 parameters (medium: longer delay, partial reset, equal rewards)
    S.GUI.Block2_DelayDuration = 3.0;
    S.GUI.Block2_ErrorResetSegment = 2;    % Reset to 75% (milder penalty)
    S.GUI.Block2_RewardLeft = 0.015;
    S.GUI.Block2_RewardRight = 0.015;

    % Block 3 parameters (hard: long delay, full reset, asymmetric rewards)
    S.GUI.Block3_DelayDuration = 4.0;
    S.GUI.Block3_ErrorResetSegment = 1;    % Full reset
    S.GUI.Block3_RewardLeft = 0.02;        % Larger reward on left
    S.GUI.Block3_RewardRight = 0.01;       % Smaller reward on right

    % Camera sync parameters
    S.GUI.CameraSyncEnabled = 1;       % Enable camera sync
    S.GUI.CameraPulseWidth = 0.002;    % 2ms HIGH pulse (250Hz = 4ms period)

    % Bitcode parameters
    S.GUI.BitcodeEnabled = 1;          % Enable trial sync bitcode

    % Zaber motor parameters
    S.GUI.ZaberEnabled = 1;            % Enable Zaber motors (set to 0 to disable)
    S.GUI.ZaberPort = 'COM6';          % Serial port (COM18/COM6/COM11)
    S.GUI.Z_motor_pos = 210000;        % Z position for licking (microsteps)
    S.GUI.Z_NonLickable = 60000;       % Z position retracted (microsteps)
    S.GUI.Lx_motor_pos = 310000;       % Lx center position
    S.GUI.Ly_motor_pos = 310000;       % Ly center position

    % Organize GUI into panels
    S.GUIPanels.Timers = {'ResponseDuration', 'BurstIgnoreDuration', 'DebounceDuration', ...
                          'InitRewardSize', 'InitWaitDuration', 'TrialTimeout'};
    S.GUIPanels.BlockDesign = {'BlocksEnabled', 'BlockSize', 'NumBlocks', ...
                               'Block1_DelayDuration', 'Block1_ErrorResetSegment', 'Block1_RewardLeft', 'Block1_RewardRight', ...
                               'Block2_DelayDuration', 'Block2_ErrorResetSegment', 'Block2_RewardLeft', 'Block2_RewardRight', ...
                               'Block3_DelayDuration', 'Block3_ErrorResetSegment', 'Block3_RewardLeft', 'Block3_RewardRight'};
    S.GUIPanels.Motors = {'ZaberEnabled', 'Z_motor_pos', 'Z_NonLickable', 'Lx_motor_pos', 'Ly_motor_pos'};
    S.GUIPanels.Hardware = {'CameraSyncEnabled', 'CameraPulseWidth', 'BitcodeEnabled'};
end

% Display parameters in GUI
BpodParameterGUI('init', S);

%% Initialize Data Storage
BpodSystem.Data.TrialTypes = [];        % Port choice: 1=left, 2=right, 0=no choice
BpodSystem.Data.SelectedPort = [];      % Same as TrialTypes (for compatibility)
BpodSystem.Data.ResponseLickCount = [];
BpodSystem.Data.IncorrectLickBursts = [];
BpodSystem.Data.DelayTimerResets = [];
BpodSystem.Data.TrialStartTime = [];
BpodSystem.Data.TrialEndTime = [];
BpodSystem.Data.TrialRewardSize = [];   % Actual reward size delivered
BpodSystem.Data.MotorPositions = [];
BpodSystem.Data.Bitcode = {};
BpodSystem.Data.Outcomes = [];          % 1=correct, 0=error, -1=ignore

% Block-specific data
BpodSystem.Data.BlockNumber = [];       % Which block each trial belongs to
BpodSystem.Data.TrialInBlock = [];      % Trial number within block
BpodSystem.Data.BlockParams = [];       % Parameters for each block
BpodSystem.Data.BlockSequence = [];     % Sequence of block types

% Water tracking
BpodSystem.Data.TotalWaterDelivered = 0;  % Total water in uL (microliters)
BpodSystem.Data.WaterPerTrial = [];       % Water delivered per trial in uL

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

%% Pause protocol for motor adjustments
disp('==========================================================');
disp('PROTOCOL PAUSED - Adjust motors and settings as needed');
if S.GUI.ZaberEnabled
    disp('Motor Control GUI opened - adjust positions and click Move buttons');
else
    disp('WARNING: ZaberEnabled=0 - Motors are DISABLED');
    disp('Set ZaberEnabled=1 in GUI to enable motor control');
end
disp('Press PLAY button in Bpod console to begin session');
disp('==========================================================');

% Create separate Motor Control GUI
CreateMotorControlGUI(S);

BpodSystem.Status.Pause = 1;
HandlePauseCondition;
if BpodSystem.Status.BeingUsed == 0
    return;
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

% Track initial water (assuming 5uL per second valve open time)
initWater = 2 * S.GUI.InitRewardSize * 5000;  % 2 ports * time * 5uL/s = uL total
BpodSystem.Data.TotalWaterDelivered = initWater;
fprintf('Initial water delivered: %.1f uL (%.3fs per port)\n', initWater, S.GUI.InitRewardSize);

disp('Session initialization complete. Ready for trials.');

%% Generate Block Sequence
[BlockSequence, BlockParams] = GenerateBlockSequence(S);
BpodSystem.Data.BlockSequence = BlockSequence;
BpodSystem.Data.BlockParams = BlockParams;

disp('=== BLOCK SEQUENCE ===');
fprintf('Total blocks: %d\n', length(BlockSequence));
for i = 1:min(length(BlockSequence), 5)  % Show first 5 blocks
    bp = BlockParams(i);
    fprintf('Block %d (Type %d): Delay=%.1fs, ErrorReset=%d, Rewards=[%.3f, %.3f]s\n', ...
        i, BlockSequence(i), bp.DelayDuration, bp.ErrorResetSegment, ...
        bp.RewardLeft, bp.RewardRight);
end
if length(BlockSequence) > 5
    fprintf('... and %d more blocks\n', length(BlockSequence) - 5);
end

%% Main Trial Loop
for currentTrial = 1:MaxTrials

    S = BpodParameterGUI('sync', S); % Sync parameters with GUI

    % Determine current block and trial within block
    [currentBlock, trialInBlock] = GetCurrentBlock(currentTrial, S.GUI.BlockSize, length(BlockSequence));
    currentBlockParams = BlockParams(currentBlock);

    BpodSystem.Data.BlockNumber(currentTrial) = currentBlock;
    BpodSystem.Data.TrialInBlock(currentTrial) = trialInBlock;

    % Generate trial-specific parameters
    TrialStartTime = now();
    BpodSystem.Data.TrialStartTime(currentTrial) = TrialStartTime;

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

    % Reward delivery for Port 1 (LEFT) - uses block-specific reward size
    sma = AddState(sma, 'Name', 'RewardPort1', ...
        'Timer', currentBlockParams.RewardLeft, ...
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

    % Reward delivery for Port 2 (RIGHT) - uses block-specific reward size
    sma = AddState(sma, 'Name', 'RewardPort2', ...
        'Timer', currentBlockParams.RewardRight, ...
        'StateChangeConditions', {'Tup', 'DebouncePort2', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {'Valve2', 1});

    % Debounce after Port 2 reward - returns to ResponsePort2
    sma = AddState(sma, 'Name', 'DebouncePort2', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort2', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {});

    % ===== DELAY PERIOD: Block-specific delay (split into 4 segments for visibility) =====
    % Determine which state to reset to on error based on block parameters
    switch currentBlockParams.ErrorResetSegment
        case 1
            errorResetState = 'Delay_2_0s';  % Full reset to start (100%)
        case 2
            errorResetState = 'Delay_1_5s';  % Reset to 75%
        case 3
            errorResetState = 'Delay_1_0s';  % Reset to 50%
        case 4
            errorResetState = 'Delay_0_5s';  % Reset to 25%
        otherwise
            errorResetState = 'Delay_2_0s';  % Default to full reset
    end

    segmentDuration = currentBlockParams.DelayDuration / 4;

    % Delay: 100% remaining (start)
    sma = AddState(sma, 'Name', 'Delay_2_0s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'Delay_1_5s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Delay: 75% remaining
    sma = AddState(sma, 'Name', 'Delay_1_5s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'Delay_1_0s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Delay: 50% remaining
    sma = AddState(sma, 'Name', 'Delay_1_0s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'Delay_0_5s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Delay: 25% remaining - final segment
    sma = AddState(sma, 'Name', 'Delay_0_5s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'RewardConsumption', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    % Burst window: ignore licks then reset to block-specific delay state
    sma = AddState(sma, 'Name', 'BurstWindow', ...
        'Timer', S.GUI.BurstIgnoreDuration, ...
        'StateChangeConditions', {'Tup', errorResetState}, ...  % Block-specific reset
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

        % Calculate trial outcome - use converted data from BpodSystem.Data
        [outcome, selectedPort, responseLicks, burstCount] = CalculateTrialOutcome(BpodSystem.Data.RawEvents.Trial{currentTrial}, currentTrial);

        BpodSystem.Data.Outcomes(currentTrial) = outcome;
        BpodSystem.Data.SelectedPort(currentTrial) = selectedPort;
        BpodSystem.Data.TrialTypes(currentTrial) = selectedPort;  % Trial type = port choice
        BpodSystem.Data.ResponseLickCount(currentTrial) = responseLicks;
        BpodSystem.Data.IncorrectLickBursts(currentTrial) = burstCount;
        BpodSystem.Data.DelayTimerResets(currentTrial) = burstCount;
        BpodSystem.Data.TrialEndTime(currentTrial) = now();

        % Store actual reward size delivered
        if selectedPort == 1
            BpodSystem.Data.TrialRewardSize(currentTrial) = currentBlockParams.RewardLeft;
        elseif selectedPort == 2
            BpodSystem.Data.TrialRewardSize(currentTrial) = currentBlockParams.RewardRight;
        else
            BpodSystem.Data.TrialRewardSize(currentTrial) = 0;  % No port selected
        end

        % Calculate and track water delivered (assuming 5uL per second valve open time)
        % Total water = valve time * number of rewards * 5000 uL/s
        trialWater = BpodSystem.Data.TrialRewardSize(currentTrial) * responseLicks * 5000;
        BpodSystem.Data.WaterPerTrial(currentTrial) = trialWater;
        BpodSystem.Data.TotalWaterDelivered = BpodSystem.Data.TotalWaterDelivered + trialWater;

        % Update online plots
        UpdateOnlinePlot(BpodSystem.Data, currentTrial);

        % Save data
        SaveBpodSessionData;

        % Display trial information with block and delay progress
        portName = {'Left', 'Right'};

        fprintf('Trial %d [Block %d-%d]: Port %s | Licks: %d', ...
            currentTrial, currentBlock, trialInBlock, portName{selectedPort}, responseLicks);

        if burstCount == 0
            fprintf(' | Delay: ✓ PERFECT');
        else
            fprintf(' | Delay: %d reset(s)', burstCount);
        end

        fprintf(' | Water: %.1f/%.1f uL\n', ...
            trialWater, BpodSystem.Data.TotalWaterDelivered);
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
    % Update online visualization of trial outcomes with block information

    global BpodSystem

    if currentTrial == 1
        % Initialize figure with larger size for 5 subplots
        BpodSystem.ProtocolFigures.OutcomePlot = figure('Name', 'Session Performance', ...
            'NumberTitle', 'off', 'Position', [100 100 1400 700]);
    end

    figure(BpodSystem.ProtocolFigures.OutcomePlot);
    clf;  % Clear figure for redrawing

    % --- Subplot 1: Port choice over trials with block boundaries ---
    subplot(2,3,1);
    trialTypes = Data.TrialTypes(1:currentTrial);

    % Plot port choices
    hold on;
    for i = 1:currentTrial
        if trialTypes(i) == 1  % Left port
            color = [0 0.4470 0.7410];  % Blue
            yVal = 1;
        elseif trialTypes(i) == 2  % Right port
            color = [0.8500 0.3250 0.0980];  % Orange
            yVal = 2;
        else  % No choice
            color = [0.5 0.5 0.5];  % Gray
            yVal = 1.5;
        end

        plot(i, yVal, 'o', 'MarkerFaceColor', color, 'MarkerEdgeColor', color, 'MarkerSize', 6);
    end

    % Draw block boundaries
    if isfield(Data, 'BlockNumber') && ~isempty(Data.BlockNumber)
        blockChanges = find(diff([0 Data.BlockNumber(1:currentTrial)]) ~= 0);
        for bc = blockChanges
            xline(bc, '--', 'Color', [0.5 0.5 0.5], 'LineWidth', 1);
        end
    end

    xlabel('Trial Number');
    ylabel('Port Choice');
    title('Port Selection (Blue=Left, Orange=Right)');
    ylim([0.5 2.5]);
    yticks([1 2]);
    yticklabels({'Left', 'Right'});
    grid on;
    hold off;

    % --- Subplot 2: Port selection distribution ---
    subplot(2,3,2);
    leftTrials = find(trialTypes == 1);
    rightTrials = find(trialTypes == 2);

    portSelection = Data.SelectedPort(1:currentTrial);
    histogram(portSelection, [0.5 1.5 2.5]);
    xlabel('Selected Port');
    ylabel('Count');
    title(sprintf('Port Selection (L=%d, R=%d)', length(leftTrials), length(rightTrials)));
    xticks([1 2]);
    xticklabels({'Left', 'Right'});

    % --- Subplot 3: Delay resets over trials ---
    subplot(2,3,3);
    delayResets = Data.DelayTimerResets(1:currentTrial);
    plot(1:currentTrial, delayResets, 'o-', 'MarkerSize', 4);
    xlabel('Trial Number');
    ylabel('Reset Count');
    title(sprintf('Delay Timer Resets (Mean=%.2f)', mean(delayResets)));
    grid on;

    % --- Subplot 4: Block parameters summary ---
    subplot(2,3,4);
    axis off;
    if isfield(Data, 'BlockNumber') && ~isempty(Data.BlockNumber)
        currentBlock = Data.BlockNumber(currentTrial);
        currentBlockParams = Data.BlockParams(currentBlock);

        infoText = {
            '=== CURRENT BLOCK INFO ===';
            sprintf('Block: %d / %d', currentBlock, length(Data.BlockParams));
            sprintf('Trial in block: %d', Data.TrialInBlock(currentTrial));
            sprintf('Block type: %d', Data.BlockSequence(currentBlock));
            '';
            '--- Parameters ---';
            sprintf('Delay: %.2fs', currentBlockParams.DelayDuration);
            sprintf('Error reset: Segment %d', currentBlockParams.ErrorResetSegment);
            sprintf('Reward L: %.3fs', currentBlockParams.RewardLeft);
            sprintf('Reward R: %.3fs', currentBlockParams.RewardRight);
        };

        text(0.1, 0.5, infoText, 'FontSize', 10, 'FontName', 'FixedWidth', ...
            'VerticalAlignment', 'middle');
    end

    % --- Subplot 5: Water consumption tracking ---
    subplot(2,3,5);
    if isfield(Data, 'WaterPerTrial') && ~isempty(Data.WaterPerTrial)
        waterPerTrial = Data.WaterPerTrial(1:currentTrial);

        % Plot cumulative water
        cumulativeWater = cumsum(waterPerTrial);

        yyaxis left
        plot(1:currentTrial, cumulativeWater, 'b-', 'LineWidth', 2);
        ylabel('Cumulative Water (uL)', 'Color', 'b');
        ylim([0 max(cumulativeWater)*1.1]);

        yyaxis right
        bar(1:currentTrial, waterPerTrial, 'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none');
        ylabel('Water per Trial (uL)', 'Color', 'k');

        xlabel('Trial Number');
        title(sprintf('Water Delivered (Total: %.1f uL)', Data.TotalWaterDelivered));
        grid on;
    else
        text(0.5, 0.5, 'No water data', 'HorizontalAlignment', 'center');
        axis off;
    end

    % --- Subplot 6: Licks per trial ---
    subplot(2,3,6);
    if isfield(Data, 'ResponseLickCount') && ~isempty(Data.ResponseLickCount)
        lickCounts = Data.ResponseLickCount(1:currentTrial);

        hold on;
        % Color by port
        for i = 1:currentTrial
            if trialTypes(i) == 1  % Left port
                color = [0 0.4470 0.7410];  % Blue
            elseif trialTypes(i) == 2  % Right port
                color = [0.8500 0.3250 0.0980];  % Orange
            else
                color = [0.5 0.5 0.5];  % Gray
            end
            bar(i, lickCounts(i), 'FaceColor', color, 'EdgeColor', 'none');
        end
        hold off;

        xlabel('Trial Number');
        ylabel('Lick Count');
        title(sprintf('Licks per Trial (Mean=%.1f)', mean(lickCounts)));
        grid on;
    else
        text(0.5, 0.5, 'No lick data', 'HorizontalAlignment', 'center');
        axis off;
    end

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


%% Block generation and management functions

function [BlockSequence, BlockParams] = GenerateBlockSequence(S)
    % Generate sequence of blocks with parameters
    % Returns:
    %   BlockSequence: Array of block type indices (e.g., [1 2 3 1 2 3...])
    %   BlockParams: Struct array with parameters for each block instance

    % Count how many block types are defined
    maxBlockTypes = 10;  % Check up to 10 block types
    numBlockTypes = 0;
    for i = 1:maxBlockTypes
        if isfield(S.GUI, sprintf('Block%d_DelayDuration', i))
            numBlockTypes = i;
        else
            break;
        end
    end

    if numBlockTypes == 0
        error('No block types defined in S.GUI');
    end

    % Generate randomized sequence of block types
    if S.GUI.BlocksEnabled
        numBlocks = S.GUI.NumBlocks;
        % Randomize block order
        BlockSequence = [];
        fullCycles = floor(numBlocks / numBlockTypes);
        remainder = mod(numBlocks, numBlockTypes);

        % Add full cycles of all block types (randomized)
        for cycle = 1:fullCycles
            BlockSequence = [BlockSequence, randperm(numBlockTypes)]; %#ok<AGROW>
        end

        % Add remainder blocks (randomized)
        if remainder > 0
            BlockSequence = [BlockSequence, randperm(numBlockTypes, remainder)]; %#ok<AGROW>
        end
    else
        % Single block mode - just use block type 1
        BlockSequence = ones(1, S.GUI.NumBlocks);
    end

    % Create BlockParams struct array with parameters for each block instance
    BlockParams = struct();
    for i = 1:length(BlockSequence)
        blockType = BlockSequence(i);
        BlockParams(i).BlockType = blockType;
        BlockParams(i).DelayDuration = S.GUI.(sprintf('Block%d_DelayDuration', blockType));
        BlockParams(i).ErrorResetSegment = S.GUI.(sprintf('Block%d_ErrorResetSegment', blockType));
        BlockParams(i).RewardLeft = S.GUI.(sprintf('Block%d_RewardLeft', blockType));
        BlockParams(i).RewardRight = S.GUI.(sprintf('Block%d_RewardRight', blockType));
    end
end


function [currentBlock, trialInBlock] = GetCurrentBlock(trialNumber, blockSize, totalBlocks)
    % Determine which block a trial belongs to and its position within the block
    % Inputs:
    %   trialNumber: Current trial number (1-indexed)
    %   blockSize: Number of trials per block
    %   totalBlocks: Total number of blocks available
    % Returns:
    %   currentBlock: Block index (1-indexed)
    %   trialInBlock: Trial number within block (1 to blockSize)

    currentBlock = ceil(trialNumber / blockSize);

    % Wrap around if we exceed total blocks (repeat sequence)
    if currentBlock > totalBlocks
        currentBlock = mod(currentBlock - 1, totalBlocks) + 1;
    end

    trialInBlock = mod(trialNumber - 1, blockSize) + 1;
end


function CreateMotorControlGUI(S)
    % Create separate motor control GUI window
    global BpodSystem motors_properties

    if ~S.GUI.ZaberEnabled
        return;
    end

    % Create figure
    BpodSystem.GUIHandles.MotorControlFig = figure('Name', 'Motor Control', ...
        'NumberTitle', 'off', ...
        'Position', [100, 300, 400, 350], ...
        'MenuBar', 'none', ...
        'Resize', 'off', ...
        'CloseRequestFcn', @(~,~) set(gcf, 'Visible', 'off'));  % Hide instead of close

    % Create UI controls
    yPos = 300;
    spacing = 60;

    % Z Motor
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Z Position (lickable):', 'HorizontalAlignment', 'left', 'FontSize', 10);
    BpodSystem.GUIHandles.Z_motor_edit = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Z_motor_pos), ...
        'FontSize', 10, ...
        'Callback', @(h,~) moveMotorCallback(h, motors_properties.Z_motor_num));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Move Z', 'FontSize', 10, ...
        'Callback', @(~,~) moveMotorCallback(BpodSystem.GUIHandles.Z_motor_edit, motors_properties.Z_motor_num));

    % Z NonLickable
    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Z Retracted (ITI):', 'HorizontalAlignment', 'left', 'FontSize', 10);
    BpodSystem.GUIHandles.Z_retract_edit = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Z_NonLickable), ...
        'FontSize', 10, ...
        'Callback', @(h,~) moveMotorCallback(h, motors_properties.Z_motor_num));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Retract Z', 'FontSize', 10, ...
        'Callback', @(~,~) moveMotorCallback(BpodSystem.GUIHandles.Z_retract_edit, motors_properties.Z_motor_num));

    % Lx Motor
    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Lx Position (left-right):', 'HorizontalAlignment', 'left', 'FontSize', 10);
    BpodSystem.GUIHandles.Lx_motor_edit = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Lx_motor_pos), ...
        'FontSize', 10, ...
        'Callback', @(h,~) moveMotorCallback(h, motors_properties.Lx_motor_num));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Move Lx', 'FontSize', 10, ...
        'Callback', @(~,~) moveMotorCallback(BpodSystem.GUIHandles.Lx_motor_edit, motors_properties.Lx_motor_num));

    % Ly Motor
    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Ly Position (anterior-posterior):', 'HorizontalAlignment', 'left', 'FontSize', 10);
    BpodSystem.GUIHandles.Ly_motor_edit = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Ly_motor_pos), ...
        'FontSize', 10, ...
        'Callback', @(h,~) moveMotorCallback(h, motors_properties.Ly_motor_num));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Move Ly', 'FontSize', 10, ...
        'Callback', @(~,~) moveMotorCallback(BpodSystem.GUIHandles.Ly_motor_edit, motors_properties.Ly_motor_num));

    % Status text
    yPos = yPos - spacing + 10;
    BpodSystem.GUIHandles.MotorStatus = uicontrol('Style', 'text', ...
        'Position', [20 yPos 360 30], ...
        'String', 'Ready - Enter position and click Move or press ENTER', ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 9, ...
        'ForegroundColor', [0 0.5 0]);

    % Info text
    uicontrol('Style', 'text', 'Position', [20 10 360 30], ...
        'String', 'Positions in microsteps. Z_lickable ≈ 210000, Z_retracted ≈ 60000', ...
        'HorizontalAlignment', 'center', 'FontSize', 8, 'ForegroundColor', [0.5 0.5 0.5]);
end


function moveMotorCallback(editHandle, motorNum)
    % Callback for motor movement
    global BpodSystem

    try
        position = str2double(get(editHandle, 'String'));

        if isnan(position)
            set(BpodSystem.GUIHandles.MotorStatus, 'String', 'ERROR: Invalid position value', ...
                'ForegroundColor', [1 0 0]);
            return;
        end

        motorNames = {'Lx', 'Z', '?', 'Ly'};
        motorName = motorNames{motorNum};

        set(BpodSystem.GUIHandles.MotorStatus, 'String', ...
            sprintf('Moving %s to %d...', motorName, round(position)), ...
            'ForegroundColor', [0 0 1]);
        drawnow;

        Motor_Move(position, motorNum);

        set(BpodSystem.GUIHandles.MotorStatus, 'String', ...
            sprintf('✓ %s moved to %d', motorName, round(position)), ...
            'ForegroundColor', [0 0.5 0]);

    catch ME
        set(BpodSystem.GUIHandles.MotorStatus, 'String', ...
            sprintf('ERROR: %s', ME.message), ...
            'ForegroundColor', [1 0 0]);
    end
end
