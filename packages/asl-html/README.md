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

All three also compile with `asl-target-js` and pass under node with the same assertion counts.
