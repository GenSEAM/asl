(module asl-agent/tests/replyWasteTest
  :x [runTests]
  :i [(asl-agent/replyWaste :a rw)])

fn ! runTests -> Bool
  (let [(stepOnly (rw/replyWaste "(:step :op \"read\" :file \"a.asl\")"))
        (proseThenWrite (rw/replyWaste "Sure, here is the plan.\n(:write :file \"a.asl\" :content :raw)"))
        (plain (rw/replyWaste "Just some prose with no forms at all."))
        (intentThenStep (rw/replyWaste "(:intent :kind :plan)\n(:step :op \"gate\")"))
        (leadingSpace (rw/replyWaste "\n\n(:step :op \"gate\")"))
        (stringStep (rw/replyWaste "(:intent :text \"(:step :op gate)\")"))
        (stringClose (rw/replyWaste "(:intent :text \"x) (:step\")"))
        (parenProse (rw/replyWaste "See (below) for details."))
        (quotedStepOnly (rw/replyWaste "\"(:step :op \\\"gate\\\")\""))
        (quotedStepProse (rw/replyWaste "He wrote \"(:step :op gate)\" in the reply."))
        (intentThenQuoted (rw/replyWaste "(:intent :kind :plan)\n\"(:step)\""))]
    (do
      (assert (and (= stepOnly.prose 0) (not stepOnly.noStep))
        (str "a reply that is only a step has prose 0 and a step, got prose " (stringFromInt64 stepOnly.prose) " noStep " (if stepOnly.noStep "true" "false")))
      (assert (and (= proseThenWrite.prose 24) (not proseThenWrite.noStep))
        (str "prose then a write form has prose 24 and a step, got prose " (stringFromInt64 proseThenWrite.prose) " noStep " (if proseThenWrite.noStep "true" "false")))
      (assert (and plain.noStep (= plain.prose plain.total))
        (str "plain prose has no step and prose equal to total, got prose " (stringFromInt64 plain.prose) " total " (stringFromInt64 plain.total)))
      (assert (not intentThenStep.noStep)
        (str "an intent form followed by a step form has a step, got noStep " (if intentThenStep.noStep "true" "false")))
      (assert (and (= leadingSpace.prose 0) (not leadingSpace.noStep))
        (str "leading whitespace before a step form is not prose, got prose " (stringFromInt64 leadingSpace.prose)))
      (assert stringStep.noStep
        (str "a step name inside a string literal is not a step form, got noStep " (if stringStep.noStep "true" "false")))
      (assert stringClose.noStep
        (str "a close paren inside a string literal does not end the form, got noStep " (if stringClose.noStep "true" "false")))
      (assert (and parenProse.noStep (= parenProse.prose parenProse.total))
        (str "prose parens are not forms, got prose " (stringFromInt64 parenProse.prose)))
      (assert (and quotedStepOnly.noStep (= quotedStepOnly.prose quotedStepOnly.total))
        (str "a quoted step form is not a step, got prose " (stringFromInt64 quotedStepOnly.prose) " total " (stringFromInt64 quotedStepOnly.total) " noStep " (if quotedStepOnly.noStep "true" "false")))
      (assert (and quotedStepProse.noStep (= quotedStepProse.prose quotedStepProse.total))
        (str "prose quoting a step form is not a step, got prose " (stringFromInt64 quotedStepProse.prose) " noStep " (if quotedStepProse.noStep "true" "false")))
      (assert intentThenQuoted.noStep
        (str "a quoted step after an intent form is not a step, got noStep " (if intentThenQuoted.noStep "true" "false")))
      true))
