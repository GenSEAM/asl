(module asl-html/asnHtml
  :x [elementNames attributeName pageToNode asnToHtml]
  :i [(asl-parser/reader :a rd) (asl-html/html :a h) (asl-html/asn :a a) (asl-html/asnCss :a css) (asl-html/asnSvg :a svg)])

fn elementNames -> (List String)
  ["html" "head" "body" "title" "meta" "link" "base" "style" "script" "noscript"
   "header" "nav" "main" "section" "article" "aside" "footer" "address" "search" "hgroup" "h1" "h2" "h3" "h4" "h5" "h6"
   "div" "p" "span" "a" "em" "strong" "small" "s" "cite" "q" "dfn" "abbr" "data" "time" "code" "var" "samp" "kbd" "sub" "sup" "i" "b" "u" "mark" "ruby" "rt" "rp" "bdi" "bdo" "br" "wbr" "ins" "del"
   "ul" "ol" "li" "dl" "dt" "dd" "menu" "figure" "figcaption" "blockquote" "pre" "hr"
   "img" "picture" "source" "video" "audio" "track" "iframe" "embed" "object" "canvas" "map" "area"
   "table" "caption" "colgroup" "col" "thead" "tbody" "tfoot" "tr" "th" "td"
   "form" "label" "input" "button" "select" "datalist" "optgroup" "option" "textarea" "output" "progress" "meter" "fieldset" "legend"
   "details" "summary" "dialog" "template" "slot"]

fn globalAttributes -> (List String)
  ["id" "class" "style" "title" "lang" "dir" "hidden" "tabindex" "accesskey" "draggable" "spellcheck" "translate" "contenteditable" "inert" "popover" "role" "slot" "part" "inputmode" "enterkeyhint" "autocapitalize" "autofocus" "nonce" "is" "itemprop" "itemscope" "itemtype" "itemid" "itemref"]

fn elementAttributes -> (List String)
  ["href" "target" "rel" "download" "hreflang" "type" "media" "referrerpolicy" "ping" "src" "srcset" "sizes" "alt" "width" "height" "loading" "decoding" "crossorigin" "usemap" "ismap" "fetchpriority"
   "charset" "name" "content" "http-equiv" "property" "as" "integrity" "async" "defer" "nomodule"
   "controls" "autoplay" "loop" "muted" "playsinline" "poster" "preload" "kind" "srclang" "label" "default" "allow" "allowfullscreen" "sandbox" "srcdoc" "data"
   "colspan" "rowspan" "headers" "scope" "span" "abbr"
   "action" "method" "enctype" "novalidate" "autocomplete" "for" "form" "value" "placeholder" "required" "disabled" "readonly" "checked" "selected" "multiple" "min" "max" "step" "minlength" "maxlength" "pattern" "size" "list" "accept" "capture" "rows" "cols" "wrap" "formaction" "formmethod" "formnovalidate" "formtarget" "low" "high" "optimum"
   "open" "datetime" "cite" "start" "reversed" "coords" "shape" "popovertarget" "popovertargetaction" "command" "commandfor"]

fn booleanAttributes -> (List String)
  ["hidden" "inert" "autofocus" "async" "defer" "nomodule" "controls" "autoplay" "loop" "muted" "playsinline" "default" "allowfullscreen" "ismap" "novalidate" "required" "disabled" "readonly" "checked" "selected" "multiple" "formnovalidate" "open" "reversed" "itemscope"]

fn attributeAliases -> (List (Pair String String))
  [(pair "cls" "class") (pair "className" "class") (pair "htmlFor" "for") (pair "httpEquiv" "http-equiv")]

fn attributeName name: String -> String
  (optionOr (a/lookup (attributeAliases) name) (a/kebab name))

fn known? name: String -> Bool
  (or (listContains? (globalAttributes) name) (or (listContains? (elementAttributes) name) (or (stringStartsWith? name "data-") (stringStartsWith? name "aria-"))))

(schema Built (:f attrs (List h/Attr)) (:f kids (List h/Node)) (:f errors (List String)))

fn addError acc: Built message: String -> Built
  (with acc :errors (listAppend acc.errors [message]))

