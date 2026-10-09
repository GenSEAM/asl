(module asl-parser/desugarHostTest :x [runTests] :i [(indentParser :a ip) (reader :a rd)])

fn ! hostEval expr: String -> ProcessOutput
  (processRun (str "asl/host/out/asl-host eval '" expr "'"))

fn lowered src: String -> String
  (mt (ip/parseIndented src) ((ok s) (rd/renderSexpr s)) ((err e) (str "parse error: " e)))

fn ! testListDestructuringRuns -> Bool
  (let [(form (lowered "let [a b] = pair\n  (+ a b)\n")) (ran (hostEval (str "(let [(pair (list 1 2))] " form ")")))] (do (assert (= ran.exitCode 0) (str "the host runs the destructuring lowering " form ", stderr: " ran.stderr ran.stdout)) (assert (= ran.stdout "3\n") (str "let [a b] = (list 1 2) binds the elements, got " ran.stdout)) true))

fn ! testThreeElementDestructuringRuns -> Bool
  (let [(form (lowered "let [x y z] = coords\n  (- (* x y) z)\n")) (ran (hostEval (str "(let [(coords (list 3 4 5))] " form ")")))] (do (assert (= ran.stdout "7\n") (str "let [x y z] = (list 3 4 5) binds each index in order, got " ran.stdout ran.stderr " from " form)) true))

fn ! testTryOkRuns -> Bool
  (let [(form (rd/renderSexpr (ip/desugarTry (rd/makeList (list (rd/makeAtom "ok") (rd/makeAtom "42")))))) (ran (hostEval form))] (do (assert (= ran.exitCode 0) (str "the host accepts the try lowering " form ", stderr: " ran.stderr)) (assert (= ran.stdout "42\n") (str "try of (ok 42) yields 42, got " ran.stdout)) true))

fn ! testTryErrRuns -> Bool
  (let [(form (rd/renderSexpr (ip/desugarTry (rd/makeList (list (rd/makeAtom "err") (rd/makeAtom "\"fail\"")))))) (ran (hostEval form))] (do (assert (= ran.exitCode 0) (str "the host accepts the try lowering " form ", stderr: " ran.stderr)) (assert (= ran.stdout "(err \"fail\")\n") (str "try of (err \"fail\") yields the error, got " ran.stdout)) true))

fn ! runTests -> Bool
  (do (assert (testListDestructuringRuns) "list destructuring runs on the host")
      (assert (testThreeElementDestructuringRuns) "three-element destructuring runs on the host")
      (assert (testTryOkRuns) "try ok runs on the host")
      (assert (testTryErrRuns) "try err runs on the host")
      true)
