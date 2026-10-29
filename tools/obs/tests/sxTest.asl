(module ws/asl/tools/obs/tests/sxTest
  :x [runTests]
  :i [(ws/asl/tools/obs/sx :a sx)])

fn rowA -> String
  "(:turn 1 :reply \"a (b \\\"c\\\" :x 1)\" :n 5 :f (:k \"v)\" 2) :z abc)"

fn testFields -> Bool
  (let [(f (sx/topFields (rowA)))]
    (do (assert (= (sx/head (rowA)) ":turn") "head is the row kind")
        (assert (= (optionOr (sx/field f ":reply") "") "a (b \"c\" :x 1)") "string value unescaped, inner key ignored")
        (assert (= (sx/intField f ":n") 5) "int field")
        (assert (= (optionOr (sx/fieldRaw f ":f") "") "(:k \"v)\" 2)") "nested form is one value")
        (assert (= (optionOr (sx/field f ":z") "") "abc") "atom value after a nested form")
        (assert (= (sx/intField f ":x") 0) "a key inside a string is not a field")
        true))

fn runTests -> Bool
  (testFields)
