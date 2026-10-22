(module asl-cli/tests/evalRejectTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a run)])

fn workDir -> String
  "asl/packages/asl-cli/tests/evalRejectWork"

fn ! eval! root: String expr: String errFile: String -> run/Done
  (run/runOneLimited (run/job (list "/bin/sh" "-c" "exec \"$0\" eval \"$1\" 2>\"$EVAL_ERR\"" (str root "/bin/asl") expr) root (run/childEnv (list (str "EVAL_ERR=" errFile)))) (run/limits 300 64))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (made (dirCreate (workDir)))
        (unknownErr (str root "/" (workDir) "/unknown.err"))
        (arityErr (str root "/" (workDir) "/arity.err"))
        (unknown (eval! root "(someUnknownSymbol 123)" unknownErr))
        (arity (eval! root "(refute)" arityErr))
        (value (eval! root "(+ 20 22)" (str root "/" (workDir) "/value.err")))
        (unknownText (resultOr (fileReadString unknownErr) "unreadable"))
        (arityText (resultOr (fileReadString arityErr) "unreadable"))
        (removed (pathRemove (workDir)))]
    (do
      (assert (ok? made) "the work directory is created")
      (assert (= unknown.exit 1) (str "eval of an unbound symbol exits 1: " unknownText))
      (assert (= unknown.out "") (str "eval of an unbound symbol prints no value: " unknown.out))
      (assert (stringContains? unknownText "ERR_UNKNOWN_SYMBOL unbound symbol: someUnknownSymbol")
              (str "eval reports the checker diagnostic for a form native lowering rejects: " unknownText))
      (refute (stringContains? unknownText "ERR_HOST_ABSENT") (str "eval does not fall back to the retired host: " unknownText))
      (assert (= arity.exit 1) (str "eval of a bare refute exits 1: " arityText))
      (assert (stringContains? arityText "ERR_ARITY refute takes a condition") (str "eval reports refute arity: " arityText))
      (assert (= value.exit 0) (str "eval of a lowerable form still runs natively: " value.out))
      (assert (= (stringTrim value.out) "42") (str "eval prints the value: " value.out))
      (assert (ok? removed) "the work directory is removed")
      true))
