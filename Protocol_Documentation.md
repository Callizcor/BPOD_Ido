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
Each trial = One complete cycle of **Wait Period → Response Period**

### Phase 1: Wait Period
**Purpose**: Enforce minimum time between response opportunities

**Duration**:
- First trial: 0 seconds (starts immediately)
- Subsequent trials: `max(2, min(15, accumulated_penalty))` seconds

**Behavior**:
- Both Port 1 and Port 2 are monitored
- Any lick during wait period = **Incorrect Lick**
  - Adds 3 seconds to penalty time
  - Licks within 0.5s count as single burst (only one penalty)
  - Trial ends immediately
  - Penalty carries to next trial

**Logic**:
```
penalty_time = min(15, penalty_time + 3)  // Cap at 15s max
```

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

### Scenario 2: Incorrect Licks with Penalties
```
Trial 1:
  [Wait: 2s] → Mouse licks Port 1 at t=0.5s [INCORRECT]
    - Penalty added: +3s
    - Trial ends immediately
  → penalty_time = 3s

Trial 2:
  [Wait: 5s] (2s base + 3s penalty)
    - Mouse licks at t=1s [INCORRECT] → +3s penalty
    - Mouse licks at t=1.2s [same burst, ignored]
    - Mouse licks at t=1.4s [same burst, ignored]
    - Trial ends
  → penalty_time = 6s

Trial 3:
  [Wait: 8s] (2s base + 6s penalty)
    - Mouse licks at t=3s [INCORRECT] → +3s
    - Penalty now: 9s
    - Trial ends
  → penalty_time = 9s

Trial 4:
  [Wait: 11s] (2s + 9s)
    - Mouse waits full 11s
    - Mouse licks Port 1 at t=12s → [Response: 3s on Port1]
    - Successful! → penalty_time resets to 0
```

### Scenario 3: Penalty Cap Example
```
Trial N:
  Current penalty = 14s
  [Wait: 15s] (capped at max)
    - Mouse licks at t=1s [INCORRECT] → Try to add +3s
    - New penalty = min(15, 14 + 3) = 15s (capped)
  → penalty_time = 15s

Next trial:
  [Wait: 15s] (still capped)
    - If mouse waits 4 seconds then licks [INCORRECT]
    - Remaining time was 11s
    - New remaining = min(15, 11 + 3) = 14s
    - Must wait 14 more seconds
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
| MaxWaitTime | 15 s | Maximum wait time cap |

All parameters adjustable via BPOD GUI during session.

---

## Data Saved Per Trial

```matlab
BpodSystem.Data.TrialTypes(i)              % 0=wait violated, 1=Port1, 2=Port2
BpodSystem.Data.TrialOutcome(i)            % 1=successful, 0=wait violated
BpodSystem.Data.WaitDuration(i)            % Actual wait duration (seconds)
BpodSystem.Data.ResponsePort(i)            % Which port chosen (0/1/2)
BpodSystem.Data.NumLicksInResponse(i)      % Number of licks during response
BpodSystem.Data.TotalWaterDelivered(i)     % Total water delivered (seconds)
BpodSystem.Data.IncorrectLicksDuringWait(i) % Number of incorrect lick bursts
BpodSystem.Data.PenaltyTimeAccumulated(i)  % Penalty at trial start
BpodSystem.Data.RawEvents.Trial{i}         % All events and timestamps
BpodSystem.Data.bitcode{i}                 % Trial sync bitcode
```

---

## Outcome Plot

Real-time visualization showing:
- **Red X**: Wait period violated (incorrect lick)
- **Green Circle**: Successful response on Port 1
- **Blue Circle**: Successful response on Port 2

Y-axis categories:
- 0.5: Wait violated
- 1.5: Port 1 responses
- 2.5: Port 2 responses

---

## Key Design Decisions

### 1. Penalty Accumulation
- Penalties accumulate across trials until successful response
- Cap at 15 seconds prevents excessive delays
- Resets to 0 after successful response period

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

### 5. Infinite Wait in ReadyForResponse
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
