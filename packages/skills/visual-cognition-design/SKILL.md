# Skill: Visual Cognition & Agentic Design System (VC-DS)
> Formal specification for reproducible, high-end editorial and Apple-grade interfaces engineered for both human perception and autonomous AI agent comprehension.

## 1. Core Axiom: Dual-Plane Architecture
Every interface must be designed on two distinct planes:
1. **The Human Visual Plane (Sensory & Visceral)**:
   - Evaluated by human eye in `<50ms` (Don Norman's Visceral Layer).
   - Characterized by monolithic editorial typography, negative optical tracking, physical materiality (frosted obsidian glass, titanium edges, optical caustics), and tactile micro-physics.
2. **The Agent Semantic Plane (Machine Substrate)**:
   - Consumed by LLMs, browser agents, and search bots in `1 single pass`.
   - Characterized by `llms.txt`, `llms-full.txt`, JSON-LD schemas (`schema.org/SoftwareApplication`), and structured S-expression wire frames (`asl/1.0`).

---

## 2. Mathematical Design Rules & Optical Physics
- **Negative Optical Tracking (Typographic Cohesion)**:
  - Display titles ($72\text{px}+$): `tracking-[-0.045em]` to `tracking-[-0.055em]`, `leading-[0.96]`.
  - Section headers ($36\text{px}-48\text{px}$): `tracking-[-0.035em]`.
  - Monospaced code & metadata ($11\text{px}-14\text{px}$): `tracking-[0.02em]`.
- **Spatial Padding Law**:
  - Capsules & Buttons: $P_x = 2 \times P_y$ (e.g. `px-7 py-3.5`).
  - Section Rhythm: `py-28` to `py-36` with generous negative space.
- **Glass & Elevation Physics**:
  - Base ground: Deep obsidian `#030508` to `#06080d`.
  - Elevated glass: `bg-white/[0.02]` to `bg-white/[0.04]` with `backdrop-blur-2xl` and `border-white/[0.08]`.
  - Specular edge: 1px inner border with top-oriented ambient light reflection.

---

## 3. Standard Component Archetypes

### Archetype A: `FloatingCapsuleHeader` (Dynamic Island)
- **Role**: Minimalist, floating centered navigation capsule that occupies <5% of screen height.
- **Structure**:
  ```tsx
  <div className="fixed top-4 left-0 right-0 z-50 flex justify-center px-4 pointer-events-none">
    <header className="pointer-events-auto max-w-4xl w-full rounded-full border border-white/[0.12] bg-[#06080d]/80 backdrop-blur-2xl px-6 h-14 flex items-center justify-between shadow-2xl">
      {/* Brand + Capsule Links + Action Pill */}
    </header>
  </div>
  ```

### Archetype B: `AsymmetricHeroCanvas`
- **Role**: Hero presentation uniting text on the left with a borderless 3D artifact on the right.
- **Rules**:
  - No enclosing box or rectangular card borders around the 3D artifact.
  - Floating frosted glass HUD chips orbit the artifact naturally in 3D space.
  - Terminal installer is embedded inline with text flow as a frosted pill.

### Archetype C: `EvolutionaryTimeline`
- **Role**: Chronological narrative contrasting previous fragile paradigms with the modern agentic era.
- **Structure**: Vertical border line with pulsing glowing active node for 2026+ AgP.

### Archetype D: `ShockAndAweStream`
- **Role**: Live A2A wire protocol stream demonstrating instant discovery probe, query, response, and real-time telemetry meters without interactive tabs.

---

## 4. Reproducibility Checklist for Autonomous Agents
When an agent builds or refactors a page using this skill, verify:
- [ ] No generic purple gradients or template bootstrap cards.
- [ ] Display titles use negative optical tracking (`tracking-[-0.045em]`).
- [ ] Navigation is housed in a floating frosted capsule.
- [ ] 3D hero assets float seamlessly without enclosing card boxes.
- [ ] Dual-plane metadata (`llms.txt`, JSON-LD schema) is verified.
- [ ] All gates and typechecks pass (`npm run build:web`).
