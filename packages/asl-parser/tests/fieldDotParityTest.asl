(module asl-parser/fieldDotParityTest
  :x [runTests]
  :i [(asl-parser/ast :a ast) (asl-parser/lexer :a lx) (asl-parser/reader :a rd)])

fn ! hostEval expr: String -> ProcessOutput
  (processRun (str (optionOr (envGet "ASL_HOST") "asl/host/out/asl-host") " eval '" expr "' 2>&1"))

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

fn ! agrees src: String want: String -> Bool
  (let [(direct (hostEval src))
        (lowered (optionOr (resultToOption (selfRead src)) "lowering failed"))
        (viaSelf (hostEval lowered))]
    (do
      (assert (= direct.stdout want) (str "host reads " src " as " want ", got " direct.stdout))
      (assert (= viaSelf.stdout want) (str "self-hosted lowering " lowered " runs as " want ", got " viaSelf.stdout))
      true))

fn ! rejects src: String -> Bool
  (let [(direct (hostEval src))
        (self (selfRead src))]
    (do
      (assert (!= direct.exitCode 0) (str "host rejects " src ": " direct.stdout))
      (assert (mt self ((err m) (stringContains? m "ERR_READ_FIELD")) ((ok s) false)) (str "self-hosted reader rejects " src " with ERR_READ_FIELD"))
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
