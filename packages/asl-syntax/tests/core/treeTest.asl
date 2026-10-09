(module asl-syntax/tests/core/treeTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/cursor :a cur)])

fn testTilingValid -> Bool
  (let [(t1 (tr/makeToken "ident" 0 3))
        (t2 (tr/makeToken "whitespace" 3 4))
        (t3 (tr/makeToken "int" 4 6))
        (root (tr/makeNode "expr" 0 6 (list (tr/elemToken t1) (tr/elemToken t2) (tr/elemToken t3))))
        (res (tr/checkTiling root 6))]
    (assert (ok? res) "valid tiling succeeds")
    (assert (= (tr/checkTilingRoot root) (ok true)) "checkTilingRoot succeeds")
    (assert (= (listLength (tr/nodeLeaves root)) 3) "root has 3 leaves")
    (assert (= (tr/tokenLength t1) 3) "token length is 3")
    (assert (= (tr/nodeLength root) 6) "node length is 6")
    true)

fn testTilingGapAtStart -> Bool
  (let [(t1 (tr/makeToken "ident" 2 5))
        (root (tr/makeNode "expr" 0 5 (list (tr/elemToken t1))))
        (res (tr/checkTiling root 5))]
    (assert (err? res) "gap at start is rejected")
    (mt res
      ((ok _) (assert false "expected error"))
      ((err msg)
       (do
         (assert (stringContains? msg "gap") "error message contains gap")
         (assert (stringContains? msg "0") "error message names offset 0"))))
    true)

fn testTilingGapInMiddle -> Bool
  (let [(t1 (tr/makeToken "ident" 0 4))
        (t2 (tr/makeToken "ident" 6 10))
        (root (tr/makeNode "expr" 0 10 (list (tr/elemToken t1) (tr/elemToken t2))))
        (res (tr/checkTiling root 10))]
    (assert (err? res) "gap in middle is rejected")
    (mt res
      ((ok _) (assert false "expected error"))
      ((err msg)
       (do
         (assert (stringContains? msg "gap") "error message contains gap")
         (assert (stringContains? msg "4") "error message names offset 4"))))
    true)

fn testTilingGapAtEnd -> Bool
  (let [(t1 (tr/makeToken "ident" 0 8))
        (root (tr/makeNode "expr" 0 10 (list (tr/elemToken t1))))
        (res (tr/checkTiling root 10))]
    (assert (err? res) "gap at end is rejected")
    (mt res
      ((ok _) (assert false "expected error"))
      ((err msg)
       (do
         (assert (stringContains? msg "gap") "error message contains gap")
         (assert (stringContains? msg "8") "error message names offset 8"))))
    true)

fn testTilingOverlapInMiddle -> Bool
  (let [(t1 (tr/makeToken "ident" 0 5))
        (t2 (tr/makeToken "ident" 3 8))
        (root (tr/makeNode "expr" 0 8 (list (tr/elemToken t1) (tr/elemToken t2))))
        (res (tr/checkTiling root 8))]
    (assert (err? res) "overlap in middle is rejected")
    (mt res
      ((ok _) (assert false "expected error"))
      ((err msg)
       (do
         (assert (stringContains? msg "overlap") "error message contains overlap")
         (assert (stringContains? msg "3") "error message names offset 3"))))
    true)

fn testTilingOverlapPastEnd -> Bool
  (let [(t1 (tr/makeToken "ident" 0 12))
        (root (tr/makeNode "expr" 0 10 (list (tr/elemToken t1))))
        (res (tr/checkTiling root 10))]
    (assert (err? res) "overlap past end is rejected")
    (mt res
      ((ok _) (assert false "expected error"))
      ((err msg)
       (do
         (assert (stringContains? msg "overlap") "error message contains overlap")
         (assert (stringContains? msg "10") "error message names offset 10"))))
    true)

