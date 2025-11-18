function FreeLicking_DynamicITI
% FREE LICKING PROTOCOL WITH BLOCK-BASED DYNAMIC PARAMETERS

global BpodSystem

%% Initialize Bpod System
MaxTrials = 1000;

%% Task Parameters
S = BpodSystem.ProtocolSettings;

if isempty(fieldnames(S))
    S.GUI.ResponseDuration = 5;
    S.GUI.BurstIgnoreDuration = 0.5;
    S.GUI.DebounceDuration = 0.05;
    S.GUI.SessionDuration = 10800;  % 3 hours in seconds

    S.GUI.InitRewardSize = 0.05;
    S.GUI.InitWaitDuration = 0.5;

    % Non-block mode parameters
    S.GUI.DefaultDelayDuration = 2.0;
    S.GUI.DefaultErrorResetSegment = 1;
    S.GUI.DefaultRewardLeft = 0.01;
    S.GUI.DefaultRewardRight = 0.01;

    S.GUI.BlocksEnabled = 0;  % Disabled by default
    S.GUI.BlockSize = 40;
    S.GUI.NumBlocks = 10;

    S.GUI.Block1_DelayDuration = 2.0;
    S.GUI.Block1_ErrorResetSegment = 1;
    S.GUI.Block1_RewardLeft = 0.01;
    S.GUI.Block1_RewardRight = 0.01;

    S.GUI.Block2_DelayDuration = 3.0;
    S.GUI.Block2_ErrorResetSegment = 2;
    S.GUI.Block2_RewardLeft = 0.015;
    S.GUI.Block2_RewardRight = 0.015;

    S.GUI.Block3_DelayDuration = 4.0;
    S.GUI.Block3_ErrorResetSegment = 1;
    S.GUI.Block3_RewardLeft = 0.02;
    S.GUI.Block3_RewardRight = 0.01;

    S.GUI.CameraSyncEnabled = 1;
    S.GUI.CameraPulseWidth = 0.002;
    S.GUI.BitcodeEnabled = 1;

    S.GUI.ZaberEnabled = 1;
    S.GUI.ZaberPort = 'COM6';
    S.GUI.Z_motor_pos = 210000;
    S.GUI.Z_NonLickable = 60000;
    S.GUI.Lx_motor_pos = 310000;
    S.GUI.Ly_motor_pos = 310000;
end

BpodSystem.ProtocolSettings = S;

%% Initialize Data Storage
BpodSystem.Data.TrialTypes = [];
BpodSystem.Data.SelectedPort = [];
BpodSystem.Data.ResponseLickCount = [];
BpodSystem.Data.IncorrectResponseLicks = [];
BpodSystem.Data.DelayLickCount = [];
BpodSystem.Data.DelayTimerResets = [];
BpodSystem.Data.TrialStartTime = [];
BpodSystem.Data.TrialEndTime = [];
BpodSystem.Data.TrialRewardSize = [];
BpodSystem.Data.MotorPositions = [];
BpodSystem.Data.Bitcode = {};
BpodSystem.Data.TotalDelayDuration = [];

BpodSystem.Data.TrialLickTimes = {};
BpodSystem.Data.TrialLickPorts = {};
BpodSystem.Data.TrialLickTypes = {};
BpodSystem.Data.TrialStateTransitions = {};

BpodSystem.Data.BlockNumber = [];
BpodSystem.Data.TrialInBlock = [];
BpodSystem.Data.BlockParams = [];
BpodSystem.Data.BlockSequence = [];

BpodSystem.Data.SessionWaterDelivered = 0;
BpodSystem.Data.WaterPerTrial = [];
BpodSystem.Data.SessionStartTime = now();

%% Initialize Zaber Motors
global motors motors_properties

if S.GUI.ZaberEnabled
    try
        motors_properties.PORT = S.GUI.ZaberPort;
        motors_properties.type = '@ZaberArseny';
        motors_properties.Z_motor_num = 2;
        motors_properties.Lx_motor_num = 1;
        motors_properties.Ly_motor_num = 4;

        BpodSystem.SoftCodeHandlerFunction = 'MySoftCodeHandler';

        motors = ZaberTCD1000(motors_properties.PORT);
        serial_open(motors);

        Motor_Move(S.GUI.Z_motor_pos, motors_properties.Z_motor_num);
        Motor_Move(S.GUI.Lx_motor_pos, motors_properties.Lx_motor_num);
        Motor_Move(S.GUI.Ly_motor_pos, motors_properties.Ly_motor_num);

        disp('Zaber motors initialized');

    catch ME
        warning('Failed to initialize Zaber motors: %s', ME.message);
        S.GUI.ZaberEnabled = 0;
    end
end

%% Create GUI Windows
CreateTimersGUI(S);
CreateBlockDesignGUI(S);
if S.GUI.ZaberEnabled
    CreateMotorControlGUI(S);
end

%% Pause protocol
disp('==========================================================');
disp('PROTOCOL PAUSED - Adjust settings as needed');
disp('GUI windows: Timers, Block Design, Motor Control');
disp('Press PLAY to begin session');
disp('==========================================================');

BpodSystem.Status.Pause = 1;
HandlePauseCondition;
if BpodSystem.Status.BeingUsed == 0
    CloseAllGUIWindows();
    return;
end

%% Session Initialization
disp(' ');
disp('===== SESSION INITIALIZATION =====');
disp('Delivering initial water to both ports...');

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

% Track initial water
initWater = 2 * S.GUI.InitRewardSize * 5000;
BpodSystem.Data.SessionWaterDelivered = initWater;
disp(['Initial water delivered: ' num2str(initWater, '%.1f') ' uL (' num2str(S.GUI.InitRewardSize, '%.3f') 's per port)']);

%% Generate Block Sequence
[BlockSequence, BlockParams] = GenerateBlockSequence(S);
BpodSystem.Data.BlockSequence = BlockSequence;
BpodSystem.Data.BlockParams = BlockParams;

