function Motor_Move(position, motorNum)
% MOTOR_MOVE Move Zaber motor to absolute position
%
% Inputs:
%   position - Target position in microsteps (0-1,049,869)
%   motorNum - Motor number (1-4)
%
% Usage:
%   Motor_Move(210000, 2);  % Move motor 2 (Z-axis) to position 210000

global motors

if isempty(motors)
    error('Motor_Move:NotConnected', 'Motors not connected. Call serial_open first.');
end

% Validate inputs
if motorNum < 1 || motorNum > 4
    error('Motor_Move:InvalidMotor', 'Motor number must be 1-4');
end

% Convert position to numeric if it's a string
if ischar(position) || isstring(position)
    position = str2double(position);
end

global maximum_zaber_position;
if position < 0 || position > maximum_zaber_position
    warning('Motor_Move:PositionRange', ...
        'Position %d may be out of range (0-%d)', position, maximum_zaber_position);
end

% Send move command using Zaber binary protocol
% Motor addressing: device number
% Command type: 20 (move absolute)
% Data: position in microsteps
try
    % Zaber binary protocol: [device, command, data1, data2, data3, data4]
    % device: motor number (1-4)
    % command: 20 (move absolute)
    % data: position as 32-bit little-endian integer

    command_byte = 20; % Move absolute
    pos_int = round(position);

    % Convert position to 4 bytes (little-endian)
    data1 = mod(pos_int, 256);
    data2 = mod(floor(pos_int / 256), 256);
    data3 = mod(floor(pos_int / 65536), 256);
    data4 = floor(pos_int / 16777216);

    % Create command packet
    command_packet = uint8([motorNum, command_byte, data1, data2, data3, data4]);

    % Send command
    fwrite(motors.sobj, command_packet);

    % Wait for response (6 bytes)
    pause(0.1); % Give motor time to respond
    if motors.sobj.BytesAvailable >= 6
        response = fread(motors.sobj, 6);
    end

catch ME
    error('Motor_Move:CommandFailed', ...
        'Failed to move motor %d: %s', motorNum, ME.message);
end

end
