function reward_iti_size
% global BpodSystem
global BpodSystem motors_properties motors S LickPortPosition LickPortPositionNextTrial;


motors_properties.PORT= 'COM18'; %vivarium='COM3'

motors_properties.type = '@ZaberArseny';
motors_properties.Z_motor_num = 1;
motors_properties.Lx_motor_num = 3;
motors_properties.Ly_motor_num = 2;
% motors_properties.Z_motor_num = 2;
% motors_properties.Lx_motor_num = 1;
% motors_properties.Ly_motor_num = 4;
BpodSystem.SoftCodeHandlerFunction = 'MySoftCodeHandler'; % for moving lickport

Camera_FPS = 250; % TTL pulses for camera
% Camera_FPS2 = 200; % Second TTL pulses for camera
MaxTrials = 9999;
RewardsForLastNTrials = 40; % THIS IS THE PERIOD OVER WHICH ADVANCEMENT PARAMETERS ARE DETERMINED
video_onset_delay=0.0;

% The state machine command interface consists of bytes sent from the Bpod

% valveState (1 byte; range = 0-15) Note: 0 = all cosed, 15 = all open
% use dec2bin matlab function to covert easly from dec to binary and
% bin2dec('') for the oppisite - {'ValveState', 3} is 1 and 2 open
% so the folbing line is triggering the second valve (valve is ethernet
% port)
LeftWaterOutput = {'ValveState',2^0}; % Ethernet port 1
%LeftWaterOutput = {'ValveState',}; % Arseny I switched the ethernet ports on BPOD, so I am giving the reward on "right port" but its actully left


RewardOutput = LeftWaterOutput;
% here we set the command to give back control to the computer to move the
% lickports (zabers)
MoveLickPortIn = {'SoftCode', 1}; 
MoveLickPortOut = {'SoftCode', 2};


%% Load Settings
%try to add if statement again for a subject with emty settings 

S = BpodSystem.ProtocolSettings; % Load settings chosen in launch manager into current workspace as a struct called S
if isempty(fieldnames(S))  % If settings file was an empty struct, populate struct with default settings
    S.GUI.WaterValveTime = 0.01;	  % in sec SET-UP SPECIFIC #reward size
    S.GUI.AutoWaterValveTime = 0.01;  % in sec SET-UP SPECIFIC #time for givedrop sma
    S.GUI.RewardChangeProb  = 0.2; %probability on which a change in reward size will occur (reward omissions are not included here)% xprod is rand, if its >=1-RewardChangeProb => gets large reward
    S.GUI.RewardChangeFactor  = 2; % change in reward time compared to regular WaterValveTime % if the flage is 2 (large reward due to comment above)- the reward size is multiplied by this
    S.GUI.RewardOmissionProb = 0.2; % Probability of a complete reward omission % if the rand is < than this, the flag is 0 and the mouse gets small reward     S.GUI.AnswerPeriodFirstLick = 10;	% in sec #not being used
    S.GUI.NumLicksForReward = 2;% changed it from 2. its meaning- if larger than 1, mouse gets reward only after xxx trials, otherwize they get reward from first lick
    S.GUI.AnswerPeriodEachLick=3;% time for them to respond for moving uper in the number of licks for getting reward after xxx licks
    S.GUI.ConsumptionPeriod = 1;	  % in sec %comment out
    S.GUI.InterTrialInterval = 0.5;	  % in sec #time for tup on reward consumption, not licking and then until trial end
    S.GUI.SpontaneousTrial = 10;	  % in sec
    
    S.GUIPanels.Behavior= {'WaterValveTime','AutoWaterValveTime','RewardChangeProb','RewardChangeFactor','RewardOmissionProb','AnswerPeriodEachLick','NumLicksForReward','ConsumptionPeriod','InterTrialInterval','SpontaneousTrial'};
    
    S.GUI.Z_motor_pos =  80000;%75000;%140000;       %[0 275287];
    S.GUI.Lx_motor_pos = 81001;%115000;       %[0 1000000];
    S.GUI.Ly_motor_pos = 40000;%260000;       %[0 1000000];
    
    
    S.GUI.X_radius = 1;
    S.GUI.Z_radius = 1;
    S.GUI.num_bins = 3;
    
    S.GUI.X_center = 81001;%115000;
    S.GUI.Y_center =40000;%260000;
    S.GUI.Z_center = 80000;%75000;%140000; %vivarium 70666. under microscop - you can play  with the mountcontrol zabers as well to change the mouse height  %50666.6667;               % lickable position
    S.GUI.Z_NonLickable = 10;%70000;        % non lickable position
    S.GUIMeta.MovingLP.Style = 'popupmenu';      % trial type selection
    S.GUIMeta.MovingLP.String = {'OFF' 'ON'};
    S.GUI.MovingLP = 2;
    S.GUIPanels.Position = {'X_radius','Z_radius','num_bins','X_center','Y_center','Z_center','Lx_motor_pos','Ly_motor_pos','Z_motor_pos','MovingLP','Z_NonLickable','ResetSeq','RollDeg'};
    
    S.GUI.ResetSeq = 0;
    S.GUI.RollDeg = 0; %in degrees. Increase numbers means right ear down, from mouse perspective
    
    
    S.GUIMeta.ProtocolType.Style = 'popupmenu';	 % protocol type selection
    S.GUIMeta.ProtocolType.String = {'2D','Spontaneous'};
    S.GUI.ProtocolType = 1;
    S.GUIPanels.Protocol= {'ProtocolType'};
    
    S.GUIMeta.Autowater.Style = 'popupmenu';	 % give free water on every trial
    S.GUIMeta.Autowater.String = {'On' 'Off'};
    S.GUI.Autowater = 2;
    S.GUI.MaxSame =10;
    S.GUI.AutowaterFirstTrialInBlock = 1;
    S.GUIPanels.TrialParameters= {'Autowater','MaxSame','AutowaterFirstTrialInBlock'};
    
    
    S.ProtocolHistory = [];	  % [protocol#, n_trials_on_this_protocol, performance]
end

%% Initialize
BpodParameterGUI('init', S);

% sync the protocol selections
p = cellfun(@(x) strcmp(x,'ProtocolType'),BpodSystem.GUIData.ParameterGUI.ParamNames);
set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manualChangeProtocol, S});
p = find(cellfun(@(x) strcmp(x,'Autolearn'),BpodSystem.GUIData.ParameterGUI.ParamNames));
set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manualChangeAutolearn, S});

%Arseny commented out
if isempty(S.ProtocolHistory)% start each day on autolearn
    S.ProtocolHistory(end+1,:) = [S.GUI.ProtocolType 1 0];
end

% change port number in ZaberTCD1000 if it doesnt work
motors = ZaberTCD1000(motors_properties.PORT);
serial_open(motors); %Arseny uncomment DEBUG

