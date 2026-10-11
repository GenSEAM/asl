(module asl-checker/tests/parityBTest
  :x [runTests]
  :i [(types :a ty) (ast :a a) (resolve :a r)])

fn diagsOf src: String -> (List ty/Diagnostic)
  (mt (a/parse src)
    ((err _) (list (ty/Diagnostic :code "parse" :message "source did not parse" :msg "" :line 0 :col 0 :path "test.asl")))
    ((ok forms) (r/resolveModule (r/collectSummary forms "test.asl") forms (mapEmpty))))

fn codesOf src: String -> (List String)
  (map (fn [(d ty/Diagnostic)] -> String d.code) (diagsOf src))

fn summaryOf src: String path: String -> r/ModuleSummary
  (r/collectSummary (mt (a/parse src) ((ok f) f) ((err _) (list))) path)

fn messagesWith src: String deps: (Map String r/ModuleSummary) -> (List String)
  (mt (a/parse src)
    ((err _) (list "parse"))
    ((ok forms) (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) (r/resolveModule (r/collectSummary forms "test.asl") forms deps))))

fn testNameBangMarksEffect -> Bool
  (do (assert (listEmpty? (codesOf "(fn loop! [] -> Int64 (do (println \"x\") 0))")) "a fn named loop! may call println")
      (assert (listEmpty? (codesOf "(fn ! loop [] -> Int64 (do (println \"x\") 0))")) "fn ! loop may call println")
      (assert (listContains? (codesOf "(fn loop [] -> Int64 (do (println \"x\") 0))") "rule-12") "an unmarked fn calling println is rule-12")
      (assert (listContains? (codesOf "(fn loop! [] -> Int64 0) (fn caller [] -> Int64 (loop!))") "rule-12") "calling a fn named loop! is effectful")
      (assert (listEmpty? (codesOf "(fn loop! [] -> Int64 0) (fn caller! [] -> Int64 (loop!))")) "a fn named caller! may call loop!")
      true)

fn testOperatorArity -> Bool
  (do (refute (listContains? (codesOf "(fn f [] -> Int64 (+ 1 2 3))") "arity") "+ takes three operands")
      (refute (listContains? (codesOf "(fn f [] -> Int64 (* 2))") "arity") "* takes one operand")
      (refute (listContains? (codesOf "(fn f [] -> Int64 (- 2))") "arity") "- takes one operand")
      (assert (listContains? (codesOf "(fn f [] -> Int64 (- 1 2 3))") "arity") "- does not take three operands")
      (assert (listContains? (codesOf "(fn f [] -> Int64 (/ 1 2 3))") "arity") "/ does not take three operands")
      (assert (listContains? (codesOf "(fn + [(a Int64) (b Int64)] -> Int64 a) (fn f [] -> Int64 (+ 1 2 3))") "arity") "a module fn named + keeps its own arity")
      true)

fn testFieldFromClosure -> Bool
  (let [(src "(fn f [(a Int64)] -> Int64 a.kinds)")
        (other (summaryOf "(module other :x [Rec] :i []) (schema Rec (:f kinds Int64))" "/w/other.asl"))
        (withOther (messagesWith src (mapSet (mapEmpty) "/w/other.asl" other)))
        (alone (messagesWith src (mapEmpty)))]
    (do (assert (listEmpty? withOther) (str "a field of a record in the loaded closure is known without a direct import: " (stringJoin withOther "; ")))
        (assert (listContains? alone "rule-2 no record in this module has a field kinds") (str "a field no loaded record declares is still rule-2: " (stringJoin alone "; ")))
        true))

fn testCycleThroughRootOnly -> Bool
  (let [(a (summaryOf "(module a :x [] :i [(b :a b)])" "/w/a.asl"))
        (b (summaryOf "(module b :x [] :i [(a :a a)])" "/w/b.asl"))
        (bx (summaryOf "(module b :x [] :i [(x :a x)])" "/w/b.asl"))
        (src "(module x :x [] :i [(a :a a)])")
        (inner (messagesWith src (mapSet (mapSet (mapEmpty) "/w/a.asl" a) "/w/b.asl" b)))
        (root (messagesWith src (mapSet (mapSet (mapEmpty) "/w/a.asl" a) "/w/b.asl" bx)))]
    (do (assert (listEmpty? (filter (fn [(m String)] -> Bool (stringStartsWith? m "rule-11")) inner)) (str "a cycle between a and b is not reported for x: " (stringJoin inner "; ")))
        (assert (listContains? root "rule-11 import cycle: x -> a -> b -> x") (str "a cycle back to x is reported once: " (stringJoin root "; ")))
        true))

fn testExhaustiveOverDeclaredEnums -> Bool
  (do (refute (listContains? (codesOf "(fn f [(o (Option Int64))] -> Int64 (mt o ((some t) t)))") "rule-4") "a match over Option without none passes")
      (refute (listContains? (codesOf "(fn f [(r (Result Int64 String))] -> Int64 (mt r ((ok v) v)))") "rule-4") "a match over Result without err passes")
      (assert (listContains? (codesOf "(enum Color (:c red []) (:c green [])) (fn f [(c Color)] -> Int64 (mt c ((red) 1)))") "rule-4") "a match over a declared enum missing a case is rule-4")
      (assert (listContains? (codesOf "(enum Maybe (:c none []) (:c some [(v Int64)])) (fn f [(x Maybe)] -> Int64 (mt x ((some v) v)))") "rule-4") "a local enum reusing some and none is its own declared enum, so a match missing none is rule-4")
      true)

