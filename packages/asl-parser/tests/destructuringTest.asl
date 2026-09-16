(module asl-parser/destructuringTest
  :d "Falsifiable test suite for Task 52602 Record and List Pattern Destructuring in Let and Function Bindings."
  :x [runTests]
  :i [(indentParser :a ip) (reader :a rd)])

(df testListDestructuringPair [] -> Bool
  :d "Verifies 2-element list destructuring [a b] = pair desugars into canonical let bindings."
  (let [(src (str "let [a b] = pair\n"
                  "  (+ a b)\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (= r "(let [(a (list-get pair 0)) (b (list-get pair 1))] (+ a b))")
                 (str "Must desugar list destructuring [a b] = pair: got " r))
         (assert (string-contains? r "(a (list-get pair 0))") "Must bind a to index 0")
         (assert (string-contains? r "(b (list-get pair 1))") "Must bind b to index 1")
         (assert (string-contains? r "(+ a b)") "Must retain body expression")
         (refute (string-contains? r "(a (list-get pair 1))") "Binding order for a must not be inverted to index 1")
         (refute (string-contains? r "(b (list-get pair 0))") "Binding order for b must not be inverted to index 0")
         (refute (string-contains? r "[a b] =") "Desugared form must not retain raw bracket pattern")
         (refute (string-contains? r "<body>") "Explicit body must not be replaced by placeholder")
         true))
      ((err msg)
       (refute true (str "Failed to parse list destructuring [a b] = pair: " msg))
       false))))

(df testListDestructuringPairWithoutBody [] -> Bool
  :d "Verifies list destructuring 'let [a b] = pair' without body defaults to canonical let with placeholder body."
  (let [(src "let [a b] = pair\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (= r "(let [(a (list-get pair 0)) (b (list-get pair 1))] <body>)")
                 (str "Must desugar 'let [a b] = pair' with placeholder body: got " r))
         (assert (string-contains? r "(a (list-get pair 0))") "Must bind a to index 0")
         (assert (string-contains? r "(b (list-get pair 1))") "Must bind b to index 1")
         (assert (string-contains? r "<body>") "Must emit placeholder body")
         (refute (string-contains? r "(a (list-get pair 1))") "Binding order must not invert")
         (refute (string-contains? r "[a b] =") "Must eliminate bracket syntax")
         true))
      ((err msg)
       (refute true (str "Failed to parse 'let [a b] = pair': " msg))
       false))))

(df testListDestructuringThreeElements [] -> Bool
  :d "Verifies 3-element list destructuring [x y z] = coords desugars with sequential indexing."
  (let [(src (str "let [x y z] = coords\n"
                  "  (+ x y z)\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (= r "(let [(x (list-get coords 0)) (y (list-get coords 1)) (z (list-get coords 2))] (+ x y z))")
                 (str "Must desugar 3-element list destructuring: got " r))
         (assert (string-contains? r "(x (list-get coords 0))") "Must bind x to index 0")
         (assert (string-contains? r "(y (list-get coords 1))") "Must bind y to index 1")
         (assert (string-contains? r "(z (list-get coords 2))") "Must bind z to index 2")
         (refute (string-contains? r "(x (list-get coords 2))") "Index for x must not invert to 2")
         (refute (string-contains? r "(z (list-get coords 0))") "Index for z must not invert to 0")
         (refute (string-contains? r "(y (list-get coords 0))") "Index for y must not shift to 0")
         (refute (string-contains? r "[x y z]") "Must eliminate raw bracket pattern")
         true))
      ((err msg)
       (refute true (str "Failed to parse 3-element list destructuring: " msg))
       false))))

(df testRecordDestructuring [] -> Bool
  :d "Verifies record destructuring {name age} = person desugars into canonical property accessors."
  (let [(src (str "let {name age} = person\n"
                  "  (format name age)\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (= r "(let [(name (.-name person)) (age (.-age person))] (format name age))")
                 (str "Must desugar record destructuring: got " r))
         (assert (string-contains? r "(name (.-name person))") "Must bind name to (.-name person)")
         (assert (string-contains? r "(age (.-age person))") "Must bind age to (.-age person)")
         (refute (string-contains? r "(name (.-age person))") "Must refute swapped property accessor for name")
         (refute (string-contains? r "(age (.-name person))") "Must refute swapped property accessor for age")
         (refute (string-contains? r "{name age}") "Must eliminate brace pattern syntax")
         (refute (string-contains? r "<body>") "Explicit body must not be replaced by placeholder")
         true))
      ((err msg)
       (refute true (str "Failed to parse record destructuring: " msg))
       false))))

