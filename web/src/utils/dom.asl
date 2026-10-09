(module aslWeb/dom :x [VNode domElement text domQuery formatVdomNode vdomTag vdomAttrs vdomChildren vdomText] :i [])

(enum VNode (:c domElem [(tag Str) (attrs (List (Pair Str Str))) (children (List VNode))] "Element DOM node") (:c domText [(content Str)] "Text leaf DOM node"))

fn domElement tag: Str attrs: (List (Pair Str Str)) children: (List VNode) -> VNode
  (domElem tag attrs children)

fn text content: Str -> VNode
  (domText content)

fn vdomTag node: VNode -> Str
  (mt node ((domText _) "") ((domElem tag _ _) tag))

fn vdomAttrs node: VNode -> (List (Pair Str Str))
  (mt node ((domText _) (list)) ((domElem _ attrs _) attrs))

fn vdomChildren node: VNode -> (List VNode)
  (mt node ((domText _) (list)) ((domElem _ _ children) children))

fn vdomText node: VNode -> Str
  (mt node ((domText content) content) ((domElem _ _ _) ""))

fn formatAttr attr: (Pair Str Str) -> Str
  (mt attr ((pair k v) (str " " k "=\"" v "\"")))

fn formatAttrs attrs: (List (Pair Str Str)) -> Str
  (fold (fn [(acc Str) (attr (Pair Str Str))] -> Str (str acc (formatAttr attr))) "" attrs)

fn formatChildren children: (List VNode) -> Str
  (fold (fn [(acc Str) (child VNode)] -> Str (str acc (formatVdomNode (some child)))) "" children)

fn formatVdomNode node: (Option VNode) -> Str
  (mt node ((none) "") ((some n) (mt n ((domText content) content) ((domElem tag attrs children) (str "<" tag (formatAttrs attrs) ">" (formatChildren children) "</" tag ">")))))

fn domQueryChildren children: (List VNode) tagName: Str -> (Option VNode)
  (mt (listHead children) ((none) none) ((some c) (mt (domQuery (some c) tagName) ((some found) (some found)) ((none) (domQueryChildren (optionOr (listTail children) (list)) tagName)))))

fn domQuery root: (Option VNode) tagName: Str -> (Option VNode)
  (mt root ((none) none) ((some r) (mt r ((domText _) none) ((domElem tag attrs children) (if (= tag tagName) (some r) (domQueryChildren children tagName))))))
