import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

//! Shows lap average power and lap normalized power as one label over one
//! number line: "LAP P/NP" above "185/187", with a trend bar underneath.
//!
//! The bar shows whether the last 30 s of riding are pulling lap NP up or
//! down: a zero tick in the middle, fill growing right when the rolling mean
//! is above NP and left when it is below, full scale at a quarter of NP
//! either way. The fill is banded by how far off the effort is, the same on
//! both sides: green for the first quarter of the scale, then blue, red and
//! purple. The side says which way, the colour how much. On rolling terrain
//! it is the earliest warning that the first hill was taken too hard.
//!
//! Two app settings apply: the label text can be replaced, and the label can
//! be hidden altogether, which hands its row to the digits.
//!
//! In a slot the round lens cuts at one end, the bar is an arc along the rim
//! instead of a row under the digits. The corners beside the text there are
//! glass that no text row can reach, and the pole slots of the busiest
//! layouts have no height to spare for a third row anyway.
//!
//! Both numbers are computed here rather than read from Activity.Info, which
//! offers no per-lap power and no normalized power on any device. See
//! LapPowerStats for the maths.
//!
//! Drawing goes straight to the Dc instead of through Rez layouts: the text has
//! to be positioned from measured font widths to survive the 260-454 px range
//! of the target devices, and an XML layout would only be a second set of
//! coordinates to keep in sync with that arithmetic.
class NormPacerView extends WatchUi.DataField {
    private const PLACEHOLDER = "--";
    private const SEPARATOR = "/";

    //! Widest realistic value, used to size the everyday font. Lap power and
    //! lap NP are three digits for any human; four-digit values fall back to
    //! mWideValueFont rather than costing digit height all the time.
    private const DIGITS_SAMPLE = "888";
    private const WIDE_DIGITS_SAMPLE = "8888";

    //! Rolling-mean deviation that fills the trend bar to one end.
    private const BAR_FULL_SCALE = 0.25;

    //! Width of the zero tick, in pixels. Wider than a hairline so it stays
    //! visible on a MIP screen in sunlight with the fill flush against it.
    private const TICK_WIDTH = 3;

    //! Half the angular width of the rim arc, in degrees. Forty each side of
    //! the pole keeps the arc's ends beside the text rather than behind them.
    private const ARC_SPAN = 40;

    private var mStats as LapPowerStats;
    private var mLapAverage as Number?;
    private var mNormalizedPower as Number?;
    private var mDeviation as Float?;

    // Trend bar geometry, settled in onLayout with the fonts. The band is
    // the gap above the bar plus the bar itself, and is part of the content
    // height the font fitting works with.
    private var mBarHeight as Number;
    private var mBarGap as Number;

    // Rim-arc geometry, valid only while mArcMode is set. The center is the
    // screen's center expressed in this Dc's coordinates, which for a bottom
    // slot is above the Dc.
    private var mArcMode as Boolean;
    private var mArcCenterX as Number;
    private var mArcCenterY as Number;
    private var mArcRadius as Number;
    private var mArcCenterAngle as Number;

    private var mLabelFont as FontType;
    private var mValueFont as FontType;
    private var mWideValueFont as FontType;

    // The number fonts carry digits and little else, so the separator and the
    // waiting placeholder need a text font. Sized to sit beside the digits.
    private var mSeparatorFont as FontType;

    // How much of the Dc's width the content may use, and where it sits
    // vertically. Both exist because a round lens narrows toward the top and
    // bottom of the screen: a field placed in those bands is handed a Dc that
    // extends past the glass.
    private var mUsableWidth as Number;
    private var mVerticalBias as Float;

    private var mLabel as String;
    private var mShowLabel as Boolean;

    // Whether the label is drawn in this slot: the setting, and then only if
    // the glass can hold it. A pole slot of a busy layout cannot, and there
    // the digits take its row instead.
    private var mLabelVisible as Boolean;

    // Where the label is anchored. In a half-width slot the lens cuts the
    // outer corner, and a wide label centered in the slot would lose its
    // first or last letters, so it is pushed toward the screen's center.
    private var mLabelX as Number;
    private var mLabelJustify as TextJustification;

    // Set when a setting changes: onLayout is only called by the system for
    // size changes, so the next onUpdate has to redo the layout itself.
    private var mLayoutDirty as Boolean;