disp(' ');
disp('===== BLOCK SEQUENCE =====');
disp(['Total blocks: ' num2str(length(BlockSequence))]);
for i = 1:min(length(BlockSequence), 5)
    bp = BlockParams(i);
    disp(['  Block ' num2str(i) ' (Type ' num2str(BlockSequence(i)) '): Delay=' num2str(bp.DelayDuration, '%.1f') 's, Reset=Seg' num2str(bp.ErrorResetSegment) ', Rewards=[' num2str(bp.RewardLeft, '%.3f') ',' num2str(bp.RewardRight, '%.3f') ']s']);
end
if length(BlockSequence) > 5
    disp(['  ... and ' num2str(length(BlockSequence) - 5) ' more blocks']);
end

disp(' ');
disp('===== SESSION STARTED =====');
disp(' ');

%% Initialize Online Plot
InitializeOnlinePlot();

%% Main Trial Loop
for currentTrial = 1:MaxTrials

    % Check if Bpod is still connected
    if BpodSystem.Status.BeingUsed == 0
        disp(' ');
        disp('===== BPOD DISCONNECTED =====');
        break;
    end

    % Check session duration
    sessionElapsed = (now() - BpodSystem.Data.SessionStartTime) * 24 * 60 * 60;
    if sessionElapsed > S.GUI.SessionDuration
        disp(' ');
        disp(['===== SESSION TIMEOUT (' num2str(sessionElapsed/60, '%.1f') ' minutes) =====']);
        break;
    end

    % Sync GUI parameters
    S = SyncAllGUIParameters();

    % Determine current block
    [currentBlock, trialInBlock] = GetCurrentBlock(currentTrial, S.GUI.BlockSize, length(BlockSequence));
    currentBlockParams = BlockParams(currentBlock);

    BpodSystem.Data.BlockNumber(currentTrial) = currentBlock;
    BpodSystem.Data.TrialInBlock(currentTrial) = trialInBlock;
    BpodSystem.Data.TrialStartTime(currentTrial) = now();

    % Generate bitcode
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

    % Camera sync timer
    if S.GUI.CameraSyncEnabled
        sma = SetGlobalTimer(sma, 'TimerID', 1, ...
            'Duration', S.GUI.CameraPulseWidth, ...
            'OnsetDelay', 0, ...
            'Channel', 'BNC1', ...
            'OnLevel', 1, ...
            'OffLevel', 0, ...
            'Loop', 1, ...
            'SendGlobalTimerEvents', 0, ...
            'LoopInterval', S.GUI.CameraPulseWidth);
    end

    % Response period timer
    sma = SetGlobalTimer(sma, 'TimerID', 2, ...
        'Duration', S.GUI.ResponseDuration, ...
        'OnsetDelay', 0, ...
        'Channel', 'BNC2', ...
        'OnLevel', 0, ...
        'OffLevel', 0, ...
        'Loop', 0, ...
        'SendGlobalTimerEvents', 1);

    % Ready state
    if S.GUI.CameraSyncEnabled
        sma = AddState(sma, 'Name', 'ReadyForLick', ...
            'Timer', 3600, ...
            'StateChangeConditions', {'Port1Out', 'StartResponsePort1', 'Port2Out', 'StartResponsePort2', 'Tup', 'exit'}, ...
            'OutputActions', {'GlobalTimerTrig', 1});
    else
        sma = AddState(sma, 'Name', 'ReadyForLick', ...
            'Timer', 3600, ...
            'StateChangeConditions', {'Port1Out', 'StartResponsePort1', 'Port2Out', 'StartResponsePort2', 'Tup', 'exit'}, ...
            'OutputActions', {});
    end

    % Response period - Port 1
    sma = AddState(sma, 'Name', 'StartResponsePort1', ...
        'Timer', 0, ...
        'StateChangeConditions', {'Tup', 'ResponsePort1'}, ...
        'OutputActions', {'GlobalTimerTrig', 2});

    sma = AddState(sma, 'Name', 'ResponsePort1', ...
        'Timer', 1000, ...
        'StateChangeConditions', {'GlobalTimer2_End', 'Delay_2_0s', 'Port1Out', 'RewardPort1', 'Port2Out', 'WrongPortResponse'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'RewardPort1', ...
        'Timer', currentBlockParams.RewardLeft, ...
        'StateChangeConditions', {'Tup', 'DebouncePort1', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {'Valve1', 1});

    sma = AddState(sma, 'Name', 'DebouncePort1', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort1', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {});

    % Response period - Port 2
    sma = AddState(sma, 'Name', 'StartResponsePort2', ...
        'Timer', 0, ...
        'StateChangeConditions', {'Tup', 'ResponsePort2'}, ...
        'OutputActions', {'GlobalTimerTrig', 2});

    sma = AddState(sma, 'Name', 'ResponsePort2', ...
        'Timer', 1000, ...
        'StateChangeConditions', {'GlobalTimer2_End', 'Delay_2_0s', 'Port2Out', 'RewardPort2', 'Port1Out', 'WrongPortResponse'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'RewardPort2', ...
        'Timer', currentBlockParams.RewardRight, ...
        'StateChangeConditions', {'Tup', 'DebouncePort2', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {'Valve2', 1});

    sma = AddState(sma, 'Name', 'DebouncePort2', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort2', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {});

    % Wrong port during response
    sma = AddState(sma, 'Name', 'WrongPortResponse', ...
        'Timer', S.GUI.DebounceDuration, ...
        'StateChangeConditions', {'Tup', 'ResponsePort1', 'GlobalTimer2_End', 'Delay_2_0s'}, ...
        'OutputActions', {});

    % Delay period
    switch currentBlockParams.ErrorResetSegment
        case 1
            errorResetState = 'Delay_2_0s';
        case 2
            errorResetState = 'Delay_1_5s';
        case 3
            errorResetState = 'Delay_1_0s';
        case 4
            errorResetState = 'Delay_0_5s';
        otherwise
            errorResetState = 'Delay_2_0s';
    end

    segmentDuration = currentBlockParams.DelayDuration / 4;

    sma = AddState(sma, 'Name', 'Delay_2_0s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'Delay_1_5s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'Delay_1_5s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'Delay_1_0s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'Delay_1_0s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'Delay_0_5s', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'Delay_0_5s', ...
        'Timer', segmentDuration, ...
        'StateChangeConditions', {'Tup', 'TrialComplete', 'Port1Out', 'BurstWindow', 'Port2Out', 'BurstWindow'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'BurstWindow', ...
        'Timer', S.GUI.BurstIgnoreDuration, ...
        'StateChangeConditions', {'Tup', errorResetState}, ...
        'OutputActions', {});

    % Terminal state
    if S.GUI.CameraSyncEnabled
        sma = AddState(sma, 'Name', 'TrialComplete', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'exit'}, ...
            'OutputActions', {'GlobalTimerCancel', 1});
    else
        sma = AddState(sma, 'Name', 'TrialComplete', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'exit'}, ...
            'OutputActions', {});
    end

    %% Run Trial
    SendStateMachine(sma);
    RawEvents = RunStateMachine();

    %% Process Trial Data
    if ~isempty(fieldnames(RawEvents))
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;

        % Extract detailed lick data
        [selectedPort, responseLicks, incorrectResponseLicks, delayLicks, burstCount, ...
         lickTimes, lickPorts, lickTypes, stateTransitions, totalDelayDuration] = ...
            ProcessTrialLickData(BpodSystem.Data.RawEvents.Trial{currentTrial}, S.GUI.ResponseDuration);

        BpodSystem.Data.SelectedPort(currentTrial) = selectedPort;
        BpodSystem.Data.TrialTypes(currentTrial) = selectedPort;
        BpodSystem.Data.ResponseLickCount(currentTrial) = responseLicks;
        BpodSystem.Data.IncorrectResponseLicks(currentTrial) = incorrectResponseLicks;
        BpodSystem.Data.DelayLickCount(currentTrial) = delayLicks;
        BpodSystem.Data.DelayTimerResets(currentTrial) = burstCount;
        BpodSystem.Data.TotalDelayDuration(currentTrial) = totalDelayDuration;
        BpodSystem.Data.TrialEndTime(currentTrial) = now();

        % Store detailed lick data
        BpodSystem.Data.TrialLickTimes{currentTrial} = lickTimes;
        BpodSystem.Data.TrialLickPorts{currentTrial} = lickPorts;
        BpodSystem.Data.TrialLickTypes{currentTrial} = lickTypes;
        BpodSystem.Data.TrialStateTransitions{currentTrial} = stateTransitions;

        % Store reward size
        if selectedPort == 1
            BpodSystem.Data.TrialRewardSize(currentTrial) = currentBlockParams.RewardLeft;
        elseif selectedPort == 2
            BpodSystem.Data.TrialRewardSize(currentTrial) = currentBlockParams.RewardRight;
        else
            BpodSystem.Data.TrialRewardSize(currentTrial) = 0;
        end

        % Calculate water
        trialWater = BpodSystem.Data.TrialRewardSize(currentTrial) * responseLicks * 5000;
        BpodSystem.Data.WaterPerTrial(currentTrial) = trialWater;
        BpodSystem.Data.SessionWaterDelivered = BpodSystem.Data.SessionWaterDelivered + trialWater;

        % Update plots
        UpdateOnlinePlot(BpodSystem.Data, currentTrial, currentBlockParams);

        % Save
        SaveBpodSessionData;

        % Console output
        portName = {'Left', 'Right', 'None'};
        portIdx = max(1, min(selectedPort, 3));

        disp(['Trial ' num2str(currentTrial) ' [Block ' num2str(currentBlock) '-' num2str(trialInBlock) ']:']);
        disp(['  Port: ' portName{portIdx}]);
        disp(['  Licks: ' num2str(responseLicks) ' correct, ' num2str(incorrectResponseLicks) ' wrong port, ' num2str(delayLicks) ' during delay']);
        disp(['  Delay resets: ' num2str(burstCount)]);
        disp(['  Water this trial: ' num2str(trialWater, '%.1f') ' uL']);
        disp(['  Total session water: ' num2str(BpodSystem.Data.SessionWaterDelivered, '%.1f') ' uL']);
        disp(' ');
    end

    % Handle pause/stop
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        disp(' ');
        disp('===== MANUAL STOP - Saving data =====');
        SaveBpodSessionData;
        break;
    end
end

%% Cleanup
disp(' ');
disp('===== CLEANING UP =====');

% Cleanup motors
global motors motors_properties

if S.GUI.ZaberEnabled && exist('motors', 'var') && ~isempty(motors)
    try
        Motor_Move(S.GUI.Z_NonLickable, motors_properties.Z_motor_num);
        serial_close(motors);
        clear global motors motors_properties;
        disp('Motors retracted and closed');
    catch ME
        warning('Motor cleanup failed: %s', ME.message);
    end
end

% Final save
SaveBpodSessionData;

disp(' ');
disp('===== SESSION COMPLETE =====');
disp(['Total trials: ' num2str(currentTrial)]);
disp(['Total water delivered: ' num2str(BpodSystem.Data.SessionWaterDelivered, '%.1f') ' uL']);
disp(['Session duration: ' num2str(sessionElapsed/60, '%.1f') ' minutes']);
disp(' ');

% Close GUI windows AFTER session complete message
CloseAllGUIWindows();

end % Main function


%% HELPER FUNCTIONS

function [selectedPort, responseLicks, incorrectResponseLicks, delayLicks, burstCount, ...
          lickTimes, lickPorts, lickTypes, stateTransitions, totalDelayDuration] = ...
          ProcessTrialLickData(RawEvents, responseDuration)

    selectedPort = 0;
    responseLicks = 0;
    incorrectResponseLicks = 0;
    delayLicks = 0;
    burstCount = 0;
    totalDelayDuration = 0;

    lickTimes = [];
    lickPorts = [];
    lickTypes = [];
    stateTransitions = struct();

    if ~isstruct(RawEvents.States)
        return;
    end

    % Determine selected port
    if isfield(RawEvents.States, 'StartResponsePort1') && ~isnan(RawEvents.States.StartResponsePort1(1))
        selectedPort = 1;
    elseif isfield(RawEvents.States, 'StartResponsePort2') && ~isnan(RawEvents.States.StartResponsePort2(1))
        selectedPort = 2;
    end

    % Get all lick events
    allLickTimes = [];
    allLickPorts = [];

    if isfield(RawEvents.Events, 'Port1Out')
        port1Licks = RawEvents.Events.Port1Out(:);
        allLickTimes = [allLickTimes; port1Licks];
        allLickPorts = [allLickPorts; ones(size(port1Licks))];
    end

    if isfield(RawEvents.Events, 'Port2Out')
        port2Licks = RawEvents.Events.Port2Out(:);
        allLickTimes = [allLickTimes; port2Licks];
        allLickPorts = [allLickPorts; 2*ones(size(port2Licks))];
    end

    % Sort by time
    [allLickTimes, sortIdx] = sort(allLickTimes);
    allLickPorts = allLickPorts(sortIdx);

    % Extract state transition times
    stateNames = fieldnames(RawEvents.States);
    for i = 1:length(stateNames)
        stateName = stateNames{i};
        stateTimes = RawEvents.States.(stateName);
        if ~isempty(stateTimes) && ~all(isnan(stateTimes(:,1)))
            stateTransitions.(stateName) = stateTimes(~isnan(stateTimes(:,1)), :);
        end
    end

    % Categorize each lick
    allLickTypes = zeros(size(allLickTimes));

    % Define response period end time
    if isfield(stateTransitions, 'StartResponsePort1')
        responseStart = stateTransitions.StartResponsePort1(1, 1);
    elseif isfield(stateTransitions, 'StartResponsePort2')
        responseStart = stateTransitions.StartResponsePort2(1, 1);
    else
        responseStart = 0;
    end
    responseEnd = responseStart + responseDuration;

    for i = 1:length(allLickTimes)
        lickTime = allLickTimes(i);
        lickPort = allLickPorts(i);

        if lickTime >= responseStart && lickTime < responseEnd
            if lickPort == selectedPort
                allLickTypes(i) = 1;
                responseLicks = responseLicks + 1;
            else
                allLickTypes(i) = 2;
                incorrectResponseLicks = incorrectResponseLicks + 1;
            end
        else
            allLickTypes(i) = 3;
            delayLicks = delayLicks + 1;
        end
    end

    lickTimes = allLickTimes;
    lickPorts = allLickPorts;
    lickTypes = allLickTypes;

    % Count burst windows
    if isfield(RawEvents.States, 'BurstWindow')
        burstCount = sum(~isnan(RawEvents.States.BurstWindow(:, 1)));
    end

    % Calculate total delay duration
    delayStates = {'Delay_2_0s', 'Delay_1_5s', 'Delay_1_0s', 'Delay_0_5s', 'BurstWindow'};
    for i = 1:length(delayStates)
        if isfield(stateTransitions, delayStates{i})
            delayTimes = stateTransitions.(delayStates{i});
            totalDelayDuration = totalDelayDuration + sum(delayTimes(:,2) - delayTimes(:,1));
        end
    end
end


function InitializeOnlinePlot()
    global BpodSystem

    BpodSystem.ProtocolFigures.OnlinePlot = figure('Name', 'Session Monitor', ...
        'NumberTitle', 'off', 'Position', [50 50 1400 800], 'Color', 'w');

    BpodSystem.GUIHandles.LickPlot = subplot(2, 2, 1);
    BpodSystem.GUIHandles.DelayPlot = subplot(2, 2, 2);
    BpodSystem.GUIHandles.InfoText = subplot(2, 2, 3);
    BpodSystem.GUIHandles.WaterPlot = subplot(2, 2, 4);

    % Initialize each subplot with placeholder
    subplot(BpodSystem.GUIHandles.LickPlot);
    text(0.5, 0.5, 'Waiting for first trial...', 'HorizontalAlignment', 'center');
    axis off;

    subplot(BpodSystem.GUIHandles.DelayPlot);
    title('Delay Performance');
    xlabel('Trial');
    ylabel('Resets');

    subplot(BpodSystem.GUIHandles.InfoText);
    axis off;
    text(0.5, 0.5, 'Trial info will appear here', 'HorizontalAlignment', 'center');

    subplot(BpodSystem.GUIHandles.WaterPlot);
    axis off;
    title('Water Delivered');

    drawnow;
end


function UpdateOnlinePlot(Data, currentTrial, currentBlockParams)
    global BpodSystem

    if currentTrial < 1 || ~isfield(BpodSystem.ProtocolFigures, 'OnlinePlot') || ~ishandle(BpodSystem.ProtocolFigures.OnlinePlot)
        return;
    end

    try
        figure(BpodSystem.ProtocolFigures.OnlinePlot);

        %% PLOT 1: Lick Events (Current + Previous Trial)
        subplot(BpodSystem.GUIHandles.LickPlot);
        cla;
        hold on;

        % Plot previous trial (if exists) with transparency and offset
        if currentTrial > 1 && length(Data.TrialLickTimes) >= (currentTrial - 1)
            try
                PlotSingleTrialLicks(Data, currentTrial - 1, 0.3, 6, 0.15);  % alpha=0.3, size=6, yOffset=0.15
            catch
                % Skip if error
            end
        end

        % Plot current trial
        if currentTrial > 0 && length(Data.TrialLickTimes) >= currentTrial
            try
                PlotSingleTrialLicks(Data, currentTrial, 1.0, 8, 0);  % alpha=1.0, size=8, yOffset=0
            catch
                % Skip if error
            end
        end

        % Configure axes
        xlabel('Time (s)');
        ylabel('');
        if currentTrial > 1
            title(['Trials ' num2str(currentTrial-1) '-' num2str(currentTrial) ' (previous smaller/above)']);
        else
            title(['Trial ' num2str(currentTrial)]);
        end
        ylim([0.5 2.5]);
        yticks([1 2]);
        yticklabels({'Left', 'Right'});
        grid on;

        % Legend
        h1 = plot(NaN, NaN, 'o', 'MarkerSize', 8, 'MarkerFaceColor', [0 0.8 0], 'MarkerEdgeColor', 'k');
        h2 = plot(NaN, NaN, 'o', 'MarkerSize', 8, 'MarkerFaceColor', [1 0.6 0], 'MarkerEdgeColor', 'k');
        h3 = plot(NaN, NaN, 'o', 'MarkerSize', 8, 'MarkerFaceColor', [1 0 0], 'MarkerEdgeColor', 'k');
        legend([h1 h2 h3], {'Correct', 'Wrong', 'Delay'}, 'Location', 'northeast');

        hold off;

        %% PLOT 2: Delay Performance
        subplot(BpodSystem.GUIHandles.DelayPlot);
        cla;
        hold on;

        windowSize = 10;
        if currentTrial >= windowSize
            rollingResets = zeros(1, currentTrial - windowSize + 1);
            for i = 1:(currentTrial - windowSize + 1)
                rollingResets(i) = mean(Data.DelayTimerResets(i:i+windowSize-1));
            end
            plot(windowSize:currentTrial, rollingResets, 'b-', 'LineWidth', 2);
        elseif currentTrial > 0
            plot(1:currentTrial, Data.DelayTimerResets(1:currentTrial), 'bo-', 'LineWidth', 2, 'MarkerSize', 6);
        end

        xlabel('Trial');
        ylabel('Resets');
        title('Delay Performance');
        grid on;
        hold off;

        %% PLOT 3: Info Text
        subplot(BpodSystem.GUIHandles.InfoText);
        cla;
        axis off;

        recentWindow = max(1, currentTrial-19):currentTrial;
        recentLeftPct = 100 * sum(Data.TrialTypes(recentWindow) == 1) / length(recentWindow);
        recentCorrectLicks = mean(Data.ResponseLickCount(recentWindow));
        recentWrongLicks = mean(Data.IncorrectResponseLicks(recentWindow));
        recentDelayLicks = mean(Data.DelayLickCount(recentWindow));
        recentResets = mean(Data.DelayTimerResets(recentWindow));

        % Inter-error-lick interval
        meanErrorInterval = NaN;
        if currentTrial > 1
            allErrorIntervals = [];
            for t = 1:currentTrial
                if length(Data.DelayLickCount) >= t && Data.DelayLickCount(t) > 1
                    if length(Data.TrialLickTimes) >= t && length(Data.TrialLickTypes) >= t
                        if ~isempty(Data.TrialLickTimes{t}) && ~isempty(Data.TrialLickTypes{t})
                            delayLickTimes = Data.TrialLickTimes{t}(Data.TrialLickTypes{t} == 3);
                            if length(delayLickTimes) > 1
                                intervals = diff(delayLickTimes);
                                allErrorIntervals = [allErrorIntervals; intervals(:)];
                            end
                        end
                    end
                end
            end
            if ~isempty(allErrorIntervals)
                meanErrorInterval = mean(allErrorIntervals);
            end
        end

        if currentTrial > 1
            timeSpan = (Data.TrialEndTime(currentTrial) - Data.TrialStartTime(recentWindow(1))) * 24 * 60;
            trialsPerMin = length(recentWindow) / timeSpan;
        else
            trialsPerMin = 0;
        end

        currentBlock = Data.BlockNumber(currentTrial);
        trialInBlock = Data.TrialInBlock(currentTrial);
        blockType = Data.BlockSequence(currentBlock);

        infoText = {
            '=== CURRENT BLOCK ===';
            sprintf('Block: %d (Type %d) | Trial: %d', currentBlock, blockType, trialInBlock);
            sprintf('Delay: %.1fs | Reset: Seg %d', ...
                currentBlockParams.DelayDuration, currentBlockParams.ErrorResetSegment);
            sprintf('Rewards: L=%.3fs R=%.3fs', ...
                currentBlockParams.RewardLeft, currentBlockParams.RewardRight);
            '';
            '=== LAST TRIAL ===';
            sprintf('Correct licks: %d', Data.ResponseLickCount(currentTrial));
            sprintf('Wrong port licks: %d', Data.IncorrectResponseLicks(currentTrial));
            sprintf('Delay errors: %d', Data.DelayLickCount(currentTrial));
            sprintf('Delay resets: %d', Data.DelayTimerResets(currentTrial));
            '';
            '=== RECENT (last 20 trials) ===';
            sprintf('Trial rate: %.1f trials/min', trialsPerMin);
            sprintf('Port preference: %.0f%% Left / %.0f%% Right', recentLeftPct, 100-recentLeftPct);
            sprintf('Avg correct licks: %.1f', recentCorrectLicks);
            sprintf('Avg wrong port licks: %.1f', recentWrongLicks);
            sprintf('Avg delay errors: %.1f', recentDelayLicks);
            sprintf('Avg delay resets: %.2f', recentResets);
            sprintf('Avg time between errors: %.2fs', meanErrorInterval);
        };

        text(0.05, 0.5, infoText, 'FontSize', 9, 'FontName', 'FixedWidth', ...
            'VerticalAlignment', 'middle', 'Interpreter', 'none');

        %% PLOT 4: Water Container
        subplot(BpodSystem.GUIHandles.WaterPlot);
        cla;
        hold on;

        maxWater = 10000;  % 10 mL = 10000 uL
        currentWater = Data.SessionWaterDelivered;
        waterLevel = min(currentWater, maxWater);

        % Container dimensions
        containerLeft = 0.2;
        containerWidth = 0.6;
        containerBottom = 0;
        containerHeight = 100;

        % Draw water (blue fill)
        waterHeight = (waterLevel / maxWater) * containerHeight;
        if waterHeight > 0
            rectangle('Position', [containerLeft, containerBottom, containerWidth, waterHeight], ...
                'FaceColor', [0.3 0.6 1], 'EdgeColor', 'none');
        end

        % Draw container outline
        rectangle('Position', [containerLeft, containerBottom, containerWidth, containerHeight], ...
            'FaceColor', 'none', 'EdgeColor', 'k', 'LineWidth', 3);

        % Add water amount text
        if waterHeight > 10
            text(containerLeft + containerWidth/2, waterHeight/2, ...
                sprintf('%.1f mL', currentWater/1000), ...
                'HorizontalAlignment', 'center', 'FontSize', 14, 'FontWeight', 'bold');
        else
            text(containerLeft + containerWidth/2, waterHeight + 5, ...
                sprintf('%.1f mL', currentWater/1000), ...
                'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold');
        end

        % Add scale on the right side (in mL)
        scaleX = containerLeft + containerWidth + 0.05;
        for tickValue = 0:2.5:10
            tickHeight = (tickValue * 1000 / maxWater) * containerHeight;
            plot([containerLeft + containerWidth, scaleX], [tickHeight, tickHeight], 'k-', 'LineWidth', 1);
            text(scaleX + 0.02, tickHeight, sprintf('%.1f', tickValue), ...
                'FontSize', 9, 'VerticalAlignment', 'middle');
        end

        % Labels
        text(scaleX + 0.1, containerHeight/2, 'mL', ...
            'FontSize', 10, 'FontWeight', 'bold', 'Rotation', -90, ...
            'HorizontalAlignment', 'center');

        xlim([0 1]);
        ylim([-5 containerHeight + 5]);
        axis off;
        title('Water Delivered');
        hold off;

        drawnow;

    catch ME
        warning('Plot update error: %s', ME.message);
        if length(ME.stack) > 0
            disp(ME.stack(1));
        end
    end
end


function PlotSingleTrialLicks(Data, trialIdx, alpha, markerSize, yOffset)
    % Helper function to plot licks for a specific trial
    % alpha: transparency (0-1)
    % markerSize: marker size in points
    % yOffset: vertical offset to shift markers

    if trialIdx < 1 || length(Data.TrialLickTimes) < trialIdx
        return;
    end

    if isempty(Data.TrialLickTimes{trialIdx})
        return;
    end

    lickTimes = Data.TrialLickTimes{trialIdx};
    lickPorts = Data.TrialLickPorts{trialIdx};
    lickTypes = Data.TrialLickTypes{trialIdx};
    stateTransitions = Data.TrialStateTransitions{trialIdx};

    % Normalize to trial start
    if isfield(stateTransitions, 'StartResponsePort1')
        trialStart = stateTransitions.StartResponsePort1(1, 1);
    elseif isfield(stateTransitions, 'StartResponsePort2')
        trialStart = stateTransitions.StartResponsePort2(1, 1);
    else
        trialStart = 0;
    end

    lickTimes = lickTimes - trialStart;

    % Get response duration
    if length(Data.TrialSettings) >= trialIdx
        responseDur = Data.TrialSettings(trialIdx).GUI.ResponseDuration;
    else
        responseDur = 5;
    end

    % Background colors (only for current trial - alpha = 1.0)
    if alpha > 0.9
        % Response period background
        fill([0 responseDur responseDur 0], [0.5 0.5 2.5 2.5], [0.9 1 0.9], ...
            'EdgeColor', 'none', 'FaceAlpha', 0.3);

        % Delay period background
        delayStart = responseDur;
        delayEnd = delayStart + Data.TotalDelayDuration(trialIdx);
        fill([delayStart delayEnd delayEnd delayStart], [0.5 0.5 2.5 2.5], [0.9 0.9 1], ...
            'EdgeColor', 'none', 'FaceAlpha', 0.3);

        % Response end line
        xline(responseDur, '--k', 'LineWidth', 2);
    end

    % Plot licks with offset
    for i = 1:length(lickTimes)
        % Current trial - use full colors
        switch lickTypes(i)
            case 1
                color = [0 0.8 0];
            case 2
                color = [1 0.6 0];
            case 3
                color = [1 0 0];
            otherwise
                color = [0.5 0.5 0.5];
        end

        % Apply vertical offset
        yPos = lickPorts(i) + yOffset;

        % Plot with transparency
        h = plot(lickTimes(i), yPos, 'o', 'MarkerSize', markerSize, ...
            'MarkerFaceColor', color, 'MarkerEdgeColor', 'k', 'LineWidth', 1);

        % Set alpha if supported
        try
            h.MarkerFaceAlpha = alpha;
            h.MarkerEdgeAlpha = alpha;
        catch
            % Alpha not supported on this marker, continue
        end
    end
end


%% GUI Functions

function CreateTimersGUI(S)
    global BpodSystem

    fig = figure('Name', 'Timers & Non-Block Parameters', ...
        'NumberTitle', 'off', ...
        'Position', [100, 400, 450, 500], ...
        'MenuBar', 'none', ...
        'Resize', 'off');

    yPos = 460;
    spacing = 40;

    % Timing parameters
    uicontrol('Style', 'text', 'Position', [20 yPos 250 20], ...
        'String', '=== TIMING PARAMETERS ===', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Response Duration (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.ResponseDuration = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.ResponseDuration));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Burst Ignore (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.BurstIgnoreDuration = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.BurstIgnoreDuration));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Debounce (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.DebounceDuration = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.DebounceDuration));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Session Duration (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.SessionDuration = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.SessionDuration));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Init Reward (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.InitRewardSize = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.InitRewardSize));

    % Non-block mode parameters
    yPos = yPos - spacing - 10;
    uicontrol('Style', 'text', 'Position', [20 yPos 300 20], ...
        'String', '=== NON-BLOCK MODE (when blocks disabled) ===', ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Default Delay (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.DefaultDelayDuration = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.DefaultDelayDuration));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Default Reset Seg:', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.DefaultErrorResetSegment = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.DefaultErrorResetSegment));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Default Reward L (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.DefaultRewardLeft = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.DefaultRewardLeft));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', 'Default Reward R (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.DefaultRewardRight = uicontrol('Style', 'edit', ...
        'Position', [230 yPos 100 25], 'String', num2str(S.GUI.DefaultRewardRight));

    BpodSystem.GUIHandles.TimersFig = fig;
