(module asl/examples/tests/resultDemoTest
  :x [runTests]
  :i [(asl/examples/resultDemo :a resultDemo)])

fn runTests -> Bool
  (do
    (assert (= (resultDemo/parsePort "8080") (ok 8080)) "parsePort ok")
    (assert (= (resultDemo/parsePort "0") (err "port out of range")) "parsePort out of range")
    (assert (= (resultDemo/parsePort "x") (err "port is not a number")) "parsePort not a number")
    true)
