(module testSelect/partial :x [runTests] :i [])

; (:m :ref TEST-RUNNER-SELECT :do "the grader's fixture: an assertion fails, then the test writes to stderr without a newline and returns true, so under --keep-going the runtime's own line would follow the unfinished one")
fn ! testPartial -> Bool
  (do (assert (= (stringLength "ab") 3) "partial breaks on purpose")
      (fdWrite 2 "progress")
      true)

fn ! runTests -> Bool
  (testPartial)
