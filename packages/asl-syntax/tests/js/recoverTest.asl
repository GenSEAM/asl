(module asl-syntax/tests/js/recoverTest
  :x [runTests]
  :i [(asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/symbols :a sym)
      (asl-syntax/js/recover :a rec)])

fn negativeFiles -> (List String)
  (list
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-3.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-4.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-1.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/class-fields/fields-asi-same-line-2.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/function-body.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/preceding-whitespace.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/comments/hashbang/statement-block.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-else.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-if.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/identifiers/val-while.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/position-invalid.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-binding-identifier.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-identifier-reference.js.sample"
    "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/in-iteration-stmt.js.sample")

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
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/numeric/7.8.3-3gs.js.sample" "octal integer literal in strict mode (runtime eval test inside try-catch)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1.js.sample" "unclosed regex literal across line terminator (runtime eval test inside try-catch)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-1gs.js.sample" "unclosed regex literal across line terminator (runtime eval test inside try-catch)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/7.8.5-2gs.js.sample" "unclosed regex literal across line terminator (runtime eval test inside try-catch)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T2.js.sample" "unclosed regex literal (runtime eval test inside try-catch)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T4.js.sample" "unclosed regex literal (runtime eval test inside try-catch)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/regexp/S7.8.5_A1.3_T5.js.sample" "unclosed regex literal (runtime eval test inside try-catch)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/rest/position-invalid.js.sample" "rest parameter cannot be followed by another parameter (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-binding-identifier.js.sample" "await cannot be binding identifier in async function (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/async/await-as-identifier-reference.js.sample" "await cannot be identifier reference in async function (negative parse case, unit S5)")
    (pair "asl/packages/asl-syntax/tests/fixtures/upstream/test262/yield/in-iteration-stmt.js.sample" "yield expression in iteration header (negative parse case, unit S5)"))

fn findExclusionReason path: String exclusions: (List (Pair String String)) -> (Option String)
  (if (listEmpty? exclusions)
    (none)
    (let [(head (optionOr (listHead exclusions) (pair "" "")))
          (tail (optionOr (listTail exclusions) (list)))]
      (if (= (pairFirst head) path)
        (some (pairSecond head))
        (findExclusionReason path tail))))

fn printExclusions! prefix: String cases: (List (Pair String String)) -> Bool
  (if (listEmpty? cases)
    true
    (let [(head (optionOr (listHead cases) (pair "" "")))
          (tail (optionOr (listTail cases) (list)))]
      (do
        (println (str "  " prefix " excluded: " (pairFirst head) " (" (pairSecond head) ")"))
        (printExclusions! prefix tail))))

fn checkNegativeFiles! files: (List String) -> Bool
  (if (listEmpty? files)
    true
    (let [(path (optionOr (listHead files) ""))
          (tl (optionOr (listTail files) (list)))
          (readRes (fileReadString path))]
      (do
        (assert (ok? readRes) (str "readable negative file: " path))
        (let [(content (resultOr readRes ""))
              (len (stringLength content))
              (checkRes (rec/check content))
              (recRoot (rec/parseWithRecovery content))
              (printed (pr/printTreeString content recRoot))
              (tiling (tr/checkTiling recRoot len))]
          (do
            (refute (ok? checkRes) (str "negative parse case rejected: " path))
            (assert (sym/hasErrorNode recRoot) (str "negative case has error node: " path))
            (assert (= printed content) (str "negative case round-trips: " path))
            (assert (ok? tiling) (str "negative case tokens tile: " path))
            (checkNegativeFiles! tl))))))

fn checkPositiveSuite! files: (List String) exclusions: (List (Pair String String)) runCount: Int64 passCount: Int64 excludedCount: Int64 -> Bool
  (if (listEmpty? files)
    (do
      (println (str "test262 positive suite: " (stringFromInt64 runCount) " run, " (stringFromInt64 passCount) " passed, " (stringFromInt64 excludedCount) " excluded"))
      (printExclusions! "test262" exclusions)
      true)
    (let [(path (optionOr (listHead files) ""))
          (tl (optionOr (listTail files) (list)))]
      (mt (findExclusionReason path exclusions)
        ((some _)
         (checkPositiveSuite! tl exclusions runCount passCount (+ excludedCount 1)))
        ((none)
         (let [(readRes (fileReadString path))]
           (do
             (assert (ok? readRes) (str "readable positive file: " path))
             (let [(content (resultOr readRes ""))
                   (len (stringLength content))
                   (checkRes (rec/check content))]
               (do
                 (assert (ok? checkRes) (str "positive parse succeeds: " path))
                 (let [(root (resultOr checkRes (tr/makeErrorNode 0 0 (list))))
                       (printed (pr/printTreeString content root))
                       (tiling (tr/checkTiling root len))]
                   (do
                     (refute (sym/hasErrorNode root) (str "positive file has no error node: " path))
                     (assert (= printed content) (str "positive file round-trips: " path))
                     (assert (ok? tiling) (str "positive file tokens tile: " path))
                     (checkPositiveSuite! tl exclusions (+ runCount 1) (+ passCount 1) excludedCount)))))))))))

fn testBrokenRecovery -> Bool
  (let [(code "var a = 1;\nvar else = 2;\nvar b = 3;\n")
        (len (stringLength code))
        (valid (rec/isSyntaxValid code))
        (root (rec/parseWithRecovery code))
        (printed (pr/printTreeString code root))
        (tiling (tr/checkTiling root len))]
    (do
      (refute valid "broken code isSyntaxValid is false")
      (assert (sym/hasErrorNode root) "broken code has error node")
      (assert (= printed code) "broken code round-trips byte exact")
      (assert (ok? tiling) "broken code tokens tile cleanly")
      true))

fn testCheckVerdictAPI -> Bool
  (let [(goodCode "let x = 10;\nlet y = 20;\n")
        (badCode "let x = 10;\nlet if = 20;\n")
        (goodV (rec/checkVerdict goodCode))
        (badV (rec/checkVerdict badCode))]
    (do
      (assert goodV.ok "good verdict ok is true")
      (assert (= goodV.message "OK") "good verdict message is OK")
      (assert (some? goodV.root) "good verdict has root")
      (refute badV.ok "bad verdict ok is false")
      (assert (some? badV.root) "bad verdict has recovery root")
      (assert (sym/hasErrorNode (optionOr badV.root (tr/makeErrorNode 0 0 (list)))) "bad verdict root has error node")
      true))

fn ! runTests -> Bool
  (do
    (assert (checkNegativeFiles! (negativeFiles)) "all negative files tested")
    (assert (checkPositiveSuite! (test262Files) (test262Exclusions) 0 0 0) "all positive test262 files tested")
    (assert (testBrokenRecovery) "statement level error recovery")
    (assert (testCheckVerdictAPI) "check verdict API")
    true)

