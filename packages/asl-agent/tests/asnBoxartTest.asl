(module aslAgent/tests/asnBoxartTest :x [runTests] :i [(asnBoxart :a box)])

fn runTests -> Bool
  (let [(n (box/BoxNode :id "n1" :label "test" :status "ok"))] (assert (not (= n.id "")) "Node exists") true)