fn testTriviaAndErrorNodes -> Bool
  (let [(tokWs (tr/makeToken "whitespace" 0 1))
        (tokNl (tr/makeToken "newline" 1 2))
        (tokCm (tr/makeToken "comment" 2 10))
        (tokBom (tr/makeToken "bom" 10 13))
        (tokInv (tr/makeToken "invalid" 13 14))
        (tokId (tr/makeToken "ident" 14 18))
        (errChild (tr/makeToken "error" 18 20))
        (errNode (tr/makeErrorNode 18 20 (list (tr/elemToken errChild))))]
    (assert (tr/isTrivia tokWs) "whitespace is trivia")
    (assert (tr/isTrivia tokNl) "newline is trivia")
    (assert (tr/isTrivia tokCm) "comment is trivia")
    (assert (tr/isTrivia tokBom) "bom is trivia")
    (assert (tr/isTrivia tokInv) "invalid is trivia")
    (assert (not (tr/isTrivia tokId)) "ident is not trivia")
    (assert (tr/isTriviaKind "whitespace") "whitespace kind is trivia")
    (assert (tr/isTriviaKind "comment") "comment kind is trivia")
    (assert (not (tr/isTriviaKind "ident")) "ident kind is not trivia")
    (assert (tr/isErrorNode errNode) "errorNode is error node")
    (assert (= (tr/nodeKind errNode) "error") "errorNode kind is error")
    (assert (= (tr/nodeStart errNode) 18) "errorNode start is 18")
    (assert (= (tr/nodeEnd errNode) 20) "errorNode end is 20")
    (assert (tr/isErrorToken errChild) "errChild is error token")
    (assert (not (tr/isErrorToken tokId)) "tokId is not error token")
    true)

fn testPrintExactSource! -> Bool
  (let [(srcText "def foo = 42\n")
        (t1 (tr/makeToken "kw" 0 3))
        (t2 (tr/makeToken "whitespace" 3 4))
        (t3 (tr/makeToken "ident" 4 7))
        (t4 (tr/makeToken "whitespace" 7 8))
        (t5 (tr/makeToken "op" 8 9))
        (t6 (tr/makeToken "whitespace" 9 10))
        (t7 (tr/makeToken "int" 10 12))
        (t8 (tr/makeToken "newline" 12 13))
        (child1 (tr/makeNode "head" 0 7 (list (tr/elemToken t1) (tr/elemToken t2) (tr/elemToken t3))))
        (child2 (tr/makeNode "body" 7 13 (list (tr/elemToken t4) (tr/elemToken t5) (tr/elemToken t6) (tr/elemToken t7) (tr/elemToken t8))))
        (root (tr/makeNode "def" 0 13 (list (tr/elemNode child1) (tr/elemNode child2))))
        (printed (pr/print srcText root))
        (printedNode (pr/printNode root srcText))
        (printedTree (pr/printTreeString srcText root))
        (printedBytes (pr/printBytes! (stringToBytes srcText) root))]
    (assert (ok? (tr/checkTiling root 13)) "tree tiles correctly")
    (assert (= printed srcText) "print string matches source text")
    (assert (= printedNode srcText) "printNode matches source text")
    (assert (= printedTree srcText) "printTreeString matches source text")
    (assert (= printedBytes (stringToBytes srcText)) "printBytes matches source bytes")
    true)

fn testPrintErrorNodesPrint! -> Bool
  (let [(srcText "(+ 1 %bad% 2)")
        (t1 (tr/makeToken "lparen" 0 1))
        (t2 (tr/makeToken "op" 1 2))
        (t3 (tr/makeToken "whitespace" 2 3))
        (t4 (tr/makeToken "int" 3 4))
        (t5 (tr/makeToken "whitespace" 4 5))
        (tErr (tr/makeToken "error" 5 10))
        (errNode (tr/makeErrorNode 5 10 (list (tr/elemToken tErr))))
        (t6 (tr/makeToken "whitespace" 10 11))
        (t7 (tr/makeToken "int" 11 12))
        (t8 (tr/makeToken "rparen" 12 13))
        (root (tr/makeNode "call" 0 13
                (list (tr/elemToken t1)
                      (tr/elemToken t2)
                      (tr/elemToken t3)
                      (tr/elemToken t4)
                      (tr/elemToken t5)
                      (tr/elemNode errNode)
                      (tr/elemToken t6)
                      (tr/elemToken t7)
                      (tr/elemToken t8))))
        (printed (pr/print srcText root))
        (printedBytes (pr/printBytes! (stringToBytes srcText) root))]
    (assert (ok? (tr/checkTiling root 13)) "tree with error node tiles")
    (assert (= printed srcText) "print with Error node reproduces exact source")
    (assert (= printedBytes (stringToBytes srcText)) "printBytes with Error node reproduces exact bytes")
    true)

