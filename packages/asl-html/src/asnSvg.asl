(module asl-html/asnSvg
  :x [elementNames attributeNames elementName attributeName drawingToNode asnToSvg]
  :i [(asl-parser/reader :a rd) (asl-html/html :a h) (asl-html/asn :a a)])

fn elementNames -> (List String)
  ["svg" "g" "defs" "symbol" "use" "path" "rect" "circle" "ellipse" "line" "polyline" "polygon" "text" "tspan" "textPath" "title" "desc" "a" "image"
   "linearGradient" "radialGradient" "stop" "clipPath" "mask" "pattern" "marker" "filter"
   "feGaussianBlur" "feOffset" "feBlend" "feColorMatrix" "feFlood" "feComposite" "feMerge" "feMergeNode" "feDropShadow"]

fn elementAliases -> (List (Pair String String))
  [(pair "rc" "rect") (pair "circ" "circle") (pair "el" "ellipse") (pair "ln" "line") (pair "pl" "polyline") (pair "poly" "polygon") (pair "p" "path") (pair "txt" "text") (pair "group" "g")]

fn attributeAliases -> (List (Pair String String))
  [(pair "w" "width") (pair "h" "height") (pair "v" "viewBox") (pair "f" "fill") (pair "s" "stroke") (pair "sw" "stroke-width") (pair "op" "opacity")
   (pair "sz" "font-size") (pair "size" "font-size") (pair "t" "transform") (pair "anchor" "text-anchor") (pair "color" "stop-color")]

fn keepCamel -> (List String)
  ["viewBox" "preserveAspectRatio" "gradientUnits" "gradientTransform" "patternUnits" "patternContentUnits" "patternTransform" "markerWidth" "markerHeight" "markerUnits"
   "refX" "refY" "pathLength" "stdDeviation" "textLength" "lengthAdjust" "clipPathUnits" "maskUnits" "maskContentUnits" "filterUnits" "primitiveUnits" "startOffset" "spreadMethod" "baseFrequency" "numOctaves" "dx" "dy"]

fn attributeNames -> (List String)
  (listAppend (keepCamel)
    ["id" "class" "style" "x" "y" "x1" "y1" "x2" "y2" "cx" "cy" "r" "rx" "ry" "fx" "fy" "width" "height" "d" "points" "transform" "href" "offset" "orient" "in" "in2" "result" "mode" "values" "type" "operator" "k1" "k2" "k3" "k4" "rotate" "xmlns"
     "fill" "fill-opacity" "fill-rule" "stroke" "stroke-width" "stroke-opacity" "stroke-linecap" "stroke-linejoin" "stroke-dasharray" "stroke-dashoffset" "stroke-miterlimit"
     "opacity" "color" "stop-color" "stop-opacity" "flood-color" "flood-opacity" "font-family" "font-size" "font-weight" "font-style" "letter-spacing" "text-anchor" "dominant-baseline" "text-decoration"
     "clip-path" "clip-rule" "mask" "filter" "marker-start" "marker-mid" "marker-end" "visibility" "display" "vector-effect" "shape-rendering" "role" "aria-label" "aria-hidden"])

fn elementName name: String -> String
  (optionOr (a/lookup (elementAliases) name) name)

fn attributeName name: String -> String
  (mt (a/lookup (attributeAliases) name)
    ((some full) full)
    ((none) (if (listContains? (keepCamel) name) name (a/kebab name))))

fn textHolder? tag: String -> Bool
  (listContains? ["text" "tspan" "textPath" "title" "desc"] tag)

fn known? name: String -> Bool
  (or (listContains? (attributeNames) name) (or (stringStartsWith? name "data-") (stringStartsWith? name "aria-")))

(schema Built (:f attrs (List h/Attr)) (:f kids (List h/Node)) (:f errors (List String)))

