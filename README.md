# Free Licking Protocol with Dynamic Inter-Trial Intervals

A Bpod protocol for studying self-initiated licking behavior in mice with dynamic inter-trial intervals, camera synchronization, and motor control.

## Overview

This protocol implements a free licking task where mice self-initiate trials by licking either of two continuously available lick ports. The protocol delivers water rewards during a 5-second response period, then requires a 2-second delay without licking. Incorrect licks during the delay reset the timer to full duration.

### Experimental Flow

```
Session Init → Ready → Response → Delay → Ready → ...
     ↓           ↓         ↓         ↓
  Water to    Wait for  5s reward  2s wait
 both ports    lick     period    (resets on lick)
```

## Files

### Core Protocol Files
- **`FreeLicking_DynamicITI.m`** - Main Bpod protocol
- **`ZaberTCD1000.m`** - Zaber motor controller class
- **`GenerateBitcodeStateMachine.m`** - Bitcode transmission state machine generator

### Configuration & Testing
- **`RigConfig_Example.m`** - Example rig configuration template
- **`TestZaberMotors.m`** - Zaber motor testing script
- **`AnalyzeFreeLickingSession.m`** - Post-session data analysis

## Hardware Requirements

### Bpod State Machine r2+

#### Lick Ports
- **Type**: Electric circuit closing (NOT infrared)
- **Events**: `Port1Out`, `Port2Out` (triggered when tongue touches metal)
- **Notes**: No `Port1In`/`Port2In` events; requires debouncing (5-50ms)

#### Solenoid Valves
- **Names**: `Valve1` (Port 1), `Valve2` (Port 2)
- **Control**: String names in OutputActions
- **Duration**: 0.01-0.05 seconds (determines reward size)

#### Camera Synchronization (BNC1)
- **Frequency**: 250Hz continuous TTL trigger
- **Pulse**: 2ms HIGH, 2ms LOW (50% duty cycle)
- **Implementation**: GlobalTimer with Loop=1, LoopInterval=0.002s
- **Timing**: Started at trial beginning, cancelled at trial end

#### Trial Synchronization Bitcode (BNC2)
- **Format**: 20-bit binary random number (0 to 1,048,575)
- **Transmission**:
  - Start pulse: 60ms HIGH
  - 20 bits: each as 20ms LOW + 20ms HIGH/LOW
  - End pulse: 60ms HIGH
- **Duration**: ~1.02 seconds total

#### Zaber Motor System
- **Axes**: Z (vertical), Lx, Ly (horizontal)
- **Serial Ports**:
  - Microroom: COM18
  - Vivarium Rig 1: COM6
  - Vivarium Rig 2: COM11
- **Position Range**: 0-620,000 microsteps
- **Typical Positions**:
  - Z_center: ~210,000 (lickable)
  - Z_retract: ~60,000 (retracted)
  - Lx/Ly_center: ~310,000

## Behavioral Structure

### Session Initialization (Once)
1. Deliver 0.05s water to Port 1
2. Wait 0.5s
3. Deliver 0.05s water to Port 2
4. Wait 0.5s
5. Enter ready state

### Trial Cycle

#### 1. Ready for Lick (Infinite Wait)
- **Duration**: Up to 3600s timeout
- **Exit**: Mouse licks either port → trial begins
- **Port Selection**: Determined by which port receives first lick

#### 2. Response Period (5 seconds)
- **Active Port**: Only selected port delivers rewards
- **Rewards**: Each lick → immediate 0.01s water delivery
- **Other Port**: Completely ignored
- **Exit**: After 5 seconds → delay period

#### 3. Delay Period (2 second timer)
- **Goal**: Wait 2 seconds without licking
- **Incorrect Lick**:
  - Enter 0.5s "burst window" (all licks ignored)
  - Return to delay with timer RESET to full 2 seconds
- **Success**: After 2 seconds → return to ready state

#### 4. Debouncing
- **Duration**: 0.05s after each lick detection
- **Purpose**: Prevents electrical contact bounce from multiple counts

## Installation & Setup

### 1. Prerequisites
- Bpod State Machine r2+ with firmware
- MATLAB with Bpod software installed
- Zaber motors (optional, if using motorized ports)

### 2. Installation
```matlab
% Copy all files to your Bpod protocol directory
% Typical location: Bpod_Gen2/Protocols/FreeLicking_DynamicITI/
```

### 3. Configuration

#### Option A: Use GUI Parameters (Default)
The protocol will load default parameters on first run and present them in the Bpod Parameter GUI.

#### Option B: Create Rig Configuration File
```matlab
% Copy and customize RigConfig_Example.m
cp RigConfig_Example.m RigConfig_YourRig.m
% Edit parameters for your specific rig
% Run before starting protocol
```

### 4. Test Hardware

#### Test Zaber Motors
```matlab
% Edit COM port in TestZaberMotors.m
% Run test script
TestZaberMotors
```

Expected output:
```
=== ZABER MOTOR TEST ===
Connection successful!
TEST 1: Reading current positions - PASSED
TEST 2: Moving Z-axis to center - PASSED
...
```

## Running the Protocol

### 1. Launch Bpod
```matlab
% Start Bpod
Bpod

% Select protocol: FreeLicking_DynamicITI
% Configure settings in Parameter GUI if needed
% Press 'R' to run
```

### 2. Monitor Session
The protocol displays real-time information:
- Trial outcomes (Correct/Error/Ignore)
- Port selection
- Reward counts
- Delay resets

