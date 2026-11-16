(module testSelect/threeFns :x [runTests] :i [])

fn testFirst -> Bool
  (do (assert (= (stringLength "one") 3) "first holds")
      true)

fn testSecond -> Bool
  (do (assert (= (stringLength "two") 3) "second opens")
      (assert (= (stringLength "two") 4) "second breaks on purpose")
      true)

fn testThird -> Bool
  (do (assert (= (stringLength "three") 5) "third holds")
      (assert (= (stringLength "adds") 4) "third adds")
      true)

fn helperCount n: Int64 -> Bool
  (> n 0)

fn runTests -> Bool
  (and (testFirst) (and (testSecond) (testThird)))