fn addViewBox tag: String attrs: (List h/Attr) -> (List h/Attr)
  (let [(names (map (fn [(a h/Attr)] -> String (mt a ((h/attrPair k v) k) ((h/attrFlag k) k))) attrs))
        (valueOf (fn [(k String)] -> String (fold (fn [(acc String) (a h/Attr)] -> String (mt a ((h/attrPair n v) (if (= n k) v acc)) ((h/attrFlag n) acc))) "" attrs)))]
    (if (and (= tag "svg") (and (not (listContains? names "viewBox")) (and (listContains? names "width") (listContains? names "height"))))
      (listAppend attrs [(h/attr "viewBox" (str "0 0 " (valueOf "width") " " (valueOf "height")))])
      attrs))

fn buildItems tag: String where: String items: (List rd/SExpr) acc: Built -> Built
  (mt (listHead items)
    ((none) acc)
    ((some item)
      (let [(rest (listDrop items 1))]
        (mt item
          ((rd/sexprAtom a)
            (if (a/keywordAtom? a)
              (let [(name (attributeName (a/bare a)))]
                (mt (mt (listHead rest) ((some x) (a/atomOf x)) ((none) (none)))
                  ((none) (buildItems tag where (listDrop rest 1) (with acc :errors (listAppend acc.errors [(str where ": attribute :" (a/bare a) " needs a single value")]))))
                  ((some v)
                    (if (known? name)
                      (buildItems tag where (listDrop rest 1) (with acc :attrs (listAppend acc.attrs [(h/attr name (a/valueText v))])))
                      (buildItems tag where (listDrop rest 1) (with acc :errors (listAppend acc.errors [(str where ": unknown attribute :" (a/bare a) " (as " name ")")])))))))
              (if (and (a/stringAtom? a) (textHolder? tag))
                (buildItems tag where rest (with acc :kids (listAppend acc.kids [(h/text (a/unquote a))])))
                (buildItems tag where rest (with acc :errors (listAppend acc.errors [(str where ": stray " a "; text belongs in text, tspan, textPath, title or desc")]))))))
          (_
            (let [(child (buildElement (str where " > ") (listLength acc.kids) item))]
              (buildItems tag where rest (with acc :kids (listAppend acc.kids [(pairFirst child)]) :errors (listAppend acc.errors (pairSecond child))))))))))

fn buildElement parent: String index: Int64 e: rd/SExpr -> (Pair h/Node (List String))
  (mt e
    ((rd/sexprList items)
      (let [(head (optionOr (a/atomOf (optionOr (listHead items) (rd/makeAtom ""))) ""))
            (tag (elementName (a/bare head)))
            (where (str parent tag "[" (stringFromInt64 index) "]"))]
        (if (and (a/keywordAtom? head) (listContains? (elementNames) tag))
          (let [(built (buildItems tag where (listDrop items 1) (Built :attrs [] :kids [] :errors [])))]
            (pair (if (= tag "svg") (h/svg (addViewBox tag built.attrs) built.kids) (h/el tag built.attrs built.kids)) built.errors))
          (pair (h/frag []) [(str where ": unknown element " head "; known: " (stringJoin (elementNames) " ") " and the aliases rc circ el ln pl poly p txt group")]))))
    (_ (pair (h/frag []) [(str parent "an element must be a list like (:rect :x 0 ...)")])))

fn drawingToNode source: String -> (Result h/Node (List String))
  (let [(root (rd/parseSexpr source))
        (head (mt root ((rd/sexprList items) (optionOr (a/atomOf (optionOr (listHead items) (rd/makeAtom ""))) "")) (_ "")))]
    (if (not (= (elementName (a/bare head)) "svg"))
      (err ["the drawing must be one (:svg ...) form"])
      (let [(built (buildElement "" 0 root))]
        (if (listEmpty? (pairSecond built)) (ok (pairFirst built)) (err (pairSecond built))))))

fn asnToSvg source: String -> (Result String (List String))
  (mt (drawingToNode source)
    ((ok node) (ok (str "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" (h/render node) "\n")))
    ((err es) (err es)))
