(module asl-html/html
  :x [Node Attr el voidEl text frag attr flag cls classes id href src alt typeAttr nameAttr valueAttr rel target titleAttr lang role aria data style
      script styleSheet document escapeText escapeAttr render renderDocument voidTag?
      a abbr address article aside audio b bdi bdo blockquote body button canvas caption cite code colgroup dataEl datalist dd del details dfn dialog div dl dt em fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup html i iframe ins kbd label legend li main mapEl mark menu meter nav noscript objectEl ol optgroup option output p picture pre progress q rp rt ruby s samp search section select slot small span strong sub summary sup table tbody td template textarea tfoot th thead time title tr u ul varEl video area base br col embed hr img input link meta source track wbr svg g defs svgSymbol svgUse svgText tspan textPath linearGradient radialGradient stop clipPath svgMask svgPattern svgMarker svgFilter foreignObject svgDesc path circle ellipse line polygon polyline rect svgImage]
  :i [(asl-html/css :a c)])

(enum Attr (:c attrPair [(k String) (v String)] "name=value attribute, value escaped on render") (:c attrFlag [(k String)] "boolean attribute"))

(enum Node (:c elemNode [(tag String) (attrs (List Attr)) (kids (List Node))] "element") (:c textNode [(s String)] "text, escaped on render") (:c fragNode [(kids (List Node))] "children rendered in sequence with no element around them") (:c rawTextNode [(tag String) (attrs (List Attr)) (body String)] "script or style: body written as text with every </ written <\\/"))

fn el tag: String attrs: (List Attr) kids: (List Node) -> Node
  (elemNode tag attrs kids)

fn voidEl tag: String attrs: (List Attr) -> Node
  (elemNode tag attrs [])

fn text s: String -> Node
  (textNode s)

fn frag kids: (List Node) -> Node
  (fragNode kids)

fn attr k: String v: String -> Attr
  (attrPair k v)

fn flag k: String -> Attr
  (attrFlag k)

fn cls v: String -> Attr
  (attrPair "class" v)

fn classes names: (List String) -> Attr
  (attrPair "class" (stringJoin (filter (fn [(n String)] -> Bool (not (stringEmpty? n))) names) " "))

fn id v: String -> Attr
  (attrPair "id" v)

fn href v: String -> Attr
  (attrPair "href" v)

fn src v: String -> Attr
  (attrPair "src" v)

fn alt v: String -> Attr
  (attrPair "alt" v)

fn typeAttr v: String -> Attr
  (attrPair "type" v)

fn nameAttr v: String -> Attr
  (attrPair "name" v)

fn valueAttr v: String -> Attr
  (attrPair "value" v)

fn rel v: String -> Attr
  (attrPair "rel" v)

fn target v: String -> Attr
  (attrPair "target" v)

fn titleAttr v: String -> Attr
  (attrPair "title" v)

fn lang v: String -> Attr
  (attrPair "lang" v)

fn role v: String -> Attr
  (attrPair "role" v)

fn aria name: String v: String -> Attr
  (attrPair (str "aria-" name) v)

fn data name: String v: String -> Attr
  (attrPair (str "data-" name) v)

fn style decls: (List c/Decl) -> Attr
  (attrPair "style" (c/renderDecls decls))

fn script attrs: (List Attr) body: String -> Node
  (rawTextNode "script" attrs body)

fn styleSheet rules: (List c/Rule) -> Node
  (rawTextNode "style" [] (c/renderSheet rules))

fn document language: String headKids: (List Node) bodyAttrs: (List Attr) bodyKids: (List Node) -> Node
  (elemNode "html" [(attrPair "lang" language)] [(elemNode "head" [] headKids) (elemNode "body" bodyAttrs bodyKids)])

fn button attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "button" (if (listAny? (fn [(a Attr)] -> Bool (mt a ((attrPair k v) (= k "type")) ((attrFlag k) false))) attrs) attrs (cons (attrPair "type" "button") attrs)) kids)

fn svg attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "svg" (cons (attrPair "xmlns" "http://www.w3.org/2000/svg") attrs) kids)

fn a attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "a" attrs kids)

fn abbr attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "abbr" attrs kids)

fn address attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "address" attrs kids)

fn article attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "article" attrs kids)

