(module asl-syntax/tests/tsx/tsxTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/tsx :a tsx)
      (aslVdom/vdom :a v)
      (aslVdom/emitJsx :a emit)])

fn checkTsx! code: String -> Bool
  (let [(res (tsx/parseTsx code))]
    (do
      (assert (ok? res) (str "parseTsx succeeds: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= printed code) (println "ROUND TRIP DIFF for " code "
GOT: " printed "
WANT: " code) ())
          (assert (= printed code) (str "exact round-trip: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "exact tiling: " code))
          true))))

fn checkTsxModule! code: String -> Bool
  (let [(res (tsx/parseTsxModule code))]
    (do
      (assert (ok? res) (str "parseTsxModule succeeds: " code))
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= printed code) (println "ROUND TRIP DIFF for " code "
GOT: " printed "
WANT: " code) ())
          (assert (= printed code) (str "exact round-trip: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "exact tiling: " code))
          true))))

fn testGenericArrowFunctions! -> Bool
  (do
    (assert (checkTsx! "<T,>(x: T): T => x;") "generic arrow trailing comma")
    (assert (checkTsx! "<T extends unknown>(x: T): T => x;") "generic arrow extends")
    (assert (checkTsx! "<T, U>(x: T, y: U): T => x;") "generic arrow multi param")
    (assert (checkTsx! "<T,>() => 1;") "generic arrow no params")
    (assert (checkTsx! "const f = <T,>(x: T): T => x;") "const generic arrow")
    (assert (checkTsx! "export const f = <T,>(x: T): T => x;") "export const generic arrow")
    (let [(res (tsx/parseTsx "<T,>(x: T): T => x;"))]
      (mt res
        ((ok root)
         (assert (= (tsx/tsxNodeKind root) "arrowFunction") "arrowFunction node kind"))
        ((err _)
         (assert false "generic arrow should parse"))))
    (assert (checkTsx! "<T>(x: T): T => x;") "generic arrow single param without comma")
    true)

fn testNoAngleAssertions! -> Bool
  (do
    (let [(res (tsx/parseTsx "<string>x;"))]
      (mt res
        ((ok root)
         (assert false (str "expected angle assertion rejected, got: " (tsx/tsxNodeKind root))))
        ((err msg)
         (assert (= msg "Parse error at offset 0") (str "angle assertion rejected in tsx: " msg)))))
    (let [(resLet (tsx/parseTsx "let a = <string>x;"))]
      (mt resLet
        ((ok root)
         (assert false (str "expected let angle assertion rejected, got: " (tsx/tsxNodeKind root))))
        ((err msg)
         (assert (= msg "Parse error at offset 8") (str "let angle assertion rejected: " msg)))))
    (let [(resConst (tsx/parseTsx "const y = <number>z;"))]
      (mt resConst
        ((ok root)
         (assert false (str "expected const angle assertion rejected, got: " (tsx/tsxNodeKind root))))
        ((err msg)
         (assert (= msg "Parse error at offset 10") (str "const angle assertion rejected: " msg)))))
    (let [(resCall (tsx/parseTsx "foo(<boolean>bar);"))]
      (mt resCall
        ((ok root)
         (assert false (str "expected call arg angle assertion rejected, got: " (tsx/tsxNodeKind root))))
        ((err msg)
         (assert (= msg "Parse error at offset 4") (str "call arg angle assertion rejected: " msg)))))
    (let [(toks (lx/tokenize "<string>x"))
          (resExpr (tsx/parseTsxExpr toks "<string>x" 0))]
      (assert (= (tr/nodeKind resExpr.node) "error") "parseTsxExpr rejects angle assertion"))
    (assert (checkTsx! "x as string;") "as expression works in tsx")
    (assert (checkTsx! "const a = x as number;") "const with as expression")
    true)

fn testJsxInTsxExpressions! -> Bool
  (do
    (assert (checkTsx! "<div className=\"foo\"><span>hello</span></div>;") "jsx in tsx statement")
    (assert (checkTsx! "<>hello <b>world</b></>;") "jsx fragment in tsx")
    (assert (checkTsx! "const el = <div className=\"container\">hello</div>;") "const jsx element")
    (assert (checkTsx! "let a = 2;\na == 3 ? (a = <h1>123</h1>) : (a = <h1>abc</h1>);") "jsx in ternary")
    (assert (checkTsx! "<C<number>/>;") "jsx tag with type argument self-closing")
    (assert (checkTsx! "<C<number>></C>;") "jsx tag with type argument matching closing")
    (assert (checkTsx! "<Component<<T>(v: T) => void> />") "jsx tag with arrow function type argument")
    true)

fn testVnodeEmitTsxModuleRoundTrip! -> Bool
  (do
    (let [(t1 (v/textNode "Plain text content"))
          (code1 (emit/emitTsxModule "TextComp" "TextProps" t1))]
      (assert (checkTsxModule! code1) "emitTsxModule text node"))
    (let [(n2 (v/elementNode "div" (mapFromPairs [(pair "className" "container")]) (list (v/elementNode "h1" (mapEmpty) (list (v/textNode "Header"))) (v/elementNode "p" (mapFromPairs [(pair "id" "desc")]) (list (v/textNode "Paragraph text"))))))
          (code2 (emit/emitTsxModule "HeaderComp" "HeaderProps" n2))]
      (assert (checkTsxModule! code2) "emitTsxModule element tree"))
    (let [(n3 (v/elementNode "input" (mapFromPairs [(pair "type" "text") (pair "disabled" "true") (pair "placeholder" "Enter text...")]) (list)))
          (code3 (emit/emitTsxModule "InputComp" "InputProps" n3))]
      (assert (checkTsxModule! code3) "emitTsxModule void tag"))
    (let [(n4 (v/elementNode "Button" (mapFromPairs [(pair "onClick" "{handleClick}") (pair "disabled" "false")]) (list (v/textNode "Submit"))))
          (code4 (emit/emitTsxModule "ButtonComp" "ButtonProps" n4))]
      (assert (checkTsxModule! code4) "emitTsxModule component tag"))
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
  (let [(res (tsx/parseTsxModule content))]
    (if (not (ok? res))
      (do
        (println (str "PARSE ERROR on " path ": " (mt res ((ok _) "") ((err e) e))))
        false)
      (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
            (printed (pr/printTreeString content root))
            (tilingRes (tr/checkTiling root (stringLength content)))
            (match? (= printed content))
            (tiling? (ok? tilingRes))
            (noErrors? (not (treeHasError? root)))]
        (do
          (if (not match?) (println "MISMATCH on " path) ())
          (if (not tiling?) (println "BAD TILING on " path) ())
          (if (not noErrors?) (println "ERROR NODES on " path) ())
          (and match? (and tiling? noErrors?))))))

fn findExclusionReason path: String exclusions: (List (Pair String String)) -> (Option String)
  (if (listEmpty? exclusions)
    (none)
    (let [(hd (optionOr (listHead exclusions) (pair "" "")))
          (tail (optionOr (listTail exclusions) (list)))]
      (if (= (pairFirst hd) path)
        (some (pairSecond hd))
        (findExclusionReason path tail))))

fn printExclusions! suiteName: String exclusions: (List (Pair String String)) -> Bool
  (if (listEmpty? exclusions)
    true
    (let [(hd (optionOr (listHead exclusions) (pair "" "")))
          (tail (optionOr (listTail exclusions) (list)))]
      (do
        (println (str "  " suiteName " excluded: " (pairFirst hd) " (" (pairSecond hd) ")"))
        (printExclusions! suiteName tail))))

fn checkBabelTsxSuite! suiteName: String files: (List String) exclusions: (List (Pair String String)) runCount: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (println (str suiteName " suite: " (stringFromInt64 runCount) " run, " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printExclusions! suiteName exclusions)
      true)
    (let [(path (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (mt (findExclusionReason path exclusions)
        ((some _)
         (checkBabelTsxSuite! suiteName rest exclusions runCount passCount (+ excludedCount 1)))
        ((none)
         (let [(readRes (fileReadString path))]
           (if (not (ok? readRes))
             (do
               (assert false (str "read failed: " path))
               (checkBabelTsxSuite! suiteName rest exclusions (+ runCount 1) passCount excludedCount))
             (let [(content (resultOr readRes ""))
                   (pass? (checkFileExactRoundTrip! path content))]
               (do
                 (assert pass? (str "round-trip: " path))
                 (checkBabelTsxSuite! suiteName rest exclusions (+ runCount 1) (if pass? (+ passCount 1) passCount) excludedCount)))))))))

fn testUpstreamBabelTsx! -> Bool
  (checkBabelTsxSuite! "babel-tsx" (upstreamBabelTsxFiles) (upstreamBabelTsxExclusions) 0 0 0)

fn upstreamBabelTsxFiles -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/generic-tsx.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/anonymous-function-generator.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/assignment-in-conditional-expression.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/brace-is-block.tsx.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/type-arguments.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/type-parameters.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/jsx-opening-element-type-args.tsx.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/type-arguments-tsx.ts.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/arrow-function-generic-tsx-trailing-comma.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/babel-tsx/arrow-function-generic-tsx.js.sample")

fn upstreamBabelTsxExclusions -> (List (Pair String String))
  (list)

fn testUnclosedAnglesAndMalformedElements -> Bool
  (do
    (let [(res1 (tsx/parseTsx "<T"))]
      (mt res1
        ((ok _) (assert false "expected error for unclosed <T"))
        ((err msg) (assert (= msg "Parse error at offset 0") (str "unclosed <T: " msg)))))
    (let [(res2 (tsx/parseTsx "<div"))]
      (mt res2
        ((ok _) (assert false "expected error for unclosed <div"))
        ((err msg) (assert (= msg "Parse error at offset 0") (str "unclosed <div: " msg)))))
    (let [(res3 (tsx/parseTsx "<T extends"))]
      (mt res3
        ((ok _) (assert false "expected error for unclosed <T extends"))
        ((err msg) (assert (= msg "Parse error at offset 0") (str "unclosed <T extends: " msg)))))
    (let [(resElem1 (tsx/parseTsxElement "<div" 0))]
      (mt resElem1
        ((ok _) (assert false "expected error for parseTsxElement on <div"))
        ((err msg) (assert (= msg "Unclosed JSX element at offset 4") (str "parseTsxElement <div offset: " msg)))))
    (let [(resElem2 (tsx/parseTsxElement "<" 0))]
      (mt resElem2
        ((ok _) (assert false "expected error for parseTsxElement on <"))
        ((err msg) (assert (= msg "Expected tag name at offset 1") (str "parseTsxElement < offset: " msg)))))
    (let [(resElem3 (tsx/parseTsxElement "<Component<T" 0))]
      (mt resElem3
        ((ok _) (assert false "expected error for parseTsxElement on <Component<T"))
        ((err msg) (assert (= msg "Expected '>' or '/>' in tag at offset 10") (str "parseTsxElement unclosed type args: " msg)))))
    true)

fn ! runTests -> Bool
  (do
    (assert (testGenericArrowFunctions!) "testGenericArrowFunctions")
    (assert (testNoAngleAssertions!) "testNoAngleAssertions")
    (assert (testJsxInTsxExpressions!) "testJsxInTsxExpressions")
    (assert (testVnodeEmitTsxModuleRoundTrip!) "testVnodeEmitTsxModuleRoundTrip")
    (assert (testUpstreamBabelTsx!) "testUpstreamBabelTsx")
    (assert (testUnclosedAnglesAndMalformedElements) "testUnclosedAnglesAndMalformedElements")
    true)