(df testRecordDestructuringWithoutBody [] -> Bool
  :d "Verifies record destructuring 'let {name age} = person' without body defaults to canonical let with placeholder body."
  (let [(src "let {name age} = person\n")
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (= r "(let [(name (.-name person)) (age (.-age person))] <body>)")
                 (str "Must desugar record destructuring without body: got " r))
         (assert (string-contains? r "(name (.-name person))") "Must bind name")
         (assert (string-contains? r "(age (.-age person))") "Must bind age")
         (assert (string-contains? r "<body>") "Must emit placeholder body")
         (refute (string-contains? r "(name (.-age person))") "Property accessors must not be swapped")
         (refute (string-contains? r "{name age}") "Must eliminate brace pattern")
         true))
      ((err msg)
       (refute true (str "Failed to parse record destructuring without body: " msg))
       false))))

(df testCombinedDestructuringWithTryOperator [] -> Bool
  :d "Verifies combined record destructuring with error propagation operator let {id data} = fetch?."
  (let [(src (str "let {id data} = fetch?\n"
                  "  (process id data)\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "(match fetch (ok __v __v) (err __e (return (err __e))))")
                 "Must lower postfix '?' into canonical try match form")
         (assert (string-contains? r "(id (.-id (match fetch (ok __v __v) (err __e (return (err __e))))))")
                 "Must bind id to (.-id ...) on lowered try expression")
         (assert (string-contains? r "(data (.-data (match fetch (ok __v __v) (err __e (return (err __e))))))")
                 "Must bind data to (.-data ...) on lowered try expression")
         (assert (string-contains? r "(process id data)") "Must preserve body expression")
         (refute (string-contains? r "fetch?") "Must not retain raw try operator")
         (refute (string-contains? r "{id data}") "Must not retain brace pattern")
         (refute (string-contains? r "(id (.-data") "Must refute cross-wired field binding for id")
         (refute (string-contains? r "(data (.-id") "Must refute cross-wired field binding for data")
         (refute (string-contains? r "(return (ok") "Err arm in try lowering must not return ok")
         true))
      ((err msg)
       (refute true (str "Failed to parse combined try destructuring: " msg))
       false))))

(df testCombinedListDestructuringWithTryOperator [] -> Bool
  :d "Verifies list destructuring interoperating with '?' try operator let [first rest] = (readStream)?."
  (let [(src (str "let [first rest] = (readStream)?\n"
                  "  first\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "(match (readStream) (ok __v __v) (err __e (return (err __e))))")
                 "Must lower (readStream)? to canonical try form")
         (assert (string-contains? r "(first (list-get (match (readStream) (ok __v __v) (err __e (return (err __e)))) 0))")
                 "Must bind first to index 0 of lowered try expression")
         (assert (string-contains? r "(rest (list-get (match (readStream) (ok __v __v) (err __e (return (err __e)))) 1))")
                 "Must bind rest to index 1 of lowered try expression")
         (refute (string-contains? r "(readStream)?") "Must not retain raw try expression")
         (refute (string-contains? r "(first (list-get (match (readStream) (ok __v __v) (err __e (return (err __e)))) 1))")
                 "Index 1 must not be bound to first variable")
         (refute (string-contains? r "[first rest]") "Must not retain raw bracket pattern")
         true))
      ((err msg)
       (refute true (str "Failed to parse list destructuring with try: " msg))
       false))))

(df testCombinedDestructuringWithDotAccess [] -> Bool
  :d "Verifies desugarDot interoperates cleanly with record and list destructuring."
  (let [(src (str "let {first last} = user.profile.name\n"
                  "  first\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "(.-name (.-profile user))") "Must lower dot-access path")
         (assert (string-contains? r "(first (.-first (.-name (.-profile user))))") "Must bind first to nested accessor")
         (assert (string-contains? r "(last (.-last (.-name (.-profile user))))") "Must bind last to nested accessor")
         (refute (string-contains? r "user.profile.name") "Raw dot identifier must not remain unlowered")
         (refute (string-contains? r "(first (.-last") "Field accessors must not be swapped")
         true))
      ((err msg)
       (refute true (str "Failed to parse dot-access destructuring: " msg))
       false))))

(df testDestructuringInFunctionBindings [] -> Bool
  :d "Verifies let destructuring syntax inside indented function body lowers to canonical df."
  (let [(src (str "fn sumCoords p: Point -> Int\n"
                  "  let [x y] = p\n"
                  "  + x y\n"))
        (res (ip/parseIndented src))]
    (mt res
      ((ok sexpr)
       (let [(r (rd/renderSexpr sexpr))]
         (assert (string-contains? r "df sumCoords") "Must define sumCoords function")
         (assert (string-contains? r "[(p Point)]") "Must parse parameter vector")
         (assert (string-contains? r "-> Int") "Must parse return type")
         (assert (string-contains? r "(let [(x (list-get p 0)) (y (list-get p 1))] (+ x y))")
                 "Must lower let destructuring within function body")
         (refute (string-contains? r "(x (list-get p 1))") "Binding order must not invert")
         (refute (string-contains? r "let [x y]") "Must eliminate let bracket syntax")
         true))
      ((err msg)
       (refute true (str "Failed to parse function with destructuring: " msg))
       false))))

