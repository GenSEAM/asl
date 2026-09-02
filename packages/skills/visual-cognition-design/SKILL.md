---
name: visual-cognition-design
description: The ASL design system — cool graphite monochrome, one purple signal, token-only components, everything visible without interaction. Use when building or reviewing any ASL surface.
---

# Visual cognition design

`DESIGN.md` at the repository root is normative. This file is the working checklist.

## Before writing a component

1. Read the roles in `web/src/index.css`. Use `ground`, `sunken`, `surface`, `inset`, `line`,
   `line-strong`, `ink`, `ink-2`, `ink-3`, `signal`.
2. Reach for `web/src/components/ui/primitives.tsx` first. A section that needs something the
   primitives do not have either adds a primitive or does not need it.

## Checklist

- [ ] No `dark:` variant anywhere. The theme rebinds tokens; components do not branch.
- [ ] No arbitrary values — `text-[…]`, `rounded-[…]`, `p-[…]`. If a step is missing, add it to
      `tailwind.config.js`.
- [ ] Radius is `2xl` or `full`. Nothing else.
- [ ] `signal` appears only on the one live state in a set, on `$`, and on a section index.
- [ ] The section argues from the problem and the outcome, not from a source listing.
- [ ] The accent is flat. No gradient-filled text, no second accent hue, no blurred glow orb,
      no glassmorphism, no photographic background wash, nothing animating perpetually.
- [ ] Section headers alternate `align` so consecutive sections do not share a silhouette.
- [ ] Every claim on screen traces to a gate in `ROADMAP.md`.
- [ ] Content is readable without clicking. No tab strip, no accordion, no filter.
- [ ] Interactive elements are real `<button>` / `<a>`; state changes carry `aria-expanded` or
      `aria-current`; lists are lists.
- [ ] Contrast check reports 0 failing pairings.
- [ ] `npx tsc --noEmit && npm run build` from `web/` is clean.

## Anti-patterns, named

Two accent hues in one system. A clipped-gradient headline. A stock render of a
glowing sphere. Five sections with the same centred badge-title-paragraph block. A card whose
fill differs from its ground by less than one perceptual step, so only the border reads. A number
on the page that nothing in the repository measures.
