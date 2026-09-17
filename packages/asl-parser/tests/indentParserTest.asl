(module asl-parser/indentParserTest
  :d "Unit tests for pure ASL v0.4 Syntactic Parser & Closed-Vocabulary Desugaring (Item 1.2, Task T12_PARSER_V04)."
  :x [runTests]
  :i [(indentParser :a ip) (reader :a rd)])

(df testDotAccessLowering [] -> Bool
  :d "Verifies compound dot-access lowers to canonical (.-prop ...)."
  (let [(d1 (ip/desugarDot "user.profile.email"))
        (r1 (rd/renderSexpr d1))]
    (assert (= r1 "(.-email (.-profile user))") (str "user.profile.email must lower to nested accessor: got " r1))
    (let [(d2 (ip/desugarDot "plainSym"))
          (r2 (rd/renderSexpr d2))]
      (assert (= r2 "plainSym") "plain symbol must remain atom")
      true)))

(df testInterpolationLowering [] -> Bool
  :d "Verifies string interpolation lowers to (str ...) with prelude builtins."
  (let [(d (ip/desugarInterpolation (list "Hello " ", your score is " "!") (list "name" "score")))
        (r (rd/renderSexpr d))]
    (assert (string-contains? r "str") "Must lower to str builtin")
    (assert (string-contains? r "Hello ") "Must preserve prefix string")
    (assert (string-contains? r "name") "Must evaluate name hole")
    (assert (string-contains? r "score") "Must evaluate score hole")
    true))

(df testFunctionDeclarationLowering [] -> Bool
  :d "Verifies fn signature and body lowering into canonical df."
  (let [(src (str "fn add x: Int y: Int -> Int\n"
                  "  add x y\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "df add") "Must define function add with df")
         (assert (string-contains? r "[(x Int) (y Int)]") "Must format parameter vector")
         (assert (string-contains? r "-> Int") "Must format return type")
         (assert (string-contains? r "(add x y)") "Must format body form")
         true))
      ((err msg)
       (assert false (str "Failed to parse fn form: " msg))
       false))))

(df testMatchWithArmsLowering [] -> Bool
  :d "Verifies match construct with multiple arms."
  (let [(src (str "match val\n"
                  "  Ok res -> res\n"
                  "  Err msg -> (print msg)\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "match val") "Must match val")
         (assert (string-contains? r "Ok res") "Must contain Ok pattern")
         (assert (string-contains? r "Err msg") "Must contain Err pattern")
         (assert (string-contains? r "(print msg)") "Must contain print call")
         true))
      ((err msg)
       (assert false (str "Failed to parse match: " msg))
       false))))

(df testSchemaLowering [] -> Bool
  :d "Verifies schema declaration with braces or indentation lowers to defschema."
  (let [(src1 "schema Point { x: Int y: Int }")
        (res1 (ip/parseIndented src1))]
    (mt res1
      ((ok sexpr1)
       (let [(r1 (rd/renderSexpr sexpr1))]
         (assert (string-contains? r1 "defschema Point") "Must define defschema Point")
         (assert (string-contains? r1 "(:field x Int") "Must contain field x")
         (assert (string-contains? r1 "(:field y Int") "Must contain field y")
         (refute (string-contains? r1 "{") "Delimiters must be lowered")
         (refute (string-contains? r1 "}") "Delimiters must be lowered")))
      ((err msg)
       (assert false (str "Failed to parse schema: " msg))))
    (let [(src2 (str "schema User\n"
                     "  name: String \"user display name\"\n"
                     "  age: Int\n"))
          (res2 (ip/parseIndented src2))]
      (mt res2
        ((ok sexpr2)
         (let [(r2 (rd/renderSexpr sexpr2))]
           (assert (string-contains? r2 "defschema User") "Must define defschema User")
           (assert (string-contains? r2 "(:field name String") "Must contain field name")
           (assert (string-contains? r2 "(:field age Int") "Must contain field age")
           (refute (string-contains? r2 "defschema Point") "Must not confuse schemas")))
        ((err msg)
         (assert false (str "Failed to parse indented schema: " msg))))
      true)))

(df testEnumLowering [] -> Bool
  :d "Verifies enum declaration lowers to defenum with cases."
  (let [(src1 "enum Color { Red Green Blue }")
        (res1 (ip/parseIndented src1))]
    (mt res1
      ((ok sexpr1)
       (let [(r1 (rd/renderSexpr sexpr1))]
         (assert (string-contains? r1 "defenum Color") "Must define defenum Color")
         (assert (string-contains? r1 "(:case Red") "Must contain case Red")
         (assert (string-contains? r1 "(:case Green") "Must contain case Green")
         (assert (string-contains? r1 "(:case Blue") "Must contain case Blue")
         (refute (string-contains? r1 "defschema") "Must not emit defschema for enum")))
      ((err msg)
       (assert false (str "Failed to parse enum: " msg))))
    (let [(src2 (str "enum Status\n"
                     "  Active\n"
                     "  Inactive\n"))
          (res2 (ip/parseIndented src2))]
      (mt res2
        ((ok sexpr2)
         (let [(r2 (rd/renderSexpr sexpr2))]
           (assert (string-contains? r2 "defenum Status") "Must define defenum Status")
           (assert (string-contains? r2 "(:case Active") "Must contain case Active")
           (assert (string-contains? r2 "(:case Inactive") "Must contain case Inactive")
           (refute (string-contains? r2 "Red") "Must not contain unrelated cases")))
        ((err msg)
         (assert false (str "Failed to parse indented enum: " msg))))
      true)))

(df testPipelineLowering [] -> Bool
  :d "Verifies pipeline operator |> lowers to nested expression or pipeline form."
  (let [(src "val |> (validate) |> (process)\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "|>") "Must recognize pipeline operator")
         (assert (string-contains? r "val") "Must contain pipeline source")
         (assert (string-contains? r "validate") "Must contain first pipe stage")
         (assert (string-contains? r "process") "Must contain second pipe stage")
         (refute (string-contains? r "undefined") "Pipe stages must not be undefined")
         true))
      ((err msg)
       (assert false (str "Failed to parse pipeline: " msg))
       false))))

(df testBracketFreeLetLowering [] -> Bool
  :d "Verifies bracket-free let assignment let x = ... lowers to canonical let."
  (let [(src (str "let x = 42\n"
                  "add x 1\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "let") "Must lower to let form")
         (assert (string-contains? r "x") "Must bind identifier x")
         (assert (string-contains? r "42") "Must bind value 42")
         (refute (string-contains? r "=") "Assignment operator must be desugared")
         true))
      ((err msg)
       (assert false (str "Failed to parse bracket-free let: " msg))
       false))))

(df runTests [] -> Bool
  :d "Runs all pure ASL v0.4 indent parser unit tests."
  (assert (testDotAccessLowering) "testDotAccessLowering passed")
  (assert (testInterpolationLowering) "testInterpolationLowering passed")
  (assert (testFunctionDeclarationLowering) "testFunctionDeclarationLowering passed")
  (assert (testMatchWithArmsLowering) "testMatchWithArmsLowering passed")
  (assert (testSchemaLowering) "testSchemaLowering passed")
  (assert (testEnumLowering) "testEnumLowering passed")
  (assert (testPipelineLowering) "testPipelineLowering passed")
  (assert (testBracketFreeLetLowering) "testBracketFreeLetLowering passed")
  true)

