(module asl-parser/indentParserTest :x [runTests] :i [(indentParser :a ip) (reader :a rd)])

fn testDotAccessLowering -> Bool
  (let [(d1 (ip/desugarDot "user.profile.email")) (r1 (rd/renderPrefix d1))] (assert (= r1 "(.-email (.-profile user))") (str "user.profile.email must lower to nested accessor: got " r1)) (let [(d2 (ip/desugarDot "plainSym")) (r2 (rd/renderPrefix d2))] (assert (= r2 "plainSym") "plain symbol must remain atom") true))

fn testInterpolationLowering -> Bool
  (let [(d (ip/desugarInterpolation (list "Hello " ", your score is " "!") (list "name" "score"))) (r (rd/renderPrefix d))] (assert (stringContains? r "str") "Must lower to str builtin") (assert (stringContains? r "Hello ") "Must preserve prefix string") (assert (stringContains? r "name") "Must evaluate name hole") (assert (stringContains? r "score") "Must evaluate score hole") true)

fn testFunctionDeclarationLowering -> Bool
  (let [(src (str "fn add x: Int y: Int -> Int\n" "  add x y\n")) (res (ip/parseIndented src))] (match res ((ok sexpr) (let [(r (rd/renderPrefix sexpr))] (assert (stringContains? r "fn add") "Must define function add with fn") (assert (stringContains? r "[(x Int) (y Int)]") "Must format parameter vector") (assert (stringContains? r "-> Int") "Must format return type") (assert (stringContains? r "(add x y)") "Must format body form") true)) ((err msg) (assert false (str "Failed to parse fn form: " msg)) false)))

fn testUnannotatedParameterUsesAny -> Bool
  (let [(res (ip/parseIndented (str "fn identity x -> Int64\n" "  x\n")))] (assert (testRawUnannotatedParamMarker) "raw parser preserves absent annotation marker") (match res ((ok sexpr) (let [(rendered (rd/renderPrefix sexpr))] (assert (stringContains? rendered "(x Any)") (str "unannotated parameter infers Any in display form: " rendered)) true)) ((err msg) (assert false (str "unannotated parameter parses: " msg)) false)))

fn testRawUnannotatedParamMarker -> Bool
  (match (ip/parseIndentedForms "fn identity x -> Int64\n  x\n") ((ok forms) (let [(rawText (rd/renderPrefix (optionOr (listHead forms) (rd/makeAtom ""))))] (assert (stringContains? rawText "(x )") (str "raw parser preserves absent annotation marker for checker inference: " rawText)) true)) ((err msg) (assert false (str "raw parser failed: " msg)) false))

fn testMatchWithArmsLowering -> Bool
  (let [(src (str "match val\n" "  Ok res -> res\n" "  Err msg -> (print msg)\n")) (res (ip/parseIndented src))] (match res ((ok sexpr) (let [(r (rd/renderPrefix sexpr))] (assert (stringContains? r "match val") "Must match val") (assert (stringContains? r "Ok res") "Must contain Ok pattern") (assert (stringContains? r "Err msg") "Must contain Err pattern") (assert (stringContains? r "(print msg)") "Must contain print call") (assert (= r "(match val ((Ok res) res) ((Err msg) (print msg)))") (str "arms must be direct siblings of match's target, not wrapped in one extra list (astConverter's liftExpr assumes flat arm siblings and silently merges all arms into one otherwise): got " r)) true)) ((err msg) (assert false (str "Failed to parse match: " msg)) false)))

fn testSchemaLowering -> Bool
  (let [(src1 "schema Point { x: Int y: Int }") (res1 (ip/parseIndented src1))] (match res1 ((ok sexpr1) (let [(r1 (rd/renderPrefix sexpr1))] (assert (stringContains? r1 "schema Point") "Must define schema Point") (assert (stringContains? r1 "(:field x Int") "Must contain field x") (assert (stringContains? r1 "(:field y Int") "Must contain field y") (refute (stringContains? r1 "{") "Delimiters must be lowered") (refute (stringContains? r1 "}") "Delimiters must be lowered"))) ((err msg) (assert false (str "Failed to parse schema: " msg)))) (let [(src2 (str "schema User\n" "  name: String \"user display name\"\n" "  age: Int\n")) (res2 (ip/parseIndented src2))] (match res2 ((ok sexpr2) (let [(r2 (rd/renderPrefix sexpr2))] (assert (stringContains? r2 "schema User") "Must define schema User") (assert (stringContains? r2 "(:field name String") "Must contain field name") (assert (stringContains? r2 "(:field age Int") "Must contain field age") (refute (stringContains? r2 "schema Point") "Must not confuse schemas"))) ((err msg) (assert false (str "Failed to parse indented schema: " msg)))) true))

