function MySoftCodeHandler(code)
% MYSOFTCODEHANDLER Handle soft codes for Zaber motor control
%
% SoftCode 1: Move lick port IN (to lickable position)
% SoftCode 2: Move lick port OUT (retracted position)
%
% This function is called by Bpod when a SoftCode OutputAction is triggered

global BpodSystem motors_properties motors

if ~BpodSystem.ProtocolSettings.GUI.ZaberEnabled
    return;
end

try
    S = BpodSystem.ProtocolSettings;

    fprintf('[DEBUG] SoftCode %d received\n', code);
    fprintf('[DEBUG] motors_properties.Z_motor_num = %d\n', motors_properties.Z_motor_num);
    fprintf('[DEBUG] motors object exists: %d\n', ~isempty(motors));

    switch code
        case 1  % Move port IN (to lickable position)
            fprintf('Moving lick port IN (Z=%d, motor #%d)...\n', S.GUI.Z_motor_pos, motors_properties.Z_motor_num);
            Motor_Move(S.GUI.Z_motor_pos, motors_properties.Z_motor_num);
            fprintf('Move command sent successfully\n');

        case 2  % Move port OUT (retracted position)
            fprintf('Moving lick port OUT (Z=%d, motor #%d)...\n', S.GUI.Z_NonLickable, motors_properties.Z_motor_num);
            Motor_Move(S.GUI.Z_NonLickable, motors_properties.Z_motor_num);
            fprintf('Move command sent successfully\n');

        otherwise
            warning('MySoftCodeHandler:UnknownCode', 'Unknown soft code: %d', code);
    end

catch ME
    warning('MySoftCodeHandler:Error', 'Soft code handler error: %s', ME.message);
    fprintf('[DEBUG] Error stack:\n');
    disp(getReport(ME));
end

end