    function initialize() {
        DataField.initialize();
        mStats = new LapPowerStats();
        mLapAverage = null;
        mNormalizedPower = null;
        mDeviation = null;
        mBarHeight = 3;
        mBarGap = 2;
        mArcMode = false;
        mArcCenterX = 0;
        mArcCenterY = 0;
        mArcRadius = 0;
        mArcCenterAngle = 90;
        mLabelFont = Graphics.FONT_XTINY;
        mValueFont = Graphics.FONT_NUMBER_MILD;
        mWideValueFont = Graphics.FONT_NUMBER_MILD;
        mSeparatorFont = Graphics.FONT_XTINY;
        mUsableWidth = 0;
        mVerticalBias = 0.5;
        mLabel = "";
        mShowLabel = true;
        mLabelVisible = true;
        mLabelX = 0;
        mLabelJustify = Graphics.TEXT_JUSTIFY_CENTER;
        mLayoutDirty = false;
        loadSettings();
    }

    //! Settings changed while the field is running. Re-read them and redo
    //! the layout on the next update, since the label may have changed size
    //! or gone away.
    function onSettingsChanged() as Void {
        loadSettings();
        mLayoutDirty = true;
    }

    private function loadSettings() as Void {
        mLabel = WatchUi.loadResource(Rez.Strings.combinedLabel) as String;
        var custom = Application.Properties.getValue("customLabel");
        if (custom instanceof String && custom.length() > 0) {
            mLabel = custom;
        }
        var show = Application.Properties.getValue("showLabel");
        mShowLabel = show instanceof Boolean ? show : true;
    }

    //! Height of the label row: nothing when the label is hidden.
    private function labelHeight(dc as Dc) as Number {
        return mLabelVisible ? dc.getFontHeight(mLabelFont) : 0;
    }

    //! Called whenever the field's size or obscurity changes. Work out the
    //! fonts and geometry once here rather than per frame.
    function onLayout(dc as Dc) as Void {
        mLayoutDirty = false;

        // The label is fixed at the smallest system font rather than scaled to
        // the slot: this field exists to replace two native fields with one, so
        // every pixel not spent naming the numbers goes to the numbers.
        mLabelFont = Graphics.FONT_XTINY;

        var flags = DataField.getObscurityFlags();
        var clippedTop = (flags & OBSCURE_TOP) != 0;
        var clippedBottom = (flags & OBSCURE_BOTTOM) != 0;

        // Anchor content to the unobscured edge rather than nudging it from
        // center: the slack between the content and the cell shrinks as the
        // value font grows, so a proportional nudge fails when it is needed.
        if (clippedTop && !clippedBottom) {
            mVerticalBias = 0.9;
        } else if (clippedBottom && !clippedTop) {
            mVerticalBias = 0.1;
        } else {
            mVerticalBias = 0.5;
        }

        // A twentieth of the field, but never thinner than a visible line.
        mBarHeight = dc.getHeight() / 20;
        if (mBarHeight < 3) {
            mBarHeight = 3;
        }
        mBarGap = mBarHeight / 2;
        if (mBarGap < 2) {
            mBarGap = 2;
        }

        placeLabel(dc, flags);

        // The arc needs the screen center, which is only known relative to
        // this Dc when the Dc spans the full width: pole slots always do.
        mArcMode = false;
        var settings = System.getDeviceSettings();
        if (
            settings.screenShape == System.SCREEN_SHAPE_ROUND &&
            clippedTop != clippedBottom &&
            dc.getWidth() == settings.screenWidth
        ) {
            var radius = settings.screenWidth / 2;
            mArcMode = true;
            mArcCenterX = radius;
            mArcCenterY = clippedTop
                ? radius
                : radius - (settings.screenHeight - dc.getHeight());
            mArcRadius = radius - mBarHeight / 2 - 1;
            mArcCenterAngle = clippedTop ? 90 : 270;
        }

        mLabelVisible = mShowLabel;
        fitFonts(dc, clippedTop, clippedBottom);
        if (mLabelVisible && !labelFits(dc)) {
            // Even the smallest digits leave no chord wide enough for the
            // label, so give its row to the digits and fit them again.
            mLabelVisible = false;
            fitFonts(dc, clippedTop, clippedBottom);
        }
    }

    //! True when the label fits the width the fitted layout allows it.
    private function labelFits(dc as Dc) as Boolean {
        return (
            dc.getTextWidthInPixels(mLabel, mLabelFont) <=
            margined(mUsableWidth)
        );
    }

