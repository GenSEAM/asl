# Vector Graphics as Checked S-Expressions: How ASL Builds SVG and HTML Without XML Boilerplate
*By GenSEAM | September 2026*

In AgentSlang (ASL), user interfaces, icons and vector diagrams are written in the same checked S-expression language as the rest of the codebase. Using `asl-html` and ASN vector forms, an agent composes drawings with functions, loops and typed helpers, the checker verifies bracket balance and argument counts before anything runs, and the renderer emits escaped HTML5 and SVG.

By contrast, prompting a model to stream raw SVG XML forces it to spend output budget on repetitive attribute quotes and closing tags:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600">
  <line x1="0" y1="300" x2="800" y2="300" stroke="#00f2ff" stroke-width="2" opacity="0.8"/>
  <rect x="120" y="140" width="160" height="5" fill="#050510"/>
  <!-- Repeat 40 times... -->
</svg>
```

On complex drawings, raw XML hits **verbose delimiter blowup** and truncates mid-tag. Authoring graphics as ASL forms keeps the source compact, programmable and statically checked.

---

## 1. The Anatomy of the SVG XML Failure Mode

Why do LLMs struggle with raw SVG XML?

1. **Repeated attribute keys:** every primitive repeats its attribute names (`x1="..."`, `y1="..."`, `stroke-width="..."`, `fill="..."`), and every one of them is paid for in output tokens.
2. **Closing tags and context exhaustion:** in large compositions (perspective grids, layered gradients, stacked 3D diagrams) the markup outgrows a single-turn output budget and the document ends unclosed.
3. **Mismatched containers:** models mix up container tags (`<g>`, `</g>`, `<defs>`, `</defs>`), producing documents that fail to parse.

---

## 2. ASN Vector Graphics

In ASN each element is one balanced form with short keyword attributes. This is the shape the ASN-to-SVG renderer in `asl/packages/asl-vdom/src/asnSvg.asl` is tested against:

```asn
(:svg :w 400 :h 400
  (:circ :cx 200 :cy 180 :r 80 :f "#ff00cc")
  (:rc :x 120 :y 140 :w 160 :h 5 :f "#050510")
  (:rc :x 120 :y 150 :w 160 :h 8 :f "#050510")
  (:ln :x1 0 :y1 300 :x2 400 :y2 300 :s "#00ffff" :sw 2)
  (:ln :x1 200 :y1 300 :x2 200 :y2 400 :s "#00ffff" :sw 2))
```

- **Tags:** `:rc` (rect), `:circ` (circle), `:ln` (line), `:poly` (polygon), `:p` (path), `:txt` (text), `:g` (group).
- **Attributes:** `:f` (fill), `:s` (stroke), `:sw` (stroke-width), `:w`, `:h`, `:v` (viewBox), `:tr` (transform, the only attribute a group carries today).
- **One closing delimiter:** every element closes with `)`. There is no closing tag to misspell, and an unbalanced form is caught by a balance check before rendering.

How many tokens does it save? We have no tracked measurement of ASN against SVG, so we quote no figure; on a small drawing like this one, where SVG's attribute names are already short, the difference is not the point. The gain we care about is structural: a truncated ASN form is caught by counting parentheses, and there is no closing-tag name for the model to get wrong.

---

## 3. Rendering to SVG

Agents write ASN; browsers render SVG. Two renderers exist in the repository:

- `asl/packages/asl-vdom/src/asnSvg.asl` (`asnToSvg`), tested by `asl/packages/asl-vdom/tests/asnSvgTest.asl`.
- `asl/packages/asl-transpile/src/svgTranspile.asl` (`asnToSvg`, `svgToAsn`), tested by `asl/packages/asl-transpile/tests/svgTranspileTest.asl`.

Both suites pass: `asl test` reports 27 assertions executed for the first and 62 for the second. There is no CLI command for the conversion; the renderers are library functions. A vector-graphics skill for coding agents is a plan; today the only skill shipped in `asl/skills` is `asl-toolbelt`.

---

## 4. Architectural Invariant

Do not let models drown in syntax boilerplate. S-expressions give autoregressive models one delimiter rule, whether they are generating code, API frames or vector graphics.

- Explore [The Agent Operational Circle](/blog/the-agent-operational-circle).
- Next Article: [Against Agent Framework Bloat: The Case for Radical Simplicity over Large Orchestrators](/blog/against-agent-framework-bloat).
