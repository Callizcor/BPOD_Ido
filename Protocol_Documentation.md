# BPOD Lick-Triggered Reward Protocol Documentation
## File: reward_2d _Ido_change_1.m

---

## Overview

This protocol implements a 2-lickport stationary task where mice self-initiate response periods by licking after a wait period. No lickport movement occurs during the session.

---

## Key Differences from Original Protocol

### Original (`reward_2d.m`):
- **Moving lickport**: Single lickport moves to different positions using Zaber motors
- **Fixed trial structure**: Predetermined trial types with specific ITIs and reward sizes
- **Trial-based**: Each trial has a fixed structure (move port → wait for lick → reward → retract)
- **Complex scheduling**: Blocks of trials with different reward/ITI combinations

### New Protocol (`reward_2d _Ido_change_1.m`):
- **Stationary lickports**: Two fixed lickports (Port 1 and Port 2), no motor control
- **Self-paced**: Mouse controls when response periods start by licking after wait completes
- **Penalty-based waiting**: Incorrect licks extend wait time dynamically
- **Simplified structure**: Focus on temporal control and self-initiated behavior

---

## Task Structure

### Trial Definition
**IMPORTANT**: Trial = From entering one Response Period to entering the next Response Period

This means a single trial includes:
- Wait Period (with potential multiple penalty additions)
- Ready for Response phase
- Response Period (3 seconds of reward delivery)

The trial does NOT end when an incorrect lick occurs - it continues within the same trial.

### Phase 1: Wait Period
**Purpose**: Enforce minimum time between response opportunities

**Duration**:
- First trial: 0 seconds (starts immediately at ReadyForResponse)
- Subsequent trials: Starts at 2 seconds minimum

**Behavior**:
- Both Port 1 and Port 2 are monitored
- Any lick during wait period = **Incorrect Lick**
  - Adds 3 seconds to REMAINING wait time (within the same trial)
  - Licks within 0.5s count as single burst (only one penalty)
  - Wait period extends and continues in same trial
  - Maximum remaining time capped at 15 seconds

**Logic (within same trial)**:
```
remaining_time = min(15, remaining_time + 3)  // Add penalty, cap at 15s remaining
// Trial continues - does NOT end
```

**Implementation**:
Uses time-sliced states (0.5s increments) to dynamically route between different remaining-time states:
- Wait_15.0s → Wait_14.5s → ... → Wait_0.5s → ReadyForResponse
- On lick at Wait_X.Ys: → IgnoreBurst (0.5s) → Wait_(X+3)s (capped at 15s)

### Phase 2: Ready for Response
**Purpose**: Wait indefinitely for mouse to initiate response

**Duration**: Unlimited (3600s timeout, effectively infinite)

**Behavior**:
- Mouse can wait as long as desired - no "missed" trials
- First lick on Port 1 → Triggers Response Period on Port 1
- First lick on Port 2 → Triggers Response Period on Port 2

### Phase 3: Response Period
**Purpose**: Reward window where licks deliver water

**Duration**: 3 seconds (from first lick that triggered response)

**Behavior**:
- **Port-specific**: Only licks on the triggered port deliver water
  - If Port 1 triggered: Only Port 1 licks give water
  - If Port 2 triggered: Only Port 2 licks give water
- **Continuous reward**: Each lick = 0.01s water bolus
- **No penalty**: Licks on the other port are ignored (no penalty)

**After Response Period**:
- Penalty time resets to 0
- Next trial begins with 2-second minimum wait

---

## Example Timeline

### Scenario 1: Successful Response
```
Trial 1:
  [Start] → [Wait: 0s] → Mouse licks Port 1 → [Response: 3s on Port1]
    - Licks: 8 times → 8 × 0.01s = 0.08s water
  → Trial 1 ends, penalty = 0

Trial 2:
  [Wait: 2s] → Mouse waits 2.5s → Licks Port 2 → [Response: 3s on Port2]
    - Licks: 5 times → 5 × 0.01s = 0.05s water
  → Trial 2 ends, penalty = 0
```

### Scenario 2: Incorrect Licks with Penalties (CORRECTED)
```
Trial 1:
  [Wait: 2s minimum]
    - t=0.5s: Mouse licks Port 1 [INCORRECT]
      → Remaining time resets to: min(15, 1.5s + 3s) = 4.5s
      → Enter IgnoreBurst for 0.5s
    - t=1.5s: Mouse licks again [INCORRECT - new burst]
      → Remaining time: min(15, 3.5s + 3s) = 6.5s
      → Enter IgnoreBurst for 0.5s
    - t=2.5s: Mouse licks [same burst as t=1.5s, ignored]
    - Mouse finally waits...
    - t=8.5s: Wait completes → ReadyForResponse
    - t=9.0s: Mouse licks Port 2 → [Response: 3s on Port2]
    - 6 licks during response → 6 × 0.01s = 0.06s water
  Trial 1 ends (total duration: ~12s)

Trial 2:
  [Wait: 2s minimum]
    - Mouse waits full 2s without licking
    - t=2.1s: Ready for response
    - t=2.5s: Mouse licks Port 1 → [Response: 3s on Port1]
    - 10 licks during response → 0.10s water
  Trial 2 ends (total duration: ~5.5s)
```

