# Halftone

A native iOS app that turns a company logo and a website link into a QR code
shaped like that logo. Everything runs on device: no accounts, no onboarding,
no backend.

## The technique

Every QR module is subdivided into a 3×3 grid of sub-modules.

- The **centre** sub-module is pinned to the module's true black/white value,
  because the centre is the point a decoder samples.
- The **eight cells around it** are free to take the logo's silhouette.

The data is carried by the centres; the picture is carried by everything else,
at three times the module resolution.

Two things keep it scannable, and both were measured rather than assumed:

1. **Function patterns are never compromised.** Finders, timing, alignment and
   format modules are drawn whole. Without this, nothing decodes at all —
   measured at 0/30 successful captures.
2. **A quota of free cells is forced back to agree with its module.** The
   `logoStrength` slider sets that quota. Cells that already agree cost nothing
   and are spent first, so the quota only buys real overrides when it has to.
   Orthogonal neighbours are given up before diagonal ones, because they sit
   closest to the sampled centre and dominate it once the image blurs.

### The centre is the cheapest robustness lever

The classic formulation makes the data-carrying centre exactly ⅓ of a module.
Growing it is far cheaper than weakening the logo. Measured against a real
decoder across five test marks and seven simulated camera captures:

| centre size | strength 0.6 | strength 0.8 | strength 1.0 |
|---|---|---|---|
| 0.33 module | 23/35 | 19/35 | 12/35 |
| 0.50 module | 32/35 | 25/35 | 18/35 |
| **0.58 module** | **35/35** | 32/35 | 24/35 |
| 0.67 module | 35/35 | 35/35 | 31/35 |

At matched likeness (~0.70 pixel agreement with the artwork), a 0.58 centre at
strength 0.6 scores 35/35 where a ⅓ centre at strength 0.5 scores 29/35. The app
ships a 0.56 centre and a default strength of 0.68.

### The mask is chosen to match the artwork

Of the eight legal data masks, the app picks the one whose module layout already
agrees most with the logo, using the standard penalty score only as a gentle
corrective so the symbol stays well-formed. Across the test set this recovered
the best available mask in four cases out of five, worth up to four points of
likeness for nothing.

---

## The generate animation

Tapping Generate makes the Dynamic Island let go of a drop, and the drop
spreads into the card.

While the verify loop runs, the island's lower edge bulges a little further
with every moment it works and its edge glows in the artwork's colour, so the
wait reads as pressure building rather than a pause. Once there is a verified
symbol the bulge hangs into a drop, stretches into a pill and its neck snaps.
What the island keeps springs back. The freed drop lightens and spreads into
the card —
its width first, then its lower edge, each on its own spring, pitching as the
lower edge overshoots and lands — and the symbol is made on it from one point.
Every cell the exporter will write is thrown out of the card's centre as a tiny
particle into a cloud that keeps creeping outward; then, from the centre out,
each particle turns for home on a curved path, growing to its full size with a
soft overshoot as it arrives. The three finders are particles too — each broken
into tiny tiles sampled from inside its real shape — and they come home last,
together, with the crisp finder laid over them. The haptics follow the liquid:
a soft tick at the snap, a firm one on landing, the bang, a ratchet as the
cells fall in, and a harder tick as the finders lock.

The resolve is drawn live from the plan's real geometry — the same cells, at
the same shapes and sizes, as the still — and that drawing is the one that
stays: there is no bitmap swapped in at the end, so nothing about the symbol
can change when the animation completes. The exports render their own bitmaps
from the same geometry, tagged sRGB, the space the colours are specified in.

The page becomes the customise page as the card touches down: the inputs give
way and the controls rise into place under the card. Tap Edit and the same
sequence runs backwards — the modules leave, the card is pulled up into a drop,
and the island takes it back.

Everything on screen is a pure function of one clock, which is what makes it
scrubbable and reversible. The join between drop and island is a pair of fillets
tangent to both — the surface-tension shape — and it is drawn as geometry rather
than as a blur-and-threshold metaball, so it needs no Metal, stays crisp at any
scale, and can be tuned frame by frame in `Tools/liquid_proto.py`, which draws
the same shapes the app does.

The island itself is never drawn. An app cannot animate it — it belongs to the
system, and ActivityKit only ever hands it content, never frame-by-frame
control. The drop's neck springs from a line just behind the island's lower
edge, derived from the top safe area rather than measured on one handset, so
the join is hidden under the real thing. On a device without an island a black
pill stands in.

