function sma = GenerateBitcodeStateMachine(bitcodeString, outputChannel)
% GENERATEBITCODESTATEMACHINE Creates state machine for 20-bit bitcode transmission
%
% Inputs:
%   bitcodeString - 20-character binary string (e.g., '10110101101010110101')
%   outputChannel - Output channel for bitcode (default: 'BNC2')
%
% Transmission Format:
%   Start pulse: 60ms HIGH
%   For each of 20 bits:
%       - 20ms LOW
%       - 20ms HIGH (if bit=1) or 20ms LOW (if bit=0)
%   End pulse: 60ms HIGH
%   Total duration: ~1.02 seconds
%
% Example:
%   bitcodeValue = randi([0, 2^20-1]);
%   bitcodeString = dec2bin(bitcodeValue, 20);
%   sma = GenerateBitcodeStateMachine(bitcodeString, 'BNC2');

if nargin < 2
    outputChannel = 'BNC2';
end

% Validate bitcode string
if length(bitcodeString) ~= 20
    error('Bitcode string must be exactly 20 characters');
end

if ~all(ismember(bitcodeString, ['0' '1']))
    error('Bitcode string must contain only 0 and 1');
end

% Timing parameters (in seconds)
START_PULSE_DURATION = 0.060;  % 60ms
BIT_LOW_DURATION = 0.020;      % 20ms
BIT_HIGH_DURATION = 0.020;     % 20ms
END_PULSE_DURATION = 0.060;    % 60ms

% Create new state machine
sma = NewStateMachine();

% Start pulse (60ms HIGH)
sma = AddState(sma, 'Name', 'BitcodeStart', ...
    'Timer', START_PULSE_DURATION, ...
    'StateChangeConditions', {'Tup', 'Bit1_Low'}, ...
    'OutputActions', {outputChannel, 1});

% Generate states for each bit
for bitIdx = 1:20
    currentBit = bitcodeString(bitIdx);

    % State name
    stateName_Low = sprintf('Bit%d_Low', bitIdx);

    % Determine next state
    if bitIdx < 20
        stateName_Next = sprintf('Bit%d_Low', bitIdx + 1);
    else
        stateName_Next = 'BitcodeEnd';
    end

    if currentBit == '1'
        % Bit = 1: LOW for 20ms, then HIGH for 20ms
        stateName_High = sprintf('Bit%d_High', bitIdx);

        % LOW phase
        sma = AddState(sma, 'Name', stateName_Low, ...
            'Timer', BIT_LOW_DURATION, ...
            'StateChangeConditions', {'Tup', stateName_High}, ...
            'OutputActions', {outputChannel, 0});

        % HIGH phase
        sma = AddState(sma, 'Name', stateName_High, ...
            'Timer', BIT_HIGH_DURATION, ...
            'StateChangeConditions', {'Tup', stateName_Next}, ...
            'OutputActions', {outputChannel, 1});

    else
        % Bit = 0: LOW for 40ms total (20ms + 20ms)
        sma = AddState(sma, 'Name', stateName_Low, ...
            'Timer', BIT_LOW_DURATION + BIT_HIGH_DURATION, ...
            'StateChangeConditions', {'Tup', stateName_Next}, ...
            'OutputActions', {outputChannel, 0});
    end
end

% End pulse (60ms HIGH)
sma = AddState(sma, 'Name', 'BitcodeEnd', ...
    'Timer', END_PULSE_DURATION, ...
    'StateChangeConditions', {'Tup', 'exit'}, ...
    'OutputActions', {outputChannel, 1});

end