end


function CreateBlockDesignGUI(S)
    global BpodSystem

    fig = figure('Name', 'Block Design', ...
        'NumberTitle', 'off', ...
        'Position', [600, 200, 600, 500], ...
        'MenuBar', 'none', ...
        'Resize', 'off');

    yPos = 460;
    spacing = 35;

    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Blocks Enabled:', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.BlocksEnabled = uicontrol('Style', 'checkbox', ...
        'Position', [180 yPos 20 20], 'Value', S.GUI.BlocksEnabled);

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Block Size:', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.BlockSize = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.BlockSize));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Num Blocks:', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.NumBlocks = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.NumBlocks));

    % Block 1
    yPos = yPos - spacing - 10;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', '=== BLOCK 1 ===', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Delay (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block1_DelayDuration = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.Block1_DelayDuration));

    uicontrol('Style', 'text', 'Position', [280 yPos 150 20], ...
        'String', 'Reset Seg:', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block1_ErrorResetSegment = uicontrol('Style', 'edit', ...
        'Position', [440 yPos 80 25], 'String', num2str(S.GUI.Block1_ErrorResetSegment));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Reward L (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block1_RewardLeft = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.Block1_RewardLeft));

    uicontrol('Style', 'text', 'Position', [280 yPos 150 20], ...
        'String', 'Reward R (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block1_RewardRight = uicontrol('Style', 'edit', ...
        'Position', [440 yPos 80 25], 'String', num2str(S.GUI.Block1_RewardRight));

    % Block 2
    yPos = yPos - spacing - 10;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', '=== BLOCK 2 ===', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Delay (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block2_DelayDuration = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.Block2_DelayDuration));

    uicontrol('Style', 'text', 'Position', [280 yPos 150 20], ...
        'String', 'Reset Seg:', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block2_ErrorResetSegment = uicontrol('Style', 'edit', ...
        'Position', [440 yPos 80 25], 'String', num2str(S.GUI.Block2_ErrorResetSegment));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Reward L (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block2_RewardLeft = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.Block2_RewardLeft));

    uicontrol('Style', 'text', 'Position', [280 yPos 150 20], ...
        'String', 'Reward R (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block2_RewardRight = uicontrol('Style', 'edit', ...
        'Position', [440 yPos 80 25], 'String', num2str(S.GUI.Block2_RewardRight));

    % Block 3
    yPos = yPos - spacing - 10;
    uicontrol('Style', 'text', 'Position', [20 yPos 200 20], ...
        'String', '=== BLOCK 3 ===', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Delay (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block3_DelayDuration = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.Block3_DelayDuration));

    uicontrol('Style', 'text', 'Position', [280 yPos 150 20], ...
        'String', 'Reset Seg:', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block3_ErrorResetSegment = uicontrol('Style', 'edit', ...
        'Position', [440 yPos 80 25], 'String', num2str(S.GUI.Block3_ErrorResetSegment));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Reward L (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block3_RewardLeft = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 80 25], 'String', num2str(S.GUI.Block3_RewardLeft));

    uicontrol('Style', 'text', 'Position', [280 yPos 150 20], ...
        'String', 'Reward R (s):', 'HorizontalAlignment', 'left');
    BpodSystem.GUIHandles.Block3_RewardRight = uicontrol('Style', 'edit', ...
        'Position', [440 yPos 80 25], 'String', num2str(S.GUI.Block3_RewardRight));

    BpodSystem.GUIHandles.BlockDesignFig = fig;
