function reward_2d_lickport_protocol_v2
% Modified BPOD protocol for 2-port lick-triggered reward task
% No lickport movement - both ports stationary and active throughout session
%
% CORRECTED Task Design:
% - TRIAL = From entering one Response Period to entering the next Response Period
% - Wait Period: Minimum 2 seconds before response period can start
% - Incorrect licks during wait add 3s to REMAINING wait time (within same trial)
% - Licks within 0.5s count as single burst (only one 3s penalty)
% - Maximum remaining wait time capped at 15 seconds
% - Response Period: Starts when mouse licks either port after wait completes
%   - Duration: 3 seconds
%   - Only the first-licked port gives water during that response period
%   - Each lick triggers 0.01s water bolus
% - No missed trials - mouse can wait indefinitely after wait period expires

global BpodSystem;

%% Define water outputs for both ports
Port1WaterOutput = {'ValveState', 2^0}; % Port 1 - Valve 1
Port2WaterOutput = {'ValveState', 2^1}; % Port 2 - Valve 2

Camera_FPS = 250; % TTL pulses for camera
MaxTrials = 99999; % Essentially unlimited - manual stop only

%% Load or Initialize Settings
S = BpodSystem.ProtocolSettings;
if isempty(fieldnames(S))
    % Basic reward parameters
    S.GUI.WaterValveTime = 0.01;           % Water bolus per lick (seconds)
    S.GUI.MinWaitPeriod = 2;               % Minimum wait between response periods (seconds)
    S.GUI.ResponsePeriodDuration = 3;      % Duration of response period (seconds)
    S.GUI.IncorrectLickPenalty = 3;        % Penalty added per lick burst (seconds)
    S.GUI.LickBurstWindow = 0.5;           % Time window to group licks as single burst (seconds)
    S.GUI.MaxWaitTime = 15;                % Maximum remaining wait time (seconds)
    S.GUI.WaitTimeIncrement = 0.5;         % Time increment for wait states (seconds)

    S.GUIPanels.TaskParameters = {'WaterValveTime', 'MinWaitPeriod', 'ResponsePeriodDuration', ...
                                   'IncorrectLickPenalty', 'LickBurstWindow', 'MaxWaitTime', 'WaitTimeIncrement'};
end

%% Initialize BpodParameterGUI
BpodParameterGUI('init', S);

%% Initialize Data Storage
BpodSystem.Data.TrialTypes = [];          % 1=Port1 response, 2=Port2 response
BpodSystem.Data.TrialOutcome = [];        % 1=successful response
BpodSystem.Data.ActualWaitDuration = [];  % Actual total wait time for each trial
BpodSystem.Data.ResponsePort = [];        % Which port was chosen (1 or 2)
BpodSystem.Data.NumLicksInResponse = [];  % Number of licks during response period
BpodSystem.Data.TotalWaterDelivered = []; % Total water per trial (seconds)
BpodSystem.Data.NumIncorrectLickBursts = []; % Number of incorrect lick bursts per trial
BpodSystem.Data.MinimumWaitAtStart = [];  % Starting minimum wait for trial

%% Initialize plots
BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [200 200 1000 400], ...
    'Name', 'Lick-triggered Task Outcome', 'NumberTitle', 'off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]);
LickTaskOutcomePlot(BpodSystem.GUIHandles.OutcomePlot, 'init');

%% Pause before starting
BpodSystem.Status.Pause = 1;
HandlePauseCondition;

