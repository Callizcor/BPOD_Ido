function serial_open(zaberObj)
% SERIAL_OPEN Open serial connection to Zaber motors
%
% Usage:
%   motors = ZaberTCD1000('COM6');
%   serial_open(motors);

global motors

if nargin < 1 || ~isa(zaberObj, 'ZaberTCD1000')
    error('serial_open:InvalidInput', 'Input must be a ZaberTCD1000 object');
end

try
    % Open the serial object that was created by ZaberTCD1000 constructor
    fopen(zaberObj.sobj);

    % Store in global variable for access by Motor_Move
    motors = zaberObj;

    fprintf('Zaber motors connected\n');

catch ME
    error('serial_open:ConnectionFailed', ...
        'Failed to open serial connection: %s', ME.message);
end

end
