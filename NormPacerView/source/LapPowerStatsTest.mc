import Toybox.Lang;
import Toybox.Test;

//! Unit tests for LapPowerStats. Test code is stripped from debug and
//! release builds, so these live alongside the source they exercise.
//! Run with: monkeyc -f monkey.jungle -d <device> -o bin/Test.prg -y <key> -t
//! then `connectiq` and `monkeydo bin/Test.prg <device> -t`.

//! Feed the same wattage for a number of consecutive seconds.
function feed(stats as LapPowerStats, watts as Number, seconds as Number) as Void {
    for (var i = 0; i < seconds; i += 1) {
        stats.addSample(watts);
    }
}

(:test)
function lapAverageIsNullBeforeAnySample(logger as Logger) as Boolean {
    var stats = new LapPowerStats();

    Test.assertMessage(
        stats.getLapAverage() == null,
        "expected null lap average before any sample"
    );
    return true;
}

(:test)
function lapAverageOfConstantPowerIsThatPower(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 200, 5);

    var average = stats.getLapAverage();
    Test.assertMessage(average != null, "expected a lap average after 5 samples");
    Test.assertEqualMessage(average as Number, 200, "constant 200 W must average 200 W");
    return true;
}

(:test)
function lapAverageIncludesZeroPowerCoasting(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 200, 30);
    feed(stats, 0, 30);

    var average = stats.getLapAverage();
    Test.assertMessage(average != null, "expected a lap average after 60 samples");
    Test.assertEqualMessage(
        average as Number,
        100,
        "coasting seconds count as 0 W, so 30 s at 200 W then 30 s at 0 W is 100 W"
    );
    return true;
}

(:test)
function lapAverageRoundsToNearestWatt(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    stats.addSample(100);
    stats.addSample(101);

    var average = stats.getLapAverage();
    Test.assertMessage(average != null, "expected a lap average after 2 samples");
    Test.assertEqualMessage(average as Number, 101, "100.5 W must round up to 101 W");
    return true;
}

(:test)
function resetClearsTheLapAverage(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 200, 30);
    stats.reset();

    Test.assertMessage(
        stats.getLapAverage() == null,
        "expected null lap average after a lap reset"
    );
    return true;
}

(:test)
function normalizedPowerIsNullBeforeAFullThirtySecondWindow(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 250, 29);

    Test.assertMessage(
        stats.getNormalizedPower() == null,
        "normalized power needs a full 30 s rolling mean, so 29 samples is not enough"
    );
    return true;
}

(:test)
function normalizedPowerIsAvailableAtThirtySamples(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 250, 30);

    Test.assertMessage(
        stats.getNormalizedPower() != null,
        "expected normalized power once 30 samples exist"
    );
    return true;
}

(:test)
function normalizedPowerOfConstantPowerIsThatPower(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 250, 60);

    var np = stats.getNormalizedPower();
    Test.assertMessage(np != null, "expected normalized power after 60 samples");
    Test.assertEqualMessage(np as Number, 250, "steady 250 W must normalize to 250 W");
    return true;
}

(:test)
function normalizedPowerSmoothsSurgesShorterThanTheWindow(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    // One second on, one second off, for two minutes. Every 30 s window holds
    // fifteen of each, so the rolling mean is a flat 200 W and NP must be 200 W.
    // Raising each raw sample to the fourth instead would give roughly 253 W.
    for (var i = 0; i < 120; i += 1) {
        stats.addSample(i % 2 == 0 ? 100 : 300);
    }

    var np = stats.getNormalizedPower();
    Test.assertMessage(np != null, "expected normalized power after 120 samples");
    Test.assertEqualMessage(
        np as Number,
        200,
        "1 s surges are shorter than the 30 s window and must not inflate NP"
    );
    return true;
}

(:test)
function normalizedPowerExceedsAverageWhenEffortVaries(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    // A minute easy then a minute hard: same 200 W average as a steady effort,
    // but physiologically harder, which is the whole point of NP.
    feed(stats, 100, 60);
    feed(stats, 300, 60);

    var average = stats.getLapAverage();
    var np = stats.getNormalizedPower();
    Test.assertMessage(average != null && np != null, "expected both values after 120 samples");
    Test.assertEqualMessage(average as Number, 200, "60 s at 100 W then 60 s at 300 W averages 200 W");
    Test.assertMessage(
        (np as Number) > (average as Number),
        "NP must exceed average power for a variable effort, got " + np
    );
    return true;
}

(:test)
function resetClearsTheNormalizedPower(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 250, 60);
    stats.reset();

    Test.assertMessage(
        stats.getNormalizedPower() == null,
        "a new lap empties the NP accumulator, so NP is unavailable until the next sample"
    );
    return true;
}

(:test)
function resetKeepsTheRollingWindow(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 250, 60);
    stats.reset();
    stats.addSample(250);

    var np = stats.getNormalizedPower();
    Test.assertMessage(
        np != null,
        "the 30 s window survives a lap reset, so NP is available one sample into the new lap"
    );
    Test.assertEqualMessage(np as Number, 250, "steady 250 W across the lap boundary must normalize to 250 W");
    return true;
}

(:test)
function rollingDeviationIsNullBeforeNormalizedPowerExists(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 250, 29);

    Test.assertMessage(
        stats.getRollingDeviation() == null,
        "no NP means nothing to deviate from"
    );
    return true;
}

(:test)
function rollingDeviationIsZeroForASteadyEffort(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 250, 60);

    var deviation = stats.getRollingDeviation();
    Test.assertMessage(deviation != null, "expected a deviation after 60 samples");
    var magnitude = (deviation as Float).abs();
    Test.assertMessage(
        magnitude < 0.001,
        "a steady effort has its rolling mean equal to NP, got " + deviation
    );
    return true;
}

(:test)
function rollingDeviationIsPositiveWhenTheWindowExceedsNp(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 200, 120);
    feed(stats, 300, 30);

    var deviation = stats.getRollingDeviation();
    Test.assertMessage(deviation != null, "expected a deviation after 150 samples");
    // The window is a flat 300 W. NP blends 91 windows of 200 W with 30
    // windows climbing toward 300 W, so it sits between the two.
    Test.assertMessage(
        (deviation as Float) > 0.0 && (deviation as Float) < 0.5,
        "surging above NP must read positive and under a half, got " + deviation
    );
    return true;
}

(:test)
function rollingDeviationIsNegativeWhenEasingOff(logger as Logger) as Boolean {
    var stats = new LapPowerStats();
    feed(stats, 300, 120);
    feed(stats, 200, 30);

    var deviation = stats.getRollingDeviation();
    Test.assertMessage(deviation != null, "expected a deviation after 150 samples");
    Test.assertMessage(
        (deviation as Float) < 0.0 && (deviation as Float) > -0.5,
        "easing off below NP must read negative and above minus a half, got " + deviation
    );
    return true;
}