    //! Decide where the label is anchored, see mLabelX.
    //!
    //! The lens cuts a half-width slot's outer corner by an amount that
    //! depends on the slot's height on the screen, which a field cannot
    //! learn. In the busiest layouts it is roughly a fifth of the slot, so a
    //! label wider than three fifths is anchored to the inner edge, where
    //! the glass is widest, rather than centered.
    private function placeLabel(dc as Dc, flags as Number) as Void {
        var width = dc.getWidth();
        var cutLeft = (flags & OBSCURE_LEFT) != 0;
        var cutRight = (flags & OBSCURE_RIGHT) != 0;
        var wide =
            dc.getTextWidthInPixels(mLabel, mLabelFont) > (width * 3) / 5;

        // Flush to the inner edge: every pixel of margin there is a pixel
        // lost to the lens at the other end.
        if (wide && cutLeft && !cutRight) {
            mLabelX = width;
            mLabelJustify = Graphics.TEXT_JUSTIFY_RIGHT;
        } else if (wide && cutRight && !cutLeft) {
            mLabelX = 0;
            mLabelJustify = Graphics.TEXT_JUSTIFY_LEFT;
        } else {
            mLabelX = width / 2;
            mLabelJustify = Graphics.TEXT_JUSTIFY_CENTER;
        }
    }

    //! Called once per second with the current activity state.
    function compute(info as Activity.Info) as Void {
        // Paused seconds are not part of the lap. Feeding them in would drag
        // both numbers toward zero while the rider stands at a junction.
        if (
            info has :timerState &&
            info.timerState != Activity.TIMER_STATE_ON
        ) {
            return;
        }

        var power = 0;
        if (info has :currentPower && info.currentPower != null) {
            power = info.currentPower as Number;
        }

        mStats.addSample(power);
        mLapAverage = mStats.getLapAverage();
        mNormalizedPower = mStats.getNormalizedPower();
        mDeviation = mStats.getRollingDeviation();
    }

    //! Both numbers describe the current lap, so the lap key restarts them.
    function onTimerLap() as Void {
        startNewLap();
    }

    //! Resetting the activity discards the lap along with everything else.
    function onTimerReset() as Void {
        startNewLap();
    }

