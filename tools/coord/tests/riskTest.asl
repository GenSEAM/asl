(module asl/tools/coord/tests/riskTest
  :x [runTests]
  :i [(asl-tools/coord/risk :a r)])

fn base -> r/RiskInput
  (r/RiskInput :names (list "asl/tools/docs/a.asl") :deleted (list) :lines 10 :added (list)
               :closure (list "asl/host/" "asl/seed/" "asl/prelude/") :gateKind "unit"
               :priorSigs 0 :mutantHistory false :publicSurface false)

fn weights x: r/RiskInput -> String
  (fold (fn [(acc String) (s r/Signal)] -> String (str acc s.name "=" s.weight ";")) "" (r/signalsOf x))

fn scoreOf x: r/RiskInput -> Int
  (let [(k (r/assess x))] k.score)

fn tierOf x: r/RiskInput -> String
  (let [(k (r/assess x))] k.tier)

fn testBase -> Bool
  (do (assert (= (weights (base)) "") "a small unit-gated change in a cold package fires nothing")
      (assert (= (scoreOf (base)) 0) "base score 0")
      (assert (= (tierOf (base)) "low") "base tier low")
      true)

fn testSignals -> Bool
  (let [(b (base))]
    (do (assert (= (weights (r/RiskInput :names (list "asl/host/c/x.c") :deleted b.deleted :lines b.lines :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "closureChanged=3;hotPackage=2;") "a host path is closure and hot")
        (assert (= (weights (r/RiskInput :names (list "asl/packages/asl-runtime/a.asl") :deleted b.deleted :lines b.lines :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "hotPackage=2;") "asl-runtime is hot, not closure")
        (assert (= (weights (r/RiskInput :names (list "asl/tools/coord/a.asl") :deleted b.deleted :lines b.lines :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "hotPackage=2;") "coord is hot")
        (assert (= (weights (r/RiskInput :names (list "asl/tools/docs/a.asl" "asl/tools/docs/b.asl" "asl/tools/docs/c.asl" "asl/tools/docs/d.asl") :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "") "4 files in one package is not spread")
        (assert (= (weights (r/RiskInput :names (list "asl/tools/docs/a.asl" "asl/tools/docs/b.asl" "asl/tools/docs/c.asl" "asl/tools/docs/d.asl" "asl/tools/docs/e.asl") :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "spread=1;") "5 files is spread")
        (assert (= (weights (r/RiskInput :names (list "asl/tools/docs/a.asl" "asl/tools/fleet/b.asl") :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "spread=1;") "2 packages is spread")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 300 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "") "300 lines is not spread")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 301 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "spread=1;") "301 lines is spread")
        (assert (= (weights (r/RiskInput :names b.names :deleted (list "asl/tools/docs/old.asl") :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "deletes=2;") "a deleted file fires deletes")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added (list (str "(procExe" "Path)")) :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "spawnOrFs=3;") "procExePath added fires spawnOrFs")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added (list "(fileWrite \"/Users/x/.asl/run/a\" t)") :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "spawnOrFs=3;") "a home store write fires spawnOrFs")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added (list "(add 1 2)") :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) "") "plain added lines fire nothing")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "none" :priorSigs 0 :mutantHistory false :publicSurface false)) "gateKind=3;") "no gate is 3")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "checkOnly" :priorSigs 0 :mutantHistory false :publicSurface false)) "gateKind=2;") "check-only gate is 2")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "corpus" :priorSigs 0 :mutantHistory false :publicSurface false)) "gateKind=1;") "corpus gate is 1")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "native" :priorSigs 0 :mutantHistory false :publicSurface false)) "gateKind=1;") "native gate is 1")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 1 :mutantHistory false :publicSurface false)) "") "one prior signature fires nothing")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 2 :mutantHistory false :publicSurface false)) "priorSigs=1;") "two prior signatures fire priorSigs")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory true :publicSurface false)) "mutantHistory=1;") "mutant history")
        (assert (= (weights (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface true)) "publicSurface=1;") "public surface")
        true))

fn testTiers -> Bool
  (let [(b (base))]
    (do (assert (= (tierOf (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory true :publicSurface false)) "low") "score 1 is low")
        (assert (= (tierOf (r/RiskInput :names b.names :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "checkOnly" :priorSigs 0 :mutantHistory false :publicSurface false)) "med") "score 2 is med")
        (assert (= (tierOf (r/RiskInput :names b.names :deleted (list "x") :lines 10 :added b.added :closure b.closure :gateKind "checkOnly" :priorSigs 0 :mutantHistory false :publicSurface false)) "med") "score 4 is med")
        (assert (= (tierOf (r/RiskInput :names b.names :deleted (list "x") :lines 10 :added b.added :closure b.closure :gateKind "none" :priorSigs 0 :mutantHistory false :publicSurface false)) "high") "score 5 is high")
        (assert (= (r/tierOf 0) "low") "tierOf 0")
        (assert (= (r/tierOf 1) "low") "tierOf 1")
        (assert (= (r/tierOf 2) "med") "tierOf 2")
        (assert (= (r/tierOf 4) "med") "tierOf 4")
        (assert (= (r/tierOf 5) "high") "tierOf 5")
        (assert (= (scoreOf (r/RiskInput :names (list "asl/host/c/x.c") :deleted b.deleted :lines 10 :added b.added :closure b.closure :gateKind "unit" :priorSigs 0 :mutantHistory false :publicSurface false)) 5) "closure plus hot sums to 5")
        (assert (= (r/packageOf "asl/packages/asl-gates/x.asl") "asl-gates") "package of a packages path")
        (assert (= (r/packageOf "asl/host/c/x.c") "asl-host") "package of a host path")
        (assert (= (r/packageOf "asl/tools/coord/x.asl") "coord") "package of a tools path")
        true))

fn ! runTests -> Bool
  (do (assert (testBase) "base")
      (assert (testSignals) "signals")
      (assert (testTiers) "tiers")
      true)
