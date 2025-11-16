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

    switch code
        case 1  % Move port IN (to lickable position)
            fprintf('Moving lick port IN (Z=%d)...\n', S.GUI.Z_motor_pos);
            Motor_Move(S.GUI.Z_motor_pos, motors_properties.Z_motor_num);

        case 2  % Move port OUT (retracted position)
            fprintf('Moving lick port OUT (Z=%d)...\n', S.GUI.Z_NonLickable);
            Motor_Move(S.GUI.Z_NonLickable, motors_properties.Z_motor_num);

        otherwise
            warning('MySoftCodeHandler:UnknownCode', 'Unknown soft code: %d', code);
    end

catch ME
    warning('MySoftCodeHandler:Error', 'Soft code handler error: %s', ME.message);
end

end