% setup manual motor inputs
p = find(cellfun(@(x) strcmp(x,'Z_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Z_Move});
Z_Move(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String'));

p = find(cellfun(@(x) strcmp(x,'Lx_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Lx_Move});
Lx_Move(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String'));

p = find(cellfun(@(x) strcmp(x,'Ly_motor_pos'),BpodSystem.GUIData.ParameterGUI.ParamNames));
set(BpodSystem.GUIHandles.ParameterGUI.Params(p),'callback',{@manual_Ly_Move});
Ly_Move(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String'));


%% Define trials
TrialTypes_seq = [];
BpodSystem.Data.TrialTypes = []; % The trial type of each trial completed will be added here.
BpodSystem.Data.LickPortMotorPosition = [];
BpodSystem.Data.ProbeTrials = [];
BpodSystem.Data.StimTrials = [];
BpodSystem.Data.MATLABStartTimes = [];

%% Initialize plots
BpodSystem.ProtocolFigures.YesNoPerfOutcomePlotFig = figure('Position', [400 400 1400 200],'Name','Outcome plot','NumberTitle','off','MenuBar','none','Resize','off');
BpodSystem.GUIHandles.YesNoPerfOutcomePlot = axes('Position', [.1 .3 .75 .6]);
uicontrol('Style','text','String','nTrials','Position',[10 150 40 20]);
BpodSystem.GUIHandles.DisplayNTrials = uicontrol('Style','edit','string','100','Position',[10 130 40 20]);

%% Initialize BIAS interface for Video
% biasThing = StickShiftBpodUserClass() ;
% biasThing.wake() ;
% biasThing.startingRun() ;

% Pause the protocol before starting
BpodSystem.Status.Pause = 1;
HandlePauseCondition;

%% Computing trial structure (could be changed during ongoing aquisition by S.GUI.ResetSeq==1)
[trial_type_mat,X_positions_mat, Z_positions_mat, TrialTypes_seq, ~, first_trial_in_block_seq, current_trial_num_in_block_seq] = trial_sequence_assembly();
OutcomePlot2D(BpodSystem.GUIHandles.YesNoPerfOutcomePlot,BpodSystem.GUIHandles.DisplayNTrials,'init',2-TrialTypes_seq);


%% Main trial loop
%% tal
% %% Initialize Parameters
% Define parameters
MaxTrials = 30000;  % Total number of trials
TrialsPerBlock = 30;  % Number of trials in each block
NumBlocks = 6;  % Number of blocks
% BlockOrder = [1, randperm(NumBlocks-1) + 1, 1];  % Randomized blocks with masking block (1) interleaved
blocks = 2:NumBlocks;  % The other blocks (excluding 1)

% Randomize the other blocks
randomizedBlocks = randperm(NumBlocks-1) + 1;

% Insert block 1 (masking block) before and after every block
BlockOrder = [];
for i = 1:length(randomizedBlocks)
    BlockOrder = [BlockOrder, 1, randomizedBlocks(i)];  % Add 1 before each block
end

% Add 1 at the end as well
% BlockOrder = [BlockOrder, 1];
% Initialize arrays for iti and reward for each block
iti_array = cell(1, NumBlocks);
Reward_array = cell(1, NumBlocks);

BlockOrder=[7, 8, 7, 9, 7, 8, 7, 9];%%% for only pure consec options
% Loop through each block and assign rewards and ITIs
for b = 1:NumBlocks
    block_type = BlockOrder(b);
    
    % Initialize rewards and ITI for each block
    reward1 = zeros(1, TrialsPerBlock);  % Use numeric values: 1 = regular, 2 = large, 3 = small
    iti = zeros(1, TrialsPerBlock);

    % Set the reward pattern: 6 regular (1), 3 large (2), 3 small (3)
    reward1(1:6) = 1;  % Regular reward
%     reward(7:9) = 2;  % Large reward
%     reward(10:12) = 3; % Small reward

       % create handmade vector for consec itis 
%     % Step 1: Create a 1x30 vector with random values of either 45 or 120
%     vector = randi([0, 1], 1, 30) * 75 + 45;
% 
%     % Step 2: Calculate the number of zeros to add (2 zeros every 10 elements)
%     num_zeros = 2 * ceil(numel(vector) / 10);
%     extended_vector = zeros(1, numel(vector) + num_zeros);
% 
%     % Step 3: Insert zeros every 10 elements
%     zero_indices = [];
%     for i = 10:10:numel(extended_vector)
%         zero_indices = [zero_indices, i, i+1]; % Add two zeros at each block
%     end
% 
%     % Remove any indices that go beyond the length of the extended vector
%     zero_indices = zero_indices(zero_indices <= numel(extended_vector));
% 
%     % Step 4: Insert original values into the extended vector
%     non_zero_indices = setdiff(1:numel(extended_vector), zero_indices);
%     extended_vector(non_zero_indices) = vector;
%     long_itis=extended_vector(1:30);
% Step 1: Create a 1x30 vector with random values of either 45 or 120
vector = randi([0, 1], 1, 30) * 75 + 45;

% Step 2: Calculate the number of zeros to add (5 zeros every 10 elements)
num_zeros = 5 * floor(numel(vector) / 10);  % Adjust zeros count accordingly
extended_vector = zeros(1, numel(vector) + num_zeros);

% Step 3: Insert zeros every 10 elements
% zero_indices = [];
% for i = 10:10:numel(extended_vector)
%     zero_indices = [zero_indices, i:i+4]; % Add five zeros at each block
% end
% 
% % Remove any indices that go beyond the length of the extended vector
% zero_indices = zero_indices(zero_indices <= numel(extended_vector));
% 
% % Step 4: Insert original values into the extended vector
% non_zero_indices = setdiff(1:numel(extended_vector), zero_indices);
% 
% % Adjust for the number of zeros added by shifting the non-zero indices
% shift = 0; % Shift to accommodate zeros
% for idx = 1:numel(non_zero_indices)
%     if non_zero_indices(idx) > zero_indices(shift+1)
%         shift = shift + 5;
%     end
%     extended_vector(non_zero_indices(idx)) = vector(idx);
% end
% 
% long_itis = extended_vector(1:30);
% %%%%% for thirds
% total_length = 30;
% % Generate the repeating pattern [60 60 60 0 0 0]
% % pattern = [45 45 45 0 45 0];
% % Repeat the pattern to fill the desired length
% long_itis = repmat(pattern, 1, total_length / length(pattern));
% %%%%% end for thirds

%%%% fixed pattern of pure with consecutive iti
long_itis=iti_long_for_pure(430);%(600);
reward_pure=reward_for_pure(430);%(600);
block_type=10;%7; % for only this pattern


    if block_type==1
        % Efficient reward shuffling that respects the rule: large/small after 2 regulars
        reward = shuffle_rewards_with_constraints_new(reward1);
        % Assign ITI based on the reward pattern
        iti=long_itis';
%         iti = assign_pure_iti(reward1);
    elseif block_type==2
        %r_l_impure, itipure
        reward=shuffle_rewards_impurel(reward1);
        iti=assign_pure_iti(reward1);
    elseif block_type==3
        %r_s_impure, itipure
        reward=shuffle_rewards_impures(reward1);
        iti=assign_pure_iti(reward1);
    elseif block_type==4
        %r_pure, itiimpure
        reward=shuffle_rewards_with_constraints_new(reward1);
%         iti=assign_iti_with_2consecutive(reward1);
        iti=long_itis';
    elseif block_type==5
        %r_l_impure, itiimpure
        reward=shuffle_rewards_with_constraints_new(reward1);
%         iti=assign_iti_with_2consecutive(reward1);
        iti=long_itis';
    elseif block_type==6
        %r_s_impure, itiimpure
        reward=shuffle_rewards_with_constraints_new(reward1);
%         iti=assign_iti_with_2consecutive(reward1);
        iti=long_itis';
    elseif block_type==7
        reward=reward_pure;
        iti=long_itis;
    elseif block_type==8
        reward=three_cons_large(30);
        iti=long_short_long_for_three_large(30);
    elseif block_type==9
        reward=three_cons_large(30);
        iti=long_long_long_for_three_large(30);
    elseif block_type==10
        reward=reward_for_pure(430);
        iti=iti_long_for_pure(430);
    end
                
    % Store the results for this block
    iti_array{b} = iti;
    Reward_array{b} = reward;
end 

% Flatten the blocks into a single trial sequence
AllRewards = horzcat(Reward_array{:});
AllRewards=[AllRewards,AllRewards,AllRewards,AllRewards,AllRewards];
Allitis = horzcat(iti_array{:});
Allitis = reshape([iti_array{:}], [], 1)';

Allitis=[Allitis,Allitis,Allitis,Allitis,Allitis];
% Allitis=zeros(length(Allitis)); % for iti zero alone
% reward small+iti 0 == 1, reward large+iti 0 == 2, reward regular+iti 0==
% 3, reward small+iti 45 == 4, reward large+iti 45 == 5, reward regular+iti 45==
% 6, reward small+iti 120 == 7, reward large+iti 120 == 8, reward regular+iti 120==
% 9
% 1=regular, 2=small, 3=large final right num!!!!
TrialTypes=[];
for typeforplot=1:length(AllRewards)
    if AllRewards(typeforplot) == 2 && Allitis(typeforplot) == 0
        TrialTypes(typeforplot)=1;
    elseif AllRewards(typeforplot) == 3 && Allitis(typeforplot) == 0
        TrialTypes(typeforplot)=2;
    elseif AllRewards(typeforplot) == 1 && Allitis(typeforplot) == 0
        TrialTypes(typeforplot)=3;
    elseif AllRewards(typeforplot) == 2 && Allitis(typeforplot) == 45
        TrialTypes(typeforplot)=2;
    elseif AllRewards(typeforplot) == 3 && Allitis(typeforplot) == 45
        TrialTypes(typeforplot)=5;
    elseif AllRewards(typeforplot) == 1 && Allitis(typeforplot) == 45
        TrialTypes(typeforplot)=6;
    elseif AllRewards(typeforplot) == 2 && Allitis(typeforplot) == 120
        TrialTypes(typeforplot)=3;
    elseif AllRewards(typeforplot) == 3 && Allitis(typeforplot) == 120
        TrialTypes(typeforplot)=8;
    elseif AllRewards(typeforplot) == 1 && Allitis(typeforplot) == 120
        TrialTypes(typeforplot)=9;
    end
end
n=30;
position_seq1=[1, 2, 2, 2, 2, 1, 1, 2, 1, 1, 2, 2, 1, 1, 2, 2, 1, 2, 2, 2, 1, 2, 1, 1, 2, 2, 2, 2, 1, 2, 1];% r=1,l=2
position_seq=repmat(position_seq1, 1, n);
% Allitis(Allitis == 120) = 80; % reduced iti to 80
% Allitis(Allitis == 0) = 0.5; % reduced iti to 80

% 
% for typeforplot=1:length(AllRewards)
%     if Allitis(typeforplot) == 0
%         TrialTypes(i)=1;
% %     elseif AllRewards(i) == 3 && Allitis(i) == 0
% %         TrialTypes(i)=2;
% %     elseif AllRewards(i) == 1 && Allitis(i) == 0
% %         TrialTypes(i)=3;
%     elseif Allitis(typeforplot) == 45
%         TrialTypes(typeforplot)=2;
% %     elseif AllRewards(i) == 3 && Allitis(i) == 45
% %         TrialTypes(i)=5;
% %     elseif AllRewards(i) == 1 && Allitis(i) == 45
% %         TrialTypes(i)=6;
%     elseif Allitis(typeforplot) == 120
%         TrialTypes(typeforplot)=3;
% %     elseif AllRewards(i) == 3 && Allitis(i) == 120
% %         TrialTypes(i)=8;
% %     elseif AllRewards(i) == 1 && Allitis(i) == 120
% %         TrialTypes(i)=9;
%     end
% end
%%% try adding notepad per trial/ this init it before the mainloop
BpodNotebook('init')
% TrialTypes = repelem(BlockOrder, 30);

% Initialize plots
BpodSystem.ProtocolFigures.OutcomePlotFig = figure('Position', [200 200 1000 600],'name','Trial type outcome plot', 'numbertitle','off', 'MenuBar', 'none', 'Resize', 'off'); % Create a figure for the outcome plot

BpodSystem.GUIHandles.OutcomePlot = axes('Position', [.075 .3 .89 .6]); % Create axes for the trial type outcome plot

TrialTypeOutcomePlot(BpodSystem.GUIHandles.OutcomePlot,'init',TrialTypes);
%%
for currentTrial = 1:MaxTrials
    S = BpodParameterGUI('sync', S); % Sync parameters with BpodParameterGUI plugin
    
    S.ProtocolHistory;
    %S.LickPortMove
    

    disp(['Starting trial ',num2str(currentTrial)])
    sma = NewStateMachine;
    sma = SetGlobalTimer(sma, 'TimerID', 1, 'Duration', 1/(2*250), 'OnsetDelay', 0,...
                         'Channel', 'BNC1', 'OnLevel', 1, 'OffLevel', 0,...
                         'Loop', 1, 'SendGlobalTimerEvents', 0, 'LoopInterval', 1/(2*250)); 
                     
    sma = SetGlobalTimer(sma, 'TimerID', 2, 'Duration', 2000, 'OnsetDelay', 0,'Channel', 'BNC2','SendGlobalTimerEvents', 0); %% Arseny - trigger sent over BNC2

    sma = AddState(sma, 'Name', 'TimerTrig1', ...
        'Timer', 0,...
        'StateChangeConditions', {'Tup', 'StartBitcodeTrialNumber'},...
        'OutputActions', {'GlobalTimerTrig', '1111'});

    % Determine current reward and iti
    reward_type = AllRewards(currentTrial);
    iti_duration_type = Allitis(currentTrial);

    %% Arseny generating bitcode (a different state for every bit). Sent over BNC2
    time_period=0.02;
    digits=20;
    %sends one pulse to signal the beginning of the bitcode that would contain a random trial-number
    sma = AddState(sma, 'Name', 'StartBitcodeTrialNumber', 'Timer', time_period*3, 'StateChangeConditions', {'Tup', 'OffState1'},'OutputActions', {'BNC2',1});
    random_number = floor(rand()*(2^digits-1));
    bitcode=dec2bin(random_number,digits);
    
    BpodSystem.Data.bitcode{currentTrial}=bitcode;
    %random trial bitcode
    for digit=1:digits
        sma = AddState(sma, 'Name', strcat('OffState',int2str(digit)), 'Timer', time_period, 'StateChangeConditions', {'Tup',strcat('OnState',int2str(digit))},'OutputActions',[]);
        bit=[];
        if bitcode(digit)=='1'
            bit={'BNC2',1};
        end
        
        sma = AddState(sma, 'Name', strcat('OnState',int2str(digit)), 'Timer', time_period, 'StateChangeConditions', {'Tup',strcat('OffState',int2str(digit+1))},'OutputActions', bit);
    end
    
    sma = AddState(sma, 'Name', strcat('OffState',int2str(digits+1)), 'Timer', time_period, 'StateChangeConditions', {'Tup','EndBitcodeTrialNumber'},'OutputActions',[]);
    %sends one pulse to signal the end of the bitcode that would contain a random trial-number
    sma = AddState(sma, 'Name', 'EndBitcodeTrialNumber', 'Timer', time_period*3, 'StateChangeConditions', {'Tup', 'OffStatePreSample'},'OutputActions', {'BNC2',1});
    
    reward_sizes_block = mod(floor((currentTrial - 1) / 300), 2) + 1;
    reward_sizes_block = 1; % commenout
    
    switch S.GUI.ProtocolType%reward_sizes_block
        case 1            
            if S.GUI.ResetSeq==1
                [trial_type_mat,X_positions_mat, Z_positions_mat, TrialTypes_seq, ~, first_trial_in_block_seq, current_trial_num_in_block_seq] = trial_sequence_assembly();
            end
%              fprintf('Starting now: X pos %.1f  Z pos %.1f\n',X_positions_mat(currentTrial),Z_positions_mat(TrialTypes_seq(currentTrial)));            
%              fprintf('Starting now: X pos %.1f  Z pos %.1f\n',X_positions_mat(TrialTypes_seq(currentTrial)),Z_positions_mat(TrialTypes_seq(currentTrial)));
%              fprintf('Starting now: X pos %.1f  Z pos %.1f\n',position_seq(currentTrial),Z_positions_mat(TrialTypes_seq(currentTrial)));
            fprintf('Starting now: X pos %.1f  Z pos %.1f\n',X_positions_mat(TrialTypes_seq(currentTrial)),Z_positions_mat(TrialTypes_seq(currentTrial)));

             OutcomePlot2D(BpodSystem.GUIHandles.YesNoPerfOutcomePlot,BpodSystem.GUIHandles.DisplayNTrials,'next_trial',TrialTypes_seq(currentTrial));
            
            % saving TrialType related infor to BPOD
            BpodSystem.Data.trial_type_mat{currentTrial}=trial_type_mat;
            BpodSystem.Data.X_positions_mat{currentTrial}=X_positions_mat;
            BpodSystem.Data.Z_positions_mat{currentTrial}=Z_positions_mat;
            BpodSystem.Data.TrialTypes(currentTrial)=TrialTypes_seq(currentTrial);
%             BpodSystem.Data.position(currentTrial)=position_seq(currentTrial);
            BpodSystem.Data.TrialBlockOrder(currentTrial)=current_trial_num_in_block_seq(currentTrial); % changed now

%            BpodSystem.Data.TrialBlockOrder(currentTrial)=current_trial_num_in_block_seq(currentTrial);
             
            flag_drop_water=0; %default
            if (S.GUI.AutowaterFirstTrialInBlock ==1) ... 
                    || (S.GUI.Autowater == 1) % or if AutoWater %drop water if its the first trial in block or if AutoWater %%&& first_trial_in_block_seq(currentTrial)==1)
                flag_drop_water = 1;
            end

            %% reward assignment 
            reward_sizes_block = 1;
            if reward_sizes_block == 1
                if reward_type==1
                    regular_reward = S.GUI.WaterValveTime;
                elseif reward_type==3
                    large_reward = S.GUI.WaterValveTime * S.GUI.RewardChangeFactor;
                else
                    small_reward = S.GUI.WaterValveTime * (1 / S.GUI.RewardChangeFactor);
                end
            elseif reward_sizes_block == 2
                if reward_type==1
                    regular_reward = S.GUI.WaterValveTime * (1 / S.GUI.RewardChangeFactor);
                elseif reward_type==3
                    large_reward = S.GUI.WaterValveTime;
                else
                    small_reward = (S.GUI.WaterValveTime * (1 / S.GUI.RewardChangeFactor)) * (1 / S.GUI.RewardChangeFactor); 
                end
            end
            large_reward = S.GUI.WaterValveTime * S.GUI.RewardChangeFactor;
            small_reward = S.GUI.WaterValveTime * (1 / S.GUI.RewardChangeFactor);

            if reward_type==1
                reward_size=regular_reward;
            elseif reward_type==2
                reward_size=small_reward;
            elseif reward_type==3
                reward_size=large_reward;
            end
            
            if iti_duration_type==0
                iti_duration=5;
            elseif iti_duration_type==45
                iti_duration=15;
            elseif iti_duration_type==120
                iti_duration=25;
            end
            
            right_position= S.GUI.X_center+ S.GUI.X_radius;
            left_position= S.GUI.X_center- S.GUI.X_radius;
            % Generate reward sizes for all trials

            BpodSystem.Data.TrialRewardFlag (currentTrial) = reward_type;% regular=1, small=2, large=3 % reward_size; 
            BpodSystem.Data.TrialITIFlag (currentTrial) = iti_duration_type;% regular=1, small=2, large=3 % reward_size; 

            BpodSystem.Data.BlockType (currentTrial) = reward_sizes_block;
            BpodSystem.Data.Iti (currentTrial) = iti_duration;%7;%iti_duration; 

            %% tals Setting Motor positions for Current trial
%             if position_seq(currentTrial) == 1
%                 LickPortPosition.X=right_position;
%                 BpodSystem.Data.zaber_pos(currentTrial)=right_position;
%             elseif position_seq(currentTrial) == 2
%                 LickPortPosition.X=left_position;
%             end
%             % LickPortPosition.X=X_positions_mat(TrialTypes_seq(currentTrial));           
%             LickPortPosition.Z=Z_positions_mat(TrialTypes_seq(currentTrial));
%             % Setting Motor positions for Next trial
%             %             LickPortPositionNextTrial.X=X_positions_mat(currentTrial(currentTrial+1));
%             %             LickPortPositionNextTrial.X=X_positions_mat(TrialTypes_seq(currentTrial+1));
%             if position_seq(currentTrial+1) == 1 
%                 LickPortPositionNextTrial.X=right_position;
%             elseif position_seq(currentTrial+1) == 2 
%                 LickPortPositionNextTrial.X=left_position;
%                 BpodSystem.Data.zaber_pos(currentTrial)=left_position;
%             end
           
                        %% Arsenys Setting Motor positions for Current trial
            LickPortPosition.X=X_positions_mat(TrialTypes_seq(currentTrial));
            LickPortPosition.Z=Z_positions_mat(TrialTypes_seq(currentTrial));
            % Setting Motor positions for Next trial
            LickPortPositionNextTrial.X=X_positions_mat(TrialTypes_seq(currentTrial+1));
            
 
            %% Lick related states
            if flag_drop_water ==1 %drop water if on AutoWater or if its the first trial in a block
%                 if currentTrial ==1  tal
%             if current_trial_num_in_block_seq(currentTrial)== 1 %% noa changed from -- if currenTrial == 1
%                     disp('AutoWater is ON for this trial');
% 
%                 sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.1, 'StateChangeConditions', {'Tup','GiveDrop'},'OutputActions',[]);
%                 else
                 sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.1, 'StateChangeConditions', {'Tup','AnswerPeriod'},'OutputActions',[]);
%                 end

                sma = AddState(sma, 'Name', 'GiveDrop', 'Timer', S.GUI.AutoWaterValveTime,'StateChangeConditions', {'Tup', 'AnswerPeriodAutoWater'},'OutputActions', RewardOutput); % RewardOutput turn on water RewardOutput
                BpodSystem.Data.TrialRewardSize (currentTrial) = S.GUI.AutoWaterValveTime; % in terms of valve time

            else
                if S.GUI.NumLicksForReward >1
                    % Giving  only after XXX licks
                    sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.001, 'StateChangeConditions', {'Tup','AnswerPeriodFirstLick'},'OutputActions',[]);
                    % sma = AddState(sma, 'Name', 'AnswerPeriodFirstLick', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'LickIn1', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn); % advance lickport and wait for response
                    sma = AddState(sma, 'Name', 'AnswerPeriodFirstLick', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'LickIn1', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn);%MoveLickPortIn % advance lickport and wait for response

                    sma = AddState(sma, 'Name', 'LickIn1', 'Timer', S.GUI.AnswerPeriodEachLick,'StateChangeConditions', {'Port1Out', 'LickOut1', 'Tup', 'NoResponse'},'OutputActions', []); % advance lickport and wait for response
                    for i_l=1:S.GUI.NumLicksForReward-1
                        sma = AddState(sma, 'Name', strcat('LickOut',int2str(i_l)), 'Timer', S.GUI.AnswerPeriodEachLick, 'StateChangeConditions', {'Port1Out', strcat('LickIn',int2str(i_l+1)), 'Tup', 'NoResponse'},'OutputActions',[]);
                        sma = AddState(sma, 'Name', strcat('LickIn',int2str(i_l+1)), 'Timer', S.GUI.AnswerPeriodEachLick, 'StateChangeConditions', {'Port1Out', strcat('LickOut',int2str(i_l+1)), 'Tup', 'NoResponse'},'OutputActions',[]);
                    end
                    sma = AddState(sma, 'Name', strcat('LickOut',int2str(i_l+1)), 'Timer', 1,'StateChangeConditions', {'Tup', 'Reward'},'OutputActions', []); % advance lickport and wait for response
                else %reward after first lick
                    sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.01, 'StateChangeConditions', {'Tup','AnswerPeriod'},'OutputActions',[]);
                end
                BpodSystem.Data.TrialRewardSize (currentTrial) = reward_size; % in terms of valve time
            end
            
            % sma = AddState(sma, 'Name', 'AnswerPeriod', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'Reward', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn); % advance lickport and wait for response
            sma = AddState(sma, 'Name', 'AnswerPeriod', 'Timer',15,'StateChangeConditions', {'Port1Out', 'Reward', 'Tup', 'InterTrialInterval'},'OutputActions', MoveLickPortIn); % MoveLickPortIn %output needs to be MoveLickPortIn % advance lickport and wait for response

            % sma = AddState(sma, 'Name', 'AnswerPeriodAutoWater', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'RewardConsumption', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn); % advance lickport and wait for response
            sma = AddState(sma, 'Name', 'AnswerPeriodAutoWater', 'Timer', 15,'StateChangeConditions', {'Port1Out', 'RewardConsumption', 'Tup', 'TrialEnd'},'OutputActions', MoveLickPortIn);% MoveLickPortIn %output needs to be MoveLickPortIn % advance lickport and wait for response

            sma = AddState(sma, 'Name', 'Reward', 'Timer', reward_size,'StateChangeConditions', {'Tup', 'RewardConsumption'},'OutputActions', RewardOutput); % turn on water
            reward_size
            % sma = AddState(sma, 'Name', 'RewardConsumption', 'Timer', S.GUI.ConsumptionPeriod,'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions', []); % reward consumption
            sma = AddState(sma, 'Name', 'RewardConsumption', 'Timer', 1,'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions', []); % reward consumption

            % sma = AddState(sma, 'Name', 'NoResponse', 'Timer', S.GUI.ConsumptionPeriod, 'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions',[]); % no response - wait same time as for reward consumption, as a time out
            sma = AddState(sma, 'Name', 'NoResponse', 'Timer', 0.001, 'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions',[]); % no response - wait same time as for reward consumption, as a time out
            %iti_duration
            sma = AddState(sma, 'Name', 'InterTrialInterval', 'Timer', iti_duration,'StateChangeConditions', {'Tup', 'TrialEnd'},'OutputActions', MoveLickPortOut);%MoveLickPortOut %output needs to be MoveLickPortOut % retract lickport
            sma = AddState(sma, 'Name', 'TrialEnd', 'Timer', 0.01,'StateChangeConditions', {'Tup', 'exit'},'OutputActions', {'GlobalTimerCancel', '1111'}); %wait for the end of the trial
            
            BpodSystem.Data.BehaviorORSpontaneous{currentTrial}='Behavior';

        case 2
            if S.GUI.ResetSeq==1
                [trial_type_mat,X_positions_mat, Z_positions_mat, TrialTypes_seq, ~, first_trial_in_block_seq, current_trial_num_in_block_seq] = trial_sequence_assembly();
            end
            
             fprintf('Starting now: X pos %.1f  Z pos %.1f\n',X_positions_mat(TrialTypes_seq(currentTrial)),Z_positions_mat(TrialTypes_seq(currentTrial)));
             OutcomePlot2D(BpodSystem.GUIHandles.YesNoPerfOutcomePlot,BpodSystem.GUIHandles.DisplayNTrials,'next_trial',TrialTypes_seq(currentTrial));
            
            % saving TrialType related infor to BPOD
            BpodSystem.Data.trial_type_mat{currentTrial}=trial_type_mat;
            BpodSystem.Data.X_positions_mat{currentTrial}=X_positions_mat;
            BpodSystem.Data.Z_positions_mat{currentTrial}=Z_positions_mat;
            BpodSystem.Data.TrialTypes(currentTrial)=TrialTypes_seq(currentTrial);
%            BpodSystem.Data.TrialBlockOrder(currentTrial)=current_trial_num_in_block_seq(currentTrial);
             
            flag_drop_water=0; %default
            if (S.GUI.AutowaterFirstTrialInBlock ==1) ... 
                    || (S.GUI.Autowater == 1) % or if AutoWater %drop water if its the first trial in block or if AutoWater %%&& first_trial_in_block_seq(currentTrial)==1)
                flag_drop_water = 1;
            end

            %% reward assignment 

            if reward_sizes_block == 1
                if reward_type==1
                    regular_reward = S.GUI.WaterValveTime;
                elseif reward_type==2
                    small_reward = S.GUI.WaterValveTime * S.GUI.RewardChangeFactor;
                else
                    large_reward = S.GUI.WaterValveTime * (1 / S.GUI.RewardChangeFactor);
                end
            elseif reward_sizes_block == 2
                if reward_type==1
                    regular_reward = S.GUI.WaterValveTime * (1 / S.GUI.RewardChangeFactor);
                elseif reward_type==2
                    small_reward = S.GUI.WaterValveTime;
                else
                    large_reward = (S.GUI.WaterValveTime * (1 / S.GUI.RewardChangeFactor)) * (1 / S.GUI.RewardChangeFactor); 
                end
            end

            if reward_type==1
                reward_size=regular_reward;
            elseif reward_type==2
                reward_size=small_reward;
            elseif reward_type==3
                reward_size=large_reward;
            end
            
            
            % Generate reward sizes for all trials

            BpodSystem.Data.TrialRewardFlag (currentTrial) = reward_size; 
            BpodSystem.Data.BlockType (currentTrial) = reward_sizes_block;
            BpodSystem.Data.Iti (currentTrial) = iti_duration; 

            %% Setting Motor positions for Current trial
            LickPortPosition.X=X_positions_mat(TrialTypes_seq(currentTrial));
            LickPortPosition.Z=Z_positions_mat(TrialTypes_seq(currentTrial));
            % Setting Motor positions for Next trial
            LickPortPositionNextTrial.X=X_positions_mat(TrialTypes_seq(currentTrial+1));
            
            
            %% Lick related states
            if flag_drop_water ==1 %drop water if on AutoWater or if its the first trial in a block
                if currentTrial ==1
                sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.1, 'StateChangeConditions', {'Tup','GiveDrop'},'OutputActions',[]);
                else
                 sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.1, 'StateChangeConditions', {'Tup','AnswerPeriod'},'OutputActions',[]);
                end

                sma = AddState(sma, 'Name', 'GiveDrop', 'Timer', S.GUI.AutoWaterValveTime,'StateChangeConditions', {'Tup', 'AnswerPeriodAutoWater'},'OutputActions', RewardOutput); % RewardOutput turn on water RewardOutput
                BpodSystem.Data.TrialRewardSize (currentTrial) = S.GUI.AutoWaterValveTime; % in terms of valve time

            else
                if S.GUI.NumLicksForReward >1
                    % Giving  only after XXX licks
                    sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.001, 'StateChangeConditions', {'Tup','AnswerPeriodFirstLick'},'OutputActions',[]);
                    % sma = AddState(sma, 'Name', 'AnswerPeriodFirstLick', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'LickIn1', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn); % advance lickport and wait for response
                    sma = AddState(sma, 'Name', 'AnswerPeriodFirstLick', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'LickIn1', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn);%MoveLickPortIn % advance lickport and wait for response

                    sma = AddState(sma, 'Name', 'LickIn1', 'Timer', S.GUI.AnswerPeriodEachLick,'StateChangeConditions', {'Port1Out', 'LickOut1', 'Tup', 'NoResponse'},'OutputActions', []); % advance lickport and wait for response
                    for i_l=1:S.GUI.NumLicksForReward-1
                        sma = AddState(sma, 'Name', strcat('LickOut',int2str(i_l)), 'Timer', S.GUI.AnswerPeriodEachLick, 'StateChangeConditions', {'Port1Out', strcat('LickIn',int2str(i_l+1)), 'Tup', 'NoResponse'},'OutputActions',[]);
                        sma = AddState(sma, 'Name', strcat('LickIn',int2str(i_l+1)), 'Timer', S.GUI.AnswerPeriodEachLick, 'StateChangeConditions', {'Port1Out', strcat('LickOut',int2str(i_l+1)), 'Tup', 'NoResponse'},'OutputActions',[]);
                    end
                    sma = AddState(sma, 'Name', strcat('LickOut',int2str(i_l+1)), 'Timer', 1,'StateChangeConditions', {'Tup', 'Reward'},'OutputActions', []); % advance lickport and wait for response
                else %reward after first lick
                    sma = AddState(sma, 'Name', strcat('OffStatePreSample'), 'Timer', 0.01, 'StateChangeConditions', {'Tup','AnswerPeriod'},'OutputActions',[]);
                end
                BpodSystem.Data.TrialRewardSize (currentTrial) = reward_size; % in terms of valve time
            end
            
            % sma = AddState(sma, 'Name', 'AnswerPeriod', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'Reward', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn); % advance lickport and wait for response
            sma = AddState(sma, 'Name', 'AnswerPeriod', 'Timer',15,'StateChangeConditions', {'Port1Out', 'Reward', 'Tup', 'Reward'},'OutputActions', MoveLickPortIn); % MoveLickPortIn %output needs to be MoveLickPortIn % advance lickport and wait for response

            % sma = AddState(sma, 'Name', 'AnswerPeriodAutoWater', 'Timer', S.GUI.AnswerPeriodFirstLick,'StateChangeConditions', {'Port1Out', 'RewardConsumption', 'Tup', 'NoResponse'},'OutputActions', MoveLickPortIn); % advance lickport and wait for response
            sma = AddState(sma, 'Name', 'AnswerPeriodAutoWater', 'Timer', 10,'StateChangeConditions', {'Port1Out', 'RewardConsumption', 'Tup', 'RewardConsumption'},'OutputActions', MoveLickPortIn);% trialend% MoveLickPortIn %output needs to be MoveLickPortIn % advance lickport and wait for response

            sma = AddState(sma, 'Name', 'Reward', 'Timer', reward_size,'StateChangeConditions', {'Tup', 'RewardConsumption'},'OutputActions', RewardOutput); % turn on water
            % sma = AddState(sma, 'Name', 'RewardConsumption', 'Timer', S.GUI.ConsumptionPeriod,'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions', []); % reward consumption
            sma = AddState(sma, 'Name', 'RewardConsumption', 'Timer', 1,'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions', []); % reward consumption

            % sma = AddState(sma, 'Name', 'NoResponse', 'Timer', S.GUI.ConsumptionPeriod, 'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions',[]); % no response - wait same time as for reward consumption, as a time out
            sma = AddState(sma, 'Name', 'NoResponse', 'Timer', 0.001, 'StateChangeConditions', {'Tup', 'InterTrialInterval'},'OutputActions',[]); % no response - wait same time as for reward consumption, as a time out
            %%iti_duration
            sma = AddState(sma, 'Name', 'InterTrialInterval', 'Timer', iti_duration,'StateChangeConditions', {'Tup', 'TrialEnd'},'OutputActions', MoveLickPortOut);%MoveLickPortOut %output needs to be MoveLickPortOut % retract lickport
            sma = AddState(sma, 'Name', 'TrialEnd', 'Timer', 0.01,'StateChangeConditions', {'Tup', 'exit'},'OutputActions', {'GlobalTimerCancel', '1111'}); %wait for the end of the trial
            
            BpodSystem.Data.BehaviorORSpontaneous{currentTrial}='Behavior';

    end
    
    %% 
    %% Starting Video
    % biasThing.startingSweep() ;
    pause(0.2)
    
    %
    
    startTime=now;
    SendStateMatrix(sma);
    
    try
        RawEvents = RunStateMatrix;		 % this step takes a long time and variable (seem to wait for GUI to update, which takes a long time)
        bad = 0;
    catch ME
        warning('RunStateMatrix error!!!'); % TW: The Bpod USB communication error fails here.
        bad = 1;
    end
    
    % biasThing.completingSweep() ;
    S.GUI.ResetSeq=0;
    if bad == 0 & ~isempty(fieldnames(RawEvents)) % If trial data was returned
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        BpodSystem.Data = BpodNotebook('sync', BpodSystem.Data); % Sync with Bpod notebook plugin
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes_seq(currentTrial); % Adds the trial type of the current trial to data
        
        %% Arseny commented out
        % save lickport position
        p = find(cellfun(@(x) strcmp(x,'LickportMotorPosition'),BpodSystem.GUIData.ParameterGUI.ParamNames));
