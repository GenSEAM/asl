(module asl-forms/tests/researchModeTest
  :x [runTests]
  :i [(asl-forms/delegate :a d) (asl-json/json :a j) (aslGateway/pyText :a pt)])

; (:m :ref RESEARCH-DEPTH :do "gate of the mode lookup researchStep uses, on temp files only: workspace table over package table, :flash falling back to the single pipeline only when no table is readable, every other miss an error")

fn modeDepth r: (Result j/Json pt/PyErr) -> String
  (match r
    ((ok m) (match (j/jsonGet m "depth") ((some (j/jstr s)) s) (_ "")))
    ((err _) ""))

fn modePipeline r: (Result j/Json pt/PyErr) -> String
  (match r
    ((ok m) (match (j/jsonGet m "pipeline") ((some (j/jstr s)) s) (_ "")))
    ((err _) ""))

fn msg r: (Result j/Json pt/PyErr) -> String
  (match r ((ok _) "") ((err e) e.msg))

fn ! runTests -> Bool
  (let [(base (str "/tmp/aslResearchMode." (stringFromInt64 (procSelf))))
        (cleanStart (pathRemove base))
        (made (dirCreate base))
        (ws (str base "/ws.asn"))
        (pkg (str base "/pkg.asn"))
        (bad (str base "/bad.asn"))
        (none1 (str base "/absent1.asn"))
        (none2 (str base "/absent2.asn"))
        (w1 (fileWrite ws "(:mode :id deep :pipeline single :depth matrix)\n"))
        (w2 (fileWrite pkg "(:mode :id deep :pipeline single :depth targeted)\n(:mode :id flash :pipeline single :depth flash)\n"))
        (w3 (fileWrite bad "(:mode :id deep :pipeline plan :subQuestions 3)\n"))
        (fromWs (d/researchModeAt! ws pkg "deep"))
        (fromPkg (d/researchModeAt! none1 pkg "deep"))
        (flashBare (d/researchModeAt! none1 none2 "flash"))
        (deepBare (d/researchModeAt! none1 none2 "deep"))
        (invalid (d/researchModeAt! bad pkg "deep"))
        (flashNoRow (d/researchModeAt! ws pkg "flash"))
        (cleaned (pathRemove base))]
    (do
      (assert (and (ok? w1) (ok? w2) (ok? w3)) "temp tables written")
      (assert (= (modeDepth fromWs) "matrix") "the workspace table wins over the package table")
      (assert (= (modeDepth fromPkg) "targeted") "without a workspace table the package table is read")
      (assert (and (= (modePipeline flashBare) "single") (= (modeDepth flashBare) "flash")) "with no readable table :flash runs the single pipeline")
      (assert (stringContains? (msg deepBare) (str "research mode table is unreadable: " none2)) "with no readable table any other depth is rejected, naming the path")
      (assert (stringContains? (msg invalid) "lacks an integer :queriesPerSub") "an invalid row in the workspace table is rejected, not skipped for the package table")
      (assert (stringContains? (msg flashNoRow) "no (:mode :id flash") "a readable table without a flash row is an error, not the fallback")
      (assert (ok? cleaned) "temp tables removed")
      true))
