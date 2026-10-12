(module asl-parser/fieldDotParityTest
  :x [runTests]
  :i [(asl-parser/ast :a ast) (asl-parser/lexer :a lx) (asl-parser/reader :a rd)
      (tools/nativeTest :a nt) (tools/fleet/run :a fr)])

fn tree e: rd/SExpr -> String
  (mt e
    ((rd/sexprAtom v) v)
    ((rd/sexprList items) (str "(" (stringJoin (map tree items) " ") ")"))
    ((rd/sexprVect items) (str "[" (stringJoin (map tree items) " ") "]")))

fn selfTree src: String -> (Result String String)
  (mt (ast/readForms (lx/tokenize src))
    ((ok forms) (ok (stringJoin (map (fn [pf] (tree pf.expr)) forms) " ")))
    ((err e) (err e.msg)))

fn selfRead src: String -> (Result String String)
  (mt (ast/readForms (lx/tokenize src))
    ((ok forms) (ok (stringJoin (map (fn [pf] (rd/renderSexpr pf.expr)) forms) " ")))
    ((err e) (err e.msg)))

fn ! nativeRun expr: String -> fr/Done
  (let [(probePath "asl/packages/asl-parser/tests/tmpFieldDotProbe.asl")
        (src (str "(module fieldDotProbe :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println " expr ")\n      (ok 0))\n"))
        (wRes (fileWrite probePath src))]
    (do
      (assert (ok? wRes) "probe source must write")
      (let [(built (nt/prepareRun probePath (nt/fingerprint)))]
        (mt built.binary
          ((none) (do (assert false (str "probe builds natively: " built.reason)) (fr/Done :idx 0 :exit 1 :out "" :ms 0 :verdict "buildFailed")))
          ((some bin) (let [(res (fr/runOne (fr/job (list bin) "." (fr/childEnv (list))))) (_ (pathRemove probePath))] res))))))

fn ! nativeBuildFails expr: String -> Bool
  (let [(probePath "asl/packages/asl-parser/tests/tmpFieldDotRejectProbe.asl")
        (src (str "(module fieldDotRejectProbe :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println " expr ")\n      (ok 0))\n"))
        (wRes (fileWrite probePath src))
        (built (nt/prepareRun probePath (nt/fingerprint)))
        (_ (pathRemove probePath))]
    (and (ok? wRes) (none? built.binary)))

fn ! agrees src: String want: String -> Bool
  (let [(direct (nativeRun src))
        (lowered (optionOr (resultToOption (selfRead src)) "lowering failed"))
        (viaSelf (nativeRun lowered))]
    (do
      (assert (= direct.out want) (str "a native run of " src " is " want ", got " direct.out))
      (assert (= viaSelf.out want) (str "self-hosted lowering " lowered " runs as " want ", got " viaSelf.out))
      true))

fn ! rejects src: String -> Bool
  (let [(self (selfRead src))]
    (do
      (assert (mt self ((err m) (stringContains? m "ERR_READ_FIELD")) ((ok s) false)) (str "self-hosted reader rejects " src " with ERR_READ_FIELD"))
      (assert (nativeBuildFails src) (str "a native build of " src " also fails"))
      true))

fn shapes -> Bool
  (do
    (assert (= (selfTree "r.a.b") (ok "(.-b (.-a r))")) "a.b.c chains left to right")
    (assert (= (selfTree "q/x.y") (ok "(.-y q/x)")) "alias/name.f applies to the qualified name")
    (assert (= (selfTree "(g r).h.i") (ok "(.-i (.-h (g r)))")) "(expr).f.g applies to the expression")
    (assert (= (selfRead "(list r.a.b (g r).h q/x.y 2.5)") (ok "(list r.a.b (g r).h q/x.y 2.5)")) "the printer writes field access in postfix form")
    (assert (= (selfRead "(list 1.5 -0.25 :k.v? \"s.t\")") (ok "(list 1.5 -0.25 :k.v? \"s.t\")")) "floats, keywords and strings keep their dots")
    (assert (= (selfRead "(module m.n :i [(a.b.c :a q)])") (ok "(module m.n :import [(a.b.c :as q)])")) "a module header keeps dotted paths")
    true)

fn ! runTests -> Bool
  (and (shapes)
    (and (agrees "(let [(r {:a 1 :b {:c 2}})] (list r.a r.b.c))" "(1 2)\n")
      (and (agrees "(let [(r {:a {:b 5}})] (do r.a).b)" "5\n")
        (and (agrees "(list 1.5 -0.25 :a.b? \"s.t\")" "(1.5 -0.25 :a.b? \"s.t\")\n")
          (and (agrees "(let [(r {:k 1 :v 2})] (with r :v 3).v)" "3\n")
            (and (rejects "(do 1).a..b") (and (rejects "(list 1 .a)") (and (rejects "(.-a r)") (agrees "(list :.-a \"(.-a r)\")" "(:.-a \"(.-a r)\")\n")))))))))