%         BpodSystem.Data.LickPortMotorPosition(currentTrial) = str2num(get(BpodSystem.GUIHandles.ParameterGUI.Params(p),'String')); % tal commented out
        
%         BpodSystem.Data.LickPortMotorPosition(currentTrial) = str2double(get(BpodSystem.GUIHandles.ParameterGUI.Params(p), 'String'));
try
    % Ensure value is a string or character vector
    valueStr = get(BpodSystem.GUIHandles.ParameterGUI.Params(p), 'String');
    
    if iscell(valueStr)
        valueStr = valueStr{1};  % Extract string from cell array
    end
    
    % Convert the string to a number
    numericValue = str2double(valueStr);
    
    if isnan(numericValue)
        error('The input string cannot be converted to a number.');
    end
    
    % Assign the numeric value
    BpodSystem.Data.LickPortMotorPosition(currentTrial) = numericValue;
    
catch ME
    disp(['Error: ' ME.message]);
end

        BpodSystem.Data.MATLABStartTimes(currentTrial) = startTime;
        
%         %%% tal for plot fix dependencies
%         Outcomes = zeros(1,BpodSystem.Data.nTrials);
%         for x = 1:BpodSystem.Data.nTrials
%             if x==1
%                 continue
%             else
%             timestart=Events.Trial{1, x-1}.States.AnswerPeriod(1);
%             timeend=BpodSystem.Data.RawEvents.Trial{1, x-1}.States.RewardConsumption(2);
%             if isfield(BpodSystem.Data.RawEvents.Trial{1,x-1}.Events, 'Port1In') %% add dependency for timming in trial
%                 if any(BpodSystem.Data.RawEvents.Trial{1,x-1}.Events.Port1In(:) > timestart & BpodSystem.Data.RawEvents.Trial{1,x-1}.Events.Port1In(:) < (timeend + 0.2))
%                      Outcomes(x-1) = 1;
%                 else
%                     Outcomes(x-1) = 3;%3
%                 end
%             else
%                 Outcomes(x-1) = 3;%3
% %             elseif ~isnan(BpodSystem.Data.RawEvents.Trial{x}.States.Punish(1))
% %                 Outcomes(x) = 0;
% %             else
% %                 Outcomes(x) = 3;
%             end
%         end
%         TrialTypeOutcomePlot(BpodSystem.GUIHandles.OutcomePlot,'update',BpodSystem.Data.nTrials+1,TrialTypes,Outcomes)
%         %%%
%         end
%         