end


function CreateMotorControlGUI(S)
    global BpodSystem

    if ~S.GUI.ZaberEnabled
        return;
    end

    if isfield(BpodSystem.GUIHandles, 'MotorControlFig') && ishandle(BpodSystem.GUIHandles.MotorControlFig)
        figure(BpodSystem.GUIHandles.MotorControlFig);
        return;
    end

    fig = figure('Name', 'Motor Control', ...
        'NumberTitle', 'off', ...
        'Position', [1250, 300, 400, 350], ...
        'MenuBar', 'none', ...
        'Resize', 'off');

    yPos = 300;
    spacing = 60;

    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Z Lickable:', 'HorizontalAlignment', 'left');
    h_z = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Z_motor_pos));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Move', ...
        'Callback', @(~,~) MoveMotor_Z(h_z));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Z Retract:', 'HorizontalAlignment', 'left');
    h_zr = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Z_NonLickable));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Move', ...
        'Callback', @(~,~) MoveMotor_Z(h_zr));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Lx:', 'HorizontalAlignment', 'left');
    h_lx = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Lx_motor_pos));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Move', ...
        'Callback', @(~,~) MoveMotor_Lx(h_lx));

    yPos = yPos - spacing;
    uicontrol('Style', 'text', 'Position', [20 yPos 150 20], ...
        'String', 'Ly:', 'HorizontalAlignment', 'left');
    h_ly = uicontrol('Style', 'edit', ...
        'Position', [180 yPos 100 25], ...
        'String', num2str(S.GUI.Ly_motor_pos));
    uicontrol('Style', 'pushbutton', 'Position', [290 yPos 80 25], ...
        'String', 'Move', ...
        'Callback', @(~,~) MoveMotor_Ly(h_ly));

    BpodSystem.GUIHandles.MotorControlFig = fig;
