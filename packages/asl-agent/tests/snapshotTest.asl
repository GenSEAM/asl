(module aslAgent/snapshotTest :x [testSnapshotEntityFormatting testSnapshotSortingSerialization testSnapshotDiffing runTests] :i [(snapshot :a snap)])

"run: (run-tests)"

fn testSnapshotEntityFormatting -> Bool
  (let [(e (snap/makeEntity "req:001" (snap/kindReq) "Autonomous ReAct loop" "src/agent.asl:42")) (formatted (snap/formatEntity e))] (assert (>= (stringLength formatted) 20) "entity formatted length >= 20") (assert (= (snap/parseKind "req") (snap/kindReq)) "parsed kind matches") true)

fn testSnapshotSortingSerialization -> Bool
  (let [(e1 (snap/makeEntity "req:002" (snap/kindReq) "TUI status bar" "src/tui.asl:10")) (e2 (snap/makeEntity "dec:001" (snap/kindDecision) "ASL Native" "docs/ADR-001.md:1")) (g (snap/makeGraph (list e1 e2) "v1.0")) (s (snap/serializeGraph g))] (assert (>= (stringLength s) 40) "serialized graph length >= 40") (assert (stringContains? s "req:002") "serialized graph contains req:002") true)

fn testSnapshotDiffing -> Bool
  (let [(e1 (snap/makeEntity "req:001" (snap/kindReq) "Spec 1" "src/a.asl:1")) (e2 (snap/makeEntity "req:002" (snap/kindReq) "Spec 2" "src/b.asl:1")) (g1 (snap/makeGraph (list e1) "v1.0")) (g2 (snap/makeGraph (list e1 e2) "v1.0")) (d (snap/diffGraphs g1 g2))] (assert (= d 1) "diff count is 1") (assert (not (= d 0)) "diff count is not 0") true)

fn testSnapshotDeserialization -> Bool
  (let [(e1 (snap/makeEntity "req:001" (snap/kindReq) "Autonomous ReAct loop" "src/agent.asl:42")) (formatted (snap/formatEntity e1)) (g (snap/deserializeGraph formatted)) (ents g.entities)] (assert (= (listLength ents) 1) "parsed entities length is 1") (let [(p1 (listHead ents))] (assert (some? p1) "parsed entity exists") (assert (= (mt p1 ((some e) e.id) (none "")) "req:001") "id matches req:001") (assert (= (mt p1 ((some e) e.payload) (none "")) "Autonomous ReAct loop") "payload matches") true))

fn runTests -> Bool
  (do (testSnapshotEntityFormatting) (testSnapshotSortingSerialization) (testSnapshotDiffing) (testSnapshotDeserialization) true)