%%% tal for plot fix dependencies
        Outcomes = zeros(1,BpodSystem.Data.nTrials);
        for x = 1:BpodSystem.Data.nTrials

            timestart=BpodSystem.Data.RawEvents.Trial{1, x}.States.AnswerPeriod(1);
            timeend=BpodSystem.Data.RawEvents.Trial{1, x}.States.RewardConsumption(2);
            if isfield(BpodSystem.Data.RawEvents.Trial{1,x}.Events, 'Port1In') %% add dependency for timming in trial
                if any(BpodSystem.Data.RawEvents.Trial{1,x}.Events.Port1In(:) > timestart & BpodSystem.Data.RawEvents.Trial{1,x}.Events.Port1In(:) < (timeend + 0.2))
                     Outcomes(x) = 1;
                else
                    Outcomes(x) = 2;%3
                end
            else
                Outcomes(x) = 2;%3
%             elseif ~isnan(BpodSystem.Data.RawEvents.Trial{x}.States.Punish(1))
%                 Outcomes(x) = 0;
%             else
%                 Outcomes(x) = 3;
            end
        end
        TrialTypeOutcomePlot(BpodSystem.GUIHandles.OutcomePlot,'update',BpodSystem.Data.nTrials+1,TrialTypes,Outcomes)
        %%%
        
                


        if S.GUI.ProtocolType == 1
            
            
            [Outcomes, PrevProtocolTypes, Early, PrevTrialTypes] = GetBehavioralPerformance(BpodSystem.Data);
            OutcomePlot2D(BpodSystem.GUIHandles.YesNoPerfOutcomePlot, BpodSystem.GUIHandles.DisplayNTrials, 'update', BpodSystem.Data.nTrials+1,TrialTypes_seq, Outcomes);
            
            %get % rewarded is past RewardsForLastNTrials trials (can probably be combined with outcomes above)
            Rewards = 0;
            for x = max([1 BpodSystem.Data.nTrials-(RewardsForLastNTrials-1)]):BpodSystem.Data.nTrials
                if BpodSystem.Data.TrialSettings(x).GUI.ProtocolType==S.GUI.ProtocolType & isfield(BpodSystem.Data.RawEvents.Trial{x}.States,'Reward')
                    if ~isnan(BpodSystem.Data.RawEvents.Trial{x}.States.Reward(1))
                        Rewards = Rewards + 1;
                    end
                end
            end
            S.ProtocolHistory(end,3) = Rewards / RewardsForLastNTrials;
            %             catch ME
            %                 warning('Data save error!!!');
            %                 bad = 1;
            %             end
        end
        if bad==0
            SaveBpodSessionData(); % Saves the field BpodSystem.Data to the current data file
            BpodSystem.ProtocolSettings = S;
            SaveBpodProtocolSettings();
        else
            warning('Data not saved!!!');
        end
    end
    
    HandlePauseCondition; % Checks to see if the protocol is paused. If so, waits until user resumes.
    if BpodSystem.Status.BeingUsed == 0
        return
    end
