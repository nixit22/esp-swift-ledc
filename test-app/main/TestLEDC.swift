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

import GPIO
import LEDC
import Platform

func testLEDC(logger: Logger) {
    do {
        let resolution = LEDC_TIMER_13_BIT
        let freqHz: UInt32 = 5000
        let timer = LedcTimer(timer: LEDC_TIMER_0, freqHz: freqHz, resolution: resolution)

        let readFreq = timer.getFreq()
        logger.i("LEDC: configured \(freqHz) Hz, hardware reports \(readFreq) Hz")

        // two channels on same timer — ch1 with inverted output
        let ch0 = try timer.addChannel(channel: LEDC_CHANNEL_0, gpioNum: GPIO_NUM_8)
        let ch1 = try timer.addChannel(channel: LEDC_CHANNEL_1, gpioNum: GPIO_NUM_9, outputInvert: true)

        // normalized duty roundtrip: 50% on 13-bit = 4096
        try ch0.setDuty(0.5)
        let rawAfterHalf = ch0.getDutyRaw()
        logger.i("LEDC: ch0 duty=50%, raw=\(rawAfterHalf) (expect 4096)")

        // raw duty roundtrip
        try ch1.setDutyRaw(1234)
        let rawReadback = ch1.getDutyRaw()
        logger.i("LEDC: ch1 setDutyRaw(1234), getDutyRaw()=\(rawReadback)")

        // frequency change
        try timer.setFreq(1000)
        let newFreq = timer.getFreq()
        logger.i("LEDC: setFreq(1000), hardware reports \(newFreq) Hz")

        // timer control
        try timer.reset()
        try timer.pause()
        try timer.resume()

        logger.i("LEDC: APIs compiled and linked successfully")
        // ch0, ch1, timer freed by deinit (channels before timer — reverse declaration order)
    } catch {
        logger.e("LEDC: setup failed: \(error.name)")
    }
}
