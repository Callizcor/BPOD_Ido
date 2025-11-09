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

if zaberObj.IsConnected
    warning('serial_open:AlreadyConnected', 'Motors already connected');
    return;
end

try
    % Create serial port object
    zaberObj.SerialPort = serialport(zaberObj.PortName, 115200);
    configureTerminator(zaberObj.SerialPort, "CR/LF");

    % Set timeouts
    zaberObj.SerialPort.Timeout = 2;

    zaberObj.IsConnected = true;
    motors = zaberObj;  % Store in global variable for access by Motor_Move

    fprintf('Zaber motors connected on %s\n', zaberObj.PortName);

catch ME
    error('serial_open:ConnectionFailed', ...
        'Failed to open connection to %s: %s', zaberObj.PortName, ME.message);
end

end