end
end

%%
% functions to move zabers

function manual_Z_Move(hObject, eventdata)
Z_Move(get(hObject,'String'));
end

function Z_Move(position)
global motors_properties;
 Motor_Move(position, motors_properties.Z_motor_num);
end


function manual_Lx_Move(hObject, eventdata)
 Lx_Move(get(hObject,'String'));
end

function Lx_Move(position)
global motors_properties;
 Motor_Move(position, motors_properties.Lx_motor_num);
end

function manual_Ly_Move(hObject, eventdata)
 Ly_Move(get(hObject,'String'));
 end

function Ly_Move(position)
global motors_properties;
 Motor_Move(position, motors_properties.Ly_motor_num);
end


%%

%% pure (x2) reward Function
function reward = shuffle_rewards_with_constraints(reward)
    % Ensure that the shuffled rewards respect the rule: small/large after 2 regular rewards
%     while true
    len_to_shuffle=length(reward(7:end));
    %     shuffled_rewards = reward(randperm(len_to_shuffle));
    % Number of each value
%     num1 = round(0.8 * len_to_shuffle); % 80% 1s
%     num2 = round(0.1 * len_to_shuffle); % 10% 2s
%     num3 = round(0.1 * len_to_shuffle); % 10% 2s

    % Generate lrewardarray
    lrewardarray = 1:3:len_to_shuffle;

    % Randomly sample 3 unique indices for large rewards
    indexslarge = randsample(lrewardarray, 3);

    % Calculate the ranges that cannot be used for small rewards
    indexsblarge1 = indexslarge - 1;
    indexsblarge2 = indexslarge - 2;
    indexsalarge1 = indexslarge + 1;
    indexsalarge2 = indexslarge + 2;

    % Combine all indices to exclude
    notuse = unique([indexslarge, indexsblarge1, indexsblarge2, indexsalarge1, indexsalarge2]);

    % Find valid options for small rewards
    optionsforsmall = setdiff(lrewardarray, notuse);

    % Ensure there is enough spacing between options
    checksmall = diff(optionsforsmall);
    validoptions = optionsforsmall([true, checksmall > 2]); % Keep valid options

    % Randomly select 3 valid indices for small rewards
    if length(validoptions) >= 3
        srewardarray = randsample(validoptions, 3);
    else
        error('Not enough valid options for small rewards.');
    end

    % Offset both sets of indices by 6
    srewardarray = srewardarray + 6;
    indexslarge = indexslarge + 6;

    % Initialize rewards array
    reward = ones(1, length(reward)); % Assuming reward is initialized as zeros
    reward(srewardarray) = 2; % Assign 2 for small rewards
    reward(indexslarge) = 3; % Assign 3 for large rewards
