function AnalyzeFreeLickingSession(sessionData)
% ANALYZEFREELICKINGSESSION Analyze behavioral data from free licking protocol
%
% Inputs:
%   sessionData - Bpod session data structure or path to .mat file
%
% Outputs:
%   Generates comprehensive analysis plots and prints summary statistics
%
% Usage:
%   AnalyzeFreeLickingSession('SessionData.mat')
%   AnalyzeFreeLickingSession(BpodSystem.Data)

%% Load data if filename provided
if ischar(sessionData) || isstring(sessionData)
    fprintf('Loading session data from: %s\n', sessionData);
    load(sessionData, 'SessionData');
    Data = SessionData;
else
    Data = sessionData;
end

%% Extract trial data
nTrials = length(Data.Outcomes);

if nTrials == 0
    fprintf('No trials found in session data\n');
    return;
end

fprintf('\n=== SESSION ANALYSIS ===\n');
fprintf('Total trials: %d\n', nTrials);

%% Calculate session statistics

% Outcome counts
correctTrials = sum(Data.Outcomes == 1);
errorTrials = sum(Data.Outcomes == 0);
ignoredTrials = sum(Data.Outcomes == -1);
completedTrials = correctTrials + errorTrials;

fprintf('\nOutcomes:\n');
fprintf('  Correct: %d (%.1f%%)\n', correctTrials, 100*correctTrials/nTrials);
fprintf('  Error: %d (%.1f%%)\n', errorTrials, 100*errorTrials/nTrials);
fprintf('  Ignored: %d (%.1f%%)\n', ignoredTrials, 100*ignoredTrials/nTrials);

if completedTrials > 0
    fprintf('  Success rate (completed only): %.1f%%\n', 100*correctTrials/completedTrials);
end

% Port selection
port1Trials = sum(Data.SelectedPort == 1);
port2Trials = sum(Data.SelectedPort == 2);

fprintf('\nPort Selection:\n');
fprintf('  Port 1: %d (%.1f%%)\n', port1Trials, 100*port1Trials/nTrials);
fprintf('  Port 2: %d (%.1f%%)\n', port2Trials, 100*port2Trials/nTrials);

% Licking statistics
totalRewards = sum(Data.ResponseLickCount);
avgRewardsPerTrial = mean(Data.ResponseLickCount);
totalDelayResets = sum(Data.DelayTimerResets);
avgResetsPerTrial = mean(Data.DelayTimerResets);

fprintf('\nLicking Behavior:\n');
fprintf('  Total rewards delivered: %d\n', totalRewards);
fprintf('  Avg rewards per trial: %.2f\n', avgRewardsPerTrial);
fprintf('  Total delay resets: %d\n', totalDelayResets);
fprintf('  Avg resets per trial: %.2f\n', avgResetsPerTrial);

% Trial duration
if isfield(Data, 'TrialStartTime') && isfield(Data, 'TrialEndTime')
    trialDurations = (Data.TrialEndTime - Data.TrialStartTime) * 24 * 60 * 60;  % Convert to seconds
    avgTrialDuration = mean(trialDurations);
    totalSessionTime = sum(trialDurations);

    fprintf('\nTiming:\n');
    fprintf('  Total session time: %.1f minutes\n', totalSessionTime/60);
    fprintf('  Avg trial duration: %.2f seconds\n', avgTrialDuration);
    fprintf('  Trials per minute: %.2f\n', nTrials/(totalSessionTime/60));
end

%% Create analysis figure
figure('Name', 'Free Licking Session Analysis', 'NumberTitle', 'off', ...
    'Position', [100, 100, 1200, 900]);

% Plot 1: Trial outcomes over time
subplot(3, 3, 1);
outcomes = Data.Outcomes;
plot(1:nTrials, outcomes, 'o-', 'MarkerSize', 4);
xlabel('Trial Number');
ylabel('Outcome');
title('Trial Outcomes');
ylim([-1.5 1.5]);
yticks([-1 0 1]);
yticklabels({'Ignore', 'Error', 'Correct'});
grid on;

% Plot 2: Port selection distribution
subplot(3, 3, 2);
histogram(Data.SelectedPort, [0.5 1.5 2.5]);
xlabel('Port');
ylabel('Count');
title('Port Selection Distribution');
xticks([1 2]);
xlim([0.5 2.5]);

% Plot 3: Success rate over time (sliding window)
subplot(3, 3, 3);
windowSize = 20;
if nTrials >= windowSize
    successRate = zeros(1, nTrials - windowSize + 1);
    for i = 1:(nTrials - windowSize + 1)
        window = Data.Outcomes(i:i+windowSize-1);
        completed = window(window ~= -1);
        if ~isempty(completed)
            successRate(i) = 100 * sum(completed == 1) / length(completed);
        end
    end
    plot(windowSize:nTrials, successRate, 'LineWidth', 2);
    xlabel('Trial Number');
    ylabel('Success Rate (%)');
    title(sprintf('Success Rate (sliding window n=%d)', windowSize));
    ylim([0 100]);
    grid on;