fn testEnumLowering -> Bool
  (let [(src1 "enum Color { Red Green Blue }") (res1 (ip/parseIndented src1))] (match res1 ((ok sexpr1) (let [(r1 (rd/renderPrefix sexpr1))] (assert (stringContains? r1 "enum Color") "Must define enum Color") (assert (stringContains? r1 "(:case Red") "Must contain case Red") (assert (stringContains? r1 "(:case Green") "Must contain case Green") (assert (stringContains? r1 "(:case Blue") "Must contain case Blue") (refute (stringContains? r1 "defschema") "Must not emit defschema for enum"))) ((err msg) (assert false (str "Failed to parse enum: " msg)))) (let [(src2 (str "enum Status\n" "  Active\n" "  Inactive\n")) (res2 (ip/parseIndented src2))] (match res2 ((ok sexpr2) (let [(r2 (rd/renderPrefix sexpr2))] (assert (stringContains? r2 "enum Status") "Must define enum Status") (assert (stringContains? r2 "(:case Active") "Must contain case Active") (assert (stringContains? r2 "(:case Inactive") "Must contain case Inactive") (refute (stringContains? r2 "Red") "Must not contain unrelated cases"))) ((err msg) (assert false (str "Failed to parse indented enum: " msg)))) true))

fn testPipelineLowering -> Bool
  (let [(src "val |> (validate) |> (process)\n") (res (ip/parseIndented src))] (match res ((ok sexpr) (let [(r (rd/renderPrefix sexpr))] (assert (stringContains? r "|>") "Must recognize pipeline operator") (assert (stringContains? r "val") "Must contain pipeline source") (assert (stringContains? r "validate") "Must contain first pipe stage") (assert (stringContains? r "process") "Must contain second pipe stage") (refute (stringContains? r "undefined") "Pipe stages must not be undefined") true)) ((err msg) (assert false (str "Failed to parse pipeline: " msg)) false)))

fn testBracketFreeLetLowering -> Bool
  (let [(src (str "let x = 42\n" "add x 1\n")) (res (ip/parseIndented src))] (match res ((ok sexpr) (let [(r (rd/renderPrefix sexpr))] (assert (stringContains? r "let") "Must lower to let form") (assert (stringContains? r "x") "Must bind identifier x") (assert (stringContains? r "42") "Must bind value 42") (refute (stringContains? r "=") "Assignment operator must be desugared") true)) ((err msg) (assert false (str "Failed to parse bracket-free let: " msg)) false)))

fn testBracketInsideStringLiteral -> Bool
  (let [(src (str "fn br -> String\n" "  \"[\"\n")) (res (ip/parseIndentedForms src)) (unbalanced (ip/parseIndentedForms "fn v -> Int\n  [1 2\n"))] (match res ((ok forms) (do (assert (= (listLength forms) 1) "a \"[\" string literal parses as one form") (assert (err? unbalanced) "a real unclosed [ still errors") true)) ((err msg) (assert false (str "a \"[\" string literal must not count as an open bracket: " msg)))))

fn testFnHeaderContinuationLowering -> Bool
  (let [(src (str "fn f a: Int64\n" "    b: Int64 -> Int64\n" "  (+ a b)\n")) (res (ip/parseIndentedForms src))] (match res ((ok forms) (let [(r (rd/renderPrefix (optionOr (listHead forms) (rd/makeAtom ""))))] (assert (= (listLength forms) 1) (str "a continued fn header must yield one top-level form, got " (stringFromInt64 (listLength forms)))) (assert (stringContains? r "fn f") "Must define function f") (assert (stringContains? r "[(a Int64) (b Int64)]") (str "Must join the continued param list: got " r)) (assert (stringContains? r "-> Int64") (str "Must not default the return type to Unit: got " r)) (assert (stringContains? r "(+ a b)") "Must keep the real body as the body form") true)) ((err msg) (assert false (str "Failed to parse fn with header continuation: " msg)) false)))

fn testFnHeaderJoinSkipsStringLiteral -> Bool
  (let [(src (str "fn demo -> String\n" "  \"abc\n" "fn x a: Int64\n" "    b: Int64 -> Int64\n" "done\"\n")) (res (ip/parseIndentedForms src))]
    (match res
      ((ok forms)
       (let [(r (rd/renderPrefix (optionOr (listHead forms) (rd/makeAtom ""))))]
         (assert (= (listLength forms) 1) (str "a fn header lookalike inside a string must not split the form, got " (stringFromInt64 (listLength forms))))
         (assert (stringContains? r "abc\\nfn x a: Int64\\n    b: Int64 -> Int64\\ndone") (str "the string literal's lines must stay joined by real newlines, not merged by a bogus header join: got " r))
         true))
      ((err msg) (assert false (str "Failed to parse fn header lookalike inside a string: " msg)) false)))

fn testFnHeaderJoinErrorPositionRemap -> Bool
  (let [(src (str "fn f a: Int64\n" "    b: \"oops\n")) (res (ip/parseIndentedForms src))]
    (match res
      ((ok _) (assert false "an unterminated string inside a joined continuation line must still error") false)
      ((err msg) (do (assert (stringContains? msg "2:8") (str "the unterminated string opened on line 2 col 8 of the source, not inside the joined header line 1: got " msg)) true))))

