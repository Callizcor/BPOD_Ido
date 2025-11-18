# FreeLicking_DynamicITI Protocol

A sophisticated Bpod protocol for free licking behavioral experiments with block-based dynamic parameters and comprehensive data collection.

## Overview

This protocol implements a free licking task where mice self-initiate trials by licking either of two ports. The protocol delivers water rewards during a response period, then requires the animal to wait through a delay period without licking. The protocol supports block-based experimental design with varying parameters across blocks.

## Key Features

### Behavioral Design
- **Self-initiated trials**: Animals start trials by licking either port
- **Response period**: 5-second window for receiving water rewards
- **Delay period**: Configurable delay with error penalty system
- **Block-based parameters**: Different difficulty levels across blocks
- **Wrong port detection**: Tracks licks to non-selected port during response

### Data Collection
- **Comprehensive lick tracking**: All lick events with timestamps, ports, and categorization
- **Water consumption**: Automatic tracking of total water delivered (μL)
- **Trial metrics**: Response licks, delay errors, timer resets per trial
- **State transitions**: Complete state machine timing data
- **Block information**: Current block type and trial position within block

### Visualization
- **4-Panel real-time display**:
  - Lick events plot (current + previous trial)
  - Delay performance (rolling average)
  - Session statistics and metrics
  - Water container visualization

### GUI Controls
- **Timers GUI**: Response duration, debounce, session timeout
- **Block Design GUI**: Configure up to 3 block types with custom parameters
- **Motor Control GUI**: Zaber motor positioning (when enabled)

### Hardware Integration
- **Camera sync**: 250Hz continuous sync signal on BNC1
- **Trial sync**: 20-bit bitcode for trial identification
- **Zaber motors**: Automated lickport positioning (optional)

## Requirements

### Software
- Bpod_Gen2 MATLAB software
- MATLAB R2017a or later

### Hardware
- Bpod State Machine
- 2 lick ports (Port1Out, Port2Out)
- 2 solenoid valves (Valve1, Valve2)
- BNC outputs (for camera sync and bitcode)
- Zaber motors (optional, for automated positioning)

## Protocol Parameters

### Timing Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| ResponseDuration | 5 s | Duration of reward delivery period |
| BurstIgnoreDuration | 0.5 s | Time to ignore licks after error |
| DebounceDuration | 0.05 s | Debounce time between rewards |
| SessionDuration | 10800 s | Maximum session length (3 hours) |
| InitRewardSize | 0.05 s | Initial water delivery at session start |

### Block Design

#### Non-Block Mode (Default)
When `BlocksEnabled = 0`, all trials use default parameters:
- Delay Duration: 2.0 s
- Error Reset Segment: 1 (full reset)
- Reward Left: 0.01 s
- Reward Right: 0.01 s

#### Block Mode
When `BlocksEnabled = 1`, trials cycle through block types:

**Block 1** (Easy)
- Delay: 2.0 s
- Error Reset: Segment 1 (100% reset)
- Rewards: L=0.01s, R=0.01s

**Block 2** (Medium)
- Delay: 3.0 s
- Error Reset: Segment 2 (75% reset)
- Rewards: L=0.015s, R=0.015s

**Block 3** (Hard)
- Delay: 4.0 s
- Error Reset: Segment 1 (100% reset)
- Rewards: L=0.02s, R=0.01s (asymmetric)

### Error Reset Segments
The delay period is divided into 4 equal segments. Error reset determines where the delay timer resets on error:
- **Segment 1**: Full reset to start (100% of delay)
- **Segment 2**: Reset to 75% point (milder penalty)
- **Segment 3**: Reset to 50% point
- **Segment 4**: Reset to 25% point (minimal penalty)

## Data Structure

### Trial-by-Trial Data
```matlab
BpodSystem.Data.TrialTypes            % Port selected (1=Left, 2=Right, 0=None)
BpodSystem.Data.SelectedPort          % Same as TrialTypes
BpodSystem.Data.ResponseLickCount     % Number of correct licks during response
BpodSystem.Data.IncorrectResponseLicks % Wrong port licks during response
BpodSystem.Data.DelayLickCount        % Total licks during delay period
BpodSystem.Data.DelayTimerResets      % Number of delay timer resets
BpodSystem.Data.TrialRewardSize       % Reward duration delivered (s)
BpodSystem.Data.WaterPerTrial         % Water delivered per trial (μL)
BpodSystem.Data.TotalDelayDuration    % Actual delay duration including resets (s)
```

### Detailed Lick Data
```matlab
BpodSystem.Data.TrialLickTimes{trial}        % Timestamps of all licks
BpodSystem.Data.TrialLickPorts{trial}        % Port for each lick (1 or 2)
BpodSystem.Data.TrialLickTypes{trial}        % Type: 1=correct, 2=wrong, 3=delay
BpodSystem.Data.TrialStateTransitions{trial} % State entry/exit times
```