    function onUpdate(dc as Dc) as Void {
        var background = getBackgroundColor();
        var valueColor =
            background == Graphics.COLOR_BLACK
                ? Graphics.COLOR_WHITE
                : Graphics.COLOR_BLACK;
        var labelColor =
            background == Graphics.COLOR_BLACK
                ? Graphics.COLOR_LT_GRAY
                : Graphics.COLOR_DK_GRAY;
        // The empty part of the trend bar: dim enough to read as background
        // next to the red or blue fill, bright enough to show the bar's extent.
        var trackColor =
            background == Graphics.COLOR_BLACK
                ? Graphics.COLOR_DK_GRAY
                : Graphics.COLOR_LT_GRAY;

        if (mLayoutDirty) {
            onLayout(dc);
        }

        dc.setColor(Graphics.COLOR_TRANSPARENT, background);
        dc.clear();

        var labelHeight = labelHeight(dc);
        var valueHeight = dc.getFontHeight(mValueFont);
        var top = (
            (dc.getHeight() - (labelHeight + valueHeight + barBand())) *
            mVerticalBias
        ).toNumber();
        var centerX = dc.getWidth() / 2;

        if (mLabelVisible) {
            dc.setColor(labelColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(mLabelX, top, mLabelFont, mLabel, mLabelJustify);
        }

        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        drawValueRow(dc, centerX, top + labelHeight, valueHeight);

        if (mArcMode) {
            drawTrendArc(dc, trackColor, valueColor);
        } else {
            drawTrendBar(
                dc,
                centerX,
                top + labelHeight + valueHeight + mBarGap,
                trackColor,
                valueColor
            );
        }
    }

    private function startNewLap() as Void {
        mStats.reset();
        mLapAverage = null;
        mNormalizedPower = null;
        mDeviation = null;
    }

    //! Height the trend bar adds to the content: the gap that separates it
    //! from the digits plus the bar itself, or nothing when it rides the rim.
    private function barBand() as Number {
        return mArcMode ? 0 : mBarGap + mBarHeight;
    }

    //! Deviation scaled so that +-1.0 is a full bar, clamped to that range.
    private function clampedFraction(deviation as Float) as Float {
        var fraction = deviation / BAR_FULL_SCALE;
        if (fraction > 1.0) {
            return 1.0;
        }
        if (fraction < -1.0) {
            return -1.0;
        }
        return fraction;
    }

    //! Fill colours from the tick outward, one per quarter of the scale.
    private function bandColors() as Array<ColorType> {
        return (
            [
                Graphics.COLOR_GREEN,
                Graphics.COLOR_BLUE,
                Graphics.COLOR_RED,
                Graphics.COLOR_PURPLE,
            ] as Array<ColorType>
        );
    }

    //! Trend bar as an arc along the rim, centered straight up in a top slot
    //! or straight down in a bottom slot. Right of center means the last
    //! 30 s are above NP, exactly as on the straight bar.
    private function drawTrendArc(
        dc as Dc,
        trackColor as ColorType,
        tickColor as ColorType
    ) as Void {
        var center = mArcCenterAngle;
        // Arc angles grow counter-clockwise, so "to the right" is toward
        // smaller angles at the top of the screen and larger at the bottom.
        var rightward = center == 90 ? -1 : 1;

        dc.setAntiAlias(true);
        dc.setPenWidth(1);
        dc.setColor(trackColor, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(
            mArcCenterX,
            mArcCenterY,
            mArcRadius,
            Graphics.ARC_CLOCKWISE,
            center + ARC_SPAN,
            center - ARC_SPAN
        );

        var deviation = mDeviation;
        if (deviation != null) {
            var fraction = clampedFraction(deviation);
            var sweep = (ARC_SPAN * fraction.abs()).toNumber();
            var toward = fraction > 0.0 ? rightward : -rightward;
            var colors = bandColors();
            var bandSpan = ARC_SPAN / colors.size();
            dc.setPenWidth(mBarHeight);
            for (var i = 0; i < colors.size(); i += 1) {
                var from = i * bandSpan;
                var to = from + bandSpan;
                drawArcSegment(
                    dc,
                    center,
                    toward,
                    from,
                    sweep < to ? sweep : to,
                    colors[i]
                );
            }
        }

        // Zero tick: a radial line through the track at the pole, a little
        // proud of the fill on the inside but short of the text below it.
        var outward = center == 90 ? -1 : 1;
        var inner = mArcRadius - mBarHeight / 2 - mBarGap;
        var outer = mArcRadius + mBarHeight / 2 + 1;
        dc.setPenWidth(TICK_WIDTH);
        dc.setColor(tickColor, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(
            mArcCenterX,
            mArcCenterY + outward * inner,
            mArcCenterX,
            mArcCenterY + outward * outer
        );
        dc.setPenWidth(1);
        dc.setAntiAlias(false);
    }

    //! One coloured stretch of the arc fill, from `from` to `to` degrees
    //! away from the center angle in the direction `toward`. Nothing is
    //! drawn for an empty stretch: drawArc treats equal ends as a circle.
    private function drawArcSegment(
        dc as Dc,
        center as Number,
        toward as Number,
        from as Number,
        to as Number,
        color as ColorType
    ) as Void {
        if (to <= from) {
            return;
        }
        var direction = toward > 0
            ? Graphics.ARC_COUNTER_CLOCKWISE
            : Graphics.ARC_CLOCKWISE;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(
            mArcCenterX,
            mArcCenterY,
            mArcRadius,
            direction,
            center + toward * from,
            center + toward * to
        );
    }

    //! Draw the trend bar with its top edge at y. The track and zero tick
    //! are always drawn so the rider knows where the bar will appear; the
    //! fill needs a deviation, which needs NP. The track is a solid dim strip
    //! rather than an outline so the fill can use the bar's full height.
    private function drawTrendBar(
        dc as Dc,
        centerX as Number,
        y as Number,
        trackColor as ColorType,
        tickColor as ColorType
    ) as Void {
        var width = margined(mUsableWidth);
        var halfWidth = width / 2;
        var left = centerX - halfWidth;

        dc.setColor(trackColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(left, y, width, mBarHeight);

        var deviation = mDeviation;
        if (deviation != null) {
            var fraction = clampedFraction(deviation);
            var fill = (fraction.abs() * halfWidth).toNumber();
            var colors = bandColors();
            var bandWidth = halfWidth / colors.size();
            // One band per quarter of the half bar, each growing away from
            // the tick; a band the fill has not reached is left to the track.
            for (var i = 0; i < colors.size(); i += 1) {
                var from = i * bandWidth;
                var to = from + bandWidth;
                if (fill < to) {
                    to = fill;
                }
                if (to <= from) {
                    break;
                }
                dc.setColor(colors[i], Graphics.COLOR_TRANSPARENT);
                if (fraction > 0.0) {
                    dc.fillRectangle(centerX + from, y, to - from, mBarHeight);
                } else {
                    dc.fillRectangle(centerX - to, y, to - from, mBarHeight);
                }
            }
        }

        // The tick overshoots the track by the gap each way so zero stays
        // obvious when the fill is flush against it.
        dc.setColor(tickColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(
            centerX - TICK_WIDTH / 2,
            y - mBarGap,
            TICK_WIDTH,
            mBarHeight + 2 * mBarGap
        );
    }

    //! Draw "185/187" centered on centerX, each piece in the font that can
    //! actually render it, and each vertically centered in the row.
    private function drawValueRow(
        dc as Dc,
        centerX as Number,
        top as Number,
        rowHeight as Number
    ) as Void {
        var left = mLapAverage == null ? PLACEHOLDER : mLapAverage.toString();
        var right =
            mNormalizedPower == null
                ? PLACEHOLDER
                : mNormalizedPower.toString();

        var digitFont =
            left.length() > DIGITS_SAMPLE.length() ||
            right.length() > DIGITS_SAMPLE.length()
                ? mWideValueFont
                : mValueFont;
        var leftFont = mLapAverage == null ? mSeparatorFont : digitFont;
        var rightFont = mNormalizedPower == null ? mSeparatorFont : digitFont;

        var total =
            dc.getTextWidthInPixels(left, leftFont) +
            dc.getTextWidthInPixels(SEPARATOR, mSeparatorFont) +
            dc.getTextWidthInPixels(right, rightFont);

        var x = centerX - total / 2;
        x += drawSegment(dc, x, top, rowHeight, leftFont, left);
        x += drawSegment(dc, x, top, rowHeight, mSeparatorFont, SEPARATOR);
        drawSegment(dc, x, top, rowHeight, rightFont, right);
    }

    //! Draw one piece of the number line, returning the width it consumed.
    private function drawSegment(
        dc as Dc,
        x as Number,
        top as Number,
        rowHeight as Number,
        font as FontType,
        text as String
    ) as Number {
        var inset = (rowHeight - dc.getFontHeight(font)) / 2;
        dc.drawText(x, top + inset, font, text, Graphics.TEXT_JUSTIFY_LEFT);
        return dc.getTextWidthInPixels(text, font);
    }

    //! Choose the largest value font that fits, together with the width the
    //! content may occupy.
    //!
    //! On a round lens the two are coupled: a taller number pushes the label
    //! row toward the narrow end of the band, which leaves less width, which
    //! may rule out the very font that caused it. So each candidate is tested
    //! against the geometry it would itself produce, largest first, and the
    //! first self-consistent one wins.
    private function fitFonts(
        dc as Dc,
        clippedTop as Boolean,
        clippedBottom as Boolean
    ) as Void {
        var candidates = valueFontCandidates();
        var labelHeight = labelHeight(dc);
        // A hidden label has no width to fit. A visible one that fits no
        // candidate merely leaves the smallest digits; onLayout then decides
        // whether to drop it.
        var labelWidth = mLabelVisible
            ? dc.getTextWidthInPixels(mLabel, mLabelFont)
            : 0;

        mValueFont = candidates[candidates.size() - 1];
        mSeparatorFont = separatorFontFor(dc, mValueFont);
        mUsableWidth = usableWidth(
            dc,
            labelHeight + dc.getFontHeight(mValueFont) + barBand(),
            clippedTop,
            clippedBottom,
            topInsetFor(dc, mValueFont),
            bottomInsetFor(dc, mValueFont)
        );

        for (var i = 0; i < candidates.size(); i += 1) {
            var font = candidates[i];
            var contentHeight =
                labelHeight + dc.getFontHeight(font) + barBand();
            if (contentHeight > dc.getHeight()) {
                continue;
            }

            var usable = usableWidth(
                dc,
                contentHeight,
                clippedTop,
                clippedBottom,
                topInsetFor(dc, font),
                bottomInsetFor(dc, font)
            );
            var available = margined(usable);
            var separator = separatorFontFor(dc, font);
            if (
                labelWidth <= available &&
                sampleWidth(dc, font, separator, DIGITS_SAMPLE) <= available
            ) {
                mValueFont = font;
                mSeparatorFont = separator;
                mUsableWidth = usable;
                break;
            }
        }

        // The four-digit fallback reuses the geometry already settled on, and
        // may never be taller than the font the layout was measured from.
        var available = margined(mUsableWidth);
        var valueHeight = dc.getFontHeight(mValueFont);
        mWideValueFont = mValueFont;
        for (var i = 0; i < candidates.size(); i += 1) {
            var font = candidates[i];
            if (
                dc.getFontHeight(font) <= valueHeight &&
                sampleWidth(dc, font, mSeparatorFont, WIDE_DIGITS_SAMPLE) <=
                    available
            ) {
                mWideValueFont = font;
                break;
            }
        }
    }

    //! Width of "<sample>/<sample>" as it would actually be drawn.
    private function sampleWidth(
        dc as Dc,
        digitFont as FontType,
        separatorFont as FontType,
        sample as String
    ) as Number {
        return (
            2 * dc.getTextWidthInPixels(sample, digitFont) +
            dc.getTextWidthInPixels(SEPARATOR, separatorFont)
        );
    }

    //! Largest text font that is no taller than the digits it sits between.
    private function separatorFontFor(
        dc as Dc,
        valueFont as FontType
    ) as FontType {
        var candidates =
            [
                Graphics.FONT_LARGE,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL,
                Graphics.FONT_TINY,
                Graphics.FONT_XTINY,
            ] as Array<FontType>;

        var limit = dc.getFontHeight(valueFont);
        for (var i = 0; i < candidates.size(); i += 1) {
            if (dc.getFontHeight(candidates[i]) <= limit) {
                return candidates[i];
            }
        }
        return Graphics.FONT_XTINY;
    }

    //! Leave a sliver of breathing room so text never runs to the very edge.
    private function margined(width as Number) as Number {
        return (width * 15) / 16;
    }

    //! Distance from the top of the content to the row the chord is
    //! measured at when the lens cuts the top: a quarter into the label, or
    //! a quarter into the digits when the label is hidden.
    private function topInsetFor(dc as Dc, valueFont as FontType) as Number {
        var font = mLabelVisible ? mLabelFont : valueFont;
        return dc.getFontHeight(font) / 4;
    }

    //! Distance from the bottom of the content to the row the chord is
    //! measured at when the lens cuts the bottom: the middle of the straight
    //! bar, or a quarter into the digits when the bar rides the rim.
    private function bottomInsetFor(dc as Dc, valueFont as FontType) as Number {
        return mArcMode ? dc.getFontHeight(valueFont) / 4 : mBarHeight / 2;
    }

    //! Usable width for a layout whose content is `contentHeight` tall.
    //!
    //! On a rectangular screen, or a field the lens does not cut, that is the
    //! whole Dc. On a round screen it is the chord at whichever row sits
    //! nearest the narrow end of the band, measured `topInset` below the
    //! content's top or `bottomInset` above its bottom. Glyphs never reach
    //! the edge of their font box, so measuring at the very edge would throw
    //! away width that is really there, and at the pole of the lens would
    //! report none at all.
    private function usableWidth(
        dc as Dc,
        contentHeight as Number,
        clippedTop as Boolean,
        clippedBottom as Boolean,
        topInset as Number,
        bottomInset as Number
    ) as Number {
        var full = dc.getWidth();
        if (!clippedTop && !clippedBottom) {
            return full;
        }

        var settings = System.getDeviceSettings();
        if (settings.screenShape != System.SCREEN_SHAPE_ROUND) {
            return full;
        }

        // Measured from the top of the screen, which is where the band starts
        // only if it is the band cut off there.
        var top = (dc.getHeight() - contentHeight) * mVerticalBias;
        var localY = clippedTop
            ? top + topInset
            : top + contentHeight - bottomInset;
        var screenY = clippedTop
            ? localY
            : settings.screenHeight - dc.getHeight() + localY;

        var radius = settings.screenWidth / 2.0;
        var offset = radius - screenY;
        var squared = radius * radius - offset * offset;
        if (squared <= 0.0) {
            return 0;
        }

        var chord = (2.0 * Math.sqrt(squared)).toNumber();
        return chord < full ? chord : full;
    }

    private function valueFontCandidates() as Array<FontType> {
        return (
            [
                Graphics.FONT_NUMBER_HOT,
                Graphics.FONT_NUMBER_MEDIUM,
                Graphics.FONT_NUMBER_MILD,
                Graphics.FONT_LARGE,
                Graphics.FONT_MEDIUM,
                Graphics.FONT_SMALL,
                Graphics.FONT_XTINY,
            ] as Array<FontType>
        );
    }
}