The card is the real plan, so what is watched developing is byte-identical to
the PNG that comes out of the exporter.

## Verification

**No render reaches the user without decoding first.**

After every render the output is rasterised at seven simulated capture
conditions — from a crisp 16 pixels per module down to 3 pixels per module with
camera shake — and decoded with **Vision** (`VNDetectBarcodesRequest`). Core
Image's independent QR detector runs alongside it as a second opinion.

If a render fails, the pipeline walks a ladder that trades likeness for
robustness one rung at a time. The final rung is a plain QR code, which was
measured to decode at **7/7 conditions at every symbol size the app can
produce** — so the loop always terminates with something valid. When the loop
has to pull back, the verify screen says so and shows the strength it settled
on, rather than hiding it.

---

## Edge cases

Thin wordmarks and detailed illustrations lose all definition at halftone
resolution, so the app detects that on upload and says so instead of silently
degrading. Three metrics, measured at the exact grid resolution the symbol will
use:

| metric | good marks | hairline wordmark | detailed illustration |
|---|---|---|---|
| ink coverage | 0.21 – 0.55 | **0.02** | 0.51 |
| stroke survival (one erosion) | 0.86 – 0.95 | **0.00 – 0.03** | **0.23** |
| edge density | 0.015 – 0.024 | 0.019 | **0.31** |

Thresholds: coverage outside 0.05–0.95, stroke survival below 0.45, or edge
density above 0.12. Each produces a specific headline and a specific suggestion.

---

## Screens

1. **Input** — drop zone for the mark (PNG, SVG, PDF, JPEG, HEIC) from Files or
   Photos, three bundled sample marks to try it with, and a field for the URL.
   Warns when the destination is long, since more modules means smaller blocks.
   If there is no logo, `og:image` / `apple-touch-icon` and `theme-color` are
   pulled from the site as a fallback. Any `sample-*.png` dropped into
   `HalftoneQR/Resources/Samples/` becomes a sample.
2. **Customise** — the same page, once the card has landed: one slider for logo
   strength, three module shapes, three finder styles, the centre emblem, Focus
   and the resolve order, all on glass under the card. Every change re-renders a
   fast preview; **Verify** proves it in place — the decoded string and the
   capture count — before Export is offered. No error-correction or mask
   controls are exposed.
3. **Export** — four finishes generated and verified at once; pick one and write
   **SVG, PDF and PNG**, plus an optional animated GIF of the resolve.

---

## Architecture

```
Core/QR/          Complete QR encoder: Reed-Solomon over GF(256), segment
                  selection, version and ECC tables, mask evaluation.
                  Written from scratch rather than using CIQRCodeGenerator,
                  because halftoning needs the function-pattern map and
                  mask control that filter does not expose.

Core/Image/       Silhouette extraction (alpha channel when present, Otsu
                  luminance threshold otherwise), quality analysis, dominant
                  colour, and decoding for raster / PDF / SVG sources.

Core/Render/      RenderPlan — a resolution-independent list of primitives.
                  PNG, PDF and SVG are all generated from this one list, so
                  the three formats cannot drift apart.

Core/Verify/      Vision + Core Image decoding under simulated capture, and
                  the retreat ladder.

Core/Export/      Four palette variants, file writing, GIF and H.264 export
                  of the resolve animation.
```

The single most important structural decision is `RenderPlan`: one geometry
description, consumed by a Core Graphics bitmap renderer, a PDF context, an SVG
writer, and the animation exporter. There is no second implementation of a
rounded rectangle anywhere in the codebase.

---

## Drawing the symbol

Runs of square cells are drawn as one shape. A cell's corner is rounded where
nothing touches it, and the notch where two cells meet at a corner is filled
with a fillet, so the mark reads as a smooth silhouette rather than a grid of
blocks and a lone module reads as a dot. The sampled centres are rounded where
nothing dark touches them, and the light centres punched out of the mark are
always rounded. Dots and diamonds stand on their own. The decisions — which
cells are dark — are unchanged; only their outlines are, and every render is
still verified.

**Focus** puts the mark first: the sampled centres and the structure in the
neutral ink, the mark in its own colour, and the centres drawn *beneath* the
mark so they only show where it is absent. Colour does the separating because
opacity cannot: `Tools/validation/focus.py` measured how light the centres can
be drawn with the mark at full ink, and a decoder thresholds on the darkest
thing in frame. At a barely visible tint 5 of 35 captures already fail; at a
visible one, half do. Under the mark, a dark centre is still dark.

