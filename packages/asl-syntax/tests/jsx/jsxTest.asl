(module asl-syntax/tests/jsx/jsxTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/jsx :a jsx)
      (aslVdom/vdom :a v)
      (aslVdom/emitJsx :a emit)])

fn checkJsx! code: String expectedSExpr: String -> Bool
  (let [(res (jsx/parseJsx code))]
    (do
      (assert (ok? res) (str "parseJsx succeeds: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (sexpr (jsx/jsxToSExpr root code))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= sexpr expectedSExpr) (println "SEXPR MISMATCH for " code "
GOT: " sexpr "
WANT: " expectedSExpr) ())
          (assert (= sexpr expectedSExpr) (str "sexpr matches: " code))
          (if (!= printed code) (println "ROUND TRIP DIFF for " code "
GOT: " printed "
WANT: " code) ())
          (assert (= printed code) (str "exact round-trip: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "exact tiling: " code))
          true))))
fn checkJsxErr code: String -> Bool
  (let [(res (jsx/parseJsx code))]
    (do
      (assert (err? res) (str "expected parse error for: " code))
      true))

fn testSelfClosingElements! -> Bool
  (do
    (checkJsx! "<div />" "(jsxElement div [])")
    (checkJsx! "<br/>" "(jsxElement br [])")
    (checkJsx! "<img src=\"foo.png\" />" "(jsxElement img [(jsxAttr src \"foo.png\")])")
    (checkJsx! "<input type='text' disabled />" "(jsxElement input [(jsxAttr type 'text') (jsxAttr disabled)])")
    (checkJsx! "<Component />" "(jsxElement Component [])")
    true)
fn testElementsWithChildren! -> Bool
  (do
    (checkJsx! "<div></div>" "(jsxElement div [] [])")
    (checkJsx! "<span>hello</span>" "(jsxElement span [] [(jsxText \"hello\")])")
    (checkJsx! "<p>line 1\nline 2</p>" "(jsxElement p [] [(jsxText \"line 1\nline 2\")])")
    (checkJsx! "<div><span>nested</span></div>" "(jsxElement div [] [(jsxElement span [] [(jsxText \"nested\")])])")
    (checkJsx! "<div>hello <b>world</b>!</div>" "(jsxElement div [] [(jsxText \"hello \") (jsxElement b [] [(jsxText \"world\")]) (jsxText \"!\")])")
    true)

fn testFragments! -> Bool
  (do
    (checkJsx! "<></>" "(jsxFragment [])")
    (checkJsx! "<>hello</>" "(jsxFragment [(jsxText \"hello\")])")
    (checkJsx! "<><div /><span /></>" "(jsxFragment [(jsxElement div []) (jsxElement span [])])")
    (checkJsx! "<><div>one</div><span>two</span></>" "(jsxFragment [(jsxElement div [] [(jsxText \"one\")]) (jsxElement span [] [(jsxText \"two\")])])")
    true)

fn testAttributesAndSpreads! -> Bool
  (do
    (checkJsx! "<div id=\"app\" className=\"container\" />" "(jsxElement div [(jsxAttr id \"app\") (jsxAttr className \"container\")])")
    (checkJsx! "<button disabled checked />" "(jsxElement button [(jsxAttr disabled) (jsxAttr checked)])")
    (checkJsx! "<div count={42} />" "(jsxElement div [(jsxAttr count (jsxExpr 42))])")
    (checkJsx! "<div active={true} />" "(jsxElement div [(jsxAttr active (jsxExpr true))])")
    (checkJsx! "<div {...props} />" "(jsxElement div [(jsxSpread props)])")
    (checkJsx! "<div id=\"x\" {...props} className=\"y\" />" "(jsxElement div [(jsxAttr id \"x\") (jsxSpread props) (jsxAttr className \"y\")])")
    (checkJsx! "<div {...a} {...b} />" "(jsxElement div [(jsxSpread a) (jsxSpread b)])")
    true)

fn testTagNamesAndNamespaces! -> Bool
  (do
    (checkJsx! "<Foo.Bar />" "(jsxElement (. Foo Bar) [])")
    (checkJsx! "<UI.Button.Primary />" "(jsxElement (. (. UI Button) Primary) [])")
    (checkJsx! "<svg:path d=\"M0 0\" />" "(jsxElement (: svg path) [(jsxAttr d \"M0 0\")])")
    (checkJsx! "<my-custom-element id=\"x\" />" "(jsxElement my-custom-element [(jsxAttr id \"x\")])")
    (checkJsx! "<div aria-label=\"close\" data-testid=\"btn-1\" />" "(jsxElement div [(jsxAttr aria-label \"close\") (jsxAttr data-testid \"btn-1\")])")
    (checkJsx! "<Foo.Bar>hello</Foo.Bar>" "(jsxElement (. Foo Bar) [] [(jsxText \"hello\")])")
    (checkJsx! "<svg:path>content</svg:path>" "(jsxElement (: svg path) [] [(jsxText \"content\")])")
    (checkJsx! "<div/>" "(jsxElement div [])")
    true)

fn testExpressionContainers! -> Bool
  (do
    (checkJsx! "<div>{name}</div>" "(jsxElement div [] [(jsxExpr name)])")
    (checkJsx! "<div>{}</div>" "(jsxElement div [] [(jsxExpr)])")
    (checkJsx! "<div>{/* comment */}</div>" "(jsxElement div [] [(jsxExpr)])")
    (checkJsx! "<div>{count + 1}</div>" "(jsxElement div [] [(jsxExpr (+ count 1))])")
    (checkJsx! "<div>{isReady && <Ready />}</div>" "(jsxElement div [] [(jsxExpr (&& isReady (jsxElement Ready [])))])")
    (checkJsx! "<div>{isLoggedIn ? <User /> : <Login />}</div>" "(jsxElement div [] [(jsxExpr (? isLoggedIn (jsxElement User []) (jsxElement Login [])))])")
    (checkJsx! "<ul>{items.map(x => <li>{x}</li>)}</ul>" "(jsxElement ul [] [(jsxExpr (call (. items map) (arrow (params x) (jsxElement li [] [(jsxExpr x)]))))])")
    true)

fn testNestedGenericsFreeCases! -> Bool
  (do
    (checkJsx! "<div><header><h1>Title</h1></header><main><p>Body</p></main><footer>Footer</footer></div>" "(jsxElement div [] [(jsxElement header [] [(jsxElement h1 [] [(jsxText \"Title\")])]) (jsxElement main [] [(jsxElement p [] [(jsxText \"Body\")])]) (jsxElement footer [] [(jsxText \"Footer\")])])")
    (checkJsx! "<>{a ? <div><span>1</span></div> : <div><span>2</span></div>}</>" "(jsxFragment [(jsxExpr (? a (jsxElement div [] [(jsxElement span [] [(jsxText \"1\")])]) (jsxElement div [] [(jsxElement span [] [(jsxText \"2\")])])))])")
    (checkJsx! "<div>{items.map(x => <div>{x.sub.map(y => <span>{y}</span>)}</div>)}</div>" "(jsxElement div [] [(jsxExpr (call (. items map) (arrow (params x) (jsxElement div [] [(jsxExpr (call (. (. x sub) map) (arrow (params y) (jsxElement span [] [(jsxExpr y)]))))]))))])")
    true)

fn testVnodeEmitJsxRoundTrip -> Bool
  (do
    (let [(t1 (v/textNode "Plain text content"))
          (code1 (emit/emitVnodeJsx t1 0))
          (res1 (jsx/parseJsx code1))]
      (do
        (assert (ok? res1) "emitVnodeJsx text node parses")
        (let [(root1 (resultOr res1 (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (pr/printTreeString code1 root1) code1) "emitVnodeJsx text node round-trip")
            (assert (ok? (tr/checkTiling root1 (stringLength code1))) "emitVnodeJsx text node tiling")))))
    (let [(n2 (v/elementNode "div" (mapFromPairs [(pair "className" "container")]) (list (v/elementNode "h1" (mapEmpty) (list (v/textNode "Header"))) (v/elementNode "p" (mapFromPairs [(pair "id" "desc")]) (list (v/textNode "Paragraph text"))))))
          (code2 (emit/emitVnodeJsx n2 0))
          (res2 (jsx/parseJsx code2))]
      (do
        (assert (ok? res2) "emitVnodeJsx element tree parses")
        (let [(root2 (resultOr res2 (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (pr/printTreeString code2 root2) code2) "emitVnodeJsx element tree round-trip")
            (assert (ok? (tr/checkTiling root2 (stringLength code2))) "emitVnodeJsx element tree tiling")))))
    (let [(n3 (v/elementNode "input" (mapFromPairs [(pair "type" "text") (pair "disabled" "true") (pair "placeholder" "Enter text...")]) (list)))
          (code3 (emit/emitVnodeJsx n3 0))
          (res3 (jsx/parseJsx code3))]
      (do
        (assert (ok? res3) "emitVnodeJsx void tag parses")
        (let [(root3 (resultOr res3 (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (pr/printTreeString code3 root3) code3) "emitVnodeJsx void tag round-trip")
            (assert (ok? (tr/checkTiling root3 (stringLength code3))) "emitVnodeJsx void tag tiling")))))
    (let [(n4 (v/elementNode "Button" (mapFromPairs [(pair "onClick" "{handleClick}") (pair "disabled" "false")]) (list (v/textNode "Submit"))))
          (code4 (emit/emitVnodeJsx n4 0))
          (res4 (jsx/parseJsx code4))]
      (do
        (assert (ok? res4) "emitVnodeJsx component tag parses")
        (let [(root4 (resultOr res4 (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (pr/printTreeString code4 root4) code4) "emitVnodeJsx component tag round-trip")
            (assert (ok? (tr/checkTiling root4 (stringLength code4))) "emitVnodeJsx component tag tiling")))))
    (let [(n5 (v/elementNode "Card" (mapFromPairs [(pair "title" "Card Title")]) (list (v/elementNode "div" (mapFromPairs [(pair "class" "card-body")]) (list (v/textNode "Body content with special characters: & < > \" '"))))))
          (code5 (emit/emitVnodeJsx n5 2))
          (res5 (jsx/parseJsx code5))]
      (do
        (assert (ok? res5) "emitVnodeJsx indented card parses")
        (let [(root5 (resultOr res5 (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (pr/printTreeString code5 root5) code5) "emitVnodeJsx indented card round-trip")
            (assert (ok? (tr/checkTiling root5 (stringLength code5))) "emitVnodeJsx indented card tiling")))))
    true)

fn testErrorCases -> Bool
  (do
    (checkJsxErr "<div></span>")
    (checkJsxErr "<div")
    (checkJsxErr "<>")
    (checkJsxErr "<div>{foo</div>")
    (checkJsxErr "<div id=\"unclosed />")
    (checkJsxErr "<div = />")
    (checkJsxErr "<div ? />")
    (checkJsxErr "<div 123 />")
    (checkJsxErr "<div foo= />")
    (checkJsxErr "<Foo.Bar></Foo.Baz>")
    (checkJsxErr "<svg:path></svg:g>")
    (checkJsxErr "</>")
    (checkJsxErr "<></div")
    true)

fn treeHasError? node: tr/Node -> Bool
  (if (tr/isErrorNode node)
    true
    (elementsHaveError? (tr/nodeChildren node)))

fn elementsHaveError? elems: (List tr/TreeElement) -> Bool
  (if (listEmpty? elems)
    false
    (let [(hd (optionOr (listHead elems) (tr/elemToken (tr/makeToken "" 0 0))))
          (tl (optionOr (listTail elems) (list)))]
      (mt hd
        ((tr/elemNode n) (if (treeHasError? n) true (elementsHaveError? tl)))
        ((tr/elemToken t) (if (tr/isErrorToken t) true (elementsHaveError? tl))))))

fn checkFileExactRoundTrip! path: String content: String -> Bool
  (let [(len (stringLength content))
        (parseRes (jsx/parse content))]
    (mt parseRes
      ((err msg)
       (do
         (println (str "PARSE ERROR [" path "]: " msg))
         false))
      ((ok root)
       (let [(printed (pr/printTreeString content root))
             (tiled (ok? (tr/checkTiling root len)))
             (hasErr (treeHasError? root))
             (exact (= printed content))]
         (do
           (if (not exact)
             (println (str "ROUNDTRIP MISMATCH [" path "]"))
             ())
           (if (not tiled)
             (println (str "TILING ERROR [" path "]"))
             ())
           (if hasErr
             (println (str "ERROR NODES IN TREE [" path "]"))
             ())
           (and exact (and tiled (not hasErr))))))))

fn printExclusions! prefix: String cases: (List (Pair String String)) -> Bool
  (if (listEmpty? cases)
    true
    (let [(head (optionOr (listHead cases) (pair "" "")))
          (tail (optionOr (listTail cases) (list)))]
      (do
        (println (str "  " prefix " excluded: " (pairFirst head) " (" (pairSecond head) ")"))
        (printExclusions! prefix tail))))

fn findExclusionReason path: String exclusions: (List (Pair String String)) -> (Option String)
  (if (listEmpty? exclusions)
    (none)
    (let [(head (optionOr (listHead exclusions) (pair "" "")))
          (tail (optionOr (listTail exclusions) (list)))]
      (if (= (pairFirst head) path)
        (some (pairSecond head))
        (findExclusionReason path tail))))

fn checkBabelJsxSuite! suiteName: String files: (List String) exclusions: (List (Pair String String)) runCount: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (println (str suiteName " suite: " (stringFromInt64 runCount) " run, " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printExclusions! suiteName exclusions)
      true)
    (let [(path (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (mt (findExclusionReason path exclusions)
        ((some _)
         (checkBabelJsxSuite! suiteName rest exclusions runCount passCount (+ excludedCount 1)))
        ((none)
         (let [(readRes (fileReadString path))]
           (if (not (ok? readRes))
             (do
               (assert false (str "read failed: " path))
               (checkBabelJsxSuite! suiteName rest exclusions (+ runCount 1) passCount excludedCount))
             (let [(content (resultOr readRes ""))
                   (pass? (checkFileExactRoundTrip! path content))]
               (do
                 (assert pass? (str "round-trip: " path))
                 (checkBabelJsxSuite! suiteName rest exclusions (+ runCount 1) (if pass? (+ passCount 1) passCount) excludedCount)))))))))

fn testUpstreamBabelJsx! -> Bool
  (checkBabelJsxSuite! "babel-jsx" (upstreamBabelFiles) (upstreamBabelExclusions) 0 0 0)

fn ! runTests -> Bool
  (do
    (assert (testSelfClosingElements!) "testSelfClosingElements")
    (assert (testElementsWithChildren!) "testElementsWithChildren")
    (assert (testFragments!) "testFragments")
    (assert (testAttributesAndSpreads!) "testAttributesAndSpreads")
    (assert (testTagNamesAndNamespaces!) "testTagNamesAndNamespaces")
    (assert (testExpressionContainers!) "testExpressionContainers")
    (assert (testNestedGenericsFreeCases!) "testNestedGenericsFreeCases")
    (assert (testVnodeEmitJsxRoundTrip) "testVnodeEmitJsxRoundTrip")
    (assert (testErrorCases) "testErrorCases")
    (assert (testUpstreamBabelJsx!) "upstream babel-jsx conformance suite")
    true)
fn upstreamBabelFiles -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/10.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/11.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/12.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/14.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/15.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/16.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/17.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/18.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/19.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/20.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/21.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/6.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/7.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/8.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/asi.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/empty-expression-container.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/entity.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/fragment-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/fragment-2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/fragment-3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/fragment-4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/fragment-5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/fragment-6.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/html-comment.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/jsx-text-closing-angle-bracket-wrapped.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/jsx-text-closing-curly-brace-wrapped.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/keyword-tag.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/namespace-tag.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/nonentity-decimal.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/nonentity.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/sequence-expression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/spread-text.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/yield-tag.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/html-entities/code-point-like-ampersand.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/html-entities/code-point.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/html-entities/html4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/html-entities/invalid.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/html-entities/no-object-prototype.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/6.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/7.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/issue-11387.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/issue-14552.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/issue-2083.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/issue-2114.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/issue-8891.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/nbsp.js.sample"
  )
fn upstreamBabelExclusions -> (List (Pair String String))
  (list
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/html-comment.js.sample" "HTML-style comment syntax (Annex B, out of scope for JSX)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/basic/16.js.sample" "JSX embedded in primary expression with binary operator (unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/babel-jsx/regression/issue-2083.js.sample" "JSX embedded in ternary conditional expression (unit S5)")
  )
