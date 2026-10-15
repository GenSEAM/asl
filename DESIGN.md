# DESIGN.md — the ASL design system

The site has one job: make the language legible. Everything below exists to keep four sections
from drifting into four private conventions.

## 1. The idea

Graphite monochrome at the accent's own hue. Hue is not decoration here — the only chromatic
element on the page is the fuchsia `signal` (335°), and it is spent on three things and nothing
else:

1. the one live state in a set (the current era, the active protocol),
2. the `$` in a shell line,
3. the numbered index on a section header.

Every neutral is that same 335°, held at six to twelve percent saturation — the greys are
derived from the accent, not picked beside it. That is what stops a saturated accent from
reading as a sticker applied to a grey page. What is out permanently is the *combination* that
marks a generated page: violet-to-cyan gradients, clipped-gradient headlines and neon glow. A
single flat accent is not that.

The mark is the chameleon: a single-stroke line drawing in `signal` (`web/site/app/mascot.asl`),
its tail the spiral of the old logo. It is typed SVG built in ASL, not an image file, so it takes
the theme's colours; the favicon is rendered from the same paths.

**The page sells the outcome, not the syntax.** A visitor is buying what the language removes —
repair loops, ambiguous structure, a program that means something different on the next runtime —
not a look at its grammar. Sections state the problem and what it costs, then what the language
does about it. Source listings belong in the docs; the public surface carries at most a shell
line.

## 2. Tokens

`web/site/app/theme.asl` holds the whole palette as one ASL table, `palette`: every colour role
with its dark and its light value. The stylesheet is generated from it, so the two themes cannot
drift apart: `:root` carries the dark values, `prefers-color-scheme: light` and
`:root[data-theme=light]` the light ones. **Rules name a role (`var(--ink)`) and never a hex.**
A colour written anywhere but `palette` is the bug.

| Role | Use |
|---|---|
| `ground` / `sunken` | Page canvas. Alternate them to band sections apart. |
| `surface` | A panel sitting above the canvas. |
| `inset` | A well recessed into a surface — code blocks, nested fields. |
| `line` / `line-strong` | Hairline; `line-strong` for anything bounding a control. |
| `ink` / `ink-2` / `ink-3` | Primary, secondary, meta. Never pure black or pure white. |
| `signal` | The fuchsia. See §1 for the three places it is allowed. |

Every ink-on-ground pairing must hold 4.5:1, `line-strong` 3:1, and each layer must stay
separated from the next. A palette change re-checks those pairings before it lands.

## 3. Scales

Every value below is a rule in `theme.asl`. A one-off value inline on an element means the
scale was missing a step: add the step instead. Elements carry classes, never `style`.

- **Type**: `micro` · `meta` · `code` · `body` · `brand` · `lead` · `h3` · `h2` · `display`.
  `h2` and `display` are `clamp()`, so there is no responsive override ladder.
- **Radius**: `2xl` (16px) for panels, `full` for pills and buttons. That is the entire scale.
- **Elevation**: `e1`–`e4`, each with blur = 2 × offset, so every layer reads at one light source.
- **Padding on a capsule**: `Px = 2 × Py` (`px-7 py-3.5`, `px-3 py-1.5`).
- **Section rhythm**: `py-28 sm:py-36`, set by `<Section>`. Sections do not set their own.

## 4. Components

The site is an ASL program (`web/site`). Markup is typed (`ui/html.asl`: one constructor per
element, every text escaped by the serializer), so no source file holds HTML in a string.
`app/layout.asl` is the exposed surface; pages are assembled from it and nothing else.

- `document` — head, top bar, main, footer for a route.
- `sectionHead` — numbered eyebrow, title, lead.
- `eyebrow` — the numbered index rule.
- `markNode` — the chameleon at top-bar size (`mascot/chameleon`).
- `copyButton` — a button wired to a message, never to a script.

Behaviour lives in `app/update.asl`: a pure `step` from a message and the model to the next model
and the DOM operations to apply. `web/bridge/boot.js` only applies those operations; a decision
written there instead of in `step` is the bug.

A primitive with no callers gets deleted, not kept for later.

## 5. Rules that are not negotiable

- **Everything visible at once.** No tabs, no accordions, no filters gating content the reader
  came for. If a section only makes sense after a click, the section is wrong.
- **Every number on the page must be traceable to a gate in `ROADMAP.md`.** Benchmark figures
  with no measurement behind them are not a design choice, they are a false claim.
- **One focus treatment** (`:focus-visible` in `theme.asl`) for the whole product.
- **`prefers-reduced-motion` is honoured globally.**
- **No decorative bitmaps, no glow.** A photographic wash reads as haze on a light ground, and a
  blurred accent orb reads as a stain on it. Atmosphere comes from layering and the dot grid.
- **Nothing animates perpetually.** No `animate-pulse` on a status dot, no spinner that is not
  reporting real progress.