end


function MoveMotor_Z(editHandle)
    global motors_properties
    position = str2double(get(editHandle, 'String'));
    if ~isnan(position)
        Motor_Move(position, motors_properties.Z_motor_num);
        disp(['Z moved to ' num2str(round(position))]);
    end
end

function MoveMotor_Lx(editHandle)
    global motors_properties
    position = str2double(get(editHandle, 'String'));
    if ~isnan(position)
        Motor_Move(position, motors_properties.Lx_motor_num);
        disp(['Lx moved to ' num2str(round(position))]);
    end
end

function MoveMotor_Ly(editHandle)
    global motors_properties
    position = str2double(get(editHandle, 'String'));
    if ~isnan(position)
        Motor_Move(position, motors_properties.Ly_motor_num);
        disp(['Ly moved to ' num2str(round(position))]);
    end
end


function CloseAllGUIWindows()
    global BpodSystem

    try
        if isfield(BpodSystem.GUIHandles, 'TimersFig') && ishandle(BpodSystem.GUIHandles.TimersFig)
            close(BpodSystem.GUIHandles.TimersFig);
            disp('Timers GUI closed');
        end

        if isfield(BpodSystem.GUIHandles, 'BlockDesignFig') && ishandle(BpodSystem.GUIHandles.BlockDesignFig)
            close(BpodSystem.GUIHandles.BlockDesignFig);
            disp('Block Design GUI closed');
        end

        if isfield(BpodSystem.GUIHandles, 'MotorControlFig') && ishandle(BpodSystem.GUIHandles.MotorControlFig)
            close(BpodSystem.GUIHandles.MotorControlFig);
            disp('Motor Control GUI closed');
        end
    catch ME
        warning('Error closing GUI windows: %s', ME.message);
    end
