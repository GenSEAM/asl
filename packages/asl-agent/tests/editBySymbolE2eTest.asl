(module aslAgent/tests/editBySymbolE2eTest
  :x [runTests]
  :i [(aslHarness/tests/agentLoopRecorderKit :a rk)
      (aslAgent/tests/gitInitKit :a gk)
      (aslAgent/exec :a ex)
      (aslAgent/aslOps :a o)
      (aslAgent/core :a c)
      (aslAgent/runOps :a r)
      (aslAgent/txn :a t)])

; (:m :ref EDIT-BY-SYMBOL :do "replaceDef through the real engine: ex/execOp! with ao/runAsl, the real read :symbol span and the real txn write, on an ASL module of about 300 lines; nothing in the run is stubbed, so an undeclared effect or an outline without spans turns it red")
fn strField rec: (List (Pair String ex/Val)) k: String -> String
  (match (ex/recGet rec k)
    ((some v) (match v ((ex/vStr s) s) (_ "")))
    ((none) ""))

fn stepOp opName: String kvs: (List (Pair String c/KvVal)) -> (List (Pair String c/KvVal))
  (listAppend (list (pair "type" (c/kvStr "step")) (pair "op" (c/kvStr opName))) kvs)

fn mid i: Int64 -> String
  (str "fn mid" (stringFromInt64 i) " x: Int64 -> Int64\n  (+ x " (stringFromInt64 i) ")\n\n")

fn baseText -> String
  (str "(module fixture/big\n  :x [alpha omega strParens commented dup])\n\n"
    "fn alpha -> Int64\n  (+ 1 2)\n\n"
    (stringJoin (map mid (range 0 45)) "")
    "fn strParens -> String\n  (str \"(( unbalanced\" \")\" \"a) b (c\")\n\n"
    "fn commented -> Int64\n  (* 3 4)\n; (:m :do \"a trailing comment after commented\")\n; another comment line\n\n"
    "fn dup -> Int64\n  1\n\n"
    (stringJoin (map mid (range 45 90)) "")
    "fn dup -> Int64\n  2\n\n"
    "fn omega -> Int64\n  (- 9 1)\n")

fn ! case! env: ex/ExecEnv root: String repo: String file: String text: String symbol: String body: String -> (Pair (List (Pair String ex/Val)) String)
  (let [path (str root "/" file)
        reset (ok? (fileWrite path text))
        run (fn [f d] (let [x (o/runAsl repo f d 120 (none) "subprocess")] (t/aslRun (o/runExit x) (o/runStdout x) (o/runStderr x))))
        rec (ex/execOp! (stepOp "replaceDef" (list (pair "file" (c/kvStr file)) (pair "symbol" (c/kvStr symbol)) (pair "content" (c/kvStr body))))
              env (r/newProcs) (fn [] "gid") (fn [p] true) (fn [a b n] true) run).rec]
    (pair rec (resultOr (fileReadString path) "<unreadable>")))

