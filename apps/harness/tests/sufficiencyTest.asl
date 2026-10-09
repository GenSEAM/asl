(module aslHarness/sufficiencyTest :x [testSufficiencyComplete testSufficiencyPartial runTests] :i [(sufficiency :a s)])

fn testSufficiencyComplete -> Bool
  (let [(tasks (list "task1" "task2")) (done (list "task1" "task2")) (rep (s/evaluateSufficiency tasks done))] (do (assert (= rep.completedCount 2)) (assert (s/isSufficient? rep)) (assert (not (= rep.completedCount 0))) true))

fn testSufficiencyPartial -> Bool
  (let [(tasks (list "task1" "task2")) (done (list "task1")) (rep (s/evaluateSufficiency tasks done))] (do (assert (= rep.completedCount 1)) (assert (not (s/isSufficient? rep))) (assert (> rep.completedCount 0)) true))

fn runTests -> Bool
  (do (assert (testSufficiencyComplete)) (assert (testSufficiencyPartial)) true)