## Design

Near-black rather than pure black. One accent colour, taken from the user's own
artwork, threaded through the environment. Monospaced type for every label,
value and the decoded string; clean sans for prose. Hairline borders, no filled
cards, no gradients, no shadows. Controls live in a bottom bar and content never
sits on it.

**Liquid Glass** is used on the bottom bar and the floating controls, gated at
both compile time (`#if compiler(>=6.2)`) and runtime (`if #available(iOS 26)`).
On earlier SDKs it degrades to a material and a hairline. The compile-time gate
matters: `Glass` does not exist in SDKs before iOS 26, so a runtime check alone
would not build.

Motion is mechanical: modules land in quantised steps with a small overshoot and
snap back. Nothing ever changes opacity. Seven choreographies ship — big bang,
scanline, bloom, wipe, spiral, develop and structure-first. Big bang is the only
one that moves cells as well as scaling them.

---

## Design assets

The first screen's artwork lives in the asset catalogue:

- `pool-background` — the water still behind screen one. Converted to JPEG on
  the way in: it needs no alpha, and that took it from 1.74 MB to 0.21 MB.
- `upload-mark` — the stacked-document mark in the upload card, trimmed to its
  ink and generated at 1x/2x/3x for its 96pt frame.

`AppBackground` prefers a video loop over the still, so dropping
`background.mp4` into `HalftoneQR/Resources/` takes over with no code change
(`.mov` and `.m4v` also work). Either way it lays the design's `000000` at 20%
over the top, which is what keeps white type legible against the bright water.

**SN Pro** — drop `SNPro-Regular.otf`, `SNPro-Medium.otf`, `SNPro-Semibold.otf`
and `SNPro-Bold.otf` into `HalftoneQR/Resources/`. The project generates its
Info.plist and so cannot express a `UIAppFonts` array; instead the app registers
every font file it finds in its bundle at launch. Until the files exist, every
call falls back to the system face at the same size, weight and tracking, so
nothing reflows when they arrive.

> Resources are flattened into the bundle root, so two files anywhere under
> `HalftoneQR/` that share a filename will fail the build with "Multiple
> commands produce". The asset catalogue is exempt — it compiles to a single
> file — but loose resources are not. Keep their filenames unique.

## Building

Open `HalftoneQR.xcodeproj` and run. Deployment target iOS 18; no dependencies,
no package resolution.

The project uses Xcode 16+ **file-system-synchronized groups**, so files added to
`HalftoneQR/` are picked up without touching the project file. This requires
Xcode 16 or later; Liquid Glass additionally requires Xcode 26.

---

## Validation

`Tools/validation/` holds the harness used to verify the engine and derive every
tuned constant in `RenderConfig`. It is a faithful Python port of the Swift
encoder and planner, checked against `segno` (reference encoder) and
`zxing-cpp` (real decoder).

```bash
pip install segno zxing-cpp pillow numpy
cd Tools/validation
python3 validate_encoder.py   # matrix equality vs segno, across v1-v40
python3 roundtrip.py          # encode -> render -> decode, wide payload sweep
python3 finetune.py           # the centre-size / strength Pareto sweep
python3 shapes.py             # finder styles x cell shapes vs the decoder
python3 samples.py            # renders the sample sheet and the resolve GIF
python3 focus.py              # how light the centres can be drawn: they cannot
```

Results at time of writing:

- **1672/1672** round-trips decode correctly across payload lengths 1–2300, all
  four ECC levels and all eight masks.
- **496** matrices byte-identical to `segno` across v1–v40 when both use the same
  mode.
- **0** discrepancies in the ECC tables, cross-checked cell by cell.

This harness earned its keep: it caught two transcription errors in the
high-ECC block-count table (v8, and a one-position shift from v32 onward) that
would have made every symbol at those sizes silently undecodable.

Two deliberate differences from `segno` are documented in the code:

- `segno` appends a spurious zero byte when the bit stream is already
  byte-aligned (`8 - length % 8` without the outer `% 8`). ISO/IEC 18004 §7.4.10
  adds padding bits only when the stream does *not* end on a codeword boundary,
  which is what this implementation does. Both decode identically.
- The N3 penalty rule (false finder patterns) admits more than one reading of
  the specification. This implementation follows the run-history interpretation.
  Mask choice is driven primarily by artwork similarity in any case.