fn aside attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "aside" attrs kids)

fn audio attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "audio" attrs kids)

fn b attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "b" attrs kids)

fn bdi attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "bdi" attrs kids)

fn bdo attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "bdo" attrs kids)

fn blockquote attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "blockquote" attrs kids)

fn body attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "body" attrs kids)


fn canvas attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "canvas" attrs kids)

fn caption attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "caption" attrs kids)

fn cite attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "cite" attrs kids)

fn code attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "code" attrs kids)

fn colgroup attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "colgroup" attrs kids)

fn dataEl attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "data" attrs kids)

fn datalist attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "datalist" attrs kids)

fn dd attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "dd" attrs kids)

fn del attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "del" attrs kids)

fn details attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "details" attrs kids)

fn dfn attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "dfn" attrs kids)

fn dialog attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "dialog" attrs kids)

fn div attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "div" attrs kids)

fn dl attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "dl" attrs kids)

fn dt attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "dt" attrs kids)

fn em attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "em" attrs kids)

fn fieldset attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "fieldset" attrs kids)

fn figcaption attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "figcaption" attrs kids)

fn figure attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "figure" attrs kids)

fn footer attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "footer" attrs kids)

fn form attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "form" attrs kids)

fn h1 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h1" attrs kids)

fn h2 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h2" attrs kids)

fn h3 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h3" attrs kids)

fn h4 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h4" attrs kids)

fn h5 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h5" attrs kids)

fn h6 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h6" attrs kids)

fn head attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "head" attrs kids)

fn header attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "header" attrs kids)

fn hgroup attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "hgroup" attrs kids)

fn html attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "html" attrs kids)

fn i attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "i" attrs kids)

fn iframe attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "iframe" attrs kids)

fn ins attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "ins" attrs kids)

fn kbd attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "kbd" attrs kids)

fn label attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "label" attrs kids)

fn legend attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "legend" attrs kids)

fn li attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "li" attrs kids)

fn main attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "main" attrs kids)

fn mapEl attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "map" attrs kids)

fn mark attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "mark" attrs kids)

fn menu attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "menu" attrs kids)

fn meter attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "meter" attrs kids)

fn nav attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "nav" attrs kids)

fn noscript attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "noscript" attrs kids)

fn objectEl attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "object" attrs kids)

fn ol attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "ol" attrs kids)

fn optgroup attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "optgroup" attrs kids)

fn option attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "option" attrs kids)

fn output attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "output" attrs kids)

fn p attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "p" attrs kids)

fn picture attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "picture" attrs kids)

fn pre attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "pre" attrs kids)

fn progress attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "progress" attrs kids)

fn q attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "q" attrs kids)

fn rp attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "rp" attrs kids)

fn rt attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "rt" attrs kids)

fn ruby attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "ruby" attrs kids)

fn s attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "s" attrs kids)

fn samp attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "samp" attrs kids)

fn search attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "search" attrs kids)

fn section attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "section" attrs kids)

fn select attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "select" attrs kids)

fn slot attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "slot" attrs kids)

fn small attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "small" attrs kids)

fn span attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "span" attrs kids)

fn strong attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "strong" attrs kids)

fn sub attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "sub" attrs kids)

fn summary attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "summary" attrs kids)

fn sup attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "sup" attrs kids)

fn table attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "table" attrs kids)

fn tbody attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "tbody" attrs kids)

fn td attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "td" attrs kids)

fn template attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "template" attrs kids)

fn textarea attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "textarea" attrs kids)

fn tfoot attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "tfoot" attrs kids)

fn th attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "th" attrs kids)

fn thead attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "thead" attrs kids)

fn time attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "time" attrs kids)

fn title attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "title" attrs kids)

fn tr attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "tr" attrs kids)

fn u attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "u" attrs kids)

fn ul attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "ul" attrs kids)

fn varEl attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "var" attrs kids)

fn video attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "video" attrs kids)

fn area attrs: (List Attr) -> Node
  (elemNode "area" attrs [])

fn base attrs: (List Attr) -> Node
  (elemNode "base" attrs [])

fn br attrs: (List Attr) -> Node
  (elemNode "br" attrs [])

fn col attrs: (List Attr) -> Node
  (elemNode "col" attrs [])

