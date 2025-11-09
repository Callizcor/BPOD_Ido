classdef ZaberTCD1000 < handle
    % ZABERTCD1000 Controller for Zaber TCD1000 motor system
    %
    % Usage:
    %   zaber = ZaberTCD1000('COM18');
    %   zaber.move(1, 210000);  % Move motor 1 to position 210000
    %   zaber.home(1);          % Home motor 1
    %   pos = zaber.getPosition(1);  % Get current position
    %   delete(zaber);          % Close connection
    %
    % Motor Configuration:
    %   Z-axis: Vertical positioning (motor 1, 2, etc.)
    %   Lx-axis: Horizontal X positioning (motor 3, 1, etc.)
    %   Ly-axis: Horizontal Y positioning (motor 2, 4, etc.)
    %   Position range: 0-620,000 microsteps
    %
    % Common Positions:
    %   Z_center: ~210,000 (lickable position)
    %   Z_retract: ~60,000 (non-lickable position)
    %   Lx_center: ~310,000
    %   Ly_center: ~310,000

    properties (Access = private)
        SerialPort      % Serial port object
        PortName        % COM port name
        IsConnected     % Connection status
    end

    methods
        function obj = ZaberTCD1000(portName)
            % Constructor - Initialize connection to Zaber controller
            %
            % Inputs:
            %   portName - Serial port name (e.g., 'COM18', 'COM6', 'COM11')

            if nargin < 1
                error('ZaberTCD1000:NoPort', 'Port name required (e.g., COM18)');
            end

            obj.PortName = portName;
            obj.IsConnected = false;

            try
                % Create serial port object
                obj.SerialPort = serialport(portName, 115200);
                configureTerminator(obj.SerialPort, "CR/LF");

                % Set timeouts
                obj.SerialPort.Timeout = 2;

                obj.IsConnected = true;
                fprintf('Zaber controller connected on %s\n', portName);

            catch ME
                error('ZaberTCD1000:ConnectionFailed', ...
                    'Failed to connect to %s: %s', portName, ME.message);
            end
        end

        function delete(obj)
            % Destructor - Clean up serial connection
            if obj.IsConnected && ~isempty(obj.SerialPort)
                try
                    delete(obj.SerialPort);
                    obj.IsConnected = false;
                    fprintf('Zaber controller disconnected\n');
                catch
                    % Silently fail on cleanup
                end
            end
        end

        function move(obj, motorNum, position)
            % Move motor to absolute position
            %
            % Inputs:
            %   motorNum - Motor number (1-4)
            %   position - Target position in microsteps (0-620,000)

            if ~obj.IsConnected
                error('ZaberTCD1000:NotConnected', 'Not connected to controller');
            end

            % Validate inputs
            if motorNum < 1 || motorNum > 4
                error('ZaberTCD1000:InvalidMotor', 'Motor number must be 1-4');
            end

            if position < 0 || position > 620000
                warning('ZaberTCD1000:PositionRange', ...
                    'Position %d may be out of range (0-620,000)', position);
            end

            % Send move command (absolute positioning)
            % Format: /[motor] move abs [position]
            command = sprintf('/%d move abs %d', motorNum, round(position));

            try
                writeline(obj.SerialPort, command);

                % Read response
                response = readline(obj.SerialPort);

                % Check for errors
                if contains(response, 'RJ') || contains(response, 'WR')
                    warning('ZaberTCD1000:MoveError', ...
                        'Motor %d move error: %s', motorNum, response);
                end

            catch ME
                error('ZaberTCD1000:CommandFailed', ...
                    'Failed to move motor %d: %s', motorNum, ME.message);
            end
        end

        function home(obj, motorNum)
            % Home motor to find reference position
            %
            % Inputs:
            %   motorNum - Motor number (1-4)

            if ~obj.IsConnected
                error('ZaberTCD1000:NotConnected', 'Not connected to controller');
            end

            % Send home command
            command = sprintf('/%d home', motorNum);

            try
                writeline(obj.SerialPort, command);

                % Read response
                response = readline(obj.SerialPort);

                fprintf('Motor %d homing: %s\n', motorNum, response);

            catch ME
                error('ZaberTCD1000:HomeFailed', ...
                    'Failed to home motor %d: %s', motorNum, ME.message);
            end
        end

        function position = getPosition(obj, motorNum)
            % Get current motor position
            %
            % Inputs:
            %   motorNum - Motor number (1-4)
            %
            % Outputs:
            %   position - Current position in microsteps

            if ~obj.IsConnected
                error('ZaberTCD1000:NotConnected', 'Not connected to controller');
            end

            % Send position query command
            command = sprintf('/%d get pos', motorNum);

            try
                writeline(obj.SerialPort, command);

                % Read response
                response = readline(obj.SerialPort);

                % Parse position from response
                % Expected format: @01 0 [position] OK IDLE -- 0
                tokens = strsplit(response);
                if length(tokens) >= 3
                    position = str2double(tokens{3});
                else
                    error('ZaberTCD1000:ParseError', 'Failed to parse position');
                end

            catch ME
                error('ZaberTCD1000:QueryFailed', ...
                    'Failed to query motor %d position: %s', motorNum, ME.message);
            end
        end

        function stop(obj, motorNum)
            % Stop motor movement immediately
            %
            % Inputs:
            %   motorNum - Motor number (1-4, or 0 for all)

            if ~obj.IsConnected
                error('ZaberTCD1000:NotConnected', 'Not connected to controller');
            end

            % Send stop command
            command = sprintf('/%d stop', motorNum);

            try
                writeline(obj.SerialPort, command);
                response = readline(obj.SerialPort);

                fprintf('Motor %d stopped: %s\n', motorNum, response);

            catch ME
                error('ZaberTCD1000:StopFailed', ...
                    'Failed to stop motor %d: %s', motorNum, ME.message);
            end
        end

        function stopAll(obj)
            % Stop all motors immediately
            obj.stop(0);
        end
    end
end
