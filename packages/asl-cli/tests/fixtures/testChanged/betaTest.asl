(module testChanged/betaTest :x [runTests] :i [(testChanged/beta :a beta)])

fn runTests -> Bool
  (do (assert (= (beta/betaValue) 2) "beta fixture suite passes") true)