fn attrFor name: String value: String -> (Option h/Attr)
  (cond
    ((listContains? (booleanAttributes) name) (cond ((= value "true") (some (h/flag name))) ((= value "false") (none)) (else (some (h/attr name value)))))
    (else (some (h/attr name value))))

fn buildItems tag: String where: String items: (List rd/SExpr) acc: Built -> Built
  (mt (listHead items)
    ((none) acc)
    ((some item)
      (let [(rest (listDrop items 1))]
        (mt item
          ((rd/sexprAtom v)
            (cond
              ((a/keywordAtom? v)
                (let [(name (attributeName (a/bare v)))]
                  (mt (mt (listHead rest) ((some x) (a/atomOf x)) ((none) (none)))
                    ((none) (buildItems tag where (listDrop rest 1) (addError acc (str where ": attribute :" (a/bare v) " needs a single value"))))
                    ((some value)
                      (if (known? name)
                        (buildItems tag where (listDrop rest 1) (mt (attrFor name (a/valueText value)) ((some at) (with acc :attrs (listAppend acc.attrs [at]))) ((none) acc)))
                        (buildItems tag where (listDrop rest 1) (addError acc (str where ": unknown attribute :" (a/bare v) " (as " name ")"))))))))
              ((a/stringAtom? v)
                (if (h/voidTag? tag)
                  (buildItems tag where rest (addError acc (str where ": " tag " is a void element and cannot hold text")))
                  (buildItems tag where rest (with acc :kids (listAppend acc.kids [(h/text (a/unquote v))])))))
              (else (buildItems tag where rest (with acc :kids (listAppend acc.kids [(h/text v)]))))))
          (_
            (let [(child (buildElement (str where " > ") (listLength acc.kids) item))]
              (buildItems tag where rest (with acc :kids (listAppend acc.kids [(pairFirst child)]) :errors (listAppend acc.errors (pairSecond child))))))))))

fn styleElement where: String items: (List rd/SExpr) -> (Pair h/Node (List String))
  (let [(sheet (css/rulesOf (str where " > ") items))]
    (mt sheet
      ((ok rules) (pair (h/styleSheet rules) []))
      ((err es) (pair (h/frag []) es))))

fn buildElement parent: String index: Int64 e: rd/SExpr -> (Pair h/Node (List String))
  (mt e
    ((rd/sexprList items)
      (let [(tag (a/headOf e))
            (where (str parent tag "[" (stringFromInt64 index) "]"))]
        (cond
          ((= tag "style") (styleElement where (listDrop items 1)))
          ((= tag "svg") (mt (svg/drawingToNode (rd/renderSexpr e)) ((ok node) (pair node [])) ((err es) (pair (h/frag []) (map (fn [(m String)] -> String (str where ": " m)) es)))))
          ((listContains? (elementNames) tag)
            (let [(built (buildItems tag where (listDrop items 1) (Built :attrs [] :kids [] :errors [])))]
              (pair (if (= tag "script")
                      (h/script built.attrs (stringJoin (map h/render built.kids) ""))
                      (if (= tag "button") (h/button built.attrs built.kids) (h/el tag built.attrs built.kids)))
                    built.errors)))
          (else (pair (h/frag []) [(str where ": unknown element :" tag "; HTML elements are the HTML5 names, svg nests an asl-html/asnSvg drawing, style takes asl-html/asnCss rules")])))))
    (_ (pair (h/frag []) [(str parent "an element must be a list like (:p \"text\")")])))

fn pageToNode source: String -> (Result h/Node (List String))
  (let [(built (buildElement "" 0 (rd/parseSexpr source)))]
    (if (listEmpty? (pairSecond built)) (ok (pairFirst built)) (err (pairSecond built))))

fn asnToHtml source: String -> (Result String (List String))
  (mt (a/unbalanced source)
    ((some es) (err es))
    ((none)
      (mt (pageToNode source)
        ((err es) (err es))
        ((ok node) (ok (if (= (a/headOf (rd/parseSexpr source)) "html") (str (h/renderDocument node) "\n") (str (h/render node) "\n")))))))