fn testNodeAtBoundariesAndOffsets -> Bool
  (let [(t1 (tr/makeToken "ident" 0 5))
        (t2 (tr/makeToken "whitespace" 5 6))
        (t3 (tr/makeToken "int" 6 10))
        (n1 (tr/makeNode "target1" 0 5 (list (tr/elemToken t1))))
        (n2 (tr/makeNode "target2" 6 10 (list (tr/elemToken t3))))
        (root (tr/makeNode "root" 0 10
                (list (tr/elemNode n1)
                      (tr/elemToken t2)
                      (tr/elemNode n2))))]
    (assert (ok? (tr/checkTiling root 10)) "root tiles [0, 10)")
    (let [(opt0 (cur/nodeAt root 0))]
      (assert (some? opt0) "nodeAt 0 returns some")
      (mt opt0
        ((some n) (assert (= (tr/nodeKind n) "target1") "nodeAt 0 is target1"))
        ((none) (assert false "expected node"))))
    (let [(opt4 (cur/nodeAt root 4))]
      (assert (some? opt4) "nodeAt 4 returns some")
      (mt opt4
        ((some n) (assert (= (tr/nodeKind n) "target1") "nodeAt 4 is target1"))
        ((none) (assert false "expected node"))))
    (let [(opt5 (cur/nodeAt root 5))]
      (assert (some? opt5) "nodeAt 5 (boundary between t1 and t2) returns some")
      (mt opt5
        ((some n) (assert (= (tr/nodeKind n) "root") "nodeAt 5 is root enclosing whitespace"))
        ((none) (assert false "expected node"))))
    (let [(opt6 (cur/nodeAt root 6))]
      (assert (some? opt6) "nodeAt 6 (boundary between t2 and n2) returns some")
      (mt opt6
        ((some n) (assert (= (tr/nodeKind n) "target2") "nodeAt 6 is target2"))
        ((none) (assert false "expected node"))))
    (let [(opt9 (cur/nodeAt root 9))]
      (assert (some? opt9) "nodeAt len-1 (9) returns some")
      (mt opt9
        ((some n) (assert (= (tr/nodeKind n) "target2") "nodeAt 9 is target2"))
        ((none) (assert false "expected node"))))
    (assert (none? (cur/nodeAt root 10)) "nodeAt len (10) returns none")
    (assert (none? (cur/nodeAt root -1)) "nodeAt negative (-1) returns none (never clamps)")
    (assert (none? (cur/nodeAt root 100)) "nodeAt past-end (100) returns none (never clamps)")
    (let [(tok0 (cur/tokenAt root 0))
          (tok5 (cur/tokenAt root 5))
          (tok6 (cur/tokenAt root 6))
          (tok9 (cur/tokenAt root 9))
          (tok10 (cur/tokenAt root 10))]
      (assert (some? tok0) "tokenAt 0 returns some")
      (assert (= (tr/tokenKind (optionOr tok0 t2)) "ident") "tokenAt 0 is ident")
      (assert (some? tok5) "tokenAt 5 returns some")
      (assert (= (tr/tokenKind (optionOr tok5 t1)) "whitespace") "tokenAt 5 is whitespace")
      (assert (some? tok6) "tokenAt 6 returns some")
      (assert (= (tr/tokenKind (optionOr tok6 t1)) "int") "tokenAt 6 is int")
      (assert (some? tok9) "tokenAt 9 returns some")
      (assert (= (tr/tokenKind (optionOr tok9 t1)) "int") "tokenAt 9 is int")
      (assert (none? tok10) "tokenAt 10 returns none"))
    true)