fn ! runTests -> Bool
  (let [root (rk/freshRecorderRoot! "editBySymbolE2e")
        tmp root
        repo (resultOr (realPath ".") ".")
        d1 (ok? (dirCreate root))
        d2 (ok? (dirCreate (str root "/.asl/vfs")))
        s1 (ok? (fileWrite (str root "/subject.txt") "subject\n"))
        g1 (and s1 (gk/initGitRepo! root "editBySymbolE2e" "editBySymbolE2e@example.invalid"))
        effects (resultOr (t/loadEffects! repo) (list))
        base (baseText)
        env (ex/makeExecEnv root repo "auto" (list "**") false "HEAD" (list)
              effects
              "" (list) 20000 120 (none) "editBySymbolE2e" (none))
        cA (case! env root repo "big.asl" base "alpha" "fn alpha -> Int64\n  (+ 10 20)\n")
        cZ (case! env root repo "big.asl" base "omega" "fn omega -> Int64\n  (- 90 1)")
        cM (case! env root repo "big.asl" base "commented" "fn commented -> Int64\n  (* 30 40)")
        cS (case! env root repo "big.asl" base "strParens" "fn strParens -> String\n  (str \"(( new\" \")\" \"x) y (z\" \")))\")")
        cD (case! env root repo "big.asl" base "dup" "fn dup -> Int64\n  3")
        cN (case! env root repo "big.asl" base "mid4x" "fn mid4x -> Int64\n  0")
        bad (str base "\n(fn broken (((\n")
        cB (case! env root repo "bad.asl" bad "alpha" "fn alpha -> Int64\n  (+ 10 20")
        cT (case! env root repo "plain.txt" "just text\nno defs\n" "alpha" "fn alpha -> Int64\n  1")
        shapeText (str base "\nschema Shape\n  (:f a Int64)\n\nfn Shape -> Int64\n  5\n")
        cH (case! env root repo "shape.asl" shapeText "Shape" "fn Shape -> Int64\n  6")
        cleaned (and (ok? (pathRemove tmp)) (not (fileExists? tmp)))]
    (do
      (assert (and (!= tmp "") (and d1 (and d2 g1))) "scratch workspace made")
      (assert (> (listLength (stringSplit base "\n")) 290) "the fixture is about 300 lines")
      (assert (= (pairSecond cA) (stringReplace base "fn alpha -> Int64\n  (+ 1 2)" "fn alpha -> Int64\n  (+ 10 20)")) (str "first def lands byte-exact, got " (strField (pairFirst cA) "status") " " (strField (pairFirst cA) "error") " " (strField (pairFirst cA) "message")))
      (assert (= (pairSecond cZ) (stringReplace base "fn omega -> Int64\n  (- 9 1)" "fn omega -> Int64\n  (- 90 1)")) (str "last def lands byte-exact, got " (strField (pairFirst cZ) "error") " " (strField (pairFirst cZ) "message")))
      (assert (= (pairSecond cM) (stringReplace base "fn commented -> Int64\n  (* 3 4)" "fn commented -> Int64\n  (* 30 40)")) (str "a def followed by comments lands byte-exact, got " (strField (pairFirst cM) "error") " " (strField (pairFirst cM) "message")))
      (assert (= (pairSecond cS) (stringReplace base "fn strParens -> String\n  (str \"(( unbalanced\" \")\" \"a) b (c\")" "fn strParens -> String\n  (str \"(( new\" \")\" \"x) y (z\" \")))\")")) (str "a def with parens in strings lands byte-exact, got " (strField (pairFirst cS) "error") " " (strField (pairFirst cS) "message")))
      (assert (and (= (strField (pairFirst cD) "error") "ERR_AMBIGUOUS_SYMBOL") (= (pairSecond cD) base)) (str "a name defined twice is refused and the file is unchanged, got " (strField (pairFirst cD) "error")))
      (assert (and (= (strField (pairFirst cN) "error") "ERR_NO_SYMBOL") (< (stringLength (strField (pairFirst cN) "message")) 400)) (str "an unknown name is refused with a bounded list, got " (strField (pairFirst cN) "error") " " (stringFromInt64 (stringLength (strField (pairFirst cN) "message")))))
      (assert (and (!= (strField (pairFirst cB) "status") "ok") (= (pairSecond cB) bad)) (str "a body that unbalances the file is refused and the file is unchanged, got " (strField (pairFirst cB) "status")))
      (assert (!= (strField (pairFirst cT) "status") "ok") (str "a text file has no definitions, got " (strField (pairFirst cT) "error")))
      (assert (= (strField (pairFirst cA) "status") "ok") "the landed receipt is ok")
      (assert (and (= (strField (pairFirst cH) "error") "ERR_AMBIGUOUS_SYMBOL") (= (pairSecond cH) shapeText)) (str "a schema and a fn of one name are two definitions: refused, file unchanged, got " (strField (pairFirst cH) "error")))
      (assert (> (listLength effects) 0) "effects.asn loaded through loadEffects!")
      (assert cleaned "the scratch workspace is removed")
      true))
