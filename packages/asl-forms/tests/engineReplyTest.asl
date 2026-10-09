(module asl-forms/tests/engineReplyTest :x [runTests] :i [(asl-forms/delegate :a d)])

fn runTests -> Bool
  (do
    (assert (not (d/engineOk? "(:x :status :okay)")) "an :okay status is not :ok")
    (assert (not (d/engineOk? "(: :status :ok)")) "an empty engine tag is rejected")
    (assert (not (d/engineOk? "(:x :status :oké)")) "a Unicode word continuation is not an :ok boundary")
    (assert (d/engineOk? "(:x :status :ok)") "a non-word ASCII boundary remains accepted")
    (assert (d/engineOk? "(:x :status :ok—)") "a non-word Unicode punctuation boundary remains accepted")
    true)
