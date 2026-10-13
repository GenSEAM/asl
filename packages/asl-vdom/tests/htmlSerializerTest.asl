(module aslVdom/tests/htmlSerializerTest :x [runTests] :i [(aslVdom/vdom :a v) (aslVdom/html :a h)])

fn testBasicTextNode -> Bool
  (let [(node (h/t "Hello & <World>")) (serialized (h/vnodeToHtml node))] (assert (= serialized "Hello &amp; &lt;World&gt;") "Text node should escape special chars") true)

fn testVoidElement -> Bool
  (let [(node (h/input (h/attrsOf (list (h/attr "type" "text") (h/attr "name" "q"))))) (serialized (h/vnodeToHtml node))] (assert (= serialized "<input name=\"q\" type=\"text\">") "Void input element must not have closing tag; attributes serialize in key order") true)

fn testNestedVdomTree -> Bool
  (let [(tree (h/secPlain (list (h/h1Plain (list (h/t "AgentScript"))) (h/divPlain (list (h/pPlain (list (h/t "Multi-Runtime")))))))) (serialized (h/vnodeToHtml tree))] (assert (= serialized "<section><h1>AgentScript</h1><div><p>Multi-Runtime</p></div></section>") "Nested VDOM tree serialization must match") true)

fn testRawHtml -> Bool
  (let [(node (h/divPlain (list (h/raw "<svg viewBox=\"0 0 10 10\"><path d=\"M0,0\"/></svg>")))) (serialized (h/vnodeToHtml node))] (assert (= serialized "<div><svg viewBox=\"0 0 10 10\"><path d=\"M0,0\"/></svg></div>") "Raw node must pass through without escaping") true)

fn testBooleanAttributes -> Bool
  (let [(nodeTrue (h/button (h/attrsOf (list (h/attr "disabled" "true"))) (list))) (nodeFalse (h/button (h/attrsOf (list (h/attr "disabled" "false"))) (list))) (sTrue (h/vnodeToHtml nodeTrue)) (sFalse (h/vnodeToHtml nodeFalse))] (assert (= sTrue "<button disabled></button>") "true boolean attr must serialize as bare attr name") (assert (= sFalse "<button></button>") "false boolean attr must be omitted completely") (refute (stringContains? sFalse "disabled=\"false\"") "Must refute false boolean attr inclusion") true)

fn runTests -> Bool
  (and (testBasicTextNode) (and (testVoidElement) (and (testNestedVdomTree) (and (testRawHtml) (testBooleanAttributes)))))
