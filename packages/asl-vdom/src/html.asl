(module aslVdom/html :x [Props makeProps propsToAttrs attrsEmpty attr attrClass attrId attrType attrValue attrName attrPlaceholder attrHref attrSrc attrAlt attrsOf withAttr withClass div span p h1 h2 h3 button input form card header footer section nav main article aside table label d s sp b btn sec hdr ftr frm inp art tbl lbl txt t el c comp divPlain spanPlain pPlain h1Plain h2Plain h3Plain buttonPlain formPlain cardPlain headerPlain footerPlain sectionPlain navPlain mainPlain articlePlain tablePlain labelPlain dPlain sPlain spPlain bPlain btnPlain secPlain hdrPlain ftrPlain frmPlain artPlain tblPlain lblPlain elPlain cPlain compPlain escapeHtml isVoidTag? attrsToHtml vnodeToHtml raw] :i [(aslVdom/vdom :a v)])

(schema Props (:f id String) (:f className String) (:f role String) (:f title String) (:f extra (Map String String)))

fn makeProps className: String -> Props
  (Props :id "" :className className :role "" :title "" :extra (mapEmpty))

fn propsToAttrs p: Props -> (Map String String)
  (let [(m0 p.extra) (m1 (if (stringEmpty? p.id) m0 (mapSet m0 "id" p.id))) (m2 (if (stringEmpty? p.className) m1 (mapSet m1 "class" p.className))) (m3 (if (stringEmpty? p.role) m2 (mapSet m2 "role" p.role))) (m4 (if (stringEmpty? p.title) m3 (mapSet m3 "title" p.title)))] m4)

fn attrsEmpty -> (Map String String)
  (mapEmpty)

fn attr k: String v: String -> (Pair String String)
  (pair k v)

fn attrClass v: String -> (Pair String String)
  (pair "class" v)

fn attrId v: String -> (Pair String String)
  (pair "id" v)

fn attrType v: String -> (Pair String String)
  (pair "type" v)

fn attrValue v: String -> (Pair String String)
  (pair "value" v)

fn attrName v: String -> (Pair String String)
  (pair "name" v)

fn attrPlaceholder v: String -> (Pair String String)
  (pair "placeholder" v)

fn attrHref v: String -> (Pair String String)
  (pair "href" v)

fn attrSrc v: String -> (Pair String String)
  (pair "src" v)

fn attrAlt v: String -> (Pair String String)
  (pair "alt" v)

fn attrsOf pairs: (List (Pair String String)) -> (Map String String)
  (fold (fn [(acc (Map String String)) (p (pair String String))] -> (Map String String) (mapSet acc (pairFirst p) (pairSecond p))) (mapEmpty) pairs)

fn withAttr attrs: (Map String String) k: String v: String -> (Map String String)
  (mapSet attrs k v)

fn withClass attrs: (Map String String) cls: String -> (Map String String)
  (mapSet attrs "class" cls)

fn t content: String -> v/VNode
  (v/t content)

fn txt content: String -> v/VNode
  (v/text content)

fn div attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "div" attrs children)

fn span attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "span" attrs children)

fn p attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "p" attrs children)

fn h1 attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "h1" attrs children)

fn h2 attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "h2" attrs children)

fn h3 attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "h3" attrs children)

fn button attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "button" attrs children)

fn input attrs: (Map String String) -> v/VNode
  (v/elem "input" attrs (list))

fn form attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "form" attrs children)

fn card attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "div" (mapSet attrs "class" "card") children)

fn header attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "header" attrs children)

fn footer attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "footer" attrs children)

fn section attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "section" attrs children)

fn sec attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "section" attrs children)

fn nav attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "nav" attrs children)

fn main attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "main" attrs children)

fn article attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "article" attrs children)

fn art attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "article" attrs children)

fn aside attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "aside" attrs children)

fn table attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "table" attrs children)

fn tbl attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "table" attrs children)

fn label attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "label" attrs children)

fn lbl attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "label" attrs children)

fn hdr attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "header" attrs children)

fn ftr attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "footer" attrs children)

fn frm attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "form" attrs children)

fn inp attrs: (Map String String) -> v/VNode
  (v/elem "input" attrs (list))

fn d attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "div" attrs children)

fn s attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "span" attrs children)

fn sp attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "span" attrs children)

fn b attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "button" attrs children)

fn btn attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/elem "button" attrs children)

fn el tag: String attrs: (Map String String) children: (List v/VNode) -> v/VNode
  (v/el tag attrs children)

fn c name: String props: (Map String String) children: (List v/VNode) -> v/VNode
  (v/c name props children)

fn comp name: String props: (Map String String) children: (List v/VNode) -> v/VNode
  (v/comp name props children)

fn divPlain children: (List v/VNode) -> v/VNode
  (v/elem "div" (mapEmpty) children)

fn spanPlain children: (List v/VNode) -> v/VNode
  (v/elem "span" (mapEmpty) children)

fn pPlain children: (List v/VNode) -> v/VNode
  (v/elem "p" (mapEmpty) children)

fn h1Plain children: (List v/VNode) -> v/VNode
  (v/elem "h1" (mapEmpty) children)

