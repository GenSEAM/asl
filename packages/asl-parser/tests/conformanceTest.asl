(module asl/packages/asl-parser/tests/conformanceTest
  :d "20-adversarial conformance suite for ASL v0.4 hardened lexer and parser (ADR D81, D77)."
  :x [runTests RunTests testAdversarialCases testDualPolarityRefutations]
  :i [(../src/indentParser :a ip) (../src/indentLexer :a il) (reader :a rd)])

(df testAdversarialCases [] -> Bool
  :d "Executes all 20 adversarial conformance cases for hardened lexer and parser."
  (do
    (let [(t1 (il/tokenize "-42"))
          (t2 (il/tokenize "-1"))
          (t3 (il/tokenize "-100"))]
      (assert (> (list-length t1) 0) "Case 1: -42 tokenized")
      (assert (> (list-length t2) 0) "Case 1: -1 tokenized")
      (assert (> (list-length t3) 0) "Case 1: -100 tokenized")
      (mt (list-head t1)
        ((some tk)
         (mt (.-kind tk)
           ((tokInt n) (assert (= n -42) "Case 1: parses as int -42"))
           (_ (assert false "Case 1: must be tokInt"))))
        ((none) (assert false "Case 1: token missing"))))

    (let [(tf1 (il/tokenize "-3.14"))
          (tf2 (il/tokenize "-0.5"))]
      (assert (> (list-length tf1) 0) "Case 2: -3.14 tokenized")
      (assert (> (list-length tf2) 0) "Case 2: -0.5 tokenized")
      (mt (list-head tf1)
        ((some tk)
         (mt (.-kind tk)
           ((tokFloat f) (assert (> (string-length (.-rawText tk)) 0) "Case 2: parses as float"))
           (_ (assert false "Case 2: must be tokFloat"))))
        ((none) (assert false "Case 2: token missing"))))

    (let [(tsub (il/tokenize "x - 42"))]
      (assert (= (list-length tsub) 4) "Case 3: x - 42 token count is 4")
      (let [(subTok (option-or (list-get tsub 1) (list-head tsub)))]
        (mt subTok
          ((some tk)
           (mt (.-kind tk)
             ((tokSymbol s) (assert (= s "-") "Case 3: subtraction token is symbol -"))
             (_ (assert false "Case 3: subtraction must be tokSymbol"))))
          ((none) (assert false "Case 3: token missing")))))

    (let [(tparen (il/tokenize "(- 100 42)"))]
      (assert (> (list-length tparen) 4) "Case 4: (- 100 42) tokenized")
      (let [(parsed (ip/parseIndented "(- 100 42)\n"))]
        (assert (is-ok? parsed) "Case 4: (- 100 42) parses ok")))

    (let [(tq (il/tokenize "?"))]
      (assert (> (list-length tq) 0) "Case 5: ? tokenized")
      (mt (list-head tq)
        ((some tk)
         (mt (.-kind tk)
           ((tokQuestion) (assert true "Case 5: tokQuestion recognized"))
           (_ (assert false "Case 5: must be tokQuestion"))))
        ((none) (assert false "Case 5: token missing"))))

    (let [(tqq (il/tokenize "??"))]
      (assert (> (list-length tqq) 0) "Case 6: ?? tokenized")
      (mt (list-head tqq)
        ((some tk)
         (mt (.-kind tk)
           ((tokCoalesce) (assert true "Case 6: tokCoalesce recognized"))
           (_ (assert false "Case 6: must be tokCoalesce"))))
        ((none) (assert false "Case 6: token missing"))))

    (let [(tqc (il/tokenize "?."))]
      (assert (> (list-length tqc) 0) "Case 7: ?. tokenized")
      (mt (list-head tqc)
        ((some tk)
         (mt (.-kind tk)
           ((tokOptChain) (assert true "Case 7: tokOptChain recognized"))
           (_ (assert false "Case 7: must be tokOptChain"))))
        ((none) (assert false "Case 7: token missing"))))

    (let [(tpipe (il/tokenize "|>"))]
      (assert (> (list-length tpipe) 0) "Case 8: |> tokenized")
      (mt (list-head tpipe)
        ((some tk)
         (mt (.-kind tk)
           ((tokPipe) (assert true "Case 8: tokPipe recognized"))
           (_ (assert false "Case 8: must be tokPipe"))))
        ((none) (assert false "Case 8: token missing"))))

    (let [(tarr (il/tokenize "->"))]
      (assert (> (list-length tarr) 0) "Case 9: -> tokenized")
      (mt (list-head tarr)
        ((some tk)
         (mt (.-kind tk)
           ((tokArrow) (assert true "Case 9: tokArrow recognized"))
           (_ (assert false "Case 9: must be tokArrow"))))
        ((none) (assert false "Case 9: token missing"))))

    (let [(tbad (il/tokenize "foo?bar"))]
      (assert (> (list-length tbad) 2) "Case 10: foo?bar split into separate tokens"))

    (let [(d1 (ip/desugarDot "user.name"))]
      (assert (= (rd/renderSexpr d1) "(.-name user)") "Case 11: user.name lowered strictly to (.-name user)"))

    (let [(d2 (ip/desugarDot "user.profile.email.domain"))]
      (assert (= (rd/renderSexpr d2) "(.-domain (.-email (.-profile user)))") "Case 12: chained dot access lowered strictly"))

    (let [(p1 (ip/parseIndented "x |> double\n"))]
      (assert (is-ok? p1) "Case 13: simple pipeline parses ok")
      (mt p1
        ((ok s) (assert (string-contains? (rd/renderSexpr s) "double") "Case 13: contains double"))
        ((err _) (assert false "Case 13: parse error"))))

    (let [(p2 (ip/parseIndented "x |> double |> add(5)\n"))]
      (assert (is-ok? p2) "Case 14: multi-stage pipeline parses ok")
      (mt p2
        ((ok s)
         (let [(r (rd/renderSexpr s))]
           (assert (string-contains? r "double") "Case 14: contains double")
           (assert (string-contains? r "add") "Case 14: contains add")))
        ((err _) (assert false "Case 14: parse error"))))

    (let [(p3 (ip/parseIndented "data |> filter(isValid) |> map(transform)\n"))]
      (assert (is-ok? p3) "Case 15: multi-arg pipeline parses ok")
      (mt p3
        ((ok s)
         (let [(r (rd/renderSexpr s))]
           (assert (string-contains? r "filter") "Case 15: contains filter")
           (assert (string-contains? r "map") "Case 15: contains map")))
        ((err _) (assert false "Case 15: parse error"))))

    (let [(tryRes (ip/desugarTry (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "42")))))]
      (assert (= (rd/sexprHead tryRes) "match") "Case 16: postfix ? lowers to match form")
      (assert (string-contains? (rd/renderSexpr tryRes) "return") "Case 16: postfix ? early returns error"))

    (let [(ptry (ip/parseIndented "try sendRequest(id)\n"))]
      (assert (is-ok? ptry) "Case 17: prefix try parses ok")
      (mt ptry
        ((ok s) (assert (= (rd/sexprHead s) "match") "Case 17: prefix try lowers to match form"))
        ((err _) (assert false "Case 17: prefix try parse failed"))))

    (let [(pcoal (ip/parseIndented "res ?? fallback\n"))]
      (assert (is-ok? pcoal) "Case 18: null coalescing parses ok")
      (mt pcoal
        ((ok s) (assert (= (rd/renderSexpr s) "(?? res fallback)") "Case 18: null coalescing lowers strictly"))
        ((err _) (assert false "Case 18: parse error"))))

    (let [(pif (ip/parseIndented (str "if x > 0:\n"
                                      "  1\n"
                                      "else:\n"
                                      "  0\n")))]
      (assert (is-ok? pif) "Case 19: indented if/else parses ok")
      (mt pif
        ((ok s) (assert (= (rd/sexprHead s) "if") "Case 19: lowers to if form"))
        ((err _) (assert false "Case 19: parse error"))))

    (let [(pmatch (ip/parseIndented (str "match res\n"
                                         "  Ok val ->\n"
                                         "    val\n"
                                         "  Err err ->\n"
                                         "    0\n")))]
      (assert (is-ok? pmatch) "Case 20: indented match parses ok")
      (mt pmatch
        ((ok s) (assert (= (rd/sexprHead s) "match") "Case 20: lowers to match form"))
        ((err _) (assert false "Case 20: parse error"))))

    true))

