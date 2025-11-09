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
fprintf('=== ZABER MOTOR TEST ===\n\n');
fprintf('Connecting to Zaber controller on %s...\n', COM_PORT);

try
    zaber = ZaberTCD1000(COM_PORT);
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
        pos_z = zaber.getPosition(MOTOR_Z);
        pos_lx = zaber.getPosition(MOTOR_LX);
        pos_ly = zaber.getPosition(MOTOR_LY);
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
        zaber.move(MOTOR_Z, TEST_POS_Z_CENTER);
        pause(2);  % Wait for movement
        pos_z = zaber.getPosition(MOTOR_Z);
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
        zaber.move(MOTOR_Z, TEST_POS_Z_RETRACT);
        pause(2);  % Wait for movement
        pos_z = zaber.getPosition(MOTOR_Z);
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
        zaber.move(MOTOR_Z, TEST_POS_Z_CENTER);
        pause(2);
        fprintf('  PASSED\n\n');
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    % Test 5: Move horizontal axes to center
    fprintf('TEST 5: Moving horizontal axes to center\n');
    try
        zaber.move(MOTOR_LX, TEST_POS_LX_CENTER);
        zaber.move(MOTOR_LY, TEST_POS_LY_CENTER);
        pause(3);  % Wait for movement
        pos_lx = zaber.getPosition(MOTOR_LX);
        pos_ly = zaber.getPosition(MOTOR_LY);
        fprintf('  Lx position: %d (target: %d)\n', pos_lx, TEST_POS_LX_CENTER);
        fprintf('  Ly position: %d (target: %d)\n', pos_ly, TEST_POS_LY_CENTER);
        fprintf('  PASSED\n\n');
    catch ME
        fprintf('  FAILED: %s\n\n', ME.message);
    end

    % Test 6: Emergency stop
    fprintf('TEST 6: Testing emergency stop\n');
    try
        zaber.move(MOTOR_Z, TEST_POS_Z_RETRACT);
        pause(0.5);
        zaber.stop(MOTOR_Z);
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
    zaber.move(MOTOR_Z, TEST_POS_Z_RETRACT);
    pause(2);

    % Close connection
    delete(zaber);
    fprintf('Zaber motors disconnected\n');
catch ME
    fprintf('Cleanup error: %s\n', ME.message);
end

fprintf('\n=== TEST COMPLETE ===\n');
