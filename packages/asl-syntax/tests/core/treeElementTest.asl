(module asl-syntax/tests/core/treeElementTest :x [runTests] :i [(asl-syntax/core/tree :a t)])

; (:m :ref COVRATCHET :do "elementStart, elementEnd and elementLength agree for a token leaf and an interior node")
fn runTests -> Bool
  (let [(leaf (t/elemToken (t/makeToken "ident" 2 5)))
        (empty (t/elemToken (t/makeToken "ident" 4 4)))
        (inner (t/elemNode (t/makeNode "call" 1 9 (list leaf))))
        (bare (t/elemNode (t/makeNode "list" 0 0 (list))))]
    (do
      (assert (= (t/elementStart leaf) 2) "token start")
      (assert (= (t/elementEnd leaf) 5) "token end")
      (assert (= (t/elementLength leaf) 3) "token length is end minus start")
      (assert (= (t/elementStart inner) 1) "node start")
      (assert (= (t/elementEnd inner) 9) "node end is its own, not its child's")
      (assert (= (t/elementLength inner) 8) "node length")
      (assert (= (t/elementStart empty) (t/elementEnd empty)) "an empty token has equal bounds")
      (assert (= (t/elementLength empty) 0) "an empty token has length 0")
      (assert (= (t/elementLength bare) 0) "an empty node has length 0")
      true))
