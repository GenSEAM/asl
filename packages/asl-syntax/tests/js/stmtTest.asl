(module asl-syntax/tests/js/stmtTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/js/lex :a lx)
      (asl-syntax/js/expr :a expr)
      (asl-syntax/js/cover :a cv)
      (asl-syntax/js/stmt :a stmt)])

fn checkScript! code: String expectedSExpr: String -> Bool
  (let [(parseRes (stmt/parse code))]
    (do
      (assert (ok? parseRes) (str "parse succeeds: " code))
      (let [(root (resultOr parseRes (tr/makeErrorNode 0 0 (list))))
            (sexpr (stmt/stmtToSExpr root code))
            (printed (pr/printTreeString code root))]
        (do
          (if (!= sexpr expectedSExpr)
            (println (str "MISMATCH for " code "\n  GOT:      " sexpr "\n  EXPECTED: " expectedSExpr))
            ())
          (assert (= sexpr expectedSExpr) (str "sexpr matches: " code))
          (assert (= printed code) (str "round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "tiling exact: " code))
          true))))

fn checkScriptRoundTripOnly code: String -> Bool
  (let [(parseRes (stmt/parse code))]
    (do
      (assert (ok? parseRes) (str "parse succeeds: " code))
      (let [(root (resultOr parseRes (tr/makeErrorNode 0 0 (list))))
            (printed (pr/printTreeString code root))]
        (do
          (assert (= printed code) (str "round-trip exact: " code))
          (assert (ok? (tr/checkTiling root (stringLength code))) (str "tiling exact: " code))
          true))))


fn testAsiYieldGenerator! -> Bool
  (let [(code "function* g() {\n  yield\n  1;\n}")
        (parseRes (stmt/parse code))]
    (do
      (assert (ok? parseRes) "ASI yield parse ok")
      (let [(root (resultOr parseRes (tr/makeErrorNode 0 0 (list))))
            (sexpr (stmt/stmtToSExpr root code))
            (kids (stmt/findChildNodes (tr/nodeChildren root)))
            (genNode (optionOr (listHead kids) (tr/makeErrorNode 0 0 (list))))
            (genKids (stmt/findChildNodes (tr/nodeChildren genNode)))
            (blockNode (optionOr (listGet genKids 1) (tr/makeErrorNode 0 0 (list))))
            (blockStmts (stmt/findChildNodes (tr/nodeChildren blockNode)))]
        (do
          (assert (= sexpr "(script (generator g (params) (block (expr (yield)) (expr 1))))") "ASI yield sexpr")
          (assert (= (listLength blockStmts) 2) "block has two statements")
          (let [(s1 (optionOr (listHead blockStmts) (tr/makeErrorNode 0 0 (list))))
                (s2 (optionOr (listGet blockStmts 1) (tr/makeErrorNode 0 0 (list))))]
            (do
              (assert (= (tr/nodeKind s1) "exprStmt") "s1 is exprStmt")
              (assert (= (tr/nodeKind s2) "exprStmt") "s2 is exprStmt")
              (let [(s1Kids (stmt/findChildNodes (tr/nodeChildren s1)))
                    (yNode (optionOr (listHead s1Kids) (tr/makeErrorNode 0 0 (list))))]
                (assert (= (tr/nodeKind yNode) "yieldExpr") "yNode is yieldExpr"))))
          (assert (checkScript! code "(script (generator g (params) (block (expr (yield)) (expr 1))))") "round-trip ASI yield")
          (assert (checkScript! "function* g() {\n  yield\n  next();\n}" "(script (generator g (params) (block (expr (yield)) (expr (call next)))))") "ASI yield newline with call")
          (assert (checkScript! "async function* ag() {\n  yield\n  await 1;\n}" "(script (asyncGenerator ag (params) (block (expr (yield)) (expr (await 1)))))") "ASI yield newline in async generator")
          true))))

fn testAsiFixtures! -> Bool
  (do
    (assert (testAsiYieldGenerator!) "ASI yield in generators")
    (assert (checkScript! "return\n1;" "(script (return) (expr 1))") "ASI return newline")
    (assert (checkScript! "return 1;" "(script (return 1))") "return 1;")
    (assert (checkScript! "return;" "(script (return))") "return;")
    (assert (checkScript! "return" "(script (return))") "return at EOF")
    (assert (checkScript! "a\n++\nb" "(script (expr a) (expr (++ b)))") "ASI ++ newline")
    (assert (checkScript! "++\na" "(script (expr (++ a)))") "newline before prefix ++")
    (assert (checkScript! "a++\nb" "(script (expr (post++ a)) (expr b))") "a++ newline b")
    (assert (checkScript! "break\nlbl;" "(script (break) (expr lbl))") "ASI break newline")
    (assert (checkScript! "break lbl;" "(script (break lbl))") "break lbl;")
    (assert (checkScript! "continue\nlbl;" "(script (continue) (expr lbl))") "ASI continue newline")
    (assert (checkScript! "continue lbl;" "(script (continue lbl))") "continue lbl;")
    (assert (checkScript! "let a = 1\nlet b = 2" "(script (let (= a 1)) (let (= b 2)))") "ASI varDecl")
    (assert (checkScriptRoundTripOnly "do {} while (false)\nx = 1;") "ASI do-while")
    (let [(code "throw\n1;")
          (res (stmt/parse code))]
      (refute (ok? res) "throw with newline before expr is rejected"))
    true)

fn testClassMemberFixtures! -> Bool
  (do
    (assert (checkScript! "class Foo {}" "(script (class Foo (body)))") "empty class decl")
    (assert (checkScript! "class Foo extends Bar {}" "(script (class Foo (extends Bar) (body)))") "class extends")
    (assert (checkScript! "class Foo { x = 1; }" "(script (class Foo (body (field x 1))))") "class field")
    (assert (checkScript! "class Foo { #x; #y = 1; }" "(script (class Foo (body (field #x) (field #y 1))))") "class private fields")
    (assert (checkScript! "class Foo { m() { return 1; } }" "(script (class Foo (body (method m (params) (block)))))") "class method")
    (assert (checkScript! "class Foo { #m() { return 1; } }" "(script (class Foo (body (method #m (params) (block)))))") "class private method")
    (assert (checkScript! "class Foo { get x() { return 1; } set x(v) {} }" "(script (class Foo (body (get x (params) (block)) (set x (params v) (block)))))") "class accessors")
    (assert (checkScript! "class Foo { get #x() { return 1; } set #x(v) {} }" "(script (class Foo (body (get #x (params) (block)) (set #x (params v) (block)))))") "class private accessors")
    (assert (checkScript! "class Foo { static get x() {} static set x(v) {} }" "(script (class Foo (body (get static x (params) (block)) (set static x (params v) (block)))))") "class static accessors")
    (assert (checkScript! "class Foo { static #priv = 42; static #m() {} }" "(script (class Foo (body (field static #priv 42) (method static #m (params) (block)))))") "class static private members")
    (assert (checkScript! "class Foo { static { doWork(); } }" "(script (class Foo (body (staticBlock (block)))))") "class static block")
    (assert (checkScriptRoundTripOnly "class Foo { [foo]() {} [bar] = 1; }") "class computed members")
    (assert (checkScript! "class Foo { async m() {} *g() {} async *ag() {} }" "(script (class Foo (body (method m (params) (block)) (method g (params) (block)) (method ag (params) (block)))))") "class async generator methods")
    true)

fn testStatements! -> Bool
  (do
    (assert (checkScript! "var a = 1, b = 2;" "(script (var (= a 1) (= b 2)))") "var decl multiple")
    (assert (checkScript! "const z = 3;" "(script (const (= z 3)))") "const decl")
    (assert (checkScript! "let [a, b] = [1, 2];" "(script (let (= (arrayPattern a b) (array 1 2))))") "destructuring array")
    (assert (checkScript! "const {c, d: e = 4} = obj;" "(script (const (= (objectPattern c d: e = 4) obj)))") "destructuring object")
    (assert (checkScript! "function f(x) { return x; }" "(script (function f (params x) (block (return x))))") "function decl")
    (assert (checkScript! "function* g() { yield 1; }" "(script (generator g (params) (block (expr (yield 1)))))") "generator decl")
    (assert (checkScript! "async function af() { await 1; }" "(script (asyncFunction af (params) (block (expr (await 1)))))") "async function decl")
    (assert (checkScript! "async function* ag() { yield await 1; }" "(script (asyncGenerator ag (params) (block (expr (yield (await 1))))))") "async generator decl")
    (assert (checkScript! "if (a) b(); else c();" "(script (if a (expr (call b)) (expr (call c))))") "if else")
    (assert (checkScript! "if (x) { y(); }" "(script (if x (block (expr (call y)))))") "if no else")
    (assert (checkScript! "while (x) { y(); }" "(script (while x (block (expr (call y)))))") "while loop")
    (assert (checkScript! "do { x(); } while (y);" "(script (doWhile (block (expr (call x))) y))") "do while loop")
    (assert (checkScript! "for (var x in obj) { process(x); }" "(script (forIn (var x) obj (block (expr (call process x)))))") "for in loop")
    (assert (checkScript! "for (const x of arr) { process(x); }" "(script (forOf (const x) arr (block (expr (call process x)))))") "for of loop")
    (assert (checkScript! "for await (const chunk of stream) { process(chunk); }" "(script (forAwaitOf (const chunk) stream (block (expr (call process chunk)))))") "for await of loop")
    (assert (checkScript! "for (;;) break;" "(script (for (break)))") "for empty parts")
    (assert (checkScript! "for (let i = 0; i < 10; i++) { sum += i; }" "(script (for (let (= i 0)) (< i 10) (post++ i) (block (expr (+= sum i)))))") "standard for loop")
    (assert (checkScript! "switch (x) { case 1: a(); break; default: b(); }" "(script (switch x (case 1 (expr (call a)) (break)) (default (expr (call b)))))") "switch stmt")
    (assert (checkScript! "try { a(); } catch (e) { b(); }" "(script (try (block (expr (call a))) (catch e (block (expr (call b))))))") "try catch")
    (assert (checkScript! "try { a(); } catch { b(); }" "(script (try (block (expr (call a))) (catch (block (expr (call b))))))") "try catch no binding")
    (assert (checkScript! "try { a(); } finally { c(); }" "(script (try (block (expr (call a))) (finally (block (expr (call c))))))") "try finally")
    (assert (checkScript! "try { a(); } catch (e) { b(); } finally { c(); }" "(script (try (block (expr (call a))) (catch e (block (expr (call b)))) (finally (block (expr (call c))))))") "try catch finally")
    (assert (checkScript! "with (ctx) { run(); }" "(script (with ctx (block (expr (call run)))))") "with stmt")
    (assert (checkScript! "debugger;" "(script (debugger))") "debugger stmt")
    (assert (checkScript! "loop: for (;;) { break loop; }" "(script (label loop (for (block (break loop)))))") "labeled stmt")
    (assert (checkScript! ";" "(script (;))") "empty stmt")
    (assert (checkScript! "{ let x = 1; { let y = 2; } }" "(script (block (let (= x 1)) (block (let (= y 2)))))") "nested block stmt")
    true)

fn test262Exclusions -> (List (Pair String String))
  (list
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-3.js.sample" "computed name interpreted as index (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-4.js.sample" "computed name interpreted as index (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-1.js.sample" "two field declarations on same line without separator (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-2.js.sample" "two field declarations on same line without separator (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/function-body.js.sample" "hashbang comment inside function body (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/preceding-whitespace.js.sample" "hashbang comment preceded by whitespace (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/statement-block.js.sample" "hashbang comment inside block (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-else.js.sample" "reserved word else as identifier (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-if.js.sample" "reserved word if as identifier (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-while.js.sample" "reserved word while as identifier (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/7.8.3-3gs.js.sample" "octal integer literal in strict mode (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1.js.sample" "unclosed regex literal across line terminator (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1gs.js.sample" "unclosed regex literal across line terminator (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-2gs.js.sample" "unclosed regex literal across line terminator (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T2.js.sample" "unclosed regex literal (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T4.js.sample" "unclosed regex literal (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T5.js.sample" "unclosed regex literal (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/position-invalid.js.sample" "rest parameter cannot be followed by another parameter (negative parse case, unit S5)"))

fn trackedJsExclusions -> (List (Pair String String))
  (list
    (pair "asl/packages/asl-syntax/tests/fixtures/js/vitePluginAsl.js.sample" "uses import/export module declarations owned by unit S4 (module.asl)")
    (pair "asl/packages/asl-syntax/tests/fixtures/js/tailwind.config.js.sample" "uses import/export module declarations owned by unit S4 (module.asl)")
    (pair "asl/packages/asl-syntax/tests/fixtures/js/vite.config.js.sample" "uses import/export module declarations owned by unit S4 (module.asl)"))

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

fn test262Files -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-bindingidentifier-concisebody-assignmentexpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-bindingidentifier-concisebody-functionbody.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-cover-concisebody-assignmentexpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-cover-initialize-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/arrowparameters-cover-rest-concisebody-functionbody.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/expression-body-implicit-return.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/arrow/params-trailing-comma-single.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/arrow-returns-promise.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-binding-identifier.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-identifier-reference.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/async-await-interleaved.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/await-in-function.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/syntax-await-has-UnaryExpression-with-MultiplicativeExpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/await/syntax-await-has-UnaryExpression.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A4_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/S7.4_A4_T3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/function-body.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/preceding-whitespace.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/statement-block.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-elements-with-initializer.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-elements-with-object-patterns.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-elements-without-initializer.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-pattern-with-elisions.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/array-rest-elements.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/object-pattern-with-no-property-list.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/property-list-bindings-elements.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/destructuring/recursive-array-and-object-patterns.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_continue-escaped.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_continue.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_start-escaped.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/other_id_start.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/part-digits-via-escape-hex.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/part-digits-via-escape-hex4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-else.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-if.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-while.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/7.3-15.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/7.3-5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/7.3-6.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A5.4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/line-terminators/S7.3_A7_T4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/7.8.3-3gs.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/S7.8.3_A1.2_T5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1gs.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-2gs.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T5.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/array-pattern.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/arrow-function.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/expected-argument-count.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/no-alias-arguments.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/object-pattern.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/position-invalid.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-empty.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-expr.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-iter.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-mult-literal.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-obj-getter-init.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/spread/spread-obj-null.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A2.3_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A4.1_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A4.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/string/S7.8.4_A4.2_T1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/evaluation-order.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-abrupt.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-function.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-member-expr.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-method.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-obj.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-primitive.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/template/literal-expr-template.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.3_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.4_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A2.5_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A3.1_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A3.2_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/white-space/S7.2_A3.3_T2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/captured-free-vars.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/formal-parameters.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/from-catch.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/from-try.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/in-iteration-stmt.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/in-rltn-expr.js.sample")

fn trackedJsFiles -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/js/vitePluginAsl.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/js/tailwind.config.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/js/vite.config.js.sample"
    "tests/harnessBench/cases/attention-flood/svc/vendor/uploader.min.js")

fn checkFileSuite! suiteName: String files: (List String) exclusions: (List (Pair String String)) runCount: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (println (str suiteName " suite: " (stringFromInt64 runCount) " run, " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printExclusions! suiteName exclusions)
      true)
    (let [(path (optionOr (listHead files) ""))
          (rest (optionOr (listTail files) (list)))]
      (mt (findExclusionReason path exclusions)
        ((some _)
         (checkFileSuite! suiteName rest exclusions runCount passCount (+ excludedCount 1)))
        ((none)
         (let [(readRes (fileReadString path))]
           (do
             (assert (ok? readRes) (str "readable " suiteName " file: " path))
             (let [(content (resultOr readRes ""))
                   (len (stringLength content))
                   (parseRes (stmt/parseScript content))]
               (do
                 (assert (ok? parseRes) (str "parse succeeds: " path))
                 (let [(root (resultOr parseRes (tr/makeErrorNode 0 0 (list))))
                       (printed (pr/printTreeString content root))]
                   (do
                     (assert (= printed content) (str "byte exact round-trip: " path))
                     (assert (ok? (tr/checkTiling root len)) (str "tokens tile: " path))
                     (checkFileSuite! suiteName rest exclusions (+ runCount 1) (+ passCount 1) excludedCount)))))))))))

fn testTest262Fixtures! -> Bool
  (checkFileSuite! "test262 stmt" (test262Files) (test262Exclusions) 0 0 0)

fn testTrackedJsFixtures! -> Bool
  (checkFileSuite! "tracked js stmt" (trackedJsFiles) (trackedJsExclusions) 0 0 0)

fn testForHeaderAsi! -> Bool
  (do
    (let [(res (stmt/parse "for (a\n b\n c)"))]
      (do
        (refute (ok? res) "no ASI inside for header: for (a\n b\n c) is rejected")
        (mt res
          ((ok _) (assert false "expected parse error"))
          ((err msg) (assert (= msg "Parse error at offset 6") "for (a\n b\n c) error has offset 6")))))
    (assert (checkScript! "for (\n;\n;\n) {}" "(script (for (block)))") "for empty parts with newlines parses")
    (assert (checkScript! "for (let i = 0;\n i < 10;\n i++\n) {}" "(script (for (let (= i 0)) (< i 10) (post++ i) (block)))") "for standard loop with newlines parses")
    true)

fn testEndOfInputCases -> Bool
  (do
    (refute (ok? (stmt/parse "throw")) "throw at EOF is rejected")
    (refute (ok? (stmt/parse "if (")) "truncated if at EOF is rejected")
    (refute (ok? (stmt/parse "while (")) "truncated while at EOF is rejected")
    (refute (ok? (stmt/parse "for (")) "truncated for at EOF is rejected")
    (refute (ok? (stmt/parse "do")) "truncated do at EOF is rejected")
    (refute (ok? (stmt/parse "switch (")) "truncated switch at EOF is rejected")
    (refute (ok? (stmt/parse "try")) "truncated try at EOF is rejected")
    (refute (ok? (stmt/parse "with (")) "truncated with at EOF is rejected")
    (refute (ok? (stmt/parse "{")) "truncated block at EOF is rejected")
    (refute (ok? (stmt/parse "class")) "truncated class at EOF is rejected")
    (refute (ok? (stmt/parse "function")) "truncated function at EOF is rejected")
    true)

fn ! runTests -> Bool
  (do
    (assert (testAsiFixtures!) "ASI fixtures")
    (assert (testEndOfInputCases) "end of input cases")
    (assert (testForHeaderAsi!) "for header ASI")
    (assert (testClassMemberFixtures!) "class member fixtures")
    (assert (testStatements!) "statements")
    (assert (testTest262Fixtures!) "test262 fixtures")
    (assert (testTrackedJsFixtures!) "tracked js fixtures")
    true)