fn testFnHeaderJoinStripsCr -> Bool
  (let [(src (str "fn f a: Int64\r\n" "    b: Int64 -> Int64\r\n" "  (+ a b)\r\n")) (res (ip/parseIndentedForms src))]
    (match res
      ((ok forms)
       (let [(r (rd/renderPrefix (optionOr (listHead forms) (rd/makeAtom ""))))]
         (assert (= (listLength forms) 1) (str "a CRLF-terminated continued fn header must still yield one top-level form, got " (stringFromInt64 (listLength forms))))
         (assert (stringContains? r "[(a Int64) (b Int64)]") (str "an embedded \\r must not corrupt the joined param list: got " r))
         (refute (stringContains? r "Any") (str "an embedded \\r must not degrade a param type to Any: got " r))
         true))
      ((err msg) (assert false (str "Failed to parse CRLF fn header with continuation: " msg)) false)))

fn testKeywordEndingInQuestionMark -> Bool
  (let [(src (str "fn f -> Int64\n" "  (g (R :valid? true :also? false))\n")) (res (ip/parseIndented src))] (match res ((ok sexpr) (let [(r (rd/renderPrefix sexpr))] (assert (stringContains? r ":valid?") (str "a keyword ending in ? lexes whole, not split into :valid and a try-operator: got " r)) (assert (stringContains? r ":also?") (str "a second such keyword in the same call also lexes whole: got " r)) (refute (stringContains? r "mt :valid") (str "must not desugar the keyword into a try/match expression: got " r)) true)) ((err msg) (assert false (str "Failed to parse keyword ending in ?: " msg)) false)))

fn testRecordLiteralBodyLowering -> Bool
  (let [(src (str "fn sysvAbi -> Map\n" "  (do {:intArgs [\"rdi\" \"rsi\"] :retReg \"rax\"})\n")) (res (ip/parseIndented src))] (match res ((ok sexpr) (let [(r (rd/renderPrefix sexpr))] (assert (= r "(fn sysvAbi [] -> Map (do ({ :intArgs (list \"rdi\" \"rsi\") :retReg \"rax\" })))") (str "a record literal, also as a do-block's sole body statement, is the ({ k v ... }) list asl-ir/lower lowers to opRecord; a flat { field... } splice reaches lower as an unknown symbol {: got " r)) true)) ((err msg) (assert false (str "Failed to parse record-literal do body: " msg)) false)))

fn formCountOf src: String -> Int64
  (match (ip/parseIndentedForms src) ((ok forms) (listLength forms)) ((err _) -1))

fn testLaterBraceDoesNotCaptureEarlierForm -> Bool
  (let [(enumThenBrace (formCountOf "enum P\n  (a x: Int64)\n  (b y: String)\n\nschema S {\n  t: Int64\n}\n"))
        (schemaThenBrace (formCountOf "schema A\n  x: Int64\n\nschema B {\n  y: Int64\n}\n"))
        (braceEnum (formCountOf "enum E { a b }\n\nschema S {\n  t: Int64\n}\n"))]
    (do (assert (= enumThenBrace 2) "an indented enum is not turned into a brace enum by a later brace schema")
        (assert (= schemaThenBrace 2) "an indented schema is not turned into a brace schema by a later brace schema")
        (assert (= braceEnum 2) "a brace enum still ends at its own closing brace")
        (refute (= enumThenBrace 1) "the later schema must not be swallowed")
        true))


fn runTests -> Bool
  (do (assert (testLaterBraceDoesNotCaptureEarlierForm) "testLaterBraceDoesNotCaptureEarlierForm passed") (assert (testUnannotatedParameterUsesAny) "unannotated parameter infers Any") (assert (testBracketInsideStringLiteral) "testBracketInsideStringLiteral passed") (assert (testDotAccessLowering) "testDotAccessLowering passed") (assert (testInterpolationLowering) "testInterpolationLowering passed") (assert (testFunctionDeclarationLowering) "testFunctionDeclarationLowering passed") (assert (testFnHeaderContinuationLowering) "testFnHeaderContinuationLowering passed") (assert (testFnHeaderJoinSkipsStringLiteral) "testFnHeaderJoinSkipsStringLiteral passed") (assert (testFnHeaderJoinErrorPositionRemap) "testFnHeaderJoinErrorPositionRemap passed") (assert (testFnHeaderJoinStripsCr) "testFnHeaderJoinStripsCr passed") (assert (testMatchWithArmsLowering) "testMatchWithArmsLowering passed") (assert (testRecordLiteralBodyLowering) "testRecordLiteralBodyLowering passed") (assert (testSchemaLowering) "testSchemaLowering passed") (assert (testEnumLowering) "testEnumLowering passed") (assert (testPipelineLowering) "testPipelineLowering passed") (assert (testBracketFreeLetLowering) "testBracketFreeLetLowering passed") (assert (testKeywordEndingInQuestionMark) "testKeywordEndingInQuestionMark passed") true)
