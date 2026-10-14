# asl-html

Typed HTML and CSS for AgentSlang. Pages are values: a tree of `Node`s and a list of css
`Rule`s, rendered to text at the edge. Nothing in a program that uses this package holds markup
in a string, and the serializer escapes everything it writes. aslang.dev is built with it.

```asl
(module demo/page :x [page] :i [(asl-html/html :a h) (asl-html/css :a c)])

fn page title: String -> String
  (h/renderDocument
    (h/document "en"
      [(h/meta [(h/attr "charset" "utf-8")]) (h/title [] [(h/text title)])
       (h/styleSheet [(c/rule "h1" [(c/decl "color" (c/cssVar "ink"))])])]
      []
      [(h/main [] [(h/h1 [] [(h/text title)])])]))
```

## Modules

- `asl-html/html`: `Node`, `Attr`; `el`, `voidEl`, `text`, `frag`; one constructor per HTML5
  element and the common SVG elements (prelude clashes are renamed: `mapEl`, `varEl`,
  `objectEl`, `dataEl`, `svgText`, `svgFilter`, `svgMask`, `svgUse`, ...); attribute helpers
  (`cls`, `classes`, `id`, `href`, `aria`, `data`, `style` from typed declarations, ...);
  `script` and `styleSheet`; `document`; `render`, `renderDocument`.
- `asl-html/css`: `Decl` and `Rule`; `rule`, `ruleFor`, `media`, `supports`, `layer`,
  `layerOrder`, `container`, `keyframes`, `fontFace`, `importUrl`, `atRule`; value helpers;
  `renderSheet` (minified) and `renderSheetPretty`.
- `asl-html/markdown`: `blocks` and `inline`, the Markdown subset to `Node`s.
- `asl-html/svg`: typed drawing for ASL programs: a path builder (`moveTo`, `lineTo`, `curveTo`,
  `arcTo`, `close`, ...), shapes with numeric geometry (`canvas`, `rectAt`, `circleAt`,
  `polygonOf`, `textAt`, ...), transforms, paint, gradients, and `renderSvg` for a standalone file.
- `asl-html/asnSvg`: ASN drawings to SVG, for agents that write data rather than programs.

## SVG from ASN

```asn
(:svg :w 240 :h 80
  (:rc :x 0 :y 0 :w 240 :h 80 :rx 16 :f "#c2185b")
  (:circ :cx 40 :cy 40 :r 18 :f "none" :s "#fff" :sw 3)
  (:txt :x 72 :y 47 :sz 20 :fontFamily "system-ui" :f "#fff" "build passing"))
```

```sh
IN=badge.asn OUT=badge.svg asl/host/out/asl-host run asl/packages/asl-html/src/svgCli.asl
```

Elements and attributes are keywords; `rc circ el ln pl poly p txt group` and `w h v f s sw op sz t
anchor` are short aliases, and camelCase attributes become kebab-case. An unknown element, a
misspelled attribute or text outside a text element is an error that names its place in the
drawing (`svg[0] > rect[1]: unknown attribute :fil`), so an agent can fix it in one turn.

## Pages and stylesheets from ASN, and the toolbelt

`asl-html/asnHtml` and `asl-html/asnCss` do for pages and stylesheets what `asnSvg` does for
drawings:

```asn
(:html :lang "en"
  (:head (:title "Status") (:style (:rule "h1" :color "#c2185b" :fontSize "2rem")))
  (:body (:h1 "All green") (:svg :w 20 :h 20 (:circ :cx 10 :cy 10 :r 8 :f "#2e7d32"))))
```

An agent converts any of the three with the toolbelt; `:out` stages the file like `(:write)`, so
it shows in `(:diff)` and lands with `(:flush)`:

```sh
asl '(:target :name html :file "status.asn" :out "status.html")'
asl '(:target :name css :file "site.asn")'          # result returned in :output
asl '(:target :name ts :file "src/app.asl")'        # asl-target-js declarations
```

## Guarantees

- Text and attribute values are escaped; raw HTML in text stays text.
- `script` and `style` bodies are written with every `</` as `<\/`, so they cannot close their
  element.
- `button` is `type="button"` unless the caller names a type.
- Void elements (HTML and SVG) with no children self-close.

## Tests (asl-host, 2026-10-14)

| Suite | Result |
|---|---|
| `tests/htmlTest.asl` | 15 pass |
| `tests/cssTest.asl` | 4 pass |
| `tests/markdownTest.asl` | 9 pass |
| `tests/svgTest.asl` | 14 pass |
| `tests/asnTest.asl` | 7 pass |

All four also compile with `asl-target-js` and pass under node with the same assertion counts.
