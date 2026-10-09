(module testChanged/alphaTest :x [runTests] :i [(testChanged/alpha :a alpha)])

fn runTests -> Bool
  (do (assert (> (alpha/alphaValue) 0) "alpha fixture suite passes") true)
