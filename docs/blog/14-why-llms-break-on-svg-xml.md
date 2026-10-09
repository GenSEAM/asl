# Why LLMs Choke on SVG XML: Vector Graphics as Native S-Expressions
*By GenSEAM | September 2026*

When autonomous coding agents generate user interfaces, icons, architecture diagrams or vector illustrations, the industry default is prompting the LLM to emit raw SVG XML:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 600">
  <line x1="0" y1="300" x2="800" y2="300" stroke="#00f2ff" stroke-width="2" opacity="0.8"/>
  <rect x="120" y="140" width="160" height="5" fill="#050510"/>
  <!-- Repeat 40 times... -->
</svg>
```

On large drawings this runs into **the verbose delimiter blowup**: the model spends its output budget on repeated attribute names and closing tags, and a capped generation stops mid-element.

The harness keeps one small run of this in `harness/results/svg/compare/`: three stress prompts (a fox mascot, a synthwave scene, an isometric server stack) given to Gemma 31B (`gemma-4-31b-it`), once as raw SVG and once through ASN; the run's report, dated 2026-09-06, records a 1,000-token output limit. Checked on 2026-09-24 with `xmllint --noout`, two of the three raw SVG files (`synthwaveBaseTruncated.svg`, `isometricBaseTruncated.svg`) are not well-formed (one stops inside a `<path>` attribute, the other before its open groups close), while all three files produced through ASN parse. Three prompts are an anecdote, not a failure rate. That report (`harness/results/svgGemmaBaseline.asn`) also lists token counts, but it names no tokenizer and keeps only the SVG side, so we do not quote those counts here.

Vector graphics do not have to be authored as XML during agent inference. In AgentScript they are written as **ASN (AgentScript Notation)** S-expressions and rendered to SVG afterwards.

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

How much does it save? For the drawing above and its hand-written SVG equivalent (same elements and attributes, with `xmlns` and `viewBox`), tiktoken 0.12.0 counted 151 ASN tokens against 172 SVG tokens on `o200k_base` (12.2 percent fewer) and 151 against 171 on `cl100k_base` (11.7 percent), measured on 2026-09-24. That is one small drawing, not a corpus measurement. The larger gain is structural: a truncated ASN form is caught by counting parentheses, and there is no closing-tag name for the model to get wrong.

---

## 3. Rendering to SVG

Agents write ASN; browsers render SVG. Two renderers exist in the repository:

- `asl/packages/asl-vdom/src/asnSvg.asl` (`asnToSvg`), with 54 assertions in `asl/packages/asl-vdom/tests/asnSvgTest.asl`.
- `asl/packages/asl-transpile/src/svgTranspile.asl` (`asnToSvg`, `svgToAsn`), with 62 assertions in `asl/packages/asl-transpile/tests/svgTranspileTest.asl`.

On 2026-09-24 both suites passed under `./bin/asl test`, which runs the lenient asl-core engine. Neither loads on the strict stage-0 host yet: the host reports unbound names (`list-map`, `list-take`) and an import that names no declared module. There is no CLI command for the conversion; the renderers are library functions. We are building a host-clean renderer and a vector-graphics skill for coding agents on top of it; today the only skill shipped in `asl/skills` is `asl-toolbelt`.

---

## 4. Architectural Invariant

Do not let models drown in syntax boilerplate. S-expressions give autoregressive models one delimiter rule, whether they are generating code, API frames or vector graphics.

- Explore [The Agent Operational Circle](/blog/the-agent-operational-circle).
- Next Article: [Against Agent Framework Bloat: The Case for Radical Simplicity over Large Orchestrators](/blog/kill-80-percent-agent-code-bloat).
