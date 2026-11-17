(module testSelect/echoSite :x [runTests] :i [])

; (:m :ref TEST-RUNNER-SELECT :do "a passing suite that echoes the site line of a negative fixture to stderr, as suites testing failure output do; testBroken echoes the same and then really fails")
fn ! echo -> Bool
  (do (fdWrite 2 "x.asl:3:7: ERR_ASSERT: assertion failed: an echoed negative case\n")
      true)

fn ! testEcho -> Bool
  (do (assert (echo) "the echo is written")
      true)

fn ! testBroken -> Bool
  (do (assert (echo) "the echo is written")
      (assert (= (stringLength "ab") 3) "broken breaks on purpose")
      true)

fn ! runTests -> Bool
  (testEcho)
