(module asl-vdom/tests/html1CoverTest
  :x [runTests]
  :i [(aslVdom/html :a h) (aslVdom/vdom :a v)])

fn maxCls -> String
  "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fn testMakeProps -> Bool
  (let [(p (h/makeProps "btn")) (e (h/makeProps "")) (m (h/makeProps (maxCls)))]
    (assert (= p.className "btn") "makeProps normal className")
    (assert (= p.id "") "makeProps normal id empty")
    (assert (= p.role "") "makeProps normal role empty")
    (assert (= p.title "") "makeProps normal title empty")
    (assert (= (mapSize p.extra) 0) "makeProps normal extra empty")
    (assert (match (mapGet p.extra "missing") ((none) true) ((some _) false)) "makeProps none path extra lookup")
    (assert (= e.className "") "makeProps boundary empty className")
    (assert (= m.className (maxCls)) "makeProps boundary max className")
    true)

fn testPropsToAttrs -> Bool
  (let [(a (h/propsToAttrs (h/makeProps "btn"))) (e (h/propsToAttrs (h/makeProps ""))) (m (h/propsToAttrs (h/makeProps (maxCls))))]
    (assert (= (optionOr (mapGet a "class") "") "btn") "propsToAttrs normal class")
    (assert (match (mapGet a "id") ((none) true) ((some _) false)) "propsToAttrs none id absent")
    (assert (match (mapGet a "role") ((none) true) ((some _) false)) "propsToAttrs none role absent")
    (assert (= (mapSize e) 0) "propsToAttrs boundary empty")
    (assert (= (optionOr (mapGet m "class") "") (maxCls)) "propsToAttrs boundary max")
    true)

fn testAttrsEmpty -> Bool
  (do
    (assert (= (mapSize (h/attrsEmpty)) 0) "attrsEmpty empty")
    (assert (match (mapGet (h/attrsEmpty) "k") ((none) true) ((some _) false)) "attrsEmpty none path")
    true)

fn testAttrType -> Bool
  (do
    (assert (= (pairFirst (h/attrType "text")) "type") "attrType normal key")
    (assert (= (pairSecond (h/attrType "text")) "text") "attrType normal value")
    (assert (= (pairSecond (h/attrType "")) "") "attrType boundary empty")
    (assert (= (pairSecond (h/attrType (maxCls))) (maxCls)) "attrType boundary max")
    true)

fn testAttrPlaceholder -> Bool
  (do
    (assert (= (pairFirst (h/attrPlaceholder "enter name")) "placeholder") "attrPlaceholder normal key")
    (assert (= (pairSecond (h/attrPlaceholder "enter name")) "enter name") "attrPlaceholder normal value")
    (assert (= (pairSecond (h/attrPlaceholder "")) "") "attrPlaceholder boundary empty")
    (assert (= (pairSecond (h/attrPlaceholder (maxCls))) (maxCls)) "attrPlaceholder boundary max")
    true)

fn testAttrHref -> Bool
  (do
    (assert (= (pairFirst (h/attrHref "/page")) "href") "attrHref normal key")
    (assert (= (pairSecond (h/attrHref "/page")) "/page") "attrHref normal value")
    (assert (= (pairSecond (h/attrHref "")) "") "attrHref boundary empty")
    (assert (= (pairSecond (h/attrHref (maxCls))) (maxCls)) "attrHref boundary max")
    true)

fn testAttrSrc -> Bool
  (do
    (assert (= (pairFirst (h/attrSrc "/img.png")) "src") "attrSrc normal key")
    (assert (= (pairSecond (h/attrSrc "/img.png")) "/img.png") "attrSrc normal value")
    (assert (= (pairSecond (h/attrSrc "")) "") "attrSrc boundary empty")
    (assert (= (pairSecond (h/attrSrc (maxCls))) (maxCls)) "attrSrc boundary max")
    true)

fn testAttrAlt -> Bool
  (do
    (assert (= (pairFirst (h/attrAlt "photo")) "alt") "attrAlt normal key")
    (assert (= (pairSecond (h/attrAlt "photo")) "photo") "attrAlt normal value")
    (assert (= (pairSecond (h/attrAlt "")) "") "attrAlt boundary empty")
    (assert (= (pairSecond (h/attrAlt (maxCls))) (maxCls)) "attrAlt boundary max")
    true)

fn testWithAttr -> Bool
  (do
    (assert (= (optionOr (mapGet (h/withAttr (h/attrsEmpty) "k" "v") "k") "") "v") "withAttr normal")
    (assert (= (optionOr (mapGet (h/withAttr (h/attrsEmpty) "" "v") "") "") "v") "withAttr boundary empty key")
    (assert (match (mapGet (h/withAttr (h/attrsEmpty) "k" "") "k") ((some v) (= v "")) ((none) false)) "withAttr boundary empty value present")
    (assert (= (optionOr (mapGet (h/withAttr (h/attrsEmpty) (maxCls) (maxCls)) (maxCls)) "") (maxCls)) "withAttr boundary max")
    (assert (= (optionOr (mapGet (h/withAttr (h/withAttr (h/attrsEmpty) "k" "v1") "k" "v2") "k") "") "v2") "withAttr overwrite")
    true)

