(module asl-utils/tests/unionFindTest
  :x [runTests]
  :i [(asl-utils/unionFind :a uf)])

fn addCells d0: uf/Dsu cells: (List Int64) -> uf/Dsu
  (fold (fn [(d uf/Dsu) (c Int64)] -> uf/Dsu (uf/add d c)) d0 cells)

fn unionPairs d0: uf/Dsu pairs: (List (Pair Int64 Int64)) -> uf/Dsu
  (fold (fn [(d uf/Dsu) (p (Pair Int64 Int64))] -> uf/Dsu
            (uf/union d (pairFirst p) (pairSecond p)))
        d0 pairs)

fn testBasics -> Bool
  (let [(d0 (uf/empty))
        (d1 (uf/add (uf/add d0 1) 2))
        (d2 (uf/union d1 1 2))]
    (do (assert (= (uf/componentCount d0) 0) "an empty set has no components")
        (assert (= (uf/componentCount d1) 2) "two separate nodes are two components")
        (assert (not (uf/connected d1 1 2)) "separate nodes are not connected")
        (assert (uf/connected d2 1 2) "union connects two nodes")
        (assert (= (uf/componentCount d2) 1) "union of two roots merges components")
        (assert (= (uf/componentCount d1) 2) "union is persistent and leaves the input unchanged")
        (assert (uf/connected d2 1 1) "a node is connected to itself")
        true))

fn testTransitive -> Bool
  (let [(d (uf/union (uf/union (uf/union (uf/empty) 1 2) 2 3) 4 5))]
    (do (assert (uf/connected d 1 3) "union is transitive")
        (assert (not (uf/connected d 1 5)) "disjoint components stay apart")
        (assert (uf/connected d 4 5) "the second pair is connected")
        (assert (= (uf/componentCount d) 2) "three nodes in one component and two in another make two components")
        true))

fn testGrid -> Bool
  (let [(cells (list 0 2 3 5 6 8))
        (edges (list (pair 0 3) (pair 3 6) (pair 2 5) (pair 5 8)))
        (d0 (addCells (uf/empty) cells))
        (d1 (unionPairs d0 edges))
        (d2 (uf/union d1 0 2))]
    (do (assert (= (uf/componentCount d0) 6) "the grid has six open cells")
        (assert (not (uf/connected d0 0 3)) "unconnected open cells start apart")
        (assert (uf/connected d1 0 6) "the left column of the grid is connected")
        (assert (uf/connected d1 2 8) "the right column of the grid is connected")
        (assert (not (uf/connected d1 0 2)) "the blocked middle column separates the two sides")
        (assert (= (uf/componentCount d1) 2) "the grid has two components around the blocked column")
        (assert (= (uf/componentCount d2) 1) "bridging the sides leaves one component")
        (assert (uf/connected d2 0 8) "all open cells are connected after the bridge")
        true))

fn testChain -> Bool
  (let [(d (fold (fn [(s uf/Dsu) (i Int64)] -> uf/Dsu (uf/union s i (+ i 1)))
                (uf/empty)
                (list 0 1 2 3 4 5 6 7 8)))]
    (do (assert (uf/connected d 0 9) "a chain of unions connects the ends")
        (assert (= (uf/componentCount d) 1) "a chain of ten nodes is one component")
        (assert (uf/connected d 3 7) "middle nodes of the chain are connected")
        (assert (not (uf/connected d 0 10)) "a node never added stays unconnected")
        true))

fn runTests -> Bool
  (and (testBasics) (testTransitive) (testGrid) (testChain))
