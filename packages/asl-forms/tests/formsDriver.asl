(module asl-forms/tests/formsDriver :x [formsBin!] :i [(tools/nativeTest :a nt)])

fn ! formsBin! repo: String -> String
  (let [(built (nt/prepareRun "asl/packages/asl-forms/src/main.asl" (nt/fingerprint)))]
    (match built.binary
      ((some b) (if (stringStartsWith? b "/") b (str repo "/" b)))
      ((none) (do (assert false (str "asl-forms main builds natively in run mode: " built.reason)) ""))))
