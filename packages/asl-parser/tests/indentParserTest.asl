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

(df runTests [] -> Bool
  :d "Runs all pure ASL v0.4 indent parser unit tests."
  (assert (testDotAccessLowering) "testDotAccessLowering passed")
  (assert (testInterpolationLowering) "testInterpolationLowering passed")
  (assert (testFunctionDeclarationLowering) "testFunctionDeclarationLowering passed")
  (assert (testMatchWithArmsLowering) "testMatchWithArmsLowering passed")
  true)
