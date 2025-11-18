function Motor_Move(position, motor_num)
% MOTOR_MOVE Move Zaber motor to absolute position
% This version matches the working protocol's implementation
%
% Inputs:
%   position - Target position in microsteps (numeric or char)
%   motor_num - Motor number (1=Lx, 2=Z, 4=Ly for COM6 setup)
%
% Usage:
%   Motor_Move(210000, 2);  % Move motor 2 (Z-axis) to position 210000

global motors;

if isnumeric(position)
    move_absolute(motors, position, motor_num);
elseif ischar(position)
    position = str2num(position); %#ok<ST2NM>
    if isempty(position)
        move_absolute(motors, 0, motor_num);
    else
        move_absolute(motors, position, motor_num);
    end
end

end
