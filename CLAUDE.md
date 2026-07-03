# SwiftLEDC

Swift LEDC PWM driver wrapping `esp_driver_ledc`. Swift module name: **`LEDC`**.

Depends on: `SwiftPlatform`, `SwiftSupport`, `esp_driver_ledc`

## Files

| File | Role |
|---|---|
| `src/LEDC.swift` | `LedcTimer` and `LedcTimer.Channel` — public Swift API |
| `src/ledc.c` / `src/ledc.h` | Thin C wrapper — only `#include <driver/ledc.h>` |
| `module.modulemap` | Clang module `ESP_LEDC` — umbrella over `src/ledc.h` |

## Public API

```swift
// Configure a timer (frequency + duty resolution) — aborts on failure
let timer = LedcTimer(timer: LEDC_TIMER_0, freqHz: 5000, resolution: LEDC_TIMER_13_BIT)

// Bind a GPIO pin as a PWM output channel
let channel = try timer.addChannel(channel: LEDC_CHANNEL_0, gpioNum: GPIO_NUM_8)

// Set duty cycle (normalized or raw)
try channel.setDuty(0.5)           // 50%
try channel.setDutyRaw(4096)       // raw value in [0, 2^resolution]
let d: Float = channel.getDuty()   // 0.0–1.0
let r: UInt32 = channel.getDutyRaw()

// Stop output
try channel.stop()                 // drives pin low

// Timer control
try timer.setFreq(1000)
try timer.pause()
try timer.resume()
try timer.reset()

// No explicit cleanup — deinit pauses and deconfigures the timer.
// channel is destroyed before timer (reverse declaration order) — correct IDF order.
```

## Non-obvious patterns

**`LEDC_LOW_SPEED_MODE` hardcoded** — high-speed mode only exists on ESP32 (Xtensa); `LEDC_HIGH_SPEED_MODE` is conditionally compiled out for RISC-V (C6, H2). No `speed_mode` parameter is exposed.

**`setDuty` calls set + update** — `ledc_set_duty()` alone is a silent no-op. Always followed by `ledc_update_duty()` in both `setDuty()` and `setDutyRaw()`.

**`deinit` pauses before deconfiguring** — per the ESP-IDF API contract, `ledc_timer_config(deconfigure: true)` requires the timer to be paused first. `LedcTimer.deinit` calls `ledc_timer_pause` before the deconfigure `ledc_timer_config` call so callers never need to do this manually.

**`gpio_num` is `int`** — `ledc_channel_config_t.gpio_num` is `int`, not `gpio_num_t`. Converted via `Int32(gpioNum.rawValue)` in `addChannel`.

**`@_exported import ESP_LEDC`** — re-exports the C module so callers of `SwiftLEDC` get `ledc_timer_t`, `ledc_channel_t`, `LEDC_TIMER_*`, `LEDC_CHANNEL_*`, etc. without importing `ESP_LEDC` separately.

**No C glue needed** — unlike `SwiftGPIO`, which needed a C factory for SoC-conditional types, LEDC has no such conditionals. The `flags.output_invert` bitfield initializes with `.init(output_invert:)` the same way as I2C's flags bitfields.

**Fade not included (v1)** — `ledc_fade_func_install()` requires global ISR state. Defer to v2.