end


function S = SyncAllGUIParameters()
    global BpodSystem

    S = BpodSystem.ProtocolSettings;

    try
        if isfield(BpodSystem.GUIHandles, 'ResponseDuration') && ishandle(BpodSystem.GUIHandles.ResponseDuration)
            S.GUI.ResponseDuration = str2double(get(BpodSystem.GUIHandles.ResponseDuration, 'String'));
            S.GUI.BurstIgnoreDuration = str2double(get(BpodSystem.GUIHandles.BurstIgnoreDuration, 'String'));
            S.GUI.DebounceDuration = str2double(get(BpodSystem.GUIHandles.DebounceDuration, 'String'));
            S.GUI.SessionDuration = str2double(get(BpodSystem.GUIHandles.SessionDuration, 'String'));
            S.GUI.InitRewardSize = str2double(get(BpodSystem.GUIHandles.InitRewardSize, 'String'));

            % Non-block parameters
            S.GUI.DefaultDelayDuration = str2double(get(BpodSystem.GUIHandles.DefaultDelayDuration, 'String'));
            S.GUI.DefaultErrorResetSegment = str2double(get(BpodSystem.GUIHandles.DefaultErrorResetSegment, 'String'));
            S.GUI.DefaultRewardLeft = str2double(get(BpodSystem.GUIHandles.DefaultRewardLeft, 'String'));
            S.GUI.DefaultRewardRight = str2double(get(BpodSystem.GUIHandles.DefaultRewardRight, 'String'));
        end

        if isfield(BpodSystem.GUIHandles, 'BlocksEnabled') && ishandle(BpodSystem.GUIHandles.BlocksEnabled)
            S.GUI.BlocksEnabled = get(BpodSystem.GUIHandles.BlocksEnabled, 'Value');
            S.GUI.BlockSize = str2double(get(BpodSystem.GUIHandles.BlockSize, 'String'));
            S.GUI.NumBlocks = str2double(get(BpodSystem.GUIHandles.NumBlocks, 'String'));

            S.GUI.Block1_DelayDuration = str2double(get(BpodSystem.GUIHandles.Block1_DelayDuration, 'String'));
            S.GUI.Block1_ErrorResetSegment = str2double(get(BpodSystem.GUIHandles.Block1_ErrorResetSegment, 'String'));
            S.GUI.Block1_RewardLeft = str2double(get(BpodSystem.GUIHandles.Block1_RewardLeft, 'String'));
            S.GUI.Block1_RewardRight = str2double(get(BpodSystem.GUIHandles.Block1_RewardRight, 'String'));

            S.GUI.Block2_DelayDuration = str2double(get(BpodSystem.GUIHandles.Block2_DelayDuration, 'String'));
            S.GUI.Block2_ErrorResetSegment = str2double(get(BpodSystem.GUIHandles.Block2_ErrorResetSegment, 'String'));
            S.GUI.Block2_RewardLeft = str2double(get(BpodSystem.GUIHandles.Block2_RewardLeft, 'String'));
            S.GUI.Block2_RewardRight = str2double(get(BpodSystem.GUIHandles.Block2_RewardRight, 'String'));

            S.GUI.Block3_DelayDuration = str2double(get(BpodSystem.GUIHandles.Block3_DelayDuration, 'String'));
            S.GUI.Block3_ErrorResetSegment = str2double(get(BpodSystem.GUIHandles.Block3_ErrorResetSegment, 'String'));
            S.GUI.Block3_RewardLeft = str2double(get(BpodSystem.GUIHandles.Block3_RewardLeft, 'String'));
            S.GUI.Block3_RewardRight = str2double(get(BpodSystem.GUIHandles.Block3_RewardRight, 'String'));
        end
    catch ME
        warning('Error syncing GUI parameters: %s', ME.message);
    end

    BpodSystem.ProtocolSettings = S;