fn testMultiTokenBoundaries -> Bool
  (let [(t1 (tr/makeToken "alpha" 0 3))
        (t2 (tr/makeToken "beta" 3 7))
        (t3 (tr/makeToken "gamma" 7 12))
        (nA (tr/makeNode "nodeA" 0 3 (list (tr/elemToken t1))))
        (nB (tr/makeNode "nodeB" 3 7 (list (tr/elemToken t2))))
        (nC (tr/makeNode "nodeC" 7 12 (list (tr/elemToken t3))))
        (root (tr/makeNode "seq" 0 12 (list (tr/elemNode nA) (tr/elemNode nB) (tr/elemNode nC))))]
    (assert (ok? (tr/checkTiling root 12)) "multi-token seq tiles")
    (let [(at0 (cur/nodeAt root 0))]
      (assert (some? at0) "nodeAt 0 (start) returns some")
      (mt at0
        ((some n) (assert (= (tr/nodeKind n) "nodeA") "offset 0 is nodeA"))
        ((none) (assert false "expected node"))))
    (let [(at3 (cur/nodeAt root 3))]
      (assert (some? at3) "nodeAt 3 (boundary 1-2) returns some")
      (mt at3
        ((some n) (assert (= (tr/nodeKind n) "nodeB") "boundary 3 selects nodeB"))
        ((none) (assert false "expected node"))))
    (let [(at7 (cur/nodeAt root 7))]
      (assert (some? at7) "nodeAt 7 (boundary 2-3) returns some")
      (mt at7
        ((some n) (assert (= (tr/nodeKind n) "nodeC") "boundary 7 selects nodeC"))
        ((none) (assert false "expected node"))))
    (let [(at11 (cur/nodeAt root 11))]
      (assert (some? at11) "nodeAt 11 (len-1) returns some")
      (mt at11
        ((some n) (assert (= (tr/nodeKind n) "nodeC") "offset 11 is nodeC"))
        ((none) (assert false "expected node"))))
    (assert (none? (cur/nodeAt root 12)) "nodeAt 12 (len) returns none")
    true)

fn testAncestorsAndSiblings -> Bool
  (let [(t1 (tr/makeToken "a" 0 2))
        (t2 (tr/makeToken "b" 2 4))
        (t3 (tr/makeToken "c" 4 6))
        (subExpr (tr/makeNode "subExpr" 0 2 (list (tr/elemToken t1))))
        (childA (tr/makeNode "childA" 0 2 (list (tr/elemNode subExpr))))
        (childB (tr/makeNode "childB" 2 4 (list (tr/elemToken t2))))
        (childC (tr/makeNode "childC" 4 6 (list (tr/elemToken t3))))
        (root (tr/makeNode "root" 0 6 (list (tr/elemNode childA) (tr/elemNode childB) (tr/elemNode childC))))]
    (let [(rootAncs (cur/ancestors root root))]
      (assert (listEmpty? rootAncs) "root has empty ancestors"))
    (let [(aAncs (cur/ancestors root childA))]
      (assert (= (listLength aAncs) 1) "childA has 1 ancestor")
      (assert (= (tr/nodeKind (optionOr (listHead aAncs) childB)) "root") "childA ancestor is root"))
    (let [(subAncs (cur/ancestors root subExpr))]
      (assert (= (listLength subAncs) 2) "subExpr has 2 ancestors")
      (assert (= (tr/nodeKind (optionOr (listGet subAncs 0) childB)) "root") "subExpr ancestor 0 is root")
      (assert (= (tr/nodeKind (optionOr (listGet subAncs 1) childB)) "childA") "subExpr ancestor 1 is childA"))
    (let [(pSub (cur/parentNode root subExpr))]
      (assert (some? pSub) "subExpr has parent")
      (mt pSub
        ((some p) (assert (= (tr/nodeKind p) "childA") "subExpr parent is childA"))
        ((none) (assert false "expected parent"))))
    (let [(pA (cur/parentNode root childA))]
      (assert (some? pA) "childA has parent")
      (mt pA
        ((some p) (assert (= (tr/nodeKind p) "root") "childA parent is root"))
        ((none) (assert false "expected parent"))))
    (assert (none? (cur/parentNode root root)) "root has no parent")
    (let [(sibsB (cur/siblings root childB))]
      (assert (= (listLength sibsB) 2) "childB has 2 siblings")
      (assert (= (tr/nodeKind (optionOr (listGet sibsB 0) root)) "childA") "sibling 0 is childA")
      (assert (= (tr/nodeKind (optionOr (listGet sibsB 1) root)) "childC") "sibling 1 is childC"))
    (let [(nextA (cur/nextSibling root childA))]
      (assert (some? nextA) "childA has next sibling")
      (mt nextA
        ((some n) (assert (= (tr/nodeKind n) "childB") "next of childA is childB"))
        ((none) (assert false "expected next"))))
    (let [(nextB (cur/nextSibling root childB))]
      (assert (some? nextB) "childB has next sibling")
      (mt nextB
        ((some n) (assert (= (tr/nodeKind n) "childC") "next of childB is childC"))
        ((none) (assert false "expected next"))))
    (assert (none? (cur/nextSibling root childC)) "childC has no next sibling")
    (assert (none? (cur/prevSibling root childA)) "childA has no prev sibling")
    (let [(prevB (cur/prevSibling root childB))]
      (assert (some? prevB) "childB has prev sibling")
      (mt prevB
        ((some n) (assert (= (tr/nodeKind n) "childA") "prev of childB is childA"))
        ((none) (assert false "expected prev"))))
    (let [(prevC (cur/prevSibling root childC))]
      (assert (some? prevC) "childC has prev sibling")
      (mt prevC
        ((some n) (assert (= (tr/nodeKind n) "childB") "prev of childC is childB"))
        ((none) (assert false "expected prev"))))
    (let [(cOpt (cur/cursorAt root 0))]
      (assert (some? cOpt) "cursorAt 0 returns some")
      (mt cOpt
        ((some c)
         (do
           (assert (= (tr/nodeKind (cur/cursorNode c)) "subExpr") "cursorNode is subExpr")
           (assert (= (listLength (cur/cursorAncestors c)) 2) "cursorAncestors has 2 items")
           (assert (listEmpty? (cur/cursorSiblings c)) "subExpr has 0 siblings under childA")))
        ((none) (assert false "expected cursor"))))
    true)

