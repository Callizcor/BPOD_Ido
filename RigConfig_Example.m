% RIG CONFIGURATION EXAMPLE
% Copy this file and customize for your specific rig setup
%
% Usage:
%   1. Copy this file to RigConfig_YourRigName.m
%   2. Modify parameters for your rig
%   3. Run the config script before starting the protocol
%   4. Or integrate into protocol initialization

%% Rig Identification
RigName = 'Microroom_Rig1';  % Change to your rig name

%% Zaber Motor Configuration

% Serial Port
% Microroom: COM18
% Vivarium Rig 1: COM6
% Vivarium Rig 2: COM11
ZaberPort = 'COM18';

% Motor Assignments (varies by rig)
% COM6 setup: Z=2, Lx=1, Ly=4
% COM18 setup: Z=1, Lx=3, Ly=2
Z_motor_num = 2;   % Z-axis (vertical)
Lx_motor_num = 1;  % Lx-axis (horizontal X)
Ly_motor_num = 4;  % Ly-axis (horizontal Y)

% Position Calibration (in microsteps)
Z_motor_pos = 210000;        % Lickable position
Z_NonLickable = 60000;       % Retracted position (safe, non-lickable)
Lx_motor_pos = 310000;       % X center position
Ly_motor_pos = 310000;       % Y center position

% Position range: 0-620,000 microsteps

%% Task Parameters

% Timing
ResponseDuration = 5;         % Response period (seconds)
DelayDuration = 2;            % Delay period without licking (seconds)
BurstIgnoreDuration = 0.5;    % Burst window duration (seconds)
DebounceDuration = 0.05;      % Debounce duration (seconds)
TrialTimeout = 3600;          % Ready state timeout (seconds)

% Rewards
RewardSize = 0.01;            % Reward valve duration (seconds)
InitRewardSize = 0.05;        % Initial water delivery (seconds)
InitWaitDuration = 0.5;       % Wait after initial water (seconds)

% Camera Synchronization
CameraSyncEnabled = 1;        % 1=enabled, 0=disabled
CameraPulseWidth = 0.002;     % 2ms HIGH (250Hz = 4ms period total)

% Bitcode Synchronization
BitcodeEnabled = 1;           % 1=enabled, 0=disabled

% Zaber Motors
ZaberEnabled = 1;             % 1=enabled, 0=disabled

%% Apply Configuration to Bpod

% This section would be called from the main protocol
% to load these parameters into BpodSystem.ProtocolSettings

% global BpodSystem
%
% S = BpodSystem.ProtocolSettings;
%
% % Timing
% S.GUI.ResponseDuration = ResponseDuration;
% S.GUI.DelayDuration = DelayDuration;
% S.GUI.BurstIgnoreDuration = BurstIgnoreDuration;
% S.GUI.DebounceDuration = DebounceDuration;
% S.GUI.TrialTimeout = TrialTimeout;
%
% % Rewards
% S.GUI.RewardSize = RewardSize;
% S.GUI.InitRewardSize = InitRewardSize;
% S.GUI.InitWaitDuration = InitWaitDuration;
%
% % Camera
% S.GUI.CameraSyncEnabled = CameraSyncEnabled;
% S.GUI.CameraPulseWidth = CameraPulseWidth;
%
% % Bitcode
% S.GUI.BitcodeEnabled = BitcodeEnabled;
%
% % Zaber
% S.GUI.ZaberEnabled = ZaberEnabled;
% S.GUI.ZaberPort = ZaberPort;
% S.GUI.Z_motor_pos = Z_motor_pos;
% S.GUI.Z_NonLickable = Z_NonLickable;
% S.GUI.Lx_motor_pos = Lx_motor_pos;
% S.GUI.Ly_motor_pos = Ly_motor_pos;
%
% % Note: Motor numbers are set in motors_properties, not in GUI
%
% BpodSystem.ProtocolSettings = S;

%% Display Configuration

fprintf('\n=== RIG CONFIGURATION ===\n');
fprintf('Rig Name: %s\n', RigName);
fprintf('\nZaber Motors:\n');
fprintf('  Port: %s\n', ZaberPort);
fprintf('  Motor Assignments: Z=%d, Lx=%d, Ly=%d\n', Z_motor_num, Lx_motor_num, Ly_motor_num);
fprintf('  Z Positions: Center=%d, Retract=%d\n', Z_motor_pos, Z_NonLickable);
fprintf('\nTask Parameters:\n');
fprintf('  Response Duration: %.1fs\n', ResponseDuration);
fprintf('  Delay Duration: %.1fs\n', DelayDuration);
fprintf('  Reward Size: %.3fs\n', RewardSize);
fprintf('  Camera Sync: %s (%.1f Hz)\n', ...
    iff(CameraSyncEnabled, 'Enabled', 'Disabled'), 1/(2*CameraPulseWidth));
fprintf('  Bitcode: %s\n', iff(BitcodeEnabled, 'Enabled', 'Disabled'));
fprintf('========================\n\n');

function result = iff(condition, trueVal, falseVal)
    % Inline if function
    if condition
        result = trueVal;
    else
        result = falseVal;
    end
end
