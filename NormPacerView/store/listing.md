# Norm Pacer — Connect IQ store listing

Draft text for the store submission form. Nothing here is read by the build.

## Name

Norm Pacer

## Short description

Pace threshold intervals by surge-weighted lap power, with a trend bar that
warns you before the first hill blows the interval.

## Long description

Norm Pacer is a single data field for riders who pace intervals by effort
rather than by raw watts.

It shows two numbers for the current lap: plain average power, and a
surge-weighted lap power, the "norm" in the name: a 30-second rolling
average raised to the fourth power and averaged over the lap, the same
weighting the training-load metrics on your head unit use. On rolling
terrain that second number is the honest one, because a surge on a climb
costs far more than a coast on the descent gives back.

Under the numbers a trend bar shows what the last 30 seconds are doing to
the lap figure. Fill to the right of the centre mark means you are riding
above your lap norm and pulling it up; fill to the left means you are below
it. The colour tells you how far off you are: green for a small deviation,
then blue, red and purple as it grows. In the top and bottom slots of a
round watch the bar follows the bezel as an arc.

Both numbers reset on the lap key and on the workout step. The 30-second
window carries across the lap boundary, so a fresh lap shows a figure one
second in rather than half a minute later.

Settings, from the Garmin Connect app:

- Label text: replace the default "LAP P/NORM" with anything you like.
- Show label: turn the label off to give the numbers and bar the whole field.

No permissions, no phone connection, nothing leaves the watch.

Powered by LgLab.

## What's new

1.0.0: first release.

## Notes for the form

- Category: Data Fields. Activity type: Cycling.
- Supported devices come from the manifest: fēnix 8 43 mm, 47/51 mm, Pro
  47 mm, Solar 47 mm and 51 mm (also covers tactix 8 and quatix 8), Edge 850.
- Icon: `icon-512.png` in this folder, rendered from `icon.svg`.
- Screenshots: capture from the simulator with File > Save Screen Capture,
  one per layout that matters (1, 2, 4, and 7 fields on the fēnix 8, 1 and 4
  on the Edge 850).
- Do not use "Normalized Power", "NP", "TSS" or "IF" anywhere in the listing;
  they are TrainingPeaks trademarks. The text above describes the method
  ("surge-weighted", "lap norm") and never names the metric.
- Publisher name shown on the listing comes from the Connect IQ developer
  account profile; set it to LgLab there.
