(module asl-parser/tryOperatorTest
  :d "Falsifiable test suite for Task 52601 Error Propagation Operator '?' Desugaring and Single-Line Syntax."
  :x [runTests]
  :i [(indentLexer :a lx) (indentParser :a ip) (reader :a rd)])

(df testLexerTryOperator [] -> Bool
  :d "Verifies that the lexer scans '?' as tokQuestion and updates tokenTypeName correctly."
  (let [(src "val? (foo x)? ?")
        (lexRes (lx/tokenizeIndented src))
        (toks (.-first lexRes))
        (diags (.-second lexRes))]
    (assert (list-empty? diags) "Lexing try expressions should yield zero diagnostics")
    (let [(qName (lx/tokenTypeName (lx/tokQuestion)))]
      (assert (= qName "?") (str "tokenTypeName for tokQuestion must be ?, got: " qName))
      (refute (= qName "QUESTION") "tokenTypeName for tokQuestion must not be verbose QUESTION"))
    (let [(raws (map (fn [(t lx/IndentToken)] -> String (.-rawText t)) toks))
          (allRaws (string-join raws " "))]
      (assert (string-contains? allRaws "?") "Tokens must contain '?'")
      (refute (string-contains? allRaws "val?") "Postfix 'val?' must separate into 'val' and '?'")
      (refute (string-contains? allRaws "x)?") "Postfix 'x)?' must separate into 'x', ')', and '?'")
      true)))

(df testDirectTryDesugaringUnwrapOk [] -> Bool
  :d "Verifies desugarTry unwraps (ok 42) into canonical match form with value binding."
  (let [(okNode (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "42"))))
        (desugared (ip/desugarTry okNode))
        (rendered (rd/renderSexpr desugared))]
    (assert (= rendered "(match (ok 42) (ok __v __v) (err __e (return (err __e))))")
            (str "Must desugar (ok 42) into match form: got " rendered))
    (assert (string-contains? rendered "(ok __v __v)") "Must unwrap value in ok arm")
    (refute (string-contains? rendered "(return (ok") "Ok arm must not return error")
    (refute (string-contains? rendered "err __v") "Ok binder must not be bound to err")
    true))

(df testDirectTryDesugaringEarlyReturnErr [] -> Bool
  :d "Verifies desugarTry desugars (err \"fail\") into match form with early return."
  (let [(errNode (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "\"fail\""))))
        (desugared (ip/desugarTry errNode))
        (rendered (rd/renderSexpr desugared))]
    (assert (= rendered "(match (err \"fail\") (ok __v __v) (err __e (return (err __e))))")
            (str "Must desugar (err fail) into match form: got " rendered))
    (assert (string-contains? rendered "(return (err __e))") "Err arm must early-return error")
    (refute (string-contains? rendered "(return (ok") "Err arm must not return ok")
    (refute (string-contains? rendered "ok __e") "Err binder must not be bound to ok")
    true))

(df testIndentedFunctionWithTryOperator [] -> Bool
  :d "Verifies indented function definition with '?' desugars into canonical df."
  (let [(src (str "fn fetchUser id: Int64 -> Result\n"
                  "  raw = (queryDb id)?\n"
                  "  user = (parseUser raw)?\n"
                  "  ok user\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "df fetchUser") "Must define function fetchUser")
         (assert (string-contains? r "[(id Int64)]") "Must parse parameter vector")
         (assert (string-contains? r "-> Result") "Must parse return type")
         (assert (string-contains? r "(match (queryDb id) (ok __v __v) (err __e (return (err __e))))")
                 "Must desugar queryDb try expression")
         (assert (string-contains? r "(match (parseUser raw) (ok __v __v) (err __e (return (err __e))))")
                 "Must desugar parseUser try expression")
         (assert (string-contains? r "(ok user)") "Must preserve trailing body form")
         (refute (string-contains? r "?") "Desugared function AST must not contain unexpanded question marks")
         (refute (string-contains? r "queryDb id?") "queryDb call must not retain unparsed try operator")
         true))
      ((err msg)
       (refute true (str "Failed to parse indented function with try operator: " msg))
       false))))

(df testSingleLineTryOperatorUnwrap [] -> Bool
  :d "Verifies single-line expression unwrapping (ok 42) via '?'."
  (let [(src "val = (ok 42)?\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "val =") "Must preserve assignment target")
         (assert (string-contains? r "(match (ok 42) (ok __v __v) (err __e (return (err __e))))")
                 "Must desugar (ok 42)? into early-return match form")
         (assert (string-contains? r "(ok __v __v)") "Must unwrap value to __v")
         (refute (string-contains? r "(ok 42)?") "Must not leave raw (ok 42)? in AST")
         (refute (string-contains? r "err __v") "Value binder must not belong to err branch")
         true))
      ((err msg)
       (refute true (str "Failed to parse single-line (ok 42)?: " msg))
       false))))