end

%%
function reward = shuffle_rewards_with_constraints_new(reward)
    % Ensure that the shuffled rewards respect the rule: small/large after 2 regular rewards
    len_to_shuffle = length(reward(7:end));
    
    % Generate reward array
    lrewardarray = 1:3:len_to_shuffle;
    
    % Randomly sample 3 unique indices for large rewards
    indexslarge = randsample(lrewardarray, 3);
    
    % Calculate the ranges that cannot be used for small rewards
    indexsblarge1 = indexslarge - 1;
    indexsblarge2 = indexslarge - 2;
    indexsalarge1 = indexslarge + 1;
    indexsalarge2 = indexslarge + 2;
    
    % Combine all indices to exclude
    notuse = unique([indexslarge, indexsblarge1, indexsblarge2, indexsalarge1, indexsalarge2]);
    
    % Find valid options for small rewards
    optionsforsmall = setdiff(lrewardarray, notuse);
    
    % Ensure there is enough spacing between options
    checksmall = diff(optionsforsmall);
    validoptions = optionsforsmall([true, checksmall > 2]); % Keep valid options
    
    % Randomly select 3 valid indices for small rewards
    if length(validoptions) >= 3
        srewardarray = randsample(validoptions, 3);
    else
        error('Not enough valid options for small rewards.');
    end
    
    % Offset both sets of indices by 6
    srewardarray = srewardarray + 6;
    indexslarge = indexslarge + 6;
    
    % Initialize rewards array
    reward = ones(1, length(reward)); % Assuming reward is initialized as zeros
    reward(srewardarray) = 2; % Assign 2 for small rewards
    reward(indexslarge) = 3; % Assign 3 for large rewards
    
    % Check for adjacency of small (2) and large (3) rewards and shuffle if found
    while any(abs(diff([srewardarray, indexslarge])) == 1)
        % If adjacent rewards are found, shuffle again
        srewardarray = randsample(validoptions, 3);
        reward = ones(1, length(reward)); % Reset the rewards array
        reward(srewardarray) = 2; % Assign 2 for small rewards
        reward(indexslarge) = 3; % Assign 3 for large rewards
    end
end

%% pure iti function- no 45 or 120 sec consecutivly, 6 of each, rewards gets one of each 

function iti_vector = assign_pure_iti(reward)
% iti_size_v=[0,45,120];
% largerewardind=find(reward==3);
% smallrewardind=find(reward==2);
% 
% % Generate a random permutation of the indices
% shuffled_indices = randperm(length(largerewardind));
% 
% % Shuffle the vector using the random indices
% shuffled_vector_l = largerewardind(shuffled_indices);
% 
% % Generate a random permutation of the indices
% shuffled_indices = randperm(length(smallrewardind));
% 
% % Shuffle the vector using the random indices
% shuffled_vector_s = smallrewardind(shuffled_indices);
% 
% iti_vector=zeros(len(reward));
% 
% iti_vector(shuffled_vector_s)=iti_size_v;
% iti_vector(shuffled_vector_l)=iti_size_v;
% 
% indexestonotuse45=find(iti_vector==45)
% indextonotuse120=find(it_vecore==120)
% indexestonotuse45=[indexestonotuse45, indexestonotuse45+1, indexestonotuse45+2,indexestonotuse45-1, indexestonotuse45-2];
% indextonotuse120=[indextonotuse120, indextonotuse120+1, indextonotuse120+2, indextonotuse120-1, indextonotuse120-2];
% 

iti_size_v = [0, 45, 120]; % ITI sizes
largerewardind = find(reward == 3); % Indices for larger reward
smallrewardind = find(reward == 2); % Indices for small reward

% Generate a random permutation of the indices
shuffled_indices = randperm(length(largerewardind));
shuffled_vector_l = largerewardind(shuffled_indices); % Shuffled larger reward indices

% Generate a random permutation of the indices
shuffled_indices = randperm(length(smallrewardind));
shuffled_vector_s = smallrewardind(shuffled_indices); % Shuffled small reward indices

% Initialize iti_vector
iti_vector = zeros(length(reward), 1);

% Assign iti_size_v values to the shuffled indices
iti_vector(shuffled_vector_s) = iti_size_v(2); % Assign small reward (45)
iti_vector(shuffled_vector_l) = iti_size_v(3); % Assign large reward (120)

% Identify indices to avoid
indexestonotuse45 = find(iti_vector == 45);
indextonotuse120 = find(iti_vector == 120);

% Avoid indices for 45 and 120 (including surrounding 2 positions)
indexestonotuse45 = [indexestonotuse45, indexestonotuse45 + 1, indexestonotuse45 + 2, ...
                     indexestonotuse45 - 1, indexestonotuse45 - 2];
indextonotuse120 = [indextonotuse120, indextonotuse120 + 1, indextonotuse120 + 2, ...
                    indextonotuse120 - 1, indextonotuse120 - 2];

% Ensure that the indices are within bounds
indexestonotuse45 = unique(indexestonotuse45(indexestonotuse45 > 0 & indexestonotuse45 <= length(iti_vector)));
indextonotuse120 = unique(indextonotuse120(indextonotuse120 > 0 & indextonotuse120 <= length(iti_vector)));

% Find valid indices where we can assign 45 and 120
valid_indices_45 = setdiff(1:length(iti_vector), indexestonotuse45);
valid_indices_120 = setdiff(1:length(iti_vector), indextonotuse120);

% % Randomly assign 5 values of 45 to valid positions
% indices_45 = randsample(valid_indices_45, 5);
% iti_vector(indices_45) = 45;
% 
% % Randomly assign 5 values of 120 to valid positions
% indices_120 = randsample(valid_indices_120, 5);
% iti_vector(indices_120) = 120;