### Scenario 3: Penalty Cap Example (CORRECTED)
```
Trial N:
  [Wait: 2s minimum]
    - t=0.2s: Mouse licks [INCORRECT]
      → Remaining: min(15, 1.8s + 3s) = 4.8s
    - t=1.5s: Mouse licks [INCORRECT]
      → Remaining: min(15, 3.8s + 3s) = 6.8s
    - t=2.5s: Mouse licks [INCORRECT]
      → Remaining: min(15, 5.3s + 3s) = 8.3s
    - t=3.5s: Mouse licks [INCORRECT]
      → Remaining: min(15, 7.8s + 3s) = 10.8s
    - t=4.5s: Mouse licks [INCORRECT]
      → Remaining: min(15, 10.3s + 3s) = 13.3s
    - t=5.5s: Mouse licks [INCORRECT]
      → Remaining: min(15, 12.8s + 3s) = 15.0s (CAPPED!)
    - t=7.0s: Mouse licks [INCORRECT]
      → Remaining: min(15, 13.5s + 3s) = 15.0s (still capped)

    - Mouse finally stops licking and waits...
    - t=22.0s: Wait completes (15s from last lick)
    - t=22.5s: Mouse licks Port 1 → [Response: 3s]
  Trial N ends

Trial N+1:
  [Wait: 2s minimum] - Penalty resets after successful response!
    - Fresh start with 2s minimum
```

---

## State Machine Architecture

### Key States:

1. **TimerTrig** → Start camera triggers
2. **Bitcode States** → Encode trial number for external sync
3. **WaitPeriod** → Monitor for incorrect licks
4. **IncorrectLick** → Detected lick during wait
5. **LickBurstIgnore** → 0.5s window to ignore burst
6. **ReadyForResponse** → Infinite wait for first lick
7. **ResponsePeriod_Port1_Start** → Trigger response timer for Port 1
8. **GiveWater_Port1_First** → Reward first triggering lick
9. **ResponsePeriod_Port1** → Active response period on Port 1
10. **GiveWater_Port1** → Reward subsequent licks on Port 1
11. **ResponsePeriod_Port2_Start** → Trigger response timer for Port 2
12. **GiveWater_Port2_First** → Reward first triggering lick
13. **ResponsePeriod_Port2** → Active response period on Port 2
14. **GiveWater_Port2** → Reward subsequent licks on Port 2
15. **TrialEnd** → Clean up and exit

### Global Timers:
- **GlobalTimer1**: Camera triggers (250 Hz, continuous)
- **GlobalTimer2**: Response period duration (3 seconds)

---

## Hardware Configuration

### Water Valves:
```matlab
Port1WaterOutput = {'ValveState', 2^0}; % Port 1 → Valve 1 (bit 0)
Port2WaterOutput = {'ValveState', 2^1}; % Port 2 → Valve 2 (bit 1)
```

### Lick Detection:
- Port 1 licks detected via `Port1In` event
- Port 2 licks detected via `Port2In` event

### Camera Sync:
- BNC1: Camera trigger pulses (250 Hz)
- BNC2: Bitcode transmission for trial sync

---

## GUI Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| WaterValveTime | 0.01 s | Water bolus duration per lick |
| MinWaitPeriod | 2 s | Minimum wait between response periods |
| ResponsePeriodDuration | 3 s | Duration of reward window |
| IncorrectLickPenalty | 3 s | Time added per incorrect lick burst |
| LickBurstWindow | 0.5 s | Time window to group licks as one burst |
| MaxWaitTime | 15 s | Maximum remaining wait time cap |
| WaitTimeIncrement | 0.5 s | Time increment for wait states (affects state machine granularity) |

All parameters adjustable via BPOD GUI during session.

---

## Data Saved Per Trial

```matlab
BpodSystem.Data.TrialTypes(i)              % 1=Port1, 2=Port2
BpodSystem.Data.TrialOutcome(i)            % 1=successful response
BpodSystem.Data.ActualWaitDuration(i)      % Actual total wait duration (seconds)
BpodSystem.Data.ResponsePort(i)            % Which port chosen (1/2)
BpodSystem.Data.NumLicksInResponse(i)      % Number of licks during response period
BpodSystem.Data.TotalWaterDelivered(i)     % Total water delivered (seconds)
BpodSystem.Data.NumIncorrectLickBursts(i)  % Number of incorrect lick bursts in wait period
BpodSystem.Data.MinimumWaitAtStart(i)      % Starting minimum wait for this trial
BpodSystem.Data.RawEvents.Trial{i}         % All events and timestamps
BpodSystem.Data.bitcode{i}                 % Trial sync bitcode
```

