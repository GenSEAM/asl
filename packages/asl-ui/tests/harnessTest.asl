(module asl-ui/tests/harnessTest
  :x [runTests]
  :i [(asl-ui/harness :a hn) (asl-ui/view :a ui) (asl-ui/semTokens :a t)])

fn form -> ui/View
  (ui/stack (t/md) (ui/start)
    [(ui/field "Name" "Ada" 1)
     (ui/toggle "News" false 3)
     (ui/button "Send" (t/strong) 2)
     (ui/note (t/success) "Thanks, \"Ada\"")
     (ui/row (t/sm) (ui/center) [(ui/link "Docs" "/docs") (ui/link "Blog" "/blog")])])

fn rootOf v: ui/View -> ui/Item
  (resultOr (hn/mount v) (ui/resolve (ui/absent)))

fn act role: ui/Role label: String what: hn/Act -> (Result hn/Sent hn/Fault)
  (match (hn/find (rootOf (form)) role label) ((ok item) (hn/send item what)) ((err fault) (err fault)))

fn runTests -> Bool
  (let [(root (rootOf (form)))
        (twice (ui/stack (t/sm) (ui/start) [(ui/stack (t/sm) (ui/start) [(ui/link "Docs" "/a")]) (ui/stack (t/sm) (ui/start) [(ui/link "Docs" "/b")])]))]
    (assert (= (hn/mount (form)) (ok (ui/resolve (form)))) "mount returns the resolved tree of a sound view")
    (assert (= (hn/mount (ui/stack (t/sm) (ui/start) [(ui/field "" "x" 1)])) (err (hn/broken [(ui/unnamed "group0-textbox-" (ui/textboxRole))]))) "mount reports an interactive widget without a label")
    (assert (= (hn/mount (ui/row (t/sm) (ui/start) [(ui/button "Go" (t/strong) 1) (ui/button "Go" (t/strong) 2)])) (err (hn/broken [(ui/clash "group0-button-go")]))) "mount reports an id clash")
    (assert (= (resultMap (hn/find root (ui/textboxRole) "Name") (fn [i] i.id)) (ok "group0-textbox-name")) "find returns the node with the role and label")
    (assert (= (resultMap (hn/find root (ui/textboxRole) "Name") (fn [i] i.state)) (ok (ui/valued "Ada"))) "the state of a field is its value")
    (assert (= (resultMap (hn/find root (ui/switchRole) "News") (fn [i] i.state)) (ok (ui/switched false))) "the state of a toggle is its position")
    (assert (= (hn/find root (ui/buttonRole) "Name") (err (hn/missing (ui/buttonRole) "Name"))) "a label under another role is missing")
    (assert (= (hn/find root (ui/buttonRole) "send") (err (hn/missing (ui/buttonRole) "send"))) "labels match exactly")
    (assert (= (hn/find (rootOf twice) (ui/linkRole) "Docs") (err (hn/ambiguous (ui/linkRole) "Docs"))) "two nodes with the role and label are ambiguous")
    (assert (= (map (fn [i] i.label) (hn/findAll root (ui/linkRole))) ["Docs" "Blog"]) "findAll returns every node of a role in tree order")
    (assert (= (map (fn [i] i.label) (hn/findAll root (ui/statusRole))) ["Thanks, \"Ada\""]) "a note is found by the status role")
    (assert (= (act (ui/textboxRole) "Name" (hn/enter "Bo")) (ok (hn/Sent :code 1 :value "Bo"))) "entering text sends the field message with the text")
    (assert (= (act (ui/buttonRole) "Send" (hn/press)) (ok (hn/Sent :code 2 :value ""))) "pressing a button sends its message")
    (assert (= (act (ui/switchRole) "News" (hn/press)) (ok (hn/Sent :code 3 :value ""))) "pressing a toggle sends its message")
    (assert (= (act (ui/textboxRole) "Name" (hn/press)) (err (hn/inert "group0-textbox-name"))) "a field does not answer a press")
    (assert (= (act (ui/buttonRole) "Send" (hn/enter "x")) (err (hn/inert "group0-button-send"))) "a button does not take text")
    (assert (= (act (ui/linkRole) "Blog" (hn/press)) (err (hn/inert "group0-group4-link-blog"))) "a link sends no message")
    (assert (= (hn/snapshot root) "(:group :id \"group0\"\n  (:textbox :id \"group0-textbox-name\" :label \"Name\" :value \"Ada\" :msg 1)\n  (:switch :id \"group0-switch-news\" :label \"News\" :on false :msg 3)\n  (:button :id \"group0-button-send\" :label \"Send\" :msg 2)\n  (:status :id \"group0-status3\" :label \"Thanks, \\\"Ada\\\"\")\n  (:group :id \"group0-group4\"\n    (:link :id \"group0-group4-link-docs\" :label \"Docs\" :value \"/docs\")\n    (:link :id \"group0-group4-link-blog\" :label \"Blog\" :value \"/blog\")))") "the snapshot is the tree as ASN text with roles, ids, labels, state and messages")
    (assert (stringContains? (hn/snapshot (rootOf (ui/toggle "News" true 3))) ":on true") "the snapshot shows an on toggle")
    (assert (= (hn/faultText (hn/missing (ui/buttonRole) "Go")) "no button labelled \"Go\"") "a missing fault names role and label")
    (assert (= (hn/faultText (hn/ambiguous (ui/linkRole) "Docs")) "more than one link labelled \"Docs\"") "an ambiguous fault names role and label")
    (assert (= (hn/faultText (hn/inert "a-b")) "the node a-b does not answer this act") "an inert fault names the node")
    (assert (= (hn/faultText (hn/broken [(ui/clash "x") (ui/unnamed "y" (ui/linkRole))])) "two nodes share the id x; wrap one in (keyed \"name\" ...); the link at y has no label") "a broken fault lists every problem")
    true)