% Assign 5 values of 45 and 5 values of 120, ensuring no consecutive assignments
for i = 1:5
    % Randomly assign 45 to a valid position, ensuring no consecutive 45's
    while true
        index_45 = randsample(valid_indices_45, 1);
        if (index_45 > 1 && iti_vector(index_45 - 1) ~= 45) && ...
           (index_45 < length(iti_vector) && iti_vector(index_45 + 1) ~= 45)
            iti_vector(index_45) = 45;
            break;
        end
    end
    % Remove used index from valid indices
    valid_indices_45 = setdiff(valid_indices_45, index_45);
    
    % Randomly assign 120 to a valid position, ensuring no consecutive 120's
    while true
        index_120 = randsample(valid_indices_120, 1);
        if (index_120 > 1 && iti_vector(index_120 - 1) ~= 120) && ...
           (index_120 < length(iti_vector) && iti_vector(index_120 + 1) ~= 120)
            iti_vector(index_120) = 120;
            break;
        end
    end
    % Remove used index from valid indices
    valid_indices_120 = setdiff(valid_indices_120, index_120);
end

end

%%
%%%%%% no restrictions versions %%%%%
%%Function to Shuffle Rewards Without Constraints (Allowing Consecutive Values)
function reward = shuffle_rewards_with_consecutives(reward)
    len_to_shuffle = length(reward(7:end)); % Length of rewards to shuffle
    
    % Generate lrewardarray
    lrewardarray = 1:3:len_to_shuffle;
    
    % Randomly sample 3 unique indices for large rewards
    indexslarge = randsample(lrewardarray, 3);
    
    % Calculate the ranges that cannot be used for small rewards
    indexsblarge1 = indexslarge - 1;
    indexsblarge2 = indexslarge - 2;
    indexsalarge1 = indexslarge + 1;
    indexsalarge2 = indexslarge + 2;
    
    % Combine all indices to exclude
    notuse = unique([indexslarge, indexsblarge1, indexsblarge2, indexsalarge1, indexsalarge2]);
    
    % Find valid options for small rewards
    optionsforsmall = setdiff(lrewardarray, notuse);
    
    % Ensure there is enough spacing between options
    checksmall = diff(optionsforsmall);
    validoptions = optionsforsmall([true, checksmall > 2]); % Keep valid options
    
    % Randomly select 3 valid indices for small rewards
    if length(validoptions) >= 3
        srewardarray = randsample(validoptions, 3);
    else
        error('Not enough valid options for small rewards.');
    end
    
    % Offset both sets of indices by 6
    srewardarray = srewardarray + 6;
    indexslarge = indexslarge + 6;
    
    % Initialize rewards array
    reward = ones(1, length(reward)); % Assuming reward is initialized as zeros
    reward(srewardarray) = 2; % Assign 2 for small rewards
    reward(indexslarge) = 3; % Assign 3 for large rewards
end

%% Function to Assign ITI Values with Consecutive Values Allowed
function iti_vector = assign_iti_with_consecutives(reward)
    iti_size_v = [0, 45, 120]; % ITI sizes
    largerewardind = find(reward == 3); % Indices for larger reward
    smallrewardind = find(reward == 2); % Indices for small reward
    
    % Generate a random permutation of the indices
    shuffled_indices = randperm(length(largerewardind));
    shuffled_vector_l = largerewardind(shuffled_indices); % Shuffled larger reward indices
    
    % Generate a random permutation of the indices
    shuffled_indices = randperm(length(smallrewardind));
    shuffled_vector_s = smallrewardind(shuffled_indices); % Shuffled small reward indices
    
    % Initialize iti_vector
    iti_vector = zeros(length(reward), 1);
    
    % Assign iti_size_v values to the shuffled indices
    iti_vector(shuffled_vector_s) = iti_size_v(2); % Assign small reward (45)
    iti_vector(shuffled_vector_l) = iti_size_v(3); % Assign large reward (120)
    
    % Identify indices to avoid
    indexestonotuse45 = find(iti_vector == 45);
    indextonotuse120 = find(iti_vector == 120);
    
    % Avoid indices for 45 and 120 (including surrounding 2 positions)
    indexestonotuse45 = [indexestonotuse45, indexestonotuse45 + 1, indexestonotuse45 + 2, ...
                         indexestonotuse45 - 1, indexestonotuse45 - 2];
    indextonotuse120 = [indextonotuse120, indextonotuse120 + 1, indextonotuse120 + 2, ...
                        indextonotuse120 - 1, indextonotuse120 - 2];
    
    % Ensure that the indices are within bounds
    indexestonotuse45 = unique(indexestonotuse45(indexestonotuse45 > 0 & indexestonotuse45 <= length(iti_vector)));
    indextonotuse120 = unique(indextonotuse120(indextonotuse120 > 0 & indextonotuse120 <= length(iti_vector)));
    
    % Find valid indices where we can assign 45 and 120
    valid_indices_45 = setdiff(1:length(iti_vector), indexestonotuse45);
    valid_indices_120 = setdiff(1:length(iti_vector), indextonotuse120);
    
    % Assign 5 values of 45 and 5 values of 120, allowing consecutive values
    for i = 1:5
        % Randomly assign 45 to a valid position
        index_45 = randsample(valid_indices_45, 1);
        iti_vector(index_45) = 45;
        
        % Remove used index from valid indices
        valid_indices_45 = setdiff(valid_indices_45, index_45);
        
        % Randomly assign 120 to a valid position
        index_120 = randsample(valid_indices_120, 1);
        iti_vector(index_120) = 120;
        
        % Remove used index from valid indices
        valid_indices_120 = setdiff(valid_indices_120, index_120);
    end
end

%%%%%% end no restrictions %%%%%
%%
%%%%%% 2 consecutive iti %%%%
%%Function to Assign ITI Values with Forced Consecutive Placement in Pairs
function iti_vector = assign_iti_with_2consecutive(reward)
    iti_size_v = [0, 45, 120]; % ITI sizes
    largerewardind = find(reward == 3); % Indices for larger reward
    smallrewardind = find(reward == 2); % Indices for small reward
    
    % Generate a random permutation of the indices
    shuffled_indices = randperm(length(largerewardind));
    shuffled_vector_l = largerewardind(shuffled_indices); % Shuffled larger reward indices
    
    % Generate a random permutation of the indices
    shuffled_indices = randperm(length(smallrewardind));
    shuffled_vector_s = smallrewardind(shuffled_indices); % Shuffled small reward indices
    
    % Initialize iti_vector
    iti_vector = zeros(length(reward), 1);
    
    % Assign iti_size_v values to the shuffled indices
    iti_vector(shuffled_vector_s) = iti_size_v(2); % Assign small reward (45)
    iti_vector(shuffled_vector_l) = iti_size_v(3); % Assign large reward (120)
    
    % Identify indices to avoid
    indexestonotuse45 = find(iti_vector == 45);
    indextonotuse120 = find(iti_vector == 120);
    
    % Avoid indices for 45 and 120 (including surrounding 2 positions)
    indexestonotuse45 = [indexestonotuse45, indexestonotuse45 + 1, indexestonotuse45 + 2, ...
                         indexestonotuse45 - 1, indexestonotuse45 - 2];
    indextonotuse120 = [indextonotuse120, indextonotuse120 + 1, indextonotuse120 + 2, ...
                        indextonotuse120 - 1, indextonotuse120 - 2];
    
    % Ensure that the indices are within bounds
    indexestonotuse45 = unique(indexestonotuse45(indexestonotuse45 > 0 & indexestonotuse45 <= length(iti_vector)));
    indextonotuse120 = unique(indextonotuse120(indextonotuse120 > 0 & indextonotuse120 <= length(iti_vector)));
    
    % Find valid indices where we can assign 45 and 120
    valid_indices_45 = setdiff(1:length(iti_vector), indexestonotuse45);
    valid_indices_120 = setdiff(1:length(iti_vector), indextonotuse120);
    
    % Ensure consecutive 45 and 120 assignments in pairs, not triplets
    for i = 1:5
        % Randomly assign 45 and 120 in consecutive positions (pair them)
        index_45 = randsample(valid_indices_45, 1);
        iti_vector(index_45) = 45;
        
        % Find a valid index for 120, which should be the next position
        index_120 = index_45 + 1; % Ensure consecutive assignment
        
        % Check if index_120 is within bounds and not already assigned
        if index_120 <= length(iti_vector) && iti_vector(index_120) == 0
            iti_vector(index_120) = 120;
        elseif index_120 > length(iti_vector) || iti_vector(index_120) ~= 0
            % Try the next valid index by searching in the remaining valid indices
            available_120_indices = setdiff(valid_indices_120, [index_45, index_120]);
            if ~isempty(available_120_indices)
                index_120 = available_120_indices(1); % Pick the first available position
                iti_vector(index_120) = 120;
            else
                error('Cannot find a valid index for 120 after 45.');
            end
        end
        
        % Remove used indices from valid indices
        valid_indices_45 = setdiff(valid_indices_45, index_45);
        valid_indices_120 = setdiff(valid_indices_120, index_120);
        
        % Repeat for the reverse pair: 120 followed by 45
        index_120_rev = randsample(valid_indices_120, 1);
        iti_vector(index_120_rev) = 120;
        
        % Find a valid index for 45, which should be the next position
        index_45_rev = index_120_rev + 1; % Ensure consecutive assignment
        
        % Check if index_45_rev is within bounds and not already assigned
        if index_45_rev <= length(iti_vector) && iti_vector(index_45_rev) == 0
            iti_vector(index_45_rev) = 45;
        elseif index_45_rev > length(iti_vector) || iti_vector(index_45_rev) ~= 0
            % Try the next valid index by searching in the remaining valid indices
            available_45_indices = setdiff(valid_indices_45, [index_120_rev, index_45_rev]);
            if ~isempty(available_45_indices)
                index_45_rev = available_45_indices(1); % Pick the first available position
                iti_vector(index_45_rev) = 45;
            else
                error('Cannot find a valid index for 45 after 120.');
            end
        end
        
        % Remove used indices from valid indices
        valid_indices_45 = setdiff(valid_indices_45, index_45_rev);
        valid_indices_120 = setdiff(valid_indices_120, index_120_rev);
    end
