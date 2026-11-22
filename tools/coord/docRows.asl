(module asl-tools/coord/docRows
  :x [maxListed])

; (:m :ref GATE-DOC-ROWS :do "how many findings one docRows red message lists before it gives a count of the rest, so a cheap writer's message stays one readable line")
fn maxListed -> Int64
  20
