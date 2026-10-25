# SwiftLEDC

Swift LEDC PWM driver wrapping ESP-IDF's `esp_driver_ledc`. Exposes `LedcTimer` and `LedcTimer.Channel` for configuring PWM timers and duty-cycle-controlled output channels (LED brightness, servos, buzzers). Swift module name: **`LEDC`**.

Depends on: `SwiftPlatform`, `SwiftSupport`, `esp_driver_ledc`.

## Adding it to a project

This is a [SwiftPM](https://www.swift.org/package-manager/) package, built for ESP-IDF by
`swift_package()` from [esp-swift-support](https://github.com/nixit22/esp-swift-support). In your
app's `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nixit22/esp-swift-ledc.git", branch: "SPM"),
],
targets: [
    .target(name: "App", dependencies: [.product(name: "LEDC", package: "esp-swift-ledc")]),
]
```

See esp-swift-support's README for the project setup (top-level `CMakeLists.txt`, `main`
component, Swift toolchain).

## Usage

```swift
import LEDC

let timer = LedcTimer(timer: LEDC_TIMER_0, freqHz: 5000, resolution: LEDC_TIMER_13_BIT)
let channel = try timer.addChannel(channel: LEDC_CHANNEL_0, gpioNum: GPIO_NUM_8)
try channel.setDuty(0.5) // 50%
```

See [`CLAUDE.md`](CLAUDE.md) for full API details and non-obvious patterns (duty update semantics, timer teardown order).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