### 3. Stop Session
- Press the stop button in Bpod console
- Or let protocol run to completion

## Data Structure

### Per-Trial Arrays
```matlab
BpodSystem.Data.SelectedPort(trial)      % 1 or 2
BpodSystem.Data.ResponseLickCount(trial) % Number of rewards
BpodSystem.Data.IncorrectLickBursts(trial) % Delay resets
BpodSystem.Data.DelayTimerResets(trial)  % Same as above
BpodSystem.Data.TrialStartTime(trial)    % MATLAB now() format
BpodSystem.Data.TrialEndTime(trial)      % MATLAB now() format
BpodSystem.Data.TrialRewardSize(trial)   % Valve duration (s)
BpodSystem.Data.MotorPositions(trial,:)  % [Z, Lx, Ly]
BpodSystem.Data.Bitcode{trial}           % 20-char binary string
BpodSystem.Data.Outcomes(trial)          % 1=correct, 0=error, -1=ignore
```

### Outcomes
- **1 (Correct)**: Successfully completed delay period
- **0 (Error)**: Did not complete trial properly
- **-1 (Ignore)**: Timeout in ready state

## Data Analysis

### Quick Analysis
```matlab
% Load session data
load('SessionData.mat');

% Run analysis
AnalyzeFreeLickingSession(SessionData);
```

### Output
- Trial outcomes over time
- Port selection distribution
- Success rate (sliding window)
- Rewards per trial
- Delay resets
- Inter-lick intervals
- Summary statistics

### Example Statistics
```
=== SESSION ANALYSIS ===
Total trials: 150

Outcomes:
  Correct: 120 (80.0%)
  Error: 20 (13.3%)
  Ignored: 10 (6.7%)
  Success rate (completed only): 85.7%

Port Selection:
  Port 1: 75 (50.0%)
  Port 2: 75 (50.0%)

Licking Behavior:
  Total rewards delivered: 3500
  Avg rewards per trial: 23.33
  Total delay resets: 45
  Avg resets per trial: 0.30
```

## Parameters Reference

### Timing Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| ResponseDuration | 5.0 s | Response period duration |
| DelayDuration | 2.0 s | Required delay without licking |
| BurstIgnoreDuration | 0.5 s | Ignore window after incorrect lick |
| DebounceDuration | 0.05 s | Debounce period |
| TrialTimeout | 3600 s | Ready state timeout |

### Reward Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| RewardSize | 0.01 s | Valve duration per reward |
| InitRewardSize | 0.05 s | Initial session water delivery |
| InitWaitDuration | 0.5 s | Wait after initial water |

### Hardware Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| CameraSyncEnabled | 1 | Enable 250Hz camera sync |
| CameraPulseWidth | 0.002 s | Camera pulse duration (2ms) |
| BitcodeEnabled | 1 | Enable trial bitcode |
| ZaberEnabled | 0 | Enable Zaber motors |

## Troubleshooting

### No Lick Detection
1. Check lick port connections to Bpod
2. Verify Port1Out/Port2Out event names in Bpod
3. Test ports manually in Bpod console
4. Check debounce duration (may be too long)

### Motor Communication Failed
1. Verify COM port is correct
2. Check motors are powered on
3. Test with `TestZaberMotors.m`
4. Ensure no other programs using serial port
5. Try different USB cable/port

### Rewards Not Delivered
1. Check valve connections
2. Verify valve names (Valve1, Valve2)
3. Test valves manually in Bpod console
4. Check reward size (may be too small)
5. Verify water supply

### Camera Sync Issues
1. Check BNC1 connection
2. Verify 250Hz timing (oscilloscope)
3. Ensure GlobalTimer configured correctly
4. Check CameraSyncEnabled = 1

### Bitcode Not Transmitting
1. Check BNC2 connection
2. Verify BitcodeEnabled = 1
3. Monitor with oscilloscope
4. Check timing parameters

## Advanced Customization

### Modify Reward Schedule
Edit `FreeLicking_DynamicITI.m`:
```matlab
% Change reward size
S.GUI.RewardSize = 0.02;  % Increase to 20ms

% Variable reward sizes
BpodSystem.Data.TrialRewardSize(currentTrial) = S.GUI.RewardSize * (1 + 0.2*randn());
```

### Add Audio Feedback
```matlab
% In state machine, add OutputActions
'OutputActions', {'Valve1', 1, 'AudioPlayer1', 1}
```

### Custom Motor Positions per Trial
```matlab
% Before each trial
if mod(currentTrial, 10) == 0
    ZaberController.move(S.GUI.ZaberMotorZ, S.GUI.ZaberZ_Retract);
else
    ZaberController.move(S.GUI.ZaberMotorZ, S.GUI.ZaberZ_Center);
end
```

## Citation

If you use this protocol in your research, please cite:

```
Free Licking Protocol with Dynamic ITI
Bpod Protocol for Self-Initiated Licking Behavior
[Your Lab/Institution]
```

## License

This protocol is provided as-is for research purposes.

## Support

For issues and questions:
1. Check troubleshooting section above
2. Review Bpod documentation: https://sites.google.com/site/bpoddocumentation/
3. Contact your lab's Bpod expert
4. Post on Bpod forums

## Version History

### v1.0 (2025)
- Initial implementation
- Free licking with dynamic ITI
- Camera synchronization (250Hz)
- Bitcode transmission
- Zaber motor integration
- Comprehensive data tracking
- Analysis tools

---

**Last Updated**: 2025-11-09