### Block Information
```matlab
BpodSystem.Data.BlockNumber(trial)     % Block number for this trial
BpodSystem.Data.TrialInBlock(trial)    % Position within block (1 to BlockSize)
BpodSystem.Data.BlockSequence          % Sequence of block types
BpodSystem.Data.BlockParams            % Parameters for each block
```

### Session Metrics
```matlab
BpodSystem.Data.SessionWaterDelivered  % Total water delivered (μL)
BpodSystem.Data.SessionStartTime       % Session start timestamp
```

## Usage

### Starting a Session

1. **Launch Protocol**
   ```matlab
   FreeLicking_DynamicITI
   ```

2. **Configure Parameters**
   - Adjust timing parameters in the "Timers" GUI
   - Configure block design in "Block Design" GUI
   - Position motors in "Motor Control" GUI (if enabled)

3. **Begin Session**
   - Press **PLAY** in Bpod console
   - Protocol delivers initial water to both ports
   - Displays block sequence
   - Waits for animal to initiate first trial

### During Session

- **Real-time monitoring**: 4-panel display updates after each trial
- **Manual adjustment**: GUI parameters can be modified between trials
- **Pause/Resume**: Use Bpod controls to pause session
- **Manual stop**: Press STOP to end session early

### Session End

The session ends automatically when:
- Maximum trials reached (1000)
- Session duration exceeded (default 3 hours)
- Manual stop by user

**Cleanup actions:**
- Motors retract to non-lickable position
- GUI windows close
- Final data save
- Session summary displayed

## Trial Structure

```
┌─────────────────────────────────────────────────────────────┐
│ READY                                                       │
│ • Wait for first lick (Port1 or Port2)                     │
│ • Start camera sync (if enabled)                           │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ RESPONSE PERIOD (5s default)                                │
│ • Deliver water on each lick to selected port              │
│ • Track wrong port licks                                   │
│ • Debounce between rewards (0.05s)                         │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ DELAY PERIOD (block-dependent)                              │
│ • Wait without licking (2-4s depending on block)           │
│ • Divided into 4 segments for graded penalties             │
│ • Lick detection → BurstWindow → Reset to segment          │
└────────────┬────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────┐
│ TRIAL COMPLETE                                              │
│ • Stop camera sync                                          │
│ • Save data                                                 │
│ • Update plots                                              │
└─────────────────────────────────────────────────────────────┘
```

## Motor Control (Optional)

When `ZaberEnabled = 1`:

### Motor Configuration
- **Serial Port**: COM6 (configurable)
- **Z motor** (motor 2): Vertical positioning
  - Lickable position: 210000 microsteps
  - Retracted position: 60000 microsteps
- **Lx motor** (motor 1): Horizontal position (310000)
- **Ly motor** (motor 4): Lateral position (310000)

### Motor Operations
- **Session start**: Move to lickable position
- **Session end**: Retract to non-lickable position
- **Manual control**: Use GUI buttons to adjust positions

## Output and Analysis

### Session Files
Data automatically saves to:
```
Bpod Local/Data/<SubjectName>/<ProtocolName>/<SessionDate>/
```

### Analysis Script
Use the included analysis function:
```matlab
% Analyze session data
sessionData = BpodSystem.Data;

% Calculate performance metrics
leftTrials = find(sessionData.TrialTypes == 1);
rightTrials = find(sessionData.TrialTypes == 2);

avgDelayResets = mean(sessionData.DelayTimerResets);
totalWater = sessionData.SessionWaterDelivered;

% Block-specific analysis
for blockNum = 1:max(sessionData.BlockNumber)
    blockTrials = find(sessionData.BlockNumber == blockNum);
    blockPerformance = mean(sessionData.DelayTimerResets(blockTrials));
end
```

## Troubleshooting

### Common Issues

**Motors not moving**
- Check `ZaberEnabled = 1` in settings
- Verify COM port is correct
- Ensure motors are powered and connected

**No water delivery**
- Verify valve connections (Valve1, Valve2)
- Check reward durations are not zero
- Test valves manually using Bpod console

**Camera sync not working**
- Ensure `CameraSyncEnabled = 1`
- Check BNC1 connection
- Verify 250Hz signal (2ms ON, 2ms OFF)

**GUI windows not appearing**
- Windows may be off-screen - check display settings
- Restart MATLAB and protocol

## Version History

### Current Version
- Custom GUI system with 3 windows
- Session duration management
- Comprehensive water tracking
- Enhanced visualization (4-panel display)
- Non-block mode support
- Wrong port detection
- Detailed lick categorization

## License

This protocol is provided as-is for research purposes.

## Contact

For questions or issues, please contact the repository maintainer.
