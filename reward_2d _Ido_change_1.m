function reward_2d_lickport_protocol
% Modified BPOD protocol for 2-port lick-triggered reward task
% No lickport movement - both ports stationary and active throughout session
%
% Task Design:
% - Wait Period: Minimum 2 seconds between response periods
% - Incorrect licks during wait add 3s penalty (licks within 0.5s = 1 burst)
% - Maximum remaining wait time capped at 15 seconds
% - Response Period: Starts when mouse licks either port after wait completes
%   - Duration: 3 seconds
%   - Only the first-licked port gives water during that response period
%   - Each lick triggers 0.01s water bolus
% - No missed trials - mouse can wait indefinitely

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

    S.GUIPanels.TaskParameters = {'WaterValveTime', 'MinWaitPeriod', 'ResponsePeriodDuration', ...
                                   'IncorrectLickPenalty', 'LickBurstWindow', 'MaxWaitTime'};
end

%% Initialize BpodParameterGUI
BpodParameterGUI('init', S);

%% Initialize Data Storage
BpodSystem.Data.TrialTypes = [];          % 1=Port1 response, 2=Port2 response, 0=wait violated
BpodSystem.Data.TrialOutcome = [];        % 1=successful response, 0=wait violated
BpodSystem.Data.WaitDuration = [];        % Actual wait duration for each trial
BpodSystem.Data.ResponsePort = [];        % Which port was chosen (1 or 2, 0 if none)
BpodSystem.Data.NumLicksInResponse = [];  % Number of licks during response period
BpodSystem.Data.TotalWaterDelivered = []; % Total water per trial (seconds)
BpodSystem.Data.IncorrectLicksDuringWait = []; % Number of incorrect lick bursts
BpodSystem.Data.PenaltyTimeAccumulated = []; % Penalty time at start of each trial