fn embed attrs: (List Attr) -> Node
  (elemNode "embed" attrs [])

fn hr attrs: (List Attr) -> Node
  (elemNode "hr" attrs [])

fn img attrs: (List Attr) -> Node
  (elemNode "img" attrs [])

fn input attrs: (List Attr) -> Node
  (elemNode "input" attrs [])

fn link attrs: (List Attr) -> Node
  (elemNode "link" attrs [])

fn meta attrs: (List Attr) -> Node
  (elemNode "meta" attrs [])

fn source attrs: (List Attr) -> Node
  (elemNode "source" attrs [])

fn track attrs: (List Attr) -> Node
  (elemNode "track" attrs [])

fn wbr attrs: (List Attr) -> Node
  (elemNode "wbr" attrs [])


fn g attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "g" attrs kids)

fn defs attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "defs" attrs kids)

fn svgSymbol attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "symbol" attrs kids)

fn svgUse attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "use" attrs kids)

fn svgText attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "text" attrs kids)

fn tspan attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "tspan" attrs kids)

fn textPath attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "textPath" attrs kids)

fn linearGradient attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "linearGradient" attrs kids)

fn radialGradient attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "radialGradient" attrs kids)

fn stop attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "stop" attrs kids)

fn clipPath attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "clipPath" attrs kids)

fn svgMask attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "mask" attrs kids)

fn svgPattern attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "pattern" attrs kids)

fn svgMarker attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "marker" attrs kids)

fn svgFilter attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "filter" attrs kids)

fn foreignObject attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "foreignObject" attrs kids)

fn svgDesc attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "desc" attrs kids)

fn path attrs: (List Attr) -> Node
  (elemNode "path" attrs [])

fn circle attrs: (List Attr) -> Node
  (elemNode "circle" attrs [])

fn ellipse attrs: (List Attr) -> Node
  (elemNode "ellipse" attrs [])

fn line attrs: (List Attr) -> Node
  (elemNode "line" attrs [])

fn polygon attrs: (List Attr) -> Node
  (elemNode "polygon" attrs [])

fn polyline attrs: (List Attr) -> Node
  (elemNode "polyline" attrs [])

fn rect attrs: (List Attr) -> Node
  (elemNode "rect" attrs [])

fn svgImage attrs: (List Attr) -> Node
  (elemNode "image" attrs [])

fn replaceIn s: String old: String new: String -> String
  (if (stringContains? s old) (stringReplace s old new) s)

fn escapeText s: String -> String
  (replaceIn (replaceIn (replaceIn s "&" "&amp;") "<" "&lt;") ">" "&gt;")

fn escapeAttr s: String -> String
  (replaceIn (escapeText s) "\"" "&quot;")

fn voidTag? tag: String -> Bool
  (listContains? ["area" "base" "br" "col" "embed" "hr" "img" "input" "link" "meta" "source" "track" "wbr" "path" "circle" "ellipse" "line" "polygon" "polyline" "rect" "image" "stop" "use"] tag)

fn attrOut acc: (List String) at: Attr -> (List String)
  (mt at
    ((attrFlag k) (cons k (cons " " acc)))
    ((attrPair k v) (cons "\"" (cons (escapeAttr v) (cons "=\"" (cons k (cons " " acc)))))))

fn openTag acc: (List String) tag: String attrs: (List Attr) -> (List String)
  (fold attrOut (cons tag (cons "<" acc)) attrs)

fn renderInto acc: (List String) n: Node -> (List String)
  (mt n
    ((textNode s) (cons (escapeText s) acc))
    ((fragNode kids) (fold renderInto acc kids))
    ((rawTextNode tag attrs body) (cons ">" (cons tag (cons "</" (cons (replaceIn body "</" "<\\/") (cons ">" (openTag acc tag attrs)))))))
    ((elemNode tag attrs kids)
      (let [(opened (openTag acc tag attrs))]
        (if (and (voidTag? tag) (listEmpty? kids))
          (cons (if (= tag "br") ">" "/>") opened)
          (cons ">" (cons tag (cons "</" (fold renderInto (cons ">" opened) kids))))))))

fn render n: Node -> String
  (stringJoin (listReverse (renderInto [] n)) "")

fn renderDocument root: Node -> String
  (str "<!doctype html>" (render root))
