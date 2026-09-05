import Toybox.Lang;
import Toybox.Math;

//! Lap power statistics computed from a 1 Hz stream of power samples.
//!
//! Neither number this class produces is available from Activity.Info:
//! that object exposes whole-activity averagePower but nothing per-lap,
//! and no Connect IQ API exposes normalized power on any device.
//!
//! The 30 s rolling window is not reset at a lap boundary. NP models a
//! physiological response that lags power by about half a minute, so the
//! strain during the first seconds of a lap genuinely depends on the seconds
//! before it, and keeping the window gives a number one second into the lap
//! instead of thirty. The cost is that a short lap after a very different
//! one reads a little toward the previous lap for its first half minute.
class LapPowerStats {
    //! Normalized power is defined over a 30-second rolling mean.
    private const WINDOW_SECONDS = 30;

    private var mLapSum as Number;
    private var mLapCount as Number;

    // Circular buffer holding the last WINDOW_SECONDS samples, plus its sum,
    // so the rolling mean costs one add and one subtract per second rather
    // than a 30-element walk.
    private var mWindow as Array<Number>;
    private var mWindowIndex as Number;
    private var mWindowCount as Number;
    private var mWindowSum as Number;

    // Running mean of (rolling mean)^4. Double, not Float: a 1000 W rolling
    // mean contributes 1e12 per second, and an hour of those overflows the
    // ~7 significant digits of a 32-bit float into nonsense.
    private var mQuarticSum as Double;
    private var mQuarticCount as Number;

    function initialize() {
        mWindow = new Array<Number>[WINDOW_SECONDS];
        mLapSum = 0;
        mLapCount = 0;
        mWindowIndex = 0;
        mWindowCount = 0;
        mWindowSum = 0;
        mQuarticSum = 0.0d;
        mQuarticCount = 0;
        clearWindow();
    }

    //! Record one second of power. Zero-power coasting seconds count:
    //! they are part of the lap and dropping them would flatter the average.
    function addSample(power as Number) as Void {
        mLapSum += power;
        mLapCount += 1;

        mWindowSum -= mWindow[mWindowIndex];
        mWindow[mWindowIndex] = power;
        mWindowSum += power;
        mWindowIndex = (mWindowIndex + 1) % WINDOW_SECONDS;
        if (mWindowCount < WINDOW_SECONDS) {
            mWindowCount += 1;
        }

        // Only complete windows contribute, so NP is undefined for the first
        // 29 seconds of a lap rather than wrong.
        if (mWindowCount == WINDOW_SECONDS) {
            var rollingMean = mWindowSum.toDouble() / WINDOW_SECONDS;
            var squared = rollingMean * rollingMean;
            mQuarticSum += squared * squared;
            mQuarticCount += 1;
        }
    }

    //! Start a new lap. The lap totals restart; the rolling window does not,
    //! see the class comment. Both numbers are null until the next sample.
    function reset() as Void {
        mLapSum = 0;
        mLapCount = 0;
        mQuarticSum = 0.0d;
        mQuarticCount = 0;
    }

    //! Mean power for the current lap in watts, or null before the first sample.
    function getLapAverage() as Number? {
        if (mLapCount == 0) {
            return null;
        }
        return (mLapSum.toFloat() / mLapCount + 0.5).toNumber();
    }

    //! Normalized power for the current lap in watts, or null before a full
    //! 30 s rolling window exists. After the first lap the window is already
    //! full, so this is available one sample into each new lap.
    function getNormalizedPower() as Number? {
        if (mQuarticCount == 0) {
            return null;
        }
        var meanQuartic = mQuarticSum / mQuarticCount;
        return (Math.pow(meanQuartic, 0.25d) + 0.5).toNumber();
    }

    //! How far the current 30 s rolling mean sits from the lap NP, as a
    //! fraction of NP: +0.1 means the last half minute ran 10% above NP and
    //! is pulling it up, -0.1 that it is pulling NP down. Null until NP exists.
    //!
    //! Computed from the unrounded NP so a steady effort reads exactly zero
    //! rather than flickering with the rounding of the displayed watts.
    function getRollingDeviation() as Float? {
        if (mQuarticCount == 0) {
            return null;
        }
        var np = Math.pow(mQuarticSum / mQuarticCount, 0.25d);
        if (np <= 0.0d) {
            return null;
        }
        var rollingMean = mWindowSum.toDouble() / WINDOW_SECONDS;
        return ((rollingMean - np) / np).toFloat();
    }

    private function clearWindow() as Void {
        for (var i = 0; i < WINDOW_SECONDS; i += 1) {
            mWindow[i] = 0;
        }
    }
}
