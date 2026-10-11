(module servedFixture/unsupportedProbe :x [runTests] :i [])

fn quote text: String -> String
  (str "'" text "'")

fn runTests -> Bool
  (do (assert (= (quote "a") "'a'") "quote wraps its text in single quotes")
      true)