end


%% Block Management

function [BlockSequence, BlockParams] = GenerateBlockSequence(S)
    if ~S.GUI.BlocksEnabled
        % Non-block mode: use default parameters
        BlockSequence = ones(1, S.GUI.NumBlocks);
        BlockParams = struct();
        for i = 1:S.GUI.NumBlocks
            BlockParams(i).BlockType = 1;
            BlockParams(i).DelayDuration = S.GUI.DefaultDelayDuration;
            BlockParams(i).ErrorResetSegment = S.GUI.DefaultErrorResetSegment;
            BlockParams(i).RewardLeft = S.GUI.DefaultRewardLeft;
            BlockParams(i).RewardRight = S.GUI.DefaultRewardRight;
        end
        return;
    end

    % Block mode: use defined blocks
    maxBlockTypes = 10;
    numBlockTypes = 0;
    for i = 1:maxBlockTypes
        if isfield(S.GUI, sprintf('Block%d_DelayDuration', i))
            numBlockTypes = i;
        else
            break;
        end
    end

    if numBlockTypes == 0
        error('No block types defined');
    end

    numBlocks = S.GUI.NumBlocks;
    BlockSequence = [];
    fullCycles = floor(numBlocks / numBlockTypes);
    remainder = mod(numBlocks, numBlockTypes);

    for cycle = 1:fullCycles
        BlockSequence = [BlockSequence, randperm(numBlockTypes)];
    end

    if remainder > 0
        BlockSequence = [BlockSequence, randperm(numBlockTypes, remainder)];
    end

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
    currentBlock = ceil(trialNumber / blockSize);

    if currentBlock > totalBlocks
        currentBlock = mod(currentBlock - 1, totalBlocks) + 1;
    end

    trialInBlock = mod(trialNumber - 1, blockSize) + 1;
end


%% Motor Functions

function Motor_Move(position, motor_num)
    global motors;

    if isnumeric(position)
        move_absolute(motors, position, motor_num);
    elseif ischar(position)
        position = str2num(position);
        if isempty(position)
            move_absolute(motors, 0, motor_num);
        else
            move_absolute(motors, position, motor_num);
        end
    end
end


function MySoftCodeHandler(code)
    global BpodSystem motors_properties

    if ~BpodSystem.ProtocolSettings.GUI.ZaberEnabled
        return;
    end

    try
        S = BpodSystem.ProtocolSettings;

        switch code
            case 1
                Motor_Move(S.GUI.Z_motor_pos, motors_properties.Z_motor_num);
            case 2
                Motor_Move(S.GUI.Z_NonLickable, motors_properties.Z_motor_num);
        end

    catch ME
        warning('Soft code error: %s', ME.message);
    end
end
