function Motor_Move(position, motorNum)
% MOTOR_MOVE Move Zaber motor to absolute position
%
% Inputs:
%   position - Target position in microsteps (0-620,000)
%   motorNum - Motor number (1-4)
%
% Usage:
%   Motor_Move(210000, 2);  % Move motor 2 (Z-axis) to position 210000

global motors

if isempty(motors) || ~motors.IsConnected
    error('Motor_Move:NotConnected', 'Motors not connected. Call serial_open first.');
end

% Validate inputs
if motorNum < 1 || motorNum > 4
    error('Motor_Move:InvalidMotor', 'Motor number must be 1-4');
end

if position < 0 || position > 620000
    warning('Motor_Move:PositionRange', ...
        'Position %d may be out of range (0-620,000)', position);
end

% Convert position to numeric if it's a string
if ischar(position) || isstring(position)
    position = str2double(position);
end

% Send move command (absolute positioning)
% Format: /[motor] move abs [position]
command = sprintf('/%d move abs %d', motorNum, round(position));

try
    writeline(motors.SerialPort, command);

    % Read response
    response = readline(motors.SerialPort);

    % Check for errors
    if contains(response, 'RJ') || contains(response, 'WR')
        warning('Motor_Move:MoveError', ...
            'Motor %d move error: %s', motorNum, response);
    end

catch ME
    error('Motor_Move:CommandFailed', ...
        'Failed to move motor %d: %s', motorNum, ME.message);
end

end
