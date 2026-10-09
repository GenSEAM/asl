(module asl-syntax/tests/js/coverTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)])
fn checkExpr! code: String expectedSExpr: String -> Bool
  (let [(parseRes (cv/parse code))]
    (do
      (assert (ok? parseRes) (str "parse succeeds: " code))
      (let [(root (resultOr parseRes (tr/makeErrorNode 0 0 (list))))
            (unwrapped (cv/unwrapExpressionNode root))
            (sexpr (cv/coverToSExpr unwrapped code))
            (printed (pr/printTreeString code root))]
        (do
          (do (if (!= sexpr expectedSExpr) (println (str "MISMATCH for " code "\n  GOT:      " sexpr "\n  EXPECTED: " expectedSExpr)) ()) (assert (= sexpr expectedSExpr) (str "sexpr matches: " code)))
          (assert (= printed code) (str "round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "tiling exact: " code))
          true))))
fn testArrowFunctions! -> Bool
  (do
    (let [(code "() => { return 1;")
          (res (cv/parse code))]
      (refute (ok? res) "unclosed block body at EOF is rejected"))
    (let [(code "(1 + 2) => x")
          (res (cv/parse code))]
      (refute (ok? res) "invalid parameter expression (1 + 2) => x is rejected"))
    (assert (checkExpr! "x => x + 1" "(arrow (params x) (+ x 1))") "arrow ident")
    (assert (checkExpr! "(x) => x + 1" "(arrow (params x) (+ x 1))") "arrow single paren")
    (assert (checkExpr! "() => 42" "(arrow (params) 42)") "arrow zero params")
    (assert (checkExpr! "(a, b) => a + b" "(arrow (params a b) (+ a b))") "arrow two params")
    (assert (checkExpr! "(a = 1, b = 2) => a + b" "(arrow (params (= a 1) (= b 2)) (+ a b))") "arrow default params")
    (assert (checkExpr! "(...rest) => rest" "(arrow (params (... rest)) rest)") "arrow rest param")
    (assert (checkExpr! "(a, ...b) => b" "(arrow (params a (... b)) b)") "arrow param and rest")
    (assert (checkExpr! "([a, b], {c}) => a + b + c" "(arrow (params (arrayPattern a b) (objectPattern c)) (+ (+ a b) c))") "arrow destructuring params")
    (assert (checkExpr! "(x) => { return x; }" "(arrow (params x) (block))") "arrow block body")
    (assert (checkExpr! "x => y => x + y" "(arrow (params x) (arrow (params y) (+ x y)))") "nested arrows")
    true)
fn testArrowVsParenExpr -> Bool
  (do
    (let [(code "(x)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse (x)")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (n (cv/unwrapExpressionNode root))]
          (do
            (assert (= (tr/nodeKind n) "parenExpr") "(x) is parenExpr")
            (refute (= (tr/nodeKind n) "arrowFunction") "(x) is not arrowFunction")
            (assert (= (pr/printTreeString code root) code) "(x) round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "(x) tiling")))))
    (let [(code "(a, b)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse (a, b)")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (n (cv/unwrapExpressionNode root))]
          (do
            (assert (= (tr/nodeKind n) "parenExpr") "(a, b) is parenExpr")
            (refute (= (tr/nodeKind n) "arrowFunction") "(a, b) is not arrowFunction")
            (assert (= (pr/printTreeString code root) code) "(a, b) round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "(a, b) tiling")))))
    (let [(code "(a = 1)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse (a = 1)")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (n (cv/unwrapExpressionNode root))]
          (do
            (assert (= (tr/nodeKind n) "parenExpr") "(a = 1) is parenExpr")
            (refute (= (tr/nodeKind n) "arrowFunction") "(a = 1) is not arrowFunction")
            (assert (= (pr/printTreeString code root) code) "(a = 1) round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "(a = 1) tiling")))))
    (let [(code "()")
          (res (cv/parse code))]
      (refute (ok? res) "empty parens () alone is not a valid expression"))
    (let [(code "(...a)")
          (res (cv/parse code))]
      (refute (ok? res) "(...a) alone is not a valid expression"))
    (let [(code "(a, b)\n=> c")
          (res (cv/parse code))]
      (refute (ok? res) "newline before => in parenthesized params is rejected"))
    (let [(code "x\n=> x")
          (res (cv/parse code))]
      (refute (ok? res) "newline before => in ident param is rejected"))
    true)
fn testAsyncArrowFunctions! -> Bool
  (do
    (assert (checkExpr! "async x => x" "(asyncArrow (params x) x)") "async arrow ident")
    (assert (checkExpr! "async () => 42" "(asyncArrow (params) 42)") "async arrow zero params")
    (assert (checkExpr! "async (x) => x" "(asyncArrow (params x) x)") "async arrow single paren")
    (assert (checkExpr! "async (a, b) => a + b" "(asyncArrow (params a b) (+ a b))") "async arrow two params")
    (assert (checkExpr! "async (x) => { return x; }" "(asyncArrow (params x) (block))") "async arrow block body")
    (let [(code "async\nx => x")
          (res (cv/parse code))]
      (refute (ok? res) "newline after async is not async arrow"))
    true)
fn testObjectPatternVsLiteral -> Bool
  (do
    (let [(code "{ a: 1, b: 2 }")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse object literal")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (n (cv/unwrapExpressionNode root))]
          (do
            (assert (= (tr/nodeKind n) "objectLiteral") "{ a: 1, b: 2 } is objectLiteral")
            (refute (cv/isValidPattern n) "{ a: 1, b: 2 } is not valid pattern")
            (assert (err? (cv/refineToPattern n)) "refine { a: 1, b: 2 } fails")
            (assert (= (pr/printTreeString code root) code) "{ a: 1, b: 2 } round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "{ a: 1, b: 2 } tiling")))))
    (let [(code "({ a: b } = obj)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse ({ a: b } = obj)")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "({ a: b } = obj) round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "({ a: b } = obj) tiling")))))
    (let [(code "({ a } = obj)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse ({ a } = obj)")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "({ a } = obj) round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "({ a } = obj) tiling")))))
    (let [(code "({ a = 1, b = 2 } = obj)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse ({ a = 1, b = 2 } = obj)")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "({ a = 1, b = 2 } = obj) round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "({ a = 1, b = 2 } = obj) tiling")))))
    (let [(code "({ ...rest } = obj)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse ({ ...rest } = obj)")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "({ ...rest } = obj) round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "({ ...rest } = obj) tiling")))))
    (let [(code "{ a: 1 + 2 } = obj")
          (res (cv/parse code))]
      (refute (ok? res) "invalid destructuring target rejected"))
    true)
fn testArrayPatternVsLiteral -> Bool
  (do
    (let [(code "[1, 2, 3]")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse array literal")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (n (cv/unwrapExpressionNode root))]
          (do
            (assert (= (tr/nodeKind n) "arrayLiteral") "[1, 2, 3] is arrayLiteral")
            (refute (cv/isValidPattern n) "[1, 2, 3] is not valid pattern")
            (assert (err? (cv/refineToPattern n)) "refine [1, 2, 3] fails")
            (assert (= (pr/printTreeString code root) code) "[1, 2, 3] round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "[1, 2, 3] tiling")))))
    (let [(code "[a, b] = [1, 2]")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse [a, b] = [1, 2]")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "[a, b] = [1, 2] round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "[a, b] = [1, 2] tiling")))))
    (let [(code "[a = 1, ...b] = c")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse [a = 1, ...b] = c")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "[a = 1, ...b] = c round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "[a = 1, ...b] = c tiling")))))
    (let [(code "[a, , b] = c")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse [a, , b] = c")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "[a, , b] = c round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "[a, , b] = c tiling")))))
    (let [(code "[[a, b], c] = d")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse [[a, b], c] = d")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (printed (pr/printTreeString code root))]
          (do
            (assert (= printed code) "[[a, b], c] = d round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "[[a, b], c] = d tiling")))))
    (let [(code "[123] = x")
          (res (cv/parse code))]
      (refute (ok? res) "literal target in array pattern rejected"))
    true)
fn testSpreadAndRest! -> Bool
  (do
    (assert (checkExpr! "f(...args)" "(call f (... args))") "call with spread")
    (assert (checkExpr! "[...a, 1]" "(array (... a) 1)") "array with spread")
    (assert (checkExpr! "{ ...a, b: 1 }" "(object (... a) (:prop b 1))") "object with spread")
    (assert (checkExpr! "(...args) => args" "(arrow (params (... args)) args)") "arrow with rest param")
    true)
fn checkExprAsync code: String expected: String -> Bool
  (let [(res (cv/parseAsync code))]
    (mt res
      ((ok root)
       (let [(exprNode (cv/unwrapExpressionNode root))
             (sexpr (cv/coverToSExpr exprNode code))]
         (= sexpr expected)))
      ((err _) false)))

fn checkExprGenerator code: String expected: String -> Bool
  (let [(res (cv/parseGenerator code))]
    (mt res
      ((ok root)
       (let [(exprNode (cv/unwrapExpressionNode root))
             (sexpr (cv/coverToSExpr exprNode code))]
         (= sexpr expected)))
      ((err _) false)))

fn testAsyncAwaitYieldClass! -> Bool
  (do
    (assert (checkExpr! "class {}" "(class (body))") "anonymous class")
    (assert (checkExpr! "class Foo {}" "(class Foo (body))") "named class")
    (assert (checkExpr! "class Foo extends Bar {}" "(class Foo (extends Bar) (body))") "class extends")
    (assert (checkExpr! "class Foo { bar() { return 1; } }" "(class Foo (body (method bar (params) (block))))") "class with method")
    (assert (checkExpr! "class Foo { get x() { return 1; } set x(v) {} }" "(class Foo (body (get x (params) (block)) (set x (params v) (block))))") "class getter setter")
    (assert (checkExpr! "class Foo { static x = 1; #priv = 2; }" "(class Foo (body (field static x 1) (field #priv 2)))") "class static and private")
    (assert (checkExpr! "class Foo { x; y = 1; static z; static w = 2; }" "(class Foo (body (field x) (field y 1) (field static z) (field static w 2)))") "class fields with and without initializers, static")
    (assert (checkExpr! "class Foo { static { stmt(); } }" "(class Foo (body (staticBlock (block))))") "class static block")
    (assert (checkExpr! "class Foo { static bar() {} }" "(class Foo (body (method static bar (params) (block))))") "class static method")
    (assert (checkExpr! "class Foo { static get a() {} static set a(v) {} }" "(class Foo (body (get static a (params) (block)) (set static a (params v) (block))))") "class static getter setter")
    (assert (checkExpr! "class Foo { ; x = 1; ; }" "(class Foo (body (field x 1)))") "class body with semicolons")
    true)

fn test262Exclusions -> (List (Pair String String))
  (list
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/position-invalid.js.sample" "rest parameter cannot be followed by another parameter (negative parse case)"))

fn printTest262Exclusions! cases: (List (Pair String String)) -> Bool
  (if (listEmpty? cases)
    true
    (let [(head (optionOr (listHead cases) (pair "" "")))
          (tail (optionOr (listTail cases) (list)))]
      (do
        (println (str "  test262 excluded: " (pairFirst head) " (" (pairSecond head) ")"))
        (printTest262Exclusions! tail))))

fn test262ExclusionReason path: String exclusions: (List (Pair String String)) -> (Option String)
  (if (listEmpty? exclusions)
    (none)
    (let [(head (optionOr (listHead exclusions) (pair "" "")))
          (tail (optionOr (listTail exclusions) (list)))]
      (if (= (pairFirst head) path)
        (some (pairSecond head))
        (test262ExclusionReason path tail))))

fn test262Files -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-bindingidentifier-concisebody-assignmentexpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-bindingidentifier-concisebody-functionbody.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-cover-concisebody-assignmentexpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-cover-initialize-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-cover-rest-concisebody-functionbody.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/expression-body-implicit-return.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/params-trailing-comma-single.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-elements-with-initializer.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-elements-with-object-patterns.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-elements-without-initializer.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-pattern-with-elisions.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-rest-elements.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/object-pattern-with-no-property-list.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/property-list-bindings-elements.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/recursive-array-and-object-patterns.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-empty.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-expr.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-iter.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-literal.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-obj-getter-init.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-obj-null.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/array-pattern.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/arrow-function.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/expected-argument-count.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/no-alias-arguments.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/object-pattern.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/position-invalid.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/arrow-returns-promise.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-binding-identifier.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-identifier-reference.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/async-await-interleaved.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/await-in-function.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/syntax-await-has-UnaryExpression-with-MultiplicativeExpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/syntax-await-has-UnaryExpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/captured-free-vars.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/formal-parameters.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/from-catch.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/from-try.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/in-iteration-stmt.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/in-rltn-expr.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-2.js.sample")

fn checkTest262Files! files: (List String) runCount: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (println (str "test262 cover suite: " (stringFromInt64 runCount) " run, " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printTest262Exclusions! (test262Exclusions))
      (assert (= (+ runCount excludedCount) 47) "all 47 test262 cases accounted for")
      (assert (= runCount 46) "46 test262 cases executed")
      (assert (= passCount 46) "46 test262 cases passed")
      (assert (= excludedCount 1) "1 test262 cases excluded with documented reasons")
      true)
    (let [(path (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (mt (test262ExclusionReason path (test262Exclusions))
        ((some _)
         (checkTest262Files! rest runCount passCount (+ excludedCount 1)))
        ((none)
         (let [(readRes (fileReadString path))]
           (do
             (assert (ok? readRes) (str "readable test262 file: " path))
             (let [(content (resultOr readRes ""))
                   (len (stringLength content))
                   (node (cv/parseText content))]
               (do
                 (assert (ok? (tr/checkTiling node len)) (str "tokens tile: " path))
                 (let [(printed (pr/printTreeString content node))]
                   (do
                     (assert (= printed content) (str "byte exact round-trip: " path))
                     (checkTest262Files! rest (+ runCount 1) (+ passCount 1) excludedCount)))))))))))

fn testPinnedtest262Cases! -> Bool
  (checkTest262Files! (test262Files) 0 0 0)

fn testNestedDestructuringWithDefaults -> Bool
  (do
    (let [(code "({ a: { b = 1 } } = x)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse nested object pattern with default")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (node (cv/unwrapExpressionNode root))
              (kids (tr/nodeChildren node))
              (childNodes (cv/findChildNodes kids))
              (assignPat (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))))
              (patKids (tr/nodeChildren assignPat))
              (patChildNodes (cv/findChildNodes patKids))
              (objPat (optionOr (listHead patChildNodes) (tr/makeErrorNode 0 0 (list))))
              (props (cv/findChildNodes (tr/nodeChildren objPat)))
              (prop (optionOr (listHead props) (tr/makeErrorNode 0 0 (list))))
              (propKids (cv/findChildNodes (tr/nodeChildren prop)))
              (nestedVal (optionOr (listLast propKids) (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (tr/nodeKind nestedVal) "objectPattern") "nested destructuring is objectPattern")
            (assert (= (pr/printTreeString code root) code) "nested object pattern round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "nested object pattern tiling")))))
    (let [(code "({ a: [b = 1] } = x)")
          (res (cv/parse code))]
      (do
        (assert (ok? res) "parse nested array pattern with default")
        (let [(root (resultOr res (tr/makeErrorNode 0 0 (list))))
              (node (cv/unwrapExpressionNode root))
              (kids (tr/nodeChildren node))
              (childNodes (cv/findChildNodes kids))
              (assignPat (optionOr (listHead childNodes) (tr/makeErrorNode 0 0 (list))))
              (patKids (tr/nodeChildren assignPat))
              (patChildNodes (cv/findChildNodes patKids))
              (objPat (optionOr (listHead patChildNodes) (tr/makeErrorNode 0 0 (list))))
              (props (cv/findChildNodes (tr/nodeChildren objPat)))
              (prop (optionOr (listHead props) (tr/makeErrorNode 0 0 (list))))
              (propKids (cv/findChildNodes (tr/nodeChildren prop)))
              (nestedVal (optionOr (listLast propKids) (tr/makeErrorNode 0 0 (list))))]
          (do
            (assert (= (tr/nodeKind nestedVal) "arrayPattern") "nested destructuring is arrayPattern")
            (assert (= (pr/printTreeString code root) code) "nested array pattern round-trip")
            (assert (ok? (tr/checkTiling root (stringLength code))) "nested array pattern tiling")))))
    true)

fn testRestAndSpreadPositions -> Bool
  (do
    (let [(code "[...a, b] = c")
          (res (cv/parse code))]
      (refute (ok? res) "non-trailing rest in array pattern is rejected"))
    (let [(code "({ ...a, b } = c)")
          (res (cv/parse code))]
      (refute (ok? res) "non-trailing rest in object pattern is rejected"))
    (let [(code "(...a, b) => c")
          (res (cv/parse code))]
      (refute (ok? res) "non-trailing rest in parameter list is rejected"))
    (let [(code "[a, ...b] = c")
          (res (cv/parse code))]
      (assert (ok? res) "trailing rest in array pattern is accepted"))
    (let [(code "({ a, ...b } = c)")
          (res (cv/parse code))]
      (assert (ok? res) "trailing rest in object pattern is accepted"))
    (let [(code "(a, ...b) => c")
          (res (cv/parse code))]
      (assert (ok? res) "trailing rest in parameter list is accepted"))
    (let [(code "[...a, b]")
          (res (cv/parse code))]
      (assert (ok? res) "spread anywhere in array literal is accepted"))
    (let [(code "f(...a, b)")
          (res (cv/parse code))]
      (assert (ok? res) "spread anywhere in call arguments is accepted"))
    true)

fn testContextDependentYieldAndAwait! -> Bool
  (do
    (assert (checkExpr! "await + 1" "(+ await 1)") "await as identifier outside async")
    (assert (checkExpr! "yield + 1" "(+ yield 1)") "yield as identifier outside generator")
    (assert (checkExpr! "x = await" "(= x await)") "await as variable outside async")
    (assert (checkExpr! "x = yield" "(= x yield)") "yield as variable outside generator")
    (assert (checkExpr! "await(42)" "(call await 42)") "await call outside async")
    (assert (checkExpr! "yield(42)" "(call yield 42)") "yield call outside generator")
    (assert (checkExpr! "async x => await x" "(asyncArrow (params x) (await x))") "await inside async arrow")
    (assert (checkExprAsync "await x" "(await x)") "await inside async context")
    (assert (checkExprAsync "await f()" "(await (call f))") "await call inside async context")
    (assert (checkExprAsync "1 + await x" "(+ 1 (await x))") "1 + await x inside async context")
    (assert (checkExprGenerator "yield" "(yield)") "bare yield inside generator")
    (assert (checkExprGenerator "yield 42" "(yield 42)") "yield 42 inside generator")
    (assert (checkExprGenerator "yield* gen()" "(yield* (call gen))") "yield* inside generator")
    (assert (checkExprGenerator "x = yield 1" "(= x (yield 1))") "x = yield 1 inside generator")
    true)

fn ! runTests -> Bool
  (do
    (assert (testContextDependentYieldAndAwait!) "context-dependent yield and await")
    (assert (testRestAndSpreadPositions) "rest and spread positions")
    (assert (testNestedDestructuringWithDefaults) "nested destructuring with defaults")
    (assert (testPinnedtest262Cases!) "pinned test262 cases")
    (assert (testArrowFunctions!) "arrow functions")
    (assert (testArrowVsParenExpr) "arrow vs parenExpr")
    (assert (testAsyncArrowFunctions!) "async arrow functions")
    (assert (testObjectPatternVsLiteral) "object pattern vs literal")
    (assert (testArrayPatternVsLiteral) "array pattern vs literal")
    (assert (testSpreadAndRest!) "spread and rest")
    (assert (testAsyncAwaitYieldClass!) "async await yield class")
    true)
