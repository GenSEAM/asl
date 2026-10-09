(module aslMem/testSnapshot :x [runTests] :i [(aslMem/snapshot :a s)])

fn runTests -> Bool
  (let [(vCount 10) (nCount 5) (eCount 3) (epoch 123456789) (frame (s/createSnapshotFrame vCount nCount eCount epoch))] (assert (stringContains? frame "(:snapshot-manifest") "snapshot frame must contain :snapshot-manifest") (assert (stringContains? frame "123456789") "snapshot frame must contain epoch") (assert (stringContains? frame ":v-count 10") "snapshot frame must contain v-count") (assert (stringContains? frame ":n-count 5") "snapshot frame must contain n-count") (assert (stringContains? frame ":e-count 3") "snapshot frame must contain e-count") true)
