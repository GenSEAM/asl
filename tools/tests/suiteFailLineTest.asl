(module asl-tools/tests/suiteFailLineTest :x [runTests] :i [(asl-tools/nativeTest :a nt) (asl-forms/kernel :a k)])

fn staged -> String
  ".asl/cache/nativeTest/outside/33fd96.asl"

fn pkgStaged -> String
  ".asl/cache/nativeTest/outsidePkg/ab12/vtbot/asl/tests/xTest.asl"

; (:m :do "the rejected body as nativeTest's checker gate renders it: diagnostics and the :indentFix hint name the staged copy")
fn reason rel: String -> String
  (str rel ":6:10: parse unmatched ')'\n(:indentFix :file \"" rel "\" :indent ((:delete \")\" :line 6 :col 10 :stray true)) :fix \"(:fix :file \\\"" rel "\\\" :by :indent :apply true)\")")

; (:m :ref FIX-HINT-PATH-ESCAPE :do "the :indentFix form of a FAIL body, without the suite verdict suffix")
fn hintLine text: String -> String
  (let [(l (optionOr (listHead (filter (fn [(x String)] -> Bool (stringStartsWith? x "(:indentFix")) (stringSplit text "\n"))) ""))]
    (if (stringEndsWith? l " (after 0 asserts)") (optionOr (stringSlice l 0 (- (stringLength l) 18)) l) l))

fn ! runTests -> Bool
  (let [(user "/tmp/poutFix/strayTest.asl")
        (outside (nt/suiteFailLine "/w" (staged) user (reason (staged))))
        (pkg (nt/suiteFailLine "/w" (pkgStaged) "../vtbot/asl/tests/xTest.asl" (reason (pkgStaged))))
        (inRoot (nt/suiteFailLine "/w" "asl/tools/tests/aTest.asl" "/w/asl/tools/tests/aTest.asl" (reason "asl/tools/tests/aTest.asl")))
        (odd "/tmp/a\"b\\c/strayTest.asl")
        (oddLine (nt/suiteFailLine "/w" (staged) odd (reason (staged))))
        (hint (k/parseStep (hintLine oddLine)))
        (fix (k/parseStep (k/kwOr hint.kwargs "fix" "")))]
    (do
      (assert (stringStartsWith? outside (str "FAIL " user ": " user ":6:10: parse")) "an outside suite's FAIL line and diagnostic name the user's path")
      (assert (stringContains? outside (str ":indentFix :file \"" user "\"")) "the :indentFix hint names the user's path")
      (assert (stringContains? outside (str ":fix :file \\\"" user "\\\"")) "the staged (:fix) form names the user's path")
      (refute (stringContains? outside ".asl/cache/nativeTest/outside") "no staged copy is named for an outside suite")
      (assert (stringEndsWith? outside " (after 0 asserts)") "the outside FAIL line keeps the suite verdict suffix")
      (assert (stringStartsWith? pkg "FAIL ../vtbot/asl/tests/xTest.asl: ../vtbot/asl/tests/xTest.asl:6:10:") "a suite of an outside package mirror is named by the user's path")
      (refute (stringContains? pkg "outsidePkg") "no package mirror path is named")
      (assert (= inRoot (nt/failLine "asl/tools/tests/aTest.asl" (reason "asl/tools/tests/aTest.asl"))) "an in-root suite keeps its root-relative failLine")
      (assert (stringStartsWith? oddLine (str "FAIL " odd ": " odd ":6:10: parse")) "a path with a quote and a backslash names the FAIL line and diagnostic raw")
      (assert (= (k/kwOr hint.kwargs "file" "") odd) "the :indentFix :file string reads back as the path with its quote and backslash")
      (assert (= (k/kwOr fix.kwargs "file" "") odd) "the (:fix) form inside the hint reads back as the path with its quote and backslash")
      (assert (= (k/kwOr fix.kwargs "apply" "") "true") "the (:fix) form keeps its :apply after the escaped path")
      true))