%% Main trial loop
for currentTrial = 1:MaxTrials
    S = BpodParameterGUI('sync', S); % Sync parameters with GUI

    disp(['Starting trial ', num2str(currentTrial)]);

    %% Determine starting wait duration for this trial
    if currentTrial == 1
        % First trial starts immediately
        initial_wait = 0;
    else
        % Subsequent trials: minimum 2s wait
        initial_wait = S.GUI.MinWaitPeriod;
    end

    BpodSystem.Data.MinimumWaitAtStart(currentTrial) = initial_wait;

    %% Build state machine
    sma = NewStateMachine();

    % Global timer for camera triggers (continuous)
    sma = SetGlobalTimer(sma, 'TimerID', 1, 'Duration', 1/(2*Camera_FPS), 'OnsetDelay', 0, ...
                         'Channel', 'BNC1', 'OnLevel', 1, 'OffLevel', 0, ...
                         'Loop', 1, 'SendGlobalTimerEvents', 0, 'LoopInterval', 1/(2*Camera_FPS));

    % Global timer for response period (3 seconds)
    sma = SetGlobalTimer(sma, 'TimerID', 2, 'Duration', S.GUI.ResponsePeriodDuration, ...
                         'OnsetDelay', 0, 'SendGlobalTimerEvents', 1);

    % Start camera trigger
    sma = AddState(sma, 'Name', 'TimerTrig', ...
        'Timer', 0, ...
        'StateChangeConditions', {'Tup', 'StartBitcode'}, ...
        'OutputActions', {'GlobalTimerTrig', '1'});

    %% Generate and send bitcode for trial number
    time_period = 0.02;
    digits = 20;

    % Start bitcode
    sma = AddState(sma, 'Name', 'StartBitcode', ...
        'Timer', time_period * 3, ...
        'StateChangeConditions', {'Tup', 'OffState1'}, ...
        'OutputActions', {'BNC2', 1});

    % Generate random trial ID
    random_number = floor(rand() * (2^digits - 1));
    bitcode = dec2bin(random_number, digits);
    BpodSystem.Data.bitcode{currentTrial} = bitcode;

    % Bitcode transmission states
    for digit = 1:digits
        sma = AddState(sma, 'Name', ['OffState', int2str(digit)], ...
            'Timer', time_period, ...
            'StateChangeConditions', {'Tup', ['OnState', int2str(digit)]}, ...
            'OutputActions', {});

        bit = {};
        if bitcode(digit) == '1'
            bit = {'BNC2', 1};
        end

        sma = AddState(sma, 'Name', ['OnState', int2str(digit)], ...
            'Timer', time_period, ...
            'StateChangeConditions', {'Tup', ['OffState', int2str(digit + 1)]}, ...
            'OutputActions', bit);
    end

    sma = AddState(sma, 'Name', ['OffState', int2str(digits + 1)], ...
        'Timer', time_period, ...
        'StateChangeConditions', {'Tup', 'EndBitcode'}, ...
        'OutputActions', {});

    % End bitcode
    sma = AddState(sma, 'Name', 'EndBitcode', ...
        'Timer', time_period * 3, ...
        'StateChangeConditions', {'Tup', 'StartWait'}, ...
        'OutputActions', {'BNC2', 1});

    % Brief state before wait
    sma = AddState(sma, 'Name', 'StartWait', ...
        'Timer', 0.001, ...
        'StateChangeConditions', {'Tup', 'WaitPeriodRouter'}, ...
        'OutputActions', {});

    %% Wait Period States - Using time-sliced approach
    % Create wait states from 0s to MaxWaitTime in WaitTimeIncrement steps
    % Each state has duration = WaitTimeIncrement
    % On Tup: go to next lower remaining time state
    % On lick: add IncorrectLickPenalty seconds (jump forward), capped at MaxWaitTime

    time_increment = S.GUI.WaitTimeIncrement;
    max_wait = S.GUI.MaxWaitTime;
    penalty = S.GUI.IncorrectLickPenalty;
    burst_window = S.GUI.LickBurstWindow;

    % Calculate number of states needed
    num_wait_states = round(max_wait / time_increment) + 1; % 0, 0.5, 1.0, ..., 15.0

    % Router state to select correct starting wait state
    initial_wait_increments = round(initial_wait / time_increment);
    if initial_wait_increments == 0
        wait_start_state = 'ReadyForResponse';
    else
        wait_start_state = sprintf('Wait_%.1fs', initial_wait);
    end

    sma = AddState(sma, 'Name', 'WaitPeriodRouter', ...
        'Timer', 0.001, ...
        'StateChangeConditions', {'Tup', wait_start_state}, ...
        'OutputActions', {});

    % Create wait states in descending order (from max to min)
    for i = num_wait_states:-1:1
        remaining_time = (i - 1) * time_increment; % 15.0, 14.5, ..., 0.5, 0
        state_name = sprintf('Wait_%.1fs', remaining_time);

        if remaining_time <= time_increment
            % Last increment - next state is ready for response
            next_state = 'ReadyForResponse';
            state_timer = remaining_time;
            if state_timer < 0.001
                state_timer = 0.001;
            end
        else
            % Next state is one increment less
            next_remaining = remaining_time - time_increment;
            next_state = sprintf('Wait_%.1fs', next_remaining);
            state_timer = time_increment;
        end

        % On lick, go to ignore burst state for this level
        ignore_state = sprintf('IgnoreBurst_from_%.1fs', remaining_time);

        sma = AddState(sma, 'Name', state_name, ...
            'Timer', state_timer, ...
            'StateChangeConditions', {'Tup', next_state, ...
                                     'Port1In', ignore_state, ...
                                     'Port2In', ignore_state}, ...
            'OutputActions', {});
    end

    % Create ignore burst states
    for i = 1:num_wait_states
        remaining_time = (i - 1) * time_increment;
        ignore_state = sprintf('IgnoreBurst_from_%.1fs', remaining_time);

        % After burst window, add penalty to remaining time (capped at max)
        new_remaining = min(max_wait, remaining_time + penalty);
        next_wait_state = sprintf('Wait_%.1fs', new_remaining);

        sma = AddState(sma, 'Name', ignore_state, ...
            'Timer', burst_window, ...
            'StateChangeConditions', {'Tup', next_wait_state}, ...
            'OutputActions', {});
    end

    %% Ready for Response State
    % Wait indefinitely for first lick on either port
    sma = AddState(sma, 'Name', 'ReadyForResponse', ...
        'Timer', 3600, ...  % Essentially infinite
        'StateChangeConditions', {'Port1In', 'ResponsePeriod_Port1_Start', ...
                                 'Port2In', 'ResponsePeriod_Port2_Start'}, ...
        'OutputActions', {});

    %% Response Period - Port 1
    sma = AddState(sma, 'Name', 'ResponsePeriod_Port1_Start', ...
        'Timer', 0.001, ...
        'StateChangeConditions', {'Tup', 'GiveWater_Port1_First'}, ...
        'OutputActions', {'GlobalTimerTrig', '2'});

    sma = AddState(sma, 'Name', 'GiveWater_Port1_First', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port1', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port1WaterOutput);

    sma = AddState(sma, 'Name', 'ResponsePeriod_Port1', ...
        'Timer', S.GUI.ResponsePeriodDuration, ...
        'StateChangeConditions', {'Port1In', 'GiveWater_Port1', ...
                                 'GlobalTimer2_End', 'TrialEnd', ...
                                 'Tup', 'TrialEnd'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'GiveWater_Port1', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port1', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port1WaterOutput);

    %% Response Period - Port 2
    sma = AddState(sma, 'Name', 'ResponsePeriod_Port2_Start', ...
        'Timer', 0.001, ...
        'StateChangeConditions', {'Tup', 'GiveWater_Port2_First'}, ...
        'OutputActions', {'GlobalTimerTrig', '2'});

    sma = AddState(sma, 'Name', 'GiveWater_Port2_First', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port2', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port2WaterOutput);

    sma = AddState(sma, 'Name', 'ResponsePeriod_Port2', ...
        'Timer', S.GUI.ResponsePeriodDuration, ...
        'StateChangeConditions', {'Port2In', 'GiveWater_Port2', ...
                                 'GlobalTimer2_End', 'TrialEnd', ...
                                 'Tup', 'TrialEnd'}, ...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'GiveWater_Port2', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port2', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port2WaterOutput);

    %% Trial End
    sma = AddState(sma, 'Name', 'TrialEnd', ...
        'Timer', 0.01, ...
        'StateChangeConditions', {'Tup', 'exit'}, ...
        'OutputActions', {'GlobalTimerCancel', '1'});

    %% Send state machine and run
    SendStateMachine(sma);
    RawEvents = RunStateMachine;

    %% Process trial data
    if ~isempty(fieldnames(RawEvents))
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;

        % Determine trial outcome
        all_states = fieldnames(RawEvents.States);

        % Determine which port was chosen
        if any(contains(all_states, 'ResponsePeriod_Port1'))
            response_port = 1;
            trial_outcome = 1;
        elseif any(contains(all_states, 'ResponsePeriod_Port2'))
            response_port = 2;
            trial_outcome = 1;
        else
            % Should not happen
            response_port = 0;
            trial_outcome = 0;
        end

        % Count incorrect lick bursts (number of IgnoreBurst states visited)
        ignore_burst_states = all_states(contains(all_states, 'IgnoreBurst'));
        num_incorrect_bursts = length(ignore_burst_states);

        % Calculate actual wait duration
        if isfield(RawEvents.States, 'ReadyForResponse')
            ready_time = RawEvents.States.ReadyForResponse(1);
        else
            ready_time = 0;
        end

        if response_port == 1 && isfield(RawEvents.States, 'ResponsePeriod_Port1_Start')
            response_start = RawEvents.States.ResponsePeriod_Port1_Start(1);
        elseif response_port == 2 && isfield(RawEvents.States, 'ResponsePeriod_Port2_Start')
            response_start = RawEvents.States.ResponsePeriod_Port2_Start(1);
        else
            response_start = ready_time;
        end

        actual_wait = response_start - time_period; % Subtract bitcode time

        % Count licks during response period
        if response_port == 1
            if isfield(RawEvents.Events, 'Port1In')
                lick_times = RawEvents.Events.Port1In;
                response_start_time = RawEvents.States.ResponsePeriod_Port1_Start(1);
                response_end_time = response_start_time + S.GUI.ResponsePeriodDuration;
                num_licks = sum(lick_times >= response_start_time & lick_times <= response_end_time);
            else
                num_licks = 1;
            end
        elseif response_port == 2
            if isfield(RawEvents.Events, 'Port2In')
                lick_times = RawEvents.Events.Port2In;
                response_start_time = RawEvents.States.ResponsePeriod_Port2_Start(1);
                response_end_time = response_start_time + S.GUI.ResponsePeriodDuration;
                num_licks = sum(lick_times >= response_start_time & lick_times <= response_end_time);
            else
                num_licks = 1;
            end
        else
            num_licks = 0;
        end

        total_water = num_licks * S.GUI.WaterValveTime;

        % Store trial data
        BpodSystem.Data.TrialOutcome(currentTrial) = trial_outcome;
        BpodSystem.Data.ResponsePort(currentTrial) = response_port;
        BpodSystem.Data.ActualWaitDuration(currentTrial) = actual_wait;
        BpodSystem.Data.NumLicksInResponse(currentTrial) = num_licks;
        BpodSystem.Data.TotalWaterDelivered(currentTrial) = total_water;
        BpodSystem.Data.NumIncorrectLickBursts(currentTrial) = num_incorrect_bursts;
        BpodSystem.Data.TrialTypes(currentTrial) = response_port;

        % Display trial summary
        fprintf('Trial %d: Port %d | Wait: %.2fs | Incorrect bursts: %d | Licks: %d | Water: %.3fs\n', ...
            currentTrial, response_port, actual_wait, num_incorrect_bursts, num_licks, total_water);

        % Update outcome plot
        LickTaskOutcomePlot(BpodSystem.GUIHandles.OutcomePlot, 'update', currentTrial, ...
            BpodSystem.Data.TrialTypes, BpodSystem.Data.TrialOutcome);

        % Save data
        SaveBpodSessionData;
    end

    % Handle pause/stop
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        return;
    end
end

end  % End of main function


%% Outcome plot function
function LickTaskOutcomePlot(AxesHandle, Action, varargin)
    global BpodSystem

    switch Action
        case 'init'
            % Initialize plot
            axes(AxesHandle);
            hold on;
            set(AxesHandle, 'TickDir', 'out', 'YLim', [0.5, 2.5], 'YTick', [1, 2], ...
                'YTickLabel', {'Port 1', 'Port 2'});
            xlabel('Trial Number', 'FontSize', 12);
            ylabel('Response Port', 'FontSize', 12);
            title('Lick-Triggered Task Performance', 'FontSize', 14);

        case 'update'
            % Update plot with new trial
            currentTrial = varargin{1};
            trialTypes = varargin{2};
            trialOutcomes = varargin{3};

            axes(AxesHandle);

            % Plot trial outcome
            if trialTypes(currentTrial) == 1
                % Port 1 response
                plot(currentTrial, 1, 'go', 'MarkerSize', 8, 'LineWidth', 2);
            elseif trialTypes(currentTrial) == 2
                % Port 2 response
                plot(currentTrial, 2, 'bo', 'MarkerSize', 8, 'LineWidth', 2);
            end

            % Update x-axis limits
            set(AxesHandle, 'XLim', [max(1, currentTrial - 100), currentTrial + 10]);
    end
end
