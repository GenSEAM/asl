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

The mark is `( • )` — two parentheses around one evaluated core, the smallest well-formed
S-expression.

**The page sells the outcome, not the syntax.** A visitor is buying what the language removes —
repair loops, ambiguous structure, a program that means something different on the next runtime —
not a look at its grammar. Sections state the problem and what it costs, then what the language
does about it. Source listings belong in the docs; the public surface carries at most a shell
line.

## 2. Tokens

`web/src/index.css` holds the whole palette as raw RGB triplets on `:root` and `.dark`;
`tailwind.config.js` maps each to a Tailwind colour with `<alpha-value>` support. **Components
name a role and never write `dark:`.** Adding a `dark:` variant to a component is the bug.

| Role | Use |
|---|---|
| `ground` / `sunken` | Page canvas. Alternate them to band sections apart. |
| `surface` | A panel sitting above the canvas. |
| `inset` | A well recessed into a surface — code blocks, nested fields. |
| `line` / `line-strong` | Hairline; `line-strong` for anything bounding a control. |
| `ink` / `ink-2` / `ink-3` | Primary, secondary, meta. Never pure black or pure white. |
| `signal` | The fuchsia. See §1 for the three places it is allowed. |

`npm run check:tokens` (from `web/`) must report **0 failing pairings**: every ink-on-ground
combination at 4.5:1, `line-strong` at 3:1, and each layer separated by |ΔL\*| ≥ 2. It runs in
the pre-commit chain (`tools/hooks/pre-commit`, installed to `.git/hooks/`) as gate 5 of 6 — a
palette change that skips it is how a red one lands.

## 3. Scales

Every value below is a token. An arbitrary Tailwind value (`text-[2rem]`, `rounded-[2rem]`) means
the scale was missing a step — add the step instead.

- **Type**: `micro` · `meta` · `code` · `body` · `brand` · `lead` · `h3` · `h2` · `display`.
  `h2` and `display` are `clamp()`, so there is no responsive override ladder.
- **Radius**: `2xl` (16px) for panels, `full` for pills and buttons. That is the entire scale.
- **Elevation**: `e1`–`e4`, each with blur = 2 × offset, so every layer reads at one light source.
- **Padding on a capsule**: `Px = 2 × Py` (`px-7 py-3.5`, `px-3 py-1.5`).
- **Section rhythm**: `py-28 sm:py-36`, set by `<Section>`. Sections do not set their own.

## 4. Components

`web/src/components/ui/` is the exposed surface. Sections are assembled from it and nothing else.

- `Section` — vertical rhythm, container width, `ground` or `sunken` band.
- `SectionHeader` — numbered eyebrow, title, lead. `align` is the only rhythm control a section
  gets; alternating left/centre is what stops stacked sections reading as one template.
- `Eyebrow` — the numbered index rule.
- `Logo` / `Wordmark`.

A primitive with no callers gets deleted, not kept for later.

## 5. Rules that are not negotiable

- **Everything visible at once.** No tabs, no accordions, no filters gating content the reader
  came for. If a section only makes sense after a click, the section is wrong.
- **Every number on the page must be traceable to a gate in `ROADMAP.md`.** Benchmark figures
  with no measurement behind them are not a design choice, they are a false claim.
- **One focus treatment** (`:focus-visible` in `index.css`) for the whole product.
- **`prefers-reduced-motion` is honoured globally.**
- **No decorative bitmaps, no glow.** A photographic wash reads as haze on a light ground, and a
  blurred accent orb reads as a stain on it. Atmosphere comes from layering and the dot grid.
- **Nothing animates perpetually.** No `animate-pulse` on a status dot, no spinner that is not
  reporting real progress.