fn testLineRangeThroughSource -> Bool
  (let [(text "line one\nline two\nline three\n")
        (s (src/sourceFromString "test.txt" text))
        (nodeL1 (tr/makeNode "stmt1" 0 8 (list)))
        (nodeL2 (tr/makeNode "stmt2" 9 17 (list)))
        (nodeMulti (tr/makeNode "multi" 0 28 (list)))
        (lr1Opt (cur/nodeLineRange s nodeL1))
        (lr2Opt (cur/nodeLineRange s nodeL2))
        (lrMultiOpt (cur/nodeLineRange s nodeMulti))]
    (assert (some? lr1Opt) "line range 1 returns some")
    (mt lr1Opt
      ((some lr)
       (do
         (assert (= lr.startLine 1) "stmt1 start line is 1")
         (assert (= lr.endLine 1) "stmt1 end line is 1")))
      ((none) (assert false "expected line range")))
    (assert (some? lr2Opt) "line range 2 returns some")
    (mt lr2Opt
      ((some lr)
       (do
         (assert (= lr.startLine 2) "stmt2 start line is 2")
         (assert (= lr.endLine 2) "stmt2 end line is 2")))
      ((none) (assert false "expected line range")))
    (assert (some? lrMultiOpt) "line range multi returns some")
    (mt lrMultiOpt
      ((some lr)
       (do
         (assert (= lr.startLine 1) "multi start line is 1")
         (assert (= lr.endLine 3) "multi end line is 3")))
      ((none) (assert false "expected line range")))
    (assert (= (cur/nodeStartLine s nodeMulti) (some 1)) "nodeStartLine is 1")
    (assert (= (cur/nodeEndLine s nodeMulti) (some 3)) "nodeEndLine is 3")
    true)

fn ! runTests -> Bool
  (let [(r1 (testTilingValid))
        (r2 (testTilingGapAtStart))
        (r3 (testTilingGapInMiddle))
        (r4 (testTilingGapAtEnd))
        (r5 (testTilingOverlapInMiddle))
        (r6 (testTilingOverlapPastEnd))
        (r7 (testTriviaAndErrorNodes))
        (r8 (testPrintExactSource!))
        (r9 (testPrintErrorNodesPrint!))
        (r10 (testNodeAtBoundariesAndOffsets))
        (r11 (testMultiTokenBoundaries))
        (r12 (testAncestorsAndSiblings))
        (r13 (testLineRangeThroughSource))]
    (and r1
    (and r2
    (and r3
    (and r4
    (and r5
    (and r6
    (and r7
    (and r8
    (and r9
    (and r10
    (and r11
    (and r12
         r13)))))))))))))
