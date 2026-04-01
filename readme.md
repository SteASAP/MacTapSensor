# Tap Sensor — Ruby Edition

A tap-reactive sound engine for Apple Silicon MacBooks. macMoan reads accelerometer data from the built-in Bosch BMI286 IMU, detects physical taps on the chassis, and plays audio that escalates with intensity based on how rapidly you tap.

Fun, experimental, and mildly chaotic.

---

## Features

- **Tap detection** via rolling baseline comparison against accelerometer magnitude
- **Settle + re-arm** logic to filter post-impact vibration (no false double-triggers)
- **Zone-based escalation** — rapid successive taps escalate through sound zones; long idle resets
- **Configurable** threshold, cooldown, settle time, escalation windows, and sound directory
- **Path-safe audio playback** — validates file extensions and prevents path traversal
- **Zombie-free** — reaps child `afplay` processes automatically
- **Clean OOP design** — `MotionReader`, `TapDetector`, `SoundPlayer`, `App`
- **Testable** — injectable clock, no global state, full RSpec suite

---

## Requirements

- **macOS** on Apple Silicon (M1/M2/M3/M4)
- **Ruby** 2.7+
- **Bundler**
- **Root access** (`sudo`) — required for IOKit HID sensor access

---

## Installation

```bash
git clone <repo-url>
cd macMoan
bundle install
```

### Sound files

Place `.wav`, `.mp3`, `.aiff`, or `.m4a` files in `sounds/long/` organised by zone:

```
sounds/long/
├── 1.wav # zone 1 (calm)
├── 2.wav
├── 3.wav
├── 4.wav # zone 2
├── ...
├── 13.wav # zone 5 (max escalation)
└── 14.wav
```

The default zone map is defined in `Configuration`. You can customise which files belong to which zone.

---

## Usage

**Default sounds**
sudo ruby bin/tap_sensor

**Ouch sounds**
sudo ruby bin/tap_sensor --sound_dir=sounds/ouch

**Long sounds**
sudo ruby bin/tap_sensor --sound_dir=sounds/longsounds

**Your own folder**
sudo ruby bin/tap_sensor --sound_dir=path/to/your/sounds

### Command-line overrides

```bash
sudo ruby bin/tap_sensor --threshold=0.20 --cooldown=0.50 --sound_dir=sounds/ouch
```

All numeric config values can be overridden with `--key=value` flags. Use underscores in key names.

---

## Configuration

| Parameter         | Default       | Description                                                |
| ----------------- | ------------- | ---------------------------------------------------------- |
| `threshold`       | `0.30`        | Minimum magnitude delta to register as a tap               |
| `cooldown`        | `0.30`        | Minimum seconds between triggers                           |
| `settle`          | `0.45`        | Seconds to ignore all input after a hit (vibration tail)   |
| `rearm_delta`     | `0.08`        | Delta must fall below this before next trigger is armed    |
| `baseline_window` | `80`          | Number of calm samples used for rolling baseline average   |
| `escalate_window` | `2.5`         | If next tap arrives within this many seconds, zone goes up |
| `decay_window`    | `4.0`         | If gap exceeds this, zone drops by one                     |
| `reset_window`    | `8.0`         | If gap exceeds this, zone resets to 1                      |
| `max_zone`        | `5`           | Maximum escalation zone                                    |
| `sample_rate`     | `100`         | Target sensor sample rate in Hz                            |
| `sound_dir`       | `sounds/moan` | Directory containing audio files                           |

### Tuning tips

- **No tap detected** — lower `threshold` (try `0.15`)
- **Too many false triggers** — raise `threshold` and `cooldown`
- **Feels laggy** — lower `cooldown` and `settle`
- **Escalation too fast** — increase `escalate_window`

---

## How it works

1. **Read** — `MotionReader` opens the SPU IMU via IOKit HID (`AppleSPUHIDDevice`), decimates the native ~800 Hz stream to the configured sample rate, and pushes `Sample(x, y, z)` structs to a thread-safe queue.

2. **Detect** — `TapDetector` computes the 3D magnitude (`mag = sqrt(x² + y² + z²)`) and compares it to a rolling baseline of calm readings. If `|mag - baseline| > threshold`, a tap is registered. A settle window blocks re-detection during post-impact vibration, and the detector must re-arm (delta falls below `rearm_delta`) before the next trigger.

3. **Escalate** — Rapid taps increase the zone (1→5). Long pauses decay or reset it.

4. **Play** — `SoundPlayer` picks a random file from the active zone, validates the path, and spawns `/usr/bin/afplay` asynchronously.

---

## Project structure

```
src/
├── bin/
│ └── tap_sensor # entry point
├── lib/
│ ├── tap_sensor.rb # top-level require
│ └── tap_sensor/
│ ├── app.rb # main loop + signal handling
│ ├── configuration.rb # config defaults + accessors
│ ├── iokit_bridge.rb # IOKit HID FFI via Fiddle
│ ├── motion_reader.rb # high-level sensor wrapper
│ ├── sample.rb # Sample struct
│ ├── sound_player.rb # afplay wrapper + path safety
│ ├── tap_detector.rb # detection + escalation logic
│ └── tap_event.rb # TapEvent struct
├── spec/
│ ├── spec_helper.rb
│ ├── tap_detector_spec.rb
│ └── sound_player_spec.rb
├── sounds/
│ ├── moan/ # default sound pack (14 .wav)
│ ├── ouch/ # ouch sounds (6 .mp3)
│ └── longsounds/ # long-form sounds
├── Gemfile
├── .rspec
└── README.md
```

---

## Tests

```bash
bundle exec rspec
```

Tests cover spike detection, cooldown/re-arm logic, zone escalation, baseline integrity, and sound player path validation. The `TapDetector` accepts an injectable clock for deterministic time-based tests.

---

## Notes & Limitations

- Uses **undocumented IOKit HID APIs** (`AppleSPUHIDDevice` / Bosch BMI286). May break with macOS updates.
- **Apple Silicon only** — Intel Macs do not have this sensor.
- **Requires root** — IOKit HID device access is privileged.
- Not production-grade. This is an experimental toy.
- **Do not hit your MacBook hard.** Light taps only. Repeated impacts can damage hardware.

---

## License

MIT
