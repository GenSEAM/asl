(module aslAgent/tests/unwiredRetryTest
  :x [runTests]
  :i [(aslAgent/gateIntegrity :a gi)])

fn unwiredForm names: (List String) -> String
  (str "(:gateUnwired :fns (" (stringJoin (map (fn [n] (str "\"" n "\"")) names) " ") ") :do \"call each from the code path the task changes, then finish\")")

fn unwiredMessage names: (List String) -> String
  (str "unwired: new fns with no caller outside tests: " (stringJoin names ", ") "; call them from the code path the task changes, then finish" "\n" (unwiredForm names))

fn vacuousFormText -> String
  "(:gateVacuous :gates (\"./bin/asl test x\") :files (\"src/a.asl\") :do \"change the test so it fails with the file reverted\")"

fn vacuousMessage form: String -> String
  (str "a gate stayed green with src/a.asl reverted: ./bin/asl test x :passesOnRevert :exit 0" "\n" form)

fn shown v: (Option String) -> String
  (optionOr v "none")

fn ! runTests -> Bool
  (let [(names (list "a" "b"))
        (text (unwiredMessage names))
        (expected (unwiredForm names))
        (vform (vacuousFormText))
        (vmsg (vacuousMessage vform))]
    (do
      (assert (= (shown (gi/vacuousForm (pair false text))) expected) (str "an unwired message returns its form: " (shown (gi/vacuousForm (pair false text)))))
      (assert (= (shown (gi/vacuousRetry (pair false text) 0 2)) expected) "round 0 under the cap returns the form")
      (assert (= (shown (gi/vacuousRetry (pair false text) 1 2)) expected) "round 1 under the cap returns the form")
      (assert (= (shown (gi/vacuousRetry (pair false text) 2 2)) "none") "at the cap the retry is spent")
      (assert (= (shown (gi/vacuousForm (pair true text))) "none") "a passing integrity sends nothing")
      (assert (= (shown (gi/vacuousForm (pair false "restore failed"))) "none") "another cause sends nothing")
      (assert (= (shown (gi/vacuousForm (pair false vmsg))) vform) "an existing gateVacuous message still returns its form")
      true))