(df testSingleLineInlineBodyDestructuring [] -> Bool
  :d "Verifies single-line let destructuring with inline body expressions."
  (let [(src1 "let [a b] = pair in (+ a b)\n")
        (res1 (ip/parseIndented src1))]
    (mt res1
      ((ok sexpr1)
       (let [(r1 (rd/renderSexpr sexpr1))]
         (assert (= r1 "(let [(a (list-get pair 0)) (b (list-get pair 1))] (+ a b))")
                 (str "Must desugar let with 'in' inline body: got " r1))
         (refute (string-contains? r1 " in ") "Keyword 'in' must not appear in AST")
         (refute (string-contains? r1 "<body>") "Must use inline body instead of placeholder")
         true))
      ((err msg1)
       (refute true (str "Failed single-line in-let: " msg1))
       false)))
  (let [(src2 "let {x y} = pt: (+ x y)\n")
        (res2 (ip/parseIndented src2))]
    (mt res2
      ((ok sexpr2)
       (let [(r2 (rd/renderSexpr sexpr2))]
         (assert (= r2 "(let [(x (.-x pt)) (y (.-y pt))] (+ x y))")
                 (str "Must desugar let with colon inline body: got " r2))
         (refute (string-contains? r2 "pt:") "Colon must be consumed as separator")
         true))
      ((err msg2)
       (refute true (str "Failed single-line colon-let: " msg2))
       false)))
  (let [(src3 "let [a b] = pair (+ a b)\n")
        (res3 (ip/parseIndented src3))]
    (mt res3
      ((ok sexpr3)
       (let [(r3 (rd/renderSexpr sexpr3))]
         (assert (= r3 "(let [(a (list-get pair 0)) (b (list-get pair 1))] (+ a b))")
                 (str "Must desugar single-line space-separated body: got " r3))
         (refute (string-contains? r3 "<body>") "Must use inline body")
         true))
      ((err msg3)
       (refute true (str "Failed single-line space-let: " msg3))
       false))))

(df testDirectDesugarDestructuring [] -> Bool
  :d "Verifies direct invocation of desugarDestructuring for list and record patterns."
  (let [(recNode (ip/desugarDestructuring true (list "foo" "bar") (rd/makeAtom "rec") (list)))
        (recStr (rd/renderSexpr recNode))]
    (assert (= recStr "(let [(foo (.-foo rec)) (bar (.-bar rec))] <body>)")
            (str "Direct record destructuring lowering mismatch: " recStr))
    (refute (string-contains? recStr "(foo (.-bar rec))") "Direct record binding must not be cross-wired")
    (let [(listNode (ip/desugarDestructuring false (list "e0" "e1" "e2" "e3") (rd/makeAtom "vec") (list)))
          (listStr (rd/renderSexpr listNode))]
      (assert (= listStr "(let [(e0 (list-get vec 0)) (e1 (list-get vec 1)) (e2 (list-get vec 2)) (e3 (list-get vec 3))] <body>)")
              (str "Direct 4-element list destructuring mismatch: " listStr))
      (refute (string-contains? listStr "(e0 (list-get vec 3))") "Direct list binding must not be inverted")
      true)))

(df runTests [] -> Bool
  :d "Runs all falsifiable unit tests for record and list pattern destructuring."
  (assert (testListDestructuringPair) "testListDestructuringPair passed")
  (assert (testListDestructuringPairWithoutBody) "testListDestructuringPairWithoutBody passed")
  (assert (testListDestructuringThreeElements) "testListDestructuringThreeElements passed")
  (assert (testRecordDestructuring) "testRecordDestructuring passed")
  (assert (testRecordDestructuringWithoutBody) "testRecordDestructuringWithoutBody passed")
  (assert (testCombinedDestructuringWithTryOperator) "testCombinedDestructuringWithTryOperator passed")
  (assert (testCombinedListDestructuringWithTryOperator) "testCombinedListDestructuringWithTryOperator passed")
  (assert (testCombinedDestructuringWithDotAccess) "testCombinedDestructuringWithDotAccess passed")
  (assert (testDestructuringInFunctionBindings) "testDestructuringInFunctionBindings passed")
  (assert (testSingleLineInlineBodyDestructuring) "testSingleLineInlineBodyDestructuring passed")
  (assert (testDirectDesugarDestructuring) "testDirectDesugarDestructuring passed")
  true)