end

%%% end %%%


%% impure reward
function reward = shuffle_rewards_impures(reward)
    % Ensure that the shuffled rewards respect the rule: small/large after 2 regular rewards
%     while true
    len_to_shuffle=length(reward(7:end));
    %     shuffled_rewards = reward(randperm(len_to_shuffle));
    % Number of each value
%     num1 = round(0.8 * len_to_shuffle); % 80% 1s
%     num2 = round(0.1 * len_to_shuffle); % 10% 2s
%     num3 = round(0.1 * len_to_shuffle); % 10% 2s

    % Generate lrewardarray
    lrewardarray = 1:3:len_to_shuffle;

    % Randomly sample 3 unique indices for large rewards
    indexslarge = randsample(lrewardarray, 3);

    % Calculate the ranges that cannot be used for small rewards
    indexsblarge1 = indexslarge - 1;
    indexsblarge2 = indexslarge - 2;
    indexsalarge1 = indexslarge + 1;
    indexsalarge2 = indexslarge + 2;

    % Combine all indices to exclude
    notuse = unique([indexslarge, indexsblarge1, indexsblarge2, indexsalarge1, indexsalarge2]);

    % Find valid options for small rewards
    optionsforsmall = setdiff(lrewardarray, notuse);

    % Ensure there is enough spacing between options
    checksmall = diff(optionsforsmall);
    validoptions = optionsforsmall([true, checksmall > 2]); % Keep valid options

    % Randomly select 3 valid indices for small rewards
    if length(validoptions) >= 3
        srewardarray = randsample(validoptions, 2);
    else
        error('Not enough valid options for small rewards.');
    end

    % Offset both sets of indices by 6
    srewardarray = srewardarray + 6;
    indexslarge = indexslarge + 6;

    % Initialize rewards array
    reward = ones(1, length(reward)); % Assuming reward is initialized as zeros
    reward(srewardarray) = 2; % Assign 2 for small rewards
    cons=find(reward==2);
    cons1=cons(1)+1;
    reward(cons1)=2;
    reward(indexslarge) = 3; % Assign 3 for large rewards
end
%%% end inpure small reward ###


function reward = shuffle_rewards_impurel(reward)
    % Ensure that the shuffled rewards respect the rule: small/large after 2 regular rewards
%     while true
    len_to_shuffle=length(reward(7:end));
    %     shuffled_rewards = reward(randperm(len_to_shuffle));
    % Number of each value
%     num1 = round(0.8 * len_to_shuffle); % 80% 1s
%     num2 = round(0.1 * len_to_shuffle); % 10% 2s
%     num3 = round(0.1 * len_to_shuffle); % 10% 2s

    % Generate lrewardarray
    lrewardarray = 1:3:len_to_shuffle;

    % Randomly sample 3 unique indices for large rewards
    indexslarge = randsample(lrewardarray, 2);

    % Calculate the ranges that cannot be used for small rewards
    indexsblarge1 = indexslarge - 1;
    indexsblarge2 = indexslarge - 2;
    indexsalarge1 = indexslarge + 1;
    indexsalarge2 = indexslarge + 2;

    % Combine all indices to exclude
    notuse = unique([indexslarge, indexsblarge1, indexsblarge2, indexsalarge1, indexsalarge2]);

    % Find valid options for small rewards
    optionsforsmall = setdiff(lrewardarray, notuse);

    % Ensure there is enough spacing between options
    checksmall = diff(optionsforsmall);
    validoptions = optionsforsmall([true, checksmall > 2]); % Keep valid options

    % Randomly select 3 valid indices for small rewards
    if length(validoptions) >= 3
        srewardarray = randsample(validoptions, 3);
    else
        error('Not enough valid options for small rewards.');
    end

    % Offset both sets of indices by 6
    srewardarray = srewardarray + 6;
    indexslarge = indexslarge + 6;

    % Initialize rewards array
    reward = ones(1, length(reward)); % Assuming reward is initialized as zeros
    reward(srewardarray) = 2; % Assign 2 for small rewards
    reward(indexslarge) = 3; % Assign 3 for large rewards
    cons=find(reward==3);
    cons1=cons(1)+1;
    reward(cons1)=3;
end

function pattern1 = iti_long_for_pure(n)
%     base_pattern = [120 45 120 0 120 120 120 120 45 120 45 120 0 120 120];% 120 45 120 0 120 120 120 120 0 0 0 120 120 45 120];
%     base_pattern = [NaN 120 0 120 NaN NaN 120 120 NaN NaN 120 45 120 45 120 NaN 120 120 NaN NaN NaN 120 0 120 45 120 120 NaN 120 120 NaN 120 0 120 NaN 120 0 120 NaN NaN 120 45 120];
%     base_pattern = [ 120, 120, 0, 120, 120, 120, 120,120, 0, 120, 45, 120, 120, 45, 120, 120 , 45, 120, 0, 120, 120, 45, 120, 120, 45, 120, 0, 120, 120, 120, 120];%the pne for 2 pos 1
%       lickport
    base_pattern = [ 120, 120, 0, 120, 120, 120, 120,120, 0, 120, 0, 120, 120, 0, 120, 120 , 0, 120, 0, 120, 120, 0, 120, 120, 120, 120, 0, 120, 120, 120, 120];

    % Replace NaN with either 45 or 0 with 50-50% probability
%     for i = 1:length(base_pattern)
%         if isnan(base_pattern(i))  % If the value is NaN
%             if rand < 0.5
%                 base_pattern(i) = 45;  % Assign 45
%             else
%                 base_pattern(i) = 0;   % Assign 0
%             end
%         end
%     end
%     pattern1 = repmat(base_pattern, 1, n / length(base_pattern));
    values = [45, 0];  % Possible values to replace NaN
    probabilities = [0.5, 0.5];  % Equal probability for 45 and 0
    
    % Initialize the resulting pattern
    pattern1 = [];
    
    % Replicate the base pattern as many times as needed to fill 'n' elements
    for i = 1:floor(n / length(base_pattern))  % Number of full repetitions
        temp_pattern = base_pattern;  % Copy the base pattern
        
        % Find NaN positions and replace them with random values (45 or 0)
        p_indices = find(isnan(temp_pattern));  % Find 'NaN' positions
        temp_pattern(p_indices) = randsample(values, length(p_indices), true, probabilities);
        
        % Append the temporary pattern to the final pattern
        pattern1 = [pattern1 temp_pattern];
    end
end

function pattern2 = reward_for_pure(n)
    % 1=regular, 2=small, 3=large final right num!!!!

%     base_pattern = [1 NaN 1 NaN 1 NaN 1 1 NaN 1 1 1 NaN 1 NaN];% 1 NaN 1 NaN 1 NaN 1 1 NaN 1 1 1 NaN 1 1]; % Use NaN as placeholder
%     base_pattern = [1	1	3	1	3	1	1	1	3	1	1	1	1	3	1	3	1	1	1	3	1	1	1	1	1	1	3	1	1	3	1	1	3	1	1	1	1	1	3	1	1	3	1];
%       base_pattern= [3, 1, 1, 1, 3, 1, 3, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1,
%       1, 3, 1, 1, 1, 3, 1, 3, 1, 3, 1, 1, 3, 1]; %the pne for 2 pos 1
%       lickport
%         base_pattern= [ 1,   3,  1,  1,   3,  1,   3,  1,  1,   1,  1,
%         1,  1,  3,  1,   1,   1,  1,  3,   1,   1,  1,  3 , 1,  3,   1,
%         3,  1,   1,   3,   1]; % first 2d to 1d experiment mouse 101105
        base_pattern= [ 1,   1,  1,  1,   3,  1,   3,  1,  1,   1,  2,   1,  1,  3,  1,   1,   1,  1,  3,   1,   1,  1,  3 , 1,  3,   1,   2,  1,   1,   3,   1]; %mouse 90nc

    probabilities = [3/6, 1.5/6, 1.5/6];%[2/5, 1.5/5, 1.5/5];%, 1.5/5]; % Probabilities for [2, 3, 1]
    values = [1, 2, 3];

    pattern2 = [];
    for i = 1:(n / length(base_pattern))
        temp_pattern = base_pattern;
        p_indices = find(isnan(temp_pattern)); % Find 'p' positions
        temp_pattern(p_indices) = randsample(values, length(p_indices), true, probabilities);
        pattern2 = [pattern2 temp_pattern];
    end
end

function pattern3 = three_cons_large(n)
    pattern3 = ones(1, n);  % Start with all 1s
    middle_indices = floor(n/2) + (-1:1); % Select the 3 middle indices
    pattern3(middle_indices) = 3; % Set middle values to 3
end

function pattern4 = long_short_long_for_three_large(n)
    pattern4 = randsample([120, 0], n, true); % Randomly 120 or 0
    middle_indices = floor(n/2) + (-1:1);
    pattern4(middle_indices) = [120, 0, 120]; % Set middle values
end

function pattern5 = long_long_long_for_three_large(n)
    pattern5 = randsample([120, 0], n, true); % Randomly 120 or 0
    middle_indices = floor(n/2) + (-1:1);
    pattern5(middle_indices) = [120, 120, 120]; % Set middle values
end
%%% end impure large %%%%
%%%position%%%
%%%%tal%%%%