%% Initialize penalty tracking (persistent across trials)
penalty_time = 0;  % Accumulated penalty in seconds
last_trial_outcome = 1; % 1=successful, 0=wait violated

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

    %% Calculate wait duration for this trial
    if currentTrial == 1
        % First trial starts immediately
        wait_duration = 0;
    else
        % Subsequent trials: minimum 2s + any accumulated penalty (capped at 15s)
        wait_duration = min(S.GUI.MaxWaitTime, S.GUI.MinWaitPeriod + penalty_time);
    end

    % Store penalty at trial start
    BpodSystem.Data.PenaltyTimeAccumulated(currentTrial) = penalty_time;
    BpodSystem.Data.WaitDuration(currentTrial) = wait_duration;

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

    %% Generate and send bitcode for trial number (for sync with external systems)
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
        'StateChangeConditions', {'Tup', 'PreWait'}, ...
        'OutputActions', {'BNC2', 1});

    % Brief pre-wait state
    sma = AddState(sma, 'Name', 'PreWait', ...
        'Timer', 0.001, ...
        'StateChangeConditions', {'Tup', 'WaitPeriod'}, ...
        'OutputActions', {});

    %% Wait Period State
    % Monitor both ports - any lick triggers penalty
    if wait_duration > 0
        sma = AddState(sma, 'Name', 'WaitPeriod', ...
            'Timer', wait_duration, ...
            'StateChangeConditions', {'Port1In', 'IncorrectLick', 'Port2In', 'IncorrectLick', ...
                                     'Tup', 'ReadyForResponse'}, ...
            'OutputActions', {});

        % Incorrect lick detected - start burst ignore period
        sma = AddState(sma, 'Name', 'IncorrectLick', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'LickBurstIgnore'}, ...
            'OutputActions', {});

        % Ignore additional licks in the burst (0.5s window)
        sma = AddState(sma, 'Name', 'LickBurstIgnore', ...
            'Timer', S.GUI.LickBurstWindow, ...
            'StateChangeConditions', {'Tup', 'TrialEnd'}, ...
            'OutputActions', {});
    else
        % Skip wait period if duration is 0 (first trial)
        sma = AddState(sma, 'Name', 'WaitPeriod', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'ReadyForResponse'}, ...
            'OutputActions', {});

        % Dummy states (won't be reached)
        sma = AddState(sma, 'Name', 'IncorrectLick', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'TrialEnd'}, ...
            'OutputActions', {});

        sma = AddState(sma, 'Name', 'LickBurstIgnore', ...
            'Timer', 0.001, ...
            'StateChangeConditions', {'Tup', 'TrialEnd'}, ...
            'OutputActions', {});
    end

    %% Ready for Response State
    % Wait indefinitely for first lick on either port
    sma = AddState(sma, 'Name', 'ReadyForResponse', ...
        'Timer', 3600, ...  % Essentially infinite - mouse can't "miss"
        'StateChangeConditions', {'Port1In', 'ResponsePeriod_Port1_Start', ...
                                 'Port2In', 'ResponsePeriod_Port2_Start'}, ...
        'OutputActions', {});

    %% Response Period - Port 1
    % Start response period timer for Port 1
    sma = AddState(sma, 'Name', 'ResponsePeriod_Port1_Start', ...
        'Timer', 0.001, ...
        'StateChangeConditions', {'Tup', 'GiveWater_Port1_First'}, ...
        'OutputActions', {'GlobalTimerTrig', '2'});

    % Give water for the first lick that triggered response period
    sma = AddState(sma, 'Name', 'GiveWater_Port1_First', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port1', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port1WaterOutput);

    % Response period active - wait for more licks on Port 1
    sma = AddState(sma, 'Name', 'ResponsePeriod_Port1', ...
        'Timer', S.GUI.ResponsePeriodDuration, ...
        'StateChangeConditions', {'Port1In', 'GiveWater_Port1', ...
                                 'GlobalTimer2_End', 'TrialEnd', ...
                                 'Tup', 'TrialEnd'}, ...
        'OutputActions', {});

    % Give water for subsequent licks on Port 1
    sma = AddState(sma, 'Name', 'GiveWater_Port1', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port1', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port1WaterOutput);

    %% Response Period - Port 2
    % Start response period timer for Port 2
    sma = AddState(sma, 'Name', 'ResponsePeriod_Port2_Start', ...
        'Timer', 0.001, ...
        'StateChangeConditions', {'Tup', 'GiveWater_Port2_First'}, ...
        'OutputActions', {'GlobalTimerTrig', '2'});

    % Give water for the first lick that triggered response period
    sma = AddState(sma, 'Name', 'GiveWater_Port2_First', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port2', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port2WaterOutput);

    % Response period active - wait for more licks on Port 2
    sma = AddState(sma, 'Name', 'ResponsePeriod_Port2', ...
        'Timer', S.GUI.ResponsePeriodDuration, ...
        'StateChangeConditions', {'Port2In', 'GiveWater_Port2', ...
                                 'GlobalTimer2_End', 'TrialEnd', ...
                                 'Tup', 'TrialEnd'}, ...
        'OutputActions', {});

    % Give water for subsequent licks on Port 2
    sma = AddState(sma, 'Name', 'GiveWater_Port2', ...
        'Timer', S.GUI.WaterValveTime, ...
        'StateChangeConditions', {'Tup', 'ResponsePeriod_Port2', 'GlobalTimer2_End', 'TrialEnd'}, ...
        'OutputActions', Port2WaterOutput);

    %% Trial End
    sma = AddState(sma, 'Name', 'TrialEnd', ...
        'Timer', 0.01, ...
        'StateChangeConditions', {'Tup', 'exit'}, ...
        'OutputActions', {'GlobalTimerCancel', '1'});

    %% Send state machine to Bpod
    SendStateMachine(sma);
    RawEvents = RunStateMachine;

    %% Process trial data
    if ~isempty(fieldnames(RawEvents))
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents);
        BpodSystem.Data.TrialSettings(currentTrial) = S;

        % Determine trial outcome
        visited_states = {RawEvents.States};

        % Check if wait period was violated
        if any(strcmp(visited_states, 'IncorrectLick'))
            % Wait violated - add penalty
            trial_outcome = 0;
            penalty_time = min(S.GUI.MaxWaitTime, penalty_time + S.GUI.IncorrectLickPenalty);
            response_port = 0;
            num_licks = 0;
            total_water = 0;
            incorrect_licks = 1;

            disp(['Trial ', num2str(currentTrial), ': Wait violated. Penalty = ', num2str(penalty_time), 's']);

        elseif any(strcmp(visited_states, 'ResponsePeriod_Port1')) || ...
               any(strcmp(visited_states, 'GiveWater_Port1_First'))
            % Successful response on Port 1
            trial_outcome = 1;
            penalty_time = 0;  % Reset penalty after successful response
            response_port = 1;
            incorrect_licks = 0;

            % Count licks during response period
            if isfield(RawEvents.Events, 'Port1In')
                lick_times = RawEvents.Events.Port1In;
                % Find response period start time
                if isfield(RawEvents.States, 'ResponsePeriod_Port1_Start')
                    response_start = RawEvents.States.ResponsePeriod_Port1_Start(1);
                    response_end = response_start + S.GUI.ResponsePeriodDuration;
                    num_licks = sum(lick_times >= response_start & lick_times <= response_end);
                else
                    num_licks = length(lick_times);
                end
            else
                num_licks = 1;  % At least one lick to trigger response
            end

            total_water = num_licks * S.GUI.WaterValveTime;
            disp(['Trial ', num2str(currentTrial), ': Port 1 response. Licks = ', num2str(num_licks), ', Water = ', num2str(total_water), 's']);

        elseif any(strcmp(visited_states, 'ResponsePeriod_Port2')) || ...
               any(strcmp(visited_states, 'GiveWater_Port2_First'))
            % Successful response on Port 2
            trial_outcome = 1;
            penalty_time = 0;  % Reset penalty after successful response
            response_port = 2;
            incorrect_licks = 0;

            % Count licks during response period
            if isfield(RawEvents.Events, 'Port2In')
                lick_times = RawEvents.Events.Port2In;
                % Find response period start time
                if isfield(RawEvents.States, 'ResponsePeriod_Port2_Start')
                    response_start = RawEvents.States.ResponsePeriod_Port2_Start(1);
                    response_end = response_start + S.GUI.ResponsePeriodDuration;
                    num_licks = sum(lick_times >= response_start & lick_times <= response_end);
                else
                    num_licks = length(lick_times);
                end
            else
                num_licks = 1;  % At least one lick to trigger response
            end

            total_water = num_licks * S.GUI.WaterValveTime;
            disp(['Trial ', num2str(currentTrial), ': Port 2 response. Licks = ', num2str(num_licks), ', Water = ', num2str(total_water), 's']);

        else
            % Edge case - no response (shouldn't happen with infinite wait)
            trial_outcome = 0;
            response_port = 0;
            num_licks = 0;
            total_water = 0;
            incorrect_licks = 0;
        end

        % Store trial data
        BpodSystem.Data.TrialOutcome(currentTrial) = trial_outcome;
        BpodSystem.Data.ResponsePort(currentTrial) = response_port;
        BpodSystem.Data.NumLicksInResponse(currentTrial) = num_licks;
        BpodSystem.Data.TotalWaterDelivered(currentTrial) = total_water;
        BpodSystem.Data.IncorrectLicksDuringWait(currentTrial) = incorrect_licks;
        BpodSystem.Data.TrialTypes(currentTrial) = response_port;  % 0=wait violated, 1=Port1, 2=Port2

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
            set(AxesHandle, 'TickDir', 'out', 'YLim', [0, 3], 'YTick', [0.5, 1.5, 2.5], ...
                'YTickLabel', {'Wait Violated', 'Port 1', 'Port 2'});
            xlabel('Trial Number', 'FontSize', 12);
            ylabel('Trial Outcome', 'FontSize', 12);
            title('Lick-Triggered Task Performance', 'FontSize', 14);

        case 'update'
            % Update plot with new trial
            currentTrial = varargin{1};
            trialTypes = varargin{2};
            trialOutcomes = varargin{3};

            axes(AxesHandle);

            % Plot trial outcome
            if trialTypes(currentTrial) == 0
                % Wait violated
                plot(currentTrial, 0.5, 'rx', 'MarkerSize', 10, 'LineWidth', 2);
            elseif trialTypes(currentTrial) == 1
                % Port 1 response
                if trialOutcomes(currentTrial) == 1
                    plot(currentTrial, 1.5, 'go', 'MarkerSize', 8, 'LineWidth', 2);
                end
            elseif trialTypes(currentTrial) == 2
                % Port 2 response
                if trialOutcomes(currentTrial) == 1
                    plot(currentTrial, 2.5, 'bo', 'MarkerSize', 8, 'LineWidth', 2);
                end
            end

            % Update x-axis limits
            set(AxesHandle, 'XLim', [max(1, currentTrial - 100), currentTrial + 10]);
    end
end
