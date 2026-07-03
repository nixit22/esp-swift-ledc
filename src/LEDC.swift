// Copyright (c) 2026 Nicolas Christe
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

@_exported import ESP_LEDC
import Platform

private let log = Logger(tag: "LEDC")

extension Float {
    /// Clamps `self` into `range`, avoiding an out-of-range `UInt32(Float)`
    /// conversion (which traps) further down the duty-cycle pipeline.
    fileprivate func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Wrapper for an LEDC timer. Controls PWM frequency and duty resolution.
///
/// `~Copyable` — pauses and deconfigures the timer automatically in `deinit`.
///
/// LEDC_LOW_SPEED_MODE is used unconditionally — high-speed mode is only
/// available on ESP32 (Xtensa) and is compiled out on RISC-V targets (C6, H2).
public struct LedcTimer: ~Copyable {
    private let timerNum: ledc_timer_t
    public let resolution: ledc_timer_bit_t

    /// Configure an LEDC timer. Aborts on failure — intended for boot-time static allocation.
    ///
    /// - Parameters:
    ///   - timer: Timer index (default: `LEDC_TIMER_0`).
    ///   - freqHz: PWM frequency in Hz.
    ///   - resolution: Duty resolution in bits (default: `LEDC_TIMER_13_BIT`).
    ///   - clkCfg: Clock source (default: `LEDC_AUTO_CLK`).
    public init(
        timer: ledc_timer_t = LEDC_TIMER_0,
        freqHz: UInt32,
        resolution: ledc_timer_bit_t = LEDC_TIMER_13_BIT,
        clkCfg: ledc_clk_cfg_t = LEDC_AUTO_CLK
    ) {
        var cfg = ledc_timer_config_t(
            speed_mode: LEDC_LOW_SPEED_MODE,
            duty_resolution: resolution,
            timer_num: timer,
            freq_hz: freqHz,
            clk_cfg: clkCfg,
            deconfigure: false)
        ledc_timer_config(&cfg)
            .abortOnError {
                log.e("Failed to configure LEDC timer: \($0.name)")
            }
        self.timerNum = timer
        self.resolution = resolution
    }

    deinit {
        _ = ledc_timer_pause(LEDC_LOW_SPEED_MODE, timerNum)
        var cfg = ledc_timer_config_t(
            speed_mode: LEDC_LOW_SPEED_MODE,
            duty_resolution: LEDC_TIMER_1_BIT,
            timer_num: timerNum,
            freq_hz: 0,
            clk_cfg: LEDC_AUTO_CLK,
            deconfigure: true)
        _ = ledc_timer_config(&cfg)
    }

    /// Bind a GPIO pin to this timer as a PWM output channel.
    ///
    /// - Parameters:
    ///   - channel: LEDC channel index.
    ///   - gpioNum: GPIO pin to drive.
    ///   - duty: Initial duty cycle 0.0–1.0 (default: `0.0`).
    ///   - outputInvert: Invert the output signal (default: `false`).
    ///
    /// - Returns: A `Channel` to control duty.
    /// - Throws: `Error` if channel configuration fails.
    public func addChannel(
        channel: ledc_channel_t,
        gpioNum: gpio_num_t,
        duty: Float = 0.0,
        outputInvert: Bool = false
    ) throws(Error) -> Channel {
        let maxDuty = UInt32(1) << UInt32(resolution.rawValue)
        let rawDuty = UInt32(duty.clamped(to: 0.0...1.0) * Float(maxDuty))
        var cfg = ledc_channel_config_t(
            gpio_num: Int32(gpioNum.rawValue),
            speed_mode: LEDC_LOW_SPEED_MODE,
            channel: channel,
            intr_type: LEDC_INTR_DISABLE,
            timer_sel: timerNum,
            duty: rawDuty,
            hpoint: 0,
            sleep_mode: LEDC_SLEEP_MODE_NO_ALIVE_NO_PD,
            flags: .init(output_invert: outputInvert ? 1 : 0))
        try ledc_channel_config(&cfg)
            .throwEspError {
                log.e("Failed to configure LEDC channel: \($0.name)")
            }
        return Channel(channel: channel, resolution: resolution)
    }