(df testDualPolarityRefutations [] -> Bool
  :d "Executes falsifiable refutations under D77 against parser and lexer edge cases."
  (do
    (refute (is-err? (ip/parseIndented "x |> double\n")) "Refute pipeline parsing error")
    (refute (is-err? (ip/parseIndented "res ?? fallback\n")) "Refute coalescing parsing error")
    (refute (is-err? (ip/parseIndented "try send(id)\n")) "Refute prefix try parsing error")
    (refute (is-ok? (ip/parseIndented "")) "Refute empty source ok")
    (refute (= (list-length (il/tokenize "foo?bar")) 1) "Refute single token for foo?bar")
    (refute (= (list-length (il/tokenize "-42")) 3) "Refute 3 tokens (separate minus and number) for negative integer")
    (refute (= (list-length (il/tokenize "-3.14")) 3) "Refute 3 tokens (separate minus and number) for negative float")
    (refute (= (list-length (il/tokenize "x - 42")) 2) "Refute 2 tokens for subtraction with spaces")
    (refute (= (list-length (il/tokenize "??")) 3) "Refute 3 tokens (separate questions) for coalescing operator")
    (refute (= (list-length (il/tokenize "?.")) 3) "Refute 3 tokens for optchain operator")
    (refute (= (list-length (il/tokenize "|>")) 3) "Refute 3 tokens for pipe operator")
    (refute (= (list-length (il/tokenize "->")) 3) "Refute 3 tokens for arrow operator")
    (refute (rd/isAtom? (ip/desugarDot "user.name")) "Refute atom result for dot projection")
    (refute (string-contains? (rd/renderSexpr (ip/desugarDot "a.b.c")) "a.b") "Refute unlowered dot notation")
    (refute (string-contains? (rd/renderSexpr (ip/desugarTry (rd/makeAtom "x"))) "undefined") "Refute undefined in try desugar")
    (refute (is-err? (ip/parseIndented (str "if a:\n  1\nelse:\n  2\n"))) "Refute if/else block parse error")
    true))

(df runTests [] -> Bool
  :d "Runs all test suites in conformanceTest."
  (do
    (assert (testAdversarialCases) "testAdversarialCases must pass")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass")
    true))

(df RunTests [] -> Bool
  :d "Canonical runner export"
  (runTests))