else
    text(0.5, 0.5, 'Insufficient trials', 'HorizontalAlignment', 'center');
end

% Plot 4: Rewards per trial
subplot(3, 3, 4);
plot(1:nTrials, Data.ResponseLickCount, 'o-', 'MarkerSize', 4);
xlabel('Trial Number');
ylabel('Reward Count');
title('Rewards per Trial');
grid on;

% Plot 5: Delay resets per trial
subplot(3, 3, 5);
plot(1:nTrials, Data.DelayTimerResets, 'o-', 'MarkerSize', 4);
xlabel('Trial Number');
ylabel('Reset Count');
title('Delay Timer Resets per Trial');
grid on;

% Plot 6: Relationship between resets and outcome
subplot(3, 3, 6);
correctResets = Data.DelayTimerResets(Data.Outcomes == 1);
errorResets = Data.DelayTimerResets(Data.Outcomes == 0);
if ~isempty(correctResets) && ~isempty(errorResets)
    boxplot([correctResets(:); errorResets(:)], ...
        [ones(length(correctResets), 1); 2*ones(length(errorResets), 1)], ...
        'Labels', {'Correct', 'Error'});
    ylabel('Delay Resets');
    title('Resets by Outcome');
else
    text(0.5, 0.5, 'Insufficient data', 'HorizontalAlignment', 'center');
end

% Plot 7: Reward distribution
subplot(3, 3, 7);
histogram(Data.ResponseLickCount, 'BinWidth', 1);
xlabel('Rewards per Trial');
ylabel('Count');
title('Reward Distribution');

% Plot 8: Trial duration over time
if exist('trialDurations', 'var')
    subplot(3, 3, 8);
    plot(1:nTrials, trialDurations, 'o-', 'MarkerSize', 4);
    xlabel('Trial Number');
    ylabel('Duration (s)');
    title('Trial Duration Over Time');
    grid on;
end

% Plot 9: Cumulative rewards
subplot(3, 3, 9);
cumulativeRewards = cumsum(Data.ResponseLickCount);
plot(1:nTrials, cumulativeRewards, 'LineWidth', 2);
xlabel('Trial Number');
ylabel('Cumulative Rewards');
title('Cumulative Reward Delivery');
grid on;

%% Detailed licking analysis (if RawEvents available)
if isfield(Data, 'RawEvents') && isfield(Data.RawEvents, 'Trial')
    fprintf('\n=== DETAILED LICKING ANALYSIS ===\n');

    % Analyze lick timing patterns
    allLickTimes = [];
    allLickPorts = [];

    for trial = 1:min(nTrials, length(Data.RawEvents.Trial))
        events = Data.RawEvents.Trial{trial}.Events;

        if isfield(events, 'Port1Out')
            port1Licks = events.Port1Out;
            allLickTimes = [allLickTimes, port1Licks];
            allLickPorts = [allLickPorts, ones(size(port1Licks))];
        end

        if isfield(events, 'Port2Out')
            port2Licks = events.Port2Out;
            allLickTimes = [allLickTimes, port2Licks];
            allLickPorts = [allLickPorts, 2*ones(size(port2Licks))];
        end
    end

    if ~isempty(allLickTimes)
        fprintf('Total licks detected: %d\n', length(allLickTimes));

        % Calculate inter-lick intervals
        [sortedTimes, sortIdx] = sort(allLickTimes);
        sortedPorts = allLickPorts(sortIdx);

        % Find consecutive licks on same port
        samePortILI = [];
        for i = 2:length(sortedTimes)
            if sortedPorts(i) == sortedPorts(i-1)
                ili = sortedTimes(i) - sortedTimes(i-1);
                if ili < 1  % Only count ILIs < 1 second
                    samePortILI = [samePortILI, ili];
                end
            end
        end

        if ~isempty(samePortILI)
            fprintf('Median inter-lick interval: %.3f s\n', median(samePortILI));
            fprintf('Mean inter-lick interval: %.3f s\n', mean(samePortILI));

            % Plot ILI distribution
            figure('Name', 'Inter-Lick Interval Analysis', 'NumberTitle', 'off');
            histogram(samePortILI * 1000, 'BinWidth', 10);  % Convert to ms
            xlabel('Inter-Lick Interval (ms)');
            ylabel('Count');
            title('Distribution of Inter-Lick Intervals');
            grid on;
        end
    end
end

fprintf('\n=== ANALYSIS COMPLETE ===\n\n');

end