    /// Set the PWM frequency. All channels sharing this timer are affected.
    ///
    /// - Throws: `Error` on failure.
    public func setFreq(_ freqHz: UInt32) throws(Error) {
        try ledc_set_freq(LEDC_LOW_SPEED_MODE, timerNum, freqHz)
            .throwEspError {
                log.e("Failed to set LEDC frequency: \($0.name)")
            }
    }

    /// Return the current PWM frequency in Hz, or 0 on error.
    public func getFreq() -> UInt32 {
        return ledc_get_freq(LEDC_LOW_SPEED_MODE, timerNum)
    }

    /// Pause the timer. All channels using it stop toggling.
    ///
    /// - Throws: `Error` on failure.
    public func pause() throws(Error) {
        try ledc_timer_pause(LEDC_LOW_SPEED_MODE, timerNum)
            .throwEspError {
                log.e("Failed to pause LEDC timer: \($0.name)")
            }
    }

    /// Resume a paused timer.
    ///
    /// - Throws: `Error` on failure.
    public func resume() throws(Error) {
        try ledc_timer_resume(LEDC_LOW_SPEED_MODE, timerNum)
            .throwEspError {
                log.e("Failed to resume LEDC timer: \($0.name)")
            }
    }

    /// Reset the timer counter to zero.
    ///
    /// - Throws: `Error` on failure.
    public func reset() throws(Error) {
        try ledc_timer_rst(LEDC_LOW_SPEED_MODE, timerNum)
            .throwEspError {
                log.e("Failed to reset LEDC timer: \($0.name)")
            }
    }

    /// A single PWM output channel bound to an `LedcTimer`.
    ///
    /// `~Copyable` — stops the channel output automatically in `deinit`.
    public struct Channel: ~Copyable {
        private let channel: ledc_channel_t
        private let resolution: ledc_timer_bit_t

        init(channel: ledc_channel_t, resolution: ledc_timer_bit_t) {
            self.channel = channel
            self.resolution = resolution
        }

        deinit {
            _ = ledc_stop(LEDC_LOW_SPEED_MODE, channel, 0)
        }

        /// Set duty cycle as a normalized value 0.0–1.0.
        ///
        /// Calls `ledc_set_duty` + `ledc_update_duty` — both are required for
        /// the new value to take effect.
        ///
        /// - Throws: `Error` on failure.
        public func setDuty(_ duty: Float) throws(Error) {
            let maxDuty = UInt32(1) << UInt32(resolution.rawValue)
            try setDutyRaw(UInt32(duty.clamped(to: 0.0...1.0) * Float(maxDuty)))
        }

        /// Set duty cycle as a raw value in `[0, 2^resolution]`.
        ///
        /// Calls `ledc_set_duty` + `ledc_update_duty` — both are required for
        /// the new value to take effect.
        ///
        /// - Throws: `Error` on failure.
        public func setDutyRaw(_ duty: UInt32) throws(Error) {
            try ledc_set_duty(LEDC_LOW_SPEED_MODE, channel, duty)
                .throwEspError {
                    log.e("Failed to set LEDC duty: \($0.name)")
                }
            try ledc_update_duty(LEDC_LOW_SPEED_MODE, channel)
                .throwEspError {
                    log.e("Failed to update LEDC duty: \($0.name)")
                }
        }

        /// Return current duty cycle as a raw value, or 0 on error.
        public func getDutyRaw() -> UInt32 {
            let duty = ledc_get_duty(LEDC_LOW_SPEED_MODE, channel)
            return duty == LEDC_ERR_DUTY ? 0 : duty
        }

        /// Return current duty cycle as a normalized value 0.0–1.0.
        public func getDuty() -> Float {
            let maxDuty = UInt32(1) << UInt32(resolution.rawValue)
            return Float(getDutyRaw()) / Float(maxDuty)
        }

        /// Stop the channel output and drive the pin to `idleLevel`.
        ///
        /// - Parameter idleLevel: Pin level after stop: 0 (low) or 1 (high).
        /// - Throws: `Error` on failure.
        public func stop(idleLevel: UInt32 = 0) throws(Error) {
            try ledc_stop(LEDC_LOW_SPEED_MODE, channel, idleLevel)
                .throwEspError {
                    log.e("Failed to stop LEDC channel: \($0.name)")
                }
        }
    }
}