---

## Outcome Plot

Real-time visualization showing:
- **Green Circle**: Successful response on Port 1
- **Blue Circle**: Successful response on Port 2

Y-axis categories:
- 1.0: Port 1 responses
- 2.0: Port 2 responses

Note: All trials result in a response (no "missed" or "violated" trials). The number of incorrect lick bursts per trial is tracked in the data but not shown on this plot.

---

## Key Design Decisions

### 1. Penalty Accumulation (CORRECTED)
- Penalties accumulate WITHIN THE SAME TRIAL by extending remaining wait time
- Each incorrect lick burst adds 3s to remaining wait time
- Remaining time capped at 15 seconds maximum
- Trial does NOT end on incorrect lick - continues with extended wait
- Penalty resets to baseline (2s) after successful Response Period completes

### 2. Lick Burst Detection
- 0.5s window groups rapid licks as single burst
- Prevents multiple penalties for exploratory licking
- Implemented via `LickBurstIgnore` state

### 3. Port Selection
- First lick after wait determines active port
- Prevents strategy of licking both ports simultaneously
- Encourages decision-making

### 4. No Motor Control
- Removed all Zaber motor code from original protocol
- Removed position calculations and movement states
- Simplified hardware requirements
- Both lickports remain stationary throughout session

### 5. Time-Sliced State Machine
- Uses 0.5s time increments to create dynamic wait period
- 31 wait states: Wait_0s, Wait_0.5s, Wait_1.0s, ..., Wait_15.0s
- 31 ignore burst states: one for each possible starting wait level
- On lick: transitions to IgnoreBurst → adds 3s to remaining time
- Allows in-trial penalty accumulation without ending state machine

### 6. Infinite Wait in ReadyForResponse
- 3600s timer (1 hour) effectively infinite
- Mouse cannot miss opportunity by waiting
- Allows natural initiation timing

---

## Usage Instructions

### 1. Hardware Setup
- Connect Port 1 lickport to BPOD Port1In
- Connect Port 2 lickport to BPOD Port2In
- Connect Port 1 valve to ValveState bit 0
- Connect Port 2 valve to ValveState bit 1
- Connect camera to BNC1 for triggers
- Connect sync device to BNC2 for bitcode

### 2. Starting Protocol
1. Launch BPOD software
2. Select subject/session
3. Load `reward_2d _Ido_change_1.m` protocol
4. Adjust GUI parameters if needed
5. Click "Run" and then "Resume" to start
6. Protocol runs until manually stopped

### 3. Monitoring Session
- Watch outcome plot for performance
- Check MATLAB console for trial summaries
- Monitor total water delivered per trial

### 4. Stopping Session
- Click "Stop" button in BPOD console
- Data automatically saved
- Review saved data in session folder

---

## Troubleshooting

### Issue: Mouse never licks after wait period
- **Cause**: Wait time too long, mouse disengaged
- **Solution**: Reduce `MinWaitPeriod` or check water restriction

### Issue: Too many wait violations
- **Cause**: Mouse hasn't learned timing yet
- **Solution**: Normal early in training, should improve with practice
- **Check**: Ensure penalty is appropriate (not too harsh)

### Issue: Mouse only licks one port
- **Cause**: Port preference (normal)
- **Solution**: Protocol allows this - both ports are valid
- **Optional**: Could add reward magnitude differences to encourage exploration

### Issue: Water delivery seems incorrect
- **Cause**: Valve timing or calibration
- **Solution**: Adjust `WaterValveTime` parameter
- **Test**: Run calibration with known lick counts

---

## Future Modifications

### Potential Enhancements:
1. **Differential Rewards**: Different water amounts for Port 1 vs Port 2
2. **Cued Trials**: Add LED/tone cues to indicate which port is "correct"
3. **Progressive Training**: Auto-adjust parameters based on performance
4. **Maximum Response Licks**: Cap total licks per response period
5. **Port Alternation Requirement**: Encourage switching between ports
6. **Timeout Periods**: Add delay after wait violation
7. **Session Time Limit**: Auto-stop after N minutes
8. **Performance-Based Wait**: Adjust wait time based on success rate

---

## Version History

**v1.0** (Current)
- Initial implementation
- Two-port stationary lick task
- Self-paced with penalty-based wait periods
- 3-second response windows
- Each lick delivers 0.01s water bolus
- No motor control

---

## Credits

Modified from original `reward_2d.m` protocol by Ido's lab.
Adapted for stationary dual-lickport self-paced task design.
