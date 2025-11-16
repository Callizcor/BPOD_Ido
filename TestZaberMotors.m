% TEST ZABER MOTORS
% Script to test Zaber motor communication and movement
%
% Usage:
%   1. Connect Zaber motors to computer
%   2. Update COM_PORT below to match your rig
%   3. Run this script
%   4. Motors will home, move to test positions, and return

%% Configuration
COM_PORT = 'COM18';  % Change to COM6, COM11, etc. for your rig

% Motor numbers (adjust for your rig)
MOTOR_Z = 1;
MOTOR_LX = 3;
MOTOR_LY = 2;

% Test positions
TEST_POS_Z_CENTER = 210000;
TEST_POS_Z_RETRACT = 60000;
TEST_POS_LX_CENTER = 310000;
TEST_POS_LY_CENTER = 310000;

%% Initialize Zaber Controller
global motors motors_properties

fprintf('=== ZABER MOTOR TEST ===\n\n');
fprintf('Connecting to Zaber controller on %s...\n', COM_PORT);

% Setup motor properties
motors_properties.PORT = COM_PORT;
motors_properties.type = '@ZaberArseny';
motors_properties.Z_motor_num = MOTOR_Z;
motors_properties.Lx_motor_num = MOTOR_LX;
motors_properties.Ly_motor_num = MOTOR_LY;

try
    motors = ZaberTCD1000(COM_PORT);
    serial_open(motors);
    fprintf('Connection successful!\n\n');
catch ME
    fprintf('ERROR: Failed to connect to Zaber motors\n');
    fprintf('Message: %s\n', ME.message);
    fprintf('\nTroubleshooting:\n');
    fprintf('  1. Check that motors are powered on\n');
    fprintf('  2. Verify COM port is correct\n');
    fprintf('  3. Check USB cable connection\n');
    fprintf('  4. Ensure no other programs are using the port\n');
    return;
end

%% Test Sequence
try
    fprintf('Starting motor test sequence...\n\n');

    % Test 1: Get current positions
    fprintf('TEST 1: Reading current positions\n');
    try
        pos_z = motors.getPosition(MOTOR_Z);
        pos_lx = motors.getPosition(MOTOR_LX);
        pos_ly = motors.getPosition(MOTOR_LY);
        fprintf('  Z (motor %d): %d\n', MOTOR_Z, pos_z);
        fprintf('  Lx (motor %d): %d\n', MOTOR_LX, pos_lx);
        fprintf('  Ly (motor %d): %d\n', MOTOR_LY, pos_ly);
        fprintf('  PASSED\n\n');
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    % Test 2: Move Z-axis to center
    fprintf('TEST 2: Moving Z-axis to center position (%d)\n', TEST_POS_Z_CENTER);
    try
        Motor_Move(TEST_POS_Z_CENTER, MOTOR_Z);
        pause(2);  % Wait for movement
        pos_z = motors.getPosition(MOTOR_Z);
        fprintf('  Current Z position: %d\n', pos_z);
        if abs(pos_z - TEST_POS_Z_CENTER) < 100
            fprintf('  PASSED\n\n');
        else
            fprintf('  WARNING: Position mismatch\n\n');
        end
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    % Test 3: Move Z-axis to retract
    fprintf('TEST 3: Moving Z-axis to retract position (%d)\n', TEST_POS_Z_RETRACT);
    try
        Motor_Move(TEST_POS_Z_RETRACT, MOTOR_Z);
        pause(2);  % Wait for movement
        pos_z = motors.getPosition(MOTOR_Z);
        fprintf('  Current Z position: %d\n', pos_z);
        if abs(pos_z - TEST_POS_Z_RETRACT) < 100
            fprintf('  PASSED\n\n');
        else
            fprintf('  WARNING: Position mismatch\n\n');
        end
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    % Test 4: Move Z back to center
    fprintf('TEST 4: Moving Z-axis back to center\n');
    try
        Motor_Move(TEST_POS_Z_CENTER, MOTOR_Z);
        pause(2);
        fprintf('  PASSED\n\n');
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    % Test 5: Move horizontal axes to center
    fprintf('TEST 5: Moving horizontal axes to center\n');
    try
        Motor_Move(TEST_POS_LX_CENTER, MOTOR_LX);
        Motor_Move(TEST_POS_LY_CENTER, MOTOR_LY);
        pause(3);  % Wait for movement
        pos_lx = motors.getPosition(MOTOR_LX);
        pos_ly = motors.getPosition(MOTOR_LY);
        fprintf('  Lx position: %d (target: %d)\n', pos_lx, TEST_POS_LX_CENTER);
        fprintf('  Ly position: %d (target: %d)\n', pos_ly, TEST_POS_LY_CENTER);
        fprintf('  PASSED\n\n');
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    % Test 6: Emergency stop
    fprintf('TEST 6: Testing emergency stop\n');
    try
        Motor_Move(TEST_POS_Z_RETRACT, MOTOR_Z);
        pause(0.5);
        motors.stop(MOTOR_Z);
        fprintf('  PASSED\n\n');
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    fprintf('All tests completed successfully!\n\n');

catch ME
    fprintf('ERROR during test sequence: %s\n', ME.message);
end

%% Cleanup
fprintf('Cleaning up...\n');
try
    % Move Z to safe retract position
    Motor_Move(TEST_POS_Z_RETRACT, MOTOR_Z);
    pause(2);

    % Close connection
    serial_close(motors);
    clear global motors motors_properties;
    fprintf('Zaber motors disconnected\n');
catch ME
    fprintf('Cleanup error: %s\n', ME.message);
end

fprintf('\n=== TEST COMPLETE ===\n');
