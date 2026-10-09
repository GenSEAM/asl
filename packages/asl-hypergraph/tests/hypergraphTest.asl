(module asl-hypergraph/tests/hypergraphTest
  :x [testModelCreation testFindNodeById testFindEdgesByTarget testImpactDigest runTests]
  :i [(asl-hypergraph/model :a m)
      (asl-hypergraph/digest :a d)])

fn testModelCreation -> Bool
  (let [(node (m/makeHyperNode "pkg/mod:foo" "function" "pkg/mod" "foo" "A test function"))
        (edge (m/makeHyperEdge "pkg/mod:caller" "calls" "pkg/mod:foo" "callsite1"))
        (idx (m/makeHyperIndex 1 (list node) (list edge) 1000000))]
    (do
      (assert (= node.id "pkg/mod:foo") "node id matches")
      (refute (!= node.id "pkg/mod:foo") "node id refutes divergence")
      (assert (= edge.relation "calls") "edge relation is calls")
      (refute (!= edge.relation "calls") "edge relation refutes non-calls")
      (assert (= idx.version 1) "index version is 1")
      (refute (!= idx.version 1) "index version refutes non-1")
      true))

fn testFindNodeById -> Bool
  (let [(n1 (m/makeHyperNode "pkg/mod:bar" "function" "pkg/mod" "bar" "doc"))
        (n2 (m/makeHyperNode "pkg/mod:baz" "function" "pkg/mod" "baz" "doc"))
        (nodes (list n1 n2))
        (found (m/findNodeById nodes "pkg/mod:baz"))]
    (do
      (assert (some? found) "found baz node")
      (refute (none? found) "found baz node refutes none")
      (assert (= (mt found ((some n) n.symbol) (none "")) "baz") "symbol is baz")
      (refute (!= (mt found ((some n) n.symbol) (none "")) "baz") "symbol refutes non-baz")
      true))

fn testFindEdgesByTarget -> Bool
  (let [(e1 (m/makeHyperEdge "pkg/a:call1" "calls" "pkg/b:target" "site1"))
        (e2 (m/makeHyperEdge "pkg/a:call2" "calls" "pkg/b:target" "site2"))
        (e3 (m/makeHyperEdge "pkg/a:call3" "tests" "pkg/b:other" "site3"))
        (edges (list e1 e2 e3))
        (matches (m/findEdgesByTarget edges "pkg/b:target" (some "calls")))]
    (do
      (assert (= (listLength matches) 2) "found 2 matching call edges")
      (refute (!= (listLength matches) 2) "matching call edges count refutes non-2")
      true))

fn testImpactDigest -> Bool
  (let [(node (m/makeHyperNode "mod:target" "function" "mod" "target" "doc"))
        (edge1 (m/makeHyperEdge "caller1" "calls" "mod:target" "s1"))
        (edge2 (m/makeHyperEdge "test1" "tests" "mod:target" "s2"))
        (idx (m/makeHyperIndex 1 (list node) (list edge1 edge2) 1000000))
        (digest (d/generateImpactDigest idx "mod:target" 80))]
    (do
      (assert (= digest.symbol "mod:target") "digest symbol matches")
      (refute (!= digest.symbol "mod:target") "digest symbol refutes divergence")
      (assert (stringContains? digest.receiptStr ":impact-digest") "receipt contains impact-digest")
      (refute (stringEmpty? digest.receiptStr) "receipt string refutes empty")
      true))

fn ! runTests -> Bool
  (do
    (assert (testModelCreation) "testModelCreation")
    (assert (testFindNodeById) "testFindNodeById")
    (assert (testFindEdgesByTarget) "testFindEdgesByTarget")
    (assert (testImpactDigest) "testImpactDigest")
    true)
