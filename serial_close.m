function serial_close(zaberObj)
% SERIAL_CLOSE Close serial connection to Zaber motors
%
% Usage:
%   serial_close(motors);

if nargin < 1 || ~isa(zaberObj, 'ZaberTCD1000')
    error('serial_close:InvalidInput', 'Input must be a ZaberTCD1000 object');
end

try
    % Close the serial object
    fclose(zaberObj.sobj);
    fprintf('Zaber motors disconnected\n');

catch ME
    warning('serial_close:CloseFailed', ...
        'Failed to close serial connection: %s', ME.message);
end

end