fn testExactImportKeyWins -> Bool
  (let [(cliMain (summaryOf "(module asl-cli/main :x [] :i [])" "/w/asl-cli/src/main.asl"))
        (llvmMain (summaryOf "(module llvm/main :x [] :i [])" "/w/llvm/src/main.asl"))
        (src "(module t :x [] :i [(main :a m)])")
        (byPath (mapSet (mapSet (mapEmpty) "/w/asl-cli/src/main.asl" cliMain) "/w/llvm/src/main.asl" llvmMain))
        (keyed (messagesWith src (mapSet byPath "main" cliMain)))
        (unkeyed (messagesWith src byPath))]
    (do (assert (listEmpty? keyed) (str "the loader resolution of main is used: " (stringJoin keyed "; ")))
        (assert (listAny? (fn [(m String)] -> Bool (stringStartsWith? m "ERR_AMBIGUOUS_MODULE")) unkeyed) (str "without it main is ambiguous: " (stringJoin unkeyed "; ")))
        true))

fn testChainedQualifiedType -> Bool
  (let [(inner (summaryOf "(module inner :x [T] :i []) (schema T (:f a Int64)) (schema Hidden (:f b Int64))" "/w/inner.asl"))
        (outer (summaryOf "(module outer :x [] :i [(inner :a in)])" "/w/outer.asl"))
        (deps (mapSet (mapSet (mapEmpty) "/w/inner.asl" inner) "/w/outer.asl" outer))
        (good (messagesWith "(module t :x [] :i [(outer :a o)]) (fn f [(x o/in/T)] -> Int64 1)" deps))
        (hidden (messagesWith "(module t :x [] :i [(outer :a o)]) (fn f [(x o/in/Hidden)] -> Int64 1)" deps))]
    (do (assert (listEmpty? good) (str "o/in/T is the exported type T of inner: " (stringJoin good "; ")))
        (assert (listContains? hidden "rule-9 ERR_NOT_EXPORTED: Hidden is not an exported type of inner") (str "o/in/Hidden is checked against inner: " (stringJoin hidden "; ")))
        true))

fn testInvalidArmHead -> Bool
  (do (assert (listContains? (codesOf "(fn sealed [] -> Int64 1) (fn classify [] -> Bool (mt 3 (sealed false)))") "ERR_INVALID_MT_ARM") "a pattern naming a module fn is invalid")
      (assert (listContains? (codesOf "(fn classify [] -> Bool (mt 3 (println false)))") "ERR_INVALID_MT_ARM") "a pattern naming a builtin is invalid")
      (refute (listContains? (codesOf "(fn classify [] -> Bool (mt 3 (n false)))") "ERR_INVALID_MT_ARM") "a fresh name binds")
      (refute (listContains? (codesOf "(fn classify [(o (Option Int64))] -> Int64 (mt o ((some count) count) (none 0)))") "ERR_INVALID_MT_ARM") "a nested binder may reuse any name")
      (assert (listContains? (messagesWith "(module t :x [] :i [(priv :a p)]) (fn sealed [] -> Int64 1) (fn classify [] -> Bool (mt 3 (sealed false)))" (mapSet (mapEmpty) "/w/priv.asl" (summaryOf "(module priv :x [] :i []) (enum Hidden (:c sealed [] \"s\"))" "/w/priv.asl"))) "ERR_INVALID_MT_ARM mt arm has an invalid pattern head") "a module fn shadows a case of a dependency")
      true)

fn testNilIsUnknown -> Bool
  (do (assert (listContains? (messagesWith "(fn f [] -> Int64 (do nil 1))" (mapEmpty)) "rule-2 nil is not defined") "nil is not defined")
      (refute (listContains? (codesOf "(fn f [] -> Bool (do () true))") "rule-2") "() is still the unit literal")
      true)

fn testCapitalisedFnIsCall -> Bool
  (let [(dep (summaryOf "(module dep :x [Review] :i []) (fn Review [] -> Int64 1)" "/w/dep.asl"))
        (viaAlias (messagesWith "(module t :x [] :i [(dep :a d)]) (fn f [] -> Int64 (d/Review))" (mapSet (mapEmpty) "/w/dep.asl" dep)))]
    (do (assert (listEmpty? (codesOf "(fn RunTests [] -> Bool true) (fn f [] -> Bool (RunTests))")) "a local capitalised fn is called")
        (assert (listEmpty? viaAlias) (str "an imported capitalised fn is called: " (stringJoin viaAlias "; ")))
        (assert (listContains? (messagesWith "(fn f [] -> Bool (Nope))" (mapEmpty)) "rule-2 Nope is not a record type in this module") "an unknown capitalised head is still rule-2")
        true))

fn ! runTests -> Bool
  (do (assert (testCapitalisedFnIsCall) "capitalised fn heads are calls")
      (assert (testNilIsUnknown) "nil is an unknown symbol")
      (assert (testInvalidArmHead) "invalid pattern heads follow the host")
      (assert (testChainedQualifiedType) "a/b/T resolves through the import chain")
      (assert (testExactImportKeyWins) "an exact deps key wins over suffix matches")
      (assert (testExhaustiveOverDeclaredEnums) "exhaustiveness follows the host: declared enums only")
      (assert (testCycleThroughRootOnly) "rule-11 reports cycles through the checked module only")
      (assert (testOperatorArity) "operator arity follows the host")
      (assert (testFieldFromClosure) "field names come from the whole loaded closure")
      (assert (testNameBangMarksEffect) "a name ending in ! marks a fn effectful, as in the host")
      true)