fn testWithClass -> Bool
  (do
    (assert (= (optionOr (mapGet (h/withClass (h/attrsEmpty) "cls") "class") "") "cls") "withClass normal")
    (assert (= (optionOr (mapGet (h/withClass (h/attrsEmpty) "") "class") "") "") "withClass boundary empty")
    (assert (= (optionOr (mapGet (h/withClass (h/attrsEmpty) (maxCls)) "class") "") (maxCls)) "withClass boundary max")
    (assert (= (optionOr (mapGet (h/withClass (h/withClass (h/attrsEmpty) "a") "b") "class") "") "b") "withClass overwrite")
    true)

fn testFrm -> Bool
  (let [(e (h/frm (h/attrsEmpty) (list))) (one (h/frm (h/attrsEmpty) (list (h/spanPlain (list)))))]
    (assert (= (v/vnodeTag e) "form") "frm normal tag")
    (assert (= (mapSize (v/vnodeAttrs e)) 0) "frm normal attrs empty")
    (assert (= (listLength (v/vnodeChildren e)) 0) "frm boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "frm one child")
    (assert (= (v/vnodeText e) "") "frm none text path")
    (assert (match (mapGet (v/vnodeAttrs e) "class") ((none) true) ((some _) false)) "frm none attr path")
    true)

fn testSpanPlain -> Bool
  (let [(e (h/spanPlain (list))) (one (h/spanPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "span") "spanPlain normal tag")
    (assert (= (mapSize (v/vnodeAttrs e)) 0) "spanPlain normal attrs empty")
    (assert (= (listLength (v/vnodeChildren e)) 0) "spanPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "spanPlain one child")
    true)

fn testH2Plain -> Bool
  (let [(e (h/h2Plain (list))) (one (h/h2Plain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "h2") "h2Plain normal tag")
    (assert (= (mapSize (v/vnodeAttrs e)) 0) "h2Plain normal attrs empty")
    (assert (= (listLength (v/vnodeChildren e)) 0) "h2Plain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "h2Plain one child")
    true)

fn testH3Plain -> Bool
  (let [(e (h/h3Plain (list))) (one (h/h3Plain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "h3") "h3Plain normal tag")
    (assert (= (mapSize (v/vnodeAttrs e)) 0) "h3Plain normal attrs empty")
    (assert (= (listLength (v/vnodeChildren e)) 0) "h3Plain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "h3Plain one child")
    true)

fn testButtonPlain -> Bool
  (let [(e (h/buttonPlain (list))) (one (h/buttonPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "button") "buttonPlain normal tag")
    (assert (= (mapSize (v/vnodeAttrs e)) 0) "buttonPlain normal attrs empty")
    (assert (= (listLength (v/vnodeChildren e)) 0) "buttonPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "buttonPlain one child")
    true)

fn testFormPlain -> Bool
  (let [(e (h/formPlain (list))) (one (h/formPlain (list (h/spanPlain (list)))))]
    (assert (= (v/vnodeTag e) "form") "formPlain normal tag")
    (assert (= (mapSize (v/vnodeAttrs e)) 0) "formPlain normal attrs empty")
    (assert (= (listLength (v/vnodeChildren e)) 0) "formPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "formPlain one child")
    true)

fn testCardPlain -> Bool
  (let [(e (h/cardPlain (list))) (one (h/cardPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "div") "cardPlain normal tag")
    (assert (= (optionOr (mapGet (v/vnodeAttrs e) "class") "") "card") "cardPlain normal class")
    (assert (= (listLength (v/vnodeChildren e)) 0) "cardPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "cardPlain one child")
    true)

fn testHeaderPlain -> Bool
  (let [(e (h/headerPlain (list))) (one (h/headerPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "header") "headerPlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "headerPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "headerPlain one child")
    true)

fn testFooterPlain -> Bool
  (let [(e (h/footerPlain (list))) (one (h/footerPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "footer") "footerPlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "footerPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "footerPlain one child")
    true)

fn testSectionPlain -> Bool
  (let [(e (h/sectionPlain (list))) (one (h/sectionPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "section") "sectionPlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "sectionPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "sectionPlain one child")
    true)

fn testNavPlain -> Bool
  (let [(e (h/navPlain (list))) (one (h/navPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "nav") "navPlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "navPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "navPlain one child")
    true)

fn testMainPlain -> Bool
  (let [(e (h/mainPlain (list))) (one (h/mainPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "main") "mainPlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "mainPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "mainPlain one child")
    true)

fn testArticlePlain -> Bool
  (let [(e (h/articlePlain (list))) (one (h/articlePlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "article") "articlePlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "articlePlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "articlePlain one child")
    true)

fn testTablePlain -> Bool
  (let [(e (h/tablePlain (list))) (one (h/tablePlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "table") "tablePlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "tablePlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "tablePlain one child")
    true)

fn testLabelPlain -> Bool
  (let [(e (h/labelPlain (list))) (one (h/labelPlain (list (v/t "x"))))]
    (assert (= (v/vnodeTag e) "label") "labelPlain normal tag")
    (assert (= (listLength (v/vnodeChildren e)) 0) "labelPlain boundary zero children")
    (assert (= (listLength (v/vnodeChildren one)) 1) "labelPlain one child")
    true)

fn runTests -> Bool
  (and (testMakeProps) (testPropsToAttrs) (testAttrsEmpty) (testAttrType) (testAttrPlaceholder) (testAttrHref) (testAttrSrc) (testAttrAlt) (testWithAttr) (testWithClass) (testFrm) (testSpanPlain) (testH2Plain) (testH3Plain) (testButtonPlain) (testFormPlain) (testCardPlain) (testHeaderPlain) (testFooterPlain) (testSectionPlain) (testNavPlain) (testMainPlain) (testArticlePlain) (testTablePlain) (testLabelPlain))

