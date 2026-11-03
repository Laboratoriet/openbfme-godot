# Setup screen art (lane IOS-12)

The iOS first-run screen (`godot/scripts/release/first_run.gd`, `_build_ios_ui`) shows
each of these files when it is here, and lays out without it when it is not. No code
changes are needed: drop the PNG in, let Godot import it, and it appears.

| File | Where it shows | Shown at | Make it (@3x) |
|---|---|---|---|
| `logo.png` | top of the header, in place of the gold word "OpenBFME" | 40 pt tall (`LOGO_HEIGHT`), width from its aspect, left-aligned | 120 px tall, at most 1150 px wide |
| `step-1.png` | top of step 1, "On your Mac" | the card's inner width, aspect kept | 1584 px wide |
| `step-2.png` | top of step 2, "Send it to this iPhone" | the card's inner width, aspect kept | 1584 px wide |
| `step-3.png` | top of step 3, "Install" | the card's inner width, aspect kept | 1584 px wide |

## Sizes

The screen is laid out in points and scaled to the display (2x or 3x), so draw at
points and export at 3x.

- **Step pictures** fill the card's inner width: the column minus 2 × 16 pt padding.
  That is 528 pt at most (the 560 pt column), about 398 pt on the iPhone Duo's inner
  screen in landscape (two columns) and 386 pt on the folded phone upright.
  Design at **528 pt wide**, export **1584 px wide** (3x). Height is yours; the
  aspect is kept. Around 16:10 (1584 × 990 px) keeps a card from getting too tall
  on a phone; much taller than 1056 px (352 pt) pushes the text far down.
- **Logo**: 40 pt tall, so **120 px tall** at 3x. Its width follows its aspect and
  is not capped, so keep it at most **1150 px** (386 pt, the narrowest column).

## Format

- PNG, sRGB, **transparent background**: the pictures sit on the card fill
  (`C_CARD`, about #17171A) and the logo on the screen (`C_BG`, #0F0F12).
- Square corners are fine; the card's 12 pt radius is outside the 16 pt padding,
  so round the corners in the art if you want them rounded.
- Keep text out of the pictures where you can: they are scaled down on smaller
  screens (to about 73 % on the folded phone), and the screen's own text wraps.

## Import

Godot imports a PNG the first time the editor (or `Godot --headless --path godot --import`)
sees it and writes `<name>.png.import` next to it; commit both. The images are
drawn with mipmap filtering, so turning **Mipmaps > Generate** on in the Import
dock gives the cleanest downscale (optional: without mipmaps they are drawn linear).

The screen checks with `ResourceLoader.exists`, so a PNG without its import does
not show (an exported app carries only imported resources).
