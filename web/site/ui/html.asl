(module aslSite/ui/html
  :x [Node Attr elem text attr flag cls id href
      html head body meta link title script style
      header nav main section article aside footer div span p a h1 h2 h3 h4
      ul ol li code pre strong em small button time figure figcaption blockquote hr br
      table thead tbody tr th td
      svg path circle rect line g svgText
      escapeText escapeAttr render renderDocument])

(enum Attr (:c attrPair [(k String) (v String)] "name=value attribute") (:c attrFlag [(k String)] "boolean attribute"))

(enum Node (:c elemNode [(tag String) (attrs (List Attr)) (kids (List Node))] "element") (:c textNode [(s String)] "text, escaped on render"))

fn elem tag: String attrs: (List Attr) kids: (List Node) -> Node
  (elemNode tag attrs kids)

fn text s: String -> Node
  (textNode s)

fn attr k: String v: String -> Attr
  (attrPair k v)

fn flag k: String -> Attr
  (attrFlag k)

fn cls v: String -> Attr
  (attrPair "class" v)

fn id v: String -> Attr
  (attrPair "id" v)

fn href v: String -> Attr
  (attrPair "href" v)

fn html attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "html" attrs kids)

fn head kids: (List Node) -> Node
  (elemNode "head" (list) kids)

fn body attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "body" attrs kids)

fn meta attrs: (List Attr) -> Node
  (elemNode "meta" attrs (list))

fn link attrs: (List Attr) -> Node
  (elemNode "link" attrs (list))

fn title s: String -> Node
  (elemNode "title" (list) (list (textNode s)))

fn script attrs: (List Attr) -> Node
  (elemNode "script" attrs (list))

fn style css: String -> Node
  (elemNode "style" (list) (list (textNode css)))

fn header attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "header" attrs kids)

fn nav attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "nav" attrs kids)

fn main attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "main" attrs kids)

fn section attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "section" attrs kids)

fn article attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "article" attrs kids)

fn aside attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "aside" attrs kids)

fn footer attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "footer" attrs kids)

fn div attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "div" attrs kids)

fn span attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "span" attrs kids)

fn p attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "p" attrs kids)

fn a attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "a" attrs kids)

fn h1 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h1" attrs kids)

fn h2 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h2" attrs kids)

fn h3 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h3" attrs kids)

fn h4 attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "h4" attrs kids)

fn ul attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "ul" attrs kids)

fn ol attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "ol" attrs kids)

fn li attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "li" attrs kids)

fn code attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "code" attrs kids)

fn pre attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "pre" attrs kids)

fn strong attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "strong" attrs kids)

fn em attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "em" attrs kids)

fn small attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "small" attrs kids)

fn button attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "button" (listAppend (list (attrPair "type" "button")) attrs) kids)

fn time attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "time" attrs kids)

fn figure attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "figure" attrs kids)

fn figcaption attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "figcaption" attrs kids)

fn blockquote attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "blockquote" attrs kids)

fn hr attrs: (List Attr) -> Node
  (elemNode "hr" attrs (list))

fn br -> Node
  (elemNode "br" (list) (list))

fn table attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "table" attrs kids)

fn thead kids: (List Node) -> Node
  (elemNode "thead" (list) kids)

fn tbody kids: (List Node) -> Node
  (elemNode "tbody" (list) kids)

fn tr kids: (List Node) -> Node
  (elemNode "tr" (list) kids)

fn th attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "th" attrs kids)

fn td attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "td" attrs kids)

fn svg attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "svg" (listAppend (list (attrPair "xmlns" "http://www.w3.org/2000/svg")) attrs) kids)

fn path attrs: (List Attr) -> Node
  (elemNode "path" attrs (list))

fn circle attrs: (List Attr) -> Node
  (elemNode "circle" attrs (list))

fn rect attrs: (List Attr) -> Node
  (elemNode "rect" attrs (list))

fn line attrs: (List Attr) -> Node
  (elemNode "line" attrs (list))

fn g attrs: (List Attr) kids: (List Node) -> Node
  (elemNode "g" attrs kids)

fn svgText attrs: (List Attr) s: String -> Node
  (elemNode "text" attrs (list (textNode s)))

fn replaceIn s: String old: String new: String -> String
  (if (stringContains? s old) (stringReplace s old new) s)

fn escapeText s: String -> String
  (replaceIn (replaceIn (replaceIn s "&" "&amp;") "<" "&lt;") ">" "&gt;")

fn escapeAttr s: String -> String
  (replaceIn (escapeText s) "\"" "&quot;")

fn voidTag? tag: String -> Bool
  (listContains? (list "meta" "link" "br" "hr" "img" "input" "path" "circle" "rect" "line") tag)

fn rawTextTag? tag: String -> Bool
  (or (= tag "style") (= tag "script"))

fn attrOut acc: (List String) at: Attr -> (List String)
  (mt at
    ((attrFlag k) (cons k (cons " " acc)))
    ((attrPair k v) (cons "\"" (cons (escapeAttr v) (cons "=\"" (cons k (cons " " acc)))))))

fn openTag acc: (List String) tag: String attrs: (List Attr) -> (List String)
  (fold attrOut (cons tag (cons "<" acc)) attrs)

fn selfClosing? tag: String kids: (List Node) -> Bool
  (and (voidTag? tag) (listEmpty? kids))

fn closeOpen acc: (List String) tag: String kids: (List Node) -> (List String)
  (if (and (selfClosing? tag kids) (not (= tag "br"))) (cons "/>" acc) (cons ">" acc))

fn renderRaw acc: (List String) kids: (List Node) -> (List String)
  (fold (fn [(acc2 (List String)) (k Node)] -> (List String) (mt k ((textNode s) (cons s acc2)) ((elemNode t at ks) acc2))) acc kids)

fn renderInto acc: (List String) n: Node -> (List String)
  (mt n
    ((textNode s) (cons (escapeText s) acc))
    ((elemNode tag attrs kids)
      (let [(opened (closeOpen (openTag acc tag attrs) tag kids))]
        (cond
          ((selfClosing? tag kids) opened)
          ((rawTextTag? tag) (cons ">" (cons tag (cons "</" (renderRaw opened kids)))))
          (else (cons ">" (cons tag (cons "</" (fold renderInto opened kids)))))))))

fn render n: Node -> String
  (stringJoin (listReverse (renderInto (list) n)) "")

fn renderDocument root: Node -> String
  (str "<!doctype html>" (render root))