fn h2Plain children: (List v/VNode) -> v/VNode
  (v/elem "h2" (mapEmpty) children)

fn h3Plain children: (List v/VNode) -> v/VNode
  (v/elem "h3" (mapEmpty) children)

fn buttonPlain children: (List v/VNode) -> v/VNode
  (v/elem "button" (mapEmpty) children)

fn formPlain children: (List v/VNode) -> v/VNode
  (v/elem "form" (mapEmpty) children)

fn cardPlain children: (List v/VNode) -> v/VNode
  (v/elem "div" (mapSet (mapEmpty) "class" "card") children)

fn headerPlain children: (List v/VNode) -> v/VNode
  (v/elem "header" (mapEmpty) children)

fn footerPlain children: (List v/VNode) -> v/VNode
  (v/elem "footer" (mapEmpty) children)

fn dPlain children: (List v/VNode) -> v/VNode
  (v/elem "div" (mapEmpty) children)

fn sPlain children: (List v/VNode) -> v/VNode
  (v/elem "span" (mapEmpty) children)

fn bPlain children: (List v/VNode) -> v/VNode
  (v/elem "button" (mapEmpty) children)

fn btnPlain children: (List v/VNode) -> v/VNode
  (v/elem "button" (mapEmpty) children)

fn elPlain tag: String children: (List v/VNode) -> v/VNode
  (v/elPlain tag children)

fn cPlain name: String children: (List v/VNode) -> v/VNode
  (v/cPlain name children)

fn compPlain name: String children: (List v/VNode) -> v/VNode
  (v/compPlain name children)

fn sectionPlain children: (List v/VNode) -> v/VNode
  (v/elem "section" (mapEmpty) children)

fn secPlain children: (List v/VNode) -> v/VNode
  (v/elem "section" (mapEmpty) children)

fn spPlain children: (List v/VNode) -> v/VNode
  (v/elem "span" (mapEmpty) children)

fn navPlain children: (List v/VNode) -> v/VNode
  (v/elem "nav" (mapEmpty) children)

fn mainPlain children: (List v/VNode) -> v/VNode
  (v/elem "main" (mapEmpty) children)

fn articlePlain children: (List v/VNode) -> v/VNode
  (v/elem "article" (mapEmpty) children)

fn artPlain children: (List v/VNode) -> v/VNode
  (v/elem "article" (mapEmpty) children)

fn tablePlain children: (List v/VNode) -> v/VNode
  (v/elem "table" (mapEmpty) children)

fn tblPlain children: (List v/VNode) -> v/VNode
  (v/elem "table" (mapEmpty) children)

fn labelPlain children: (List v/VNode) -> v/VNode
  (v/elem "label" (mapEmpty) children)

fn lblPlain children: (List v/VNode) -> v/VNode
  (v/elem "label" (mapEmpty) children)

fn hdrPlain children: (List v/VNode) -> v/VNode
  (v/elem "header" (mapEmpty) children)

fn ftrPlain children: (List v/VNode) -> v/VNode
  (v/elem "footer" (mapEmpty) children)

fn frmPlain children: (List v/VNode) -> v/VNode
  (v/elem "form" (mapEmpty) children)

fn escapeHtml s: String -> String
  (let [(s1 (stringReplace s "&" "&amp;")) (s2 (stringReplace s1 "<" "&lt;")) (s3 (stringReplace s2 ">" "&gt;")) (s4 (stringReplace s3 "\"" "&quot;")) (s5 (stringReplace s4 "'" "&#39;"))] s5)

fn isVoidTag? tag: String -> Bool
  (or (= tag "area") (or (= tag "base") (or (= tag "br") (or (= tag "col") (or (= tag "embed") (or (= tag "hr") (or (= tag "img") (or (= tag "input") (or (= tag "link") (or (= tag "meta") (or (= tag "param") (or (= tag "source") (or (= tag "track") (= tag "wbr"))))))))))))))

fn attrsToHtml attrs: (Map String String) -> String
  (let [(keys (mapKeys attrs))] (if (= (listLength keys) 0) "" (let [(attrStrs (map (fn [(k String)] -> String (let [(v (optionOr (mapGet attrs k) ""))] (if (= v "false") "" (if (= v "true") (str " " k) (str " " k "=\"" (escapeHtml v) "\""))))) keys))] (stringJoin attrStrs ""))))

fn raw content: String -> v/VNode
  (v/elementNode "raw" (mapSet (mapEmpty) "html" content) (list))

fn vnodeToHtml node: v/VNode -> Str
  (mt node ((v/textNode content) (escapeHtml content)) ((v/elementNode tag attrs children) (if (or (= tag "raw") (= tag "!raw")) (optionOr (mapGet attrs "html") "") (let [(attrStr (attrsToHtml attrs)) (chLen (listLength children))] (if (= chLen 0) (if (isVoidTag? tag) (str "<" tag attrStr ">") (str "<" tag attrStr "></" tag ">")) (let [(chStrs (map (fn [(ch v/VNode)] -> String (vnodeToHtml ch)) children)) (body (stringJoin chStrs ""))] (str "<" tag attrStr ">" body "</" tag ">")))))))