(df testSingleLineTryOperatorEarlyReturn [] -> Bool
  :d "Verifies single-line expression with (err \"fail\") desugars to early-return match form."
  (let [(src "val = (err \"fail\")?\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "val =") "Must preserve assignment target")
         (assert (string-contains? r "(match (err \"fail\") (ok __v __v) (err __e (return (err __e))))")
                 "Must desugar (err fail)? into early-return match form")
         (assert (string-contains? r "(return (err __e))") "Must emit return (err __e)")
         (refute (string-contains? r "(err \"fail\")?") "Must not leave raw (err fail)? in AST")
         (refute (string-contains? r "ok __e") "Error binder must not belong to ok branch")
         true))
      ((err msg)
       (refute true (str "Failed to parse single-line (err fail)?: " msg))
       false))))

(df testPostfixTryOnIdentifier [] -> Bool
  :d "Verifies postfix '?' on plain identifier val? desugars cleanly."
  (let [(src "step?\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (= r "(match step (ok __v __v) (err __e (return (err __e))))")
                 (str "Must desugar step? to match form, got: " r))
         (refute (string-contains? r "step?") "Must not leave step? unlowered")
         (refute (string-contains? r "error") "Must not produce parser error")
         true))
      ((err msg)
       (refute true (str "Failed to parse step?: " msg))
       false))))

(df testInteropWithDotAccess [] -> Bool
  :d "Verifies desugarDot interoperates cleanly with postfix '?' try expression."
  (let [(src "val = service.client.fetch?\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "(.-fetch (.-client service))")
                 "Must lower compound dot-access into nested property accessor")
         (assert (string-contains? r "(match (.-fetch (.-client service)) (ok __v __v) (err __e (return (err __e))))")
                 "Must wrap lowered dot-access in try match form")
         (refute (string-contains? r "service.client.fetch") "Raw dot identifier must not remain unlowered")
         (refute (string-contains? r "fetch?") "Must not leave fetch? unlowered")
         true))
      ((err msg)
       (refute true (str "Failed to parse dot-access try expression: " msg))
       false))))

(df testInteropWithStringInterpolation [] -> Bool
  :d "Verifies desugarInterpolation interoperates cleanly with postfix '?' try expression."
  (let [(src "val = \"https://api.internal/{endpoint}\"?\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "(str \"https://api.internal/\" endpoint)")
                 "Must lower interpolated string into str call")
         (assert (string-contains? r "(match (str \"https://api.internal/\" endpoint) (ok __v __v) (err __e (return (err __e))))")
                 "Must wrap lowered interpolation in try match form")
         (refute (string-contains? r "{endpoint}") "Raw interpolation hole must not remain unlowered")
         (refute (string-contains? r "\"?") "Must not leave trailing question mark unlowered")
         true))
      ((err msg)
       (refute true (str "Failed to parse string interpolation try expression: " msg))
       false))))

(df testInsideParensTryOperator [] -> Bool
  :d "Verifies try operator '?' inside parenthesized call argument."
  (let [(src "(process val?)\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "(match val (ok __v __v) (err __e (return (err __e))))")
                 "Must desugar try expression inside parenthesized argument")
         (assert (string-starts-with? r "(process") "Outer call form process must be preserved")
         (refute (string-contains? r "val?") "Must not leave val? unlowered")
         true))
      ((err msg)
       (refute true (str "Failed to parse inside parens try operator: " msg))
       false))))

(df testStandaloneQuestionMark [] -> Bool
  :d "Verifies standalone '?' parses as an atom symbol without error."
  (let [(src "?\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (= r "?") "Standalone '?' must parse as atom '?'")
         (refute (string-contains? r "match") "Standalone '?' must not generate match form")
         true))
      ((err msg)
       (refute true (str "Failed to parse standalone '?': " msg))
       false))))

(df runTests [] -> Bool
  :d "Runs all falsifiable unit tests for error propagation operator '?' desugaring."
  (assert (testLexerTryOperator) "testLexerTryOperator passed")
  (assert (testDirectTryDesugaringUnwrapOk) "testDirectTryDesugaringUnwrapOk passed")
  (assert (testDirectTryDesugaringEarlyReturnErr) "testDirectTryDesugaringEarlyReturnErr passed")
  (assert (testIndentedFunctionWithTryOperator) "testIndentedFunctionWithTryOperator passed")
  (assert (testSingleLineTryOperatorUnwrap) "testSingleLineTryOperatorUnwrap passed")
  (assert (testSingleLineTryOperatorEarlyReturn) "testSingleLineTryOperatorEarlyReturn passed")
  (assert (testPostfixTryOnIdentifier) "testPostfixTryOnIdentifier passed")
  (assert (testInteropWithDotAccess) "testInteropWithDotAccess passed")
  (assert (testInteropWithStringInterpolation) "testInteropWithStringInterpolation passed")
  (assert (testInsideParensTryOperator) "testInsideParensTryOperator passed")
  (assert (testStandaloneQuestionMark) "testStandaloneQuestionMark passed")
  true)
