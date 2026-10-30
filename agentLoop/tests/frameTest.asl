(module asl/agentLoop/tests/frameTest
  :x [runTests]
  :i [(asl/agentLoop/frame :a fr)])

fn base -> fr/Frame
  (fr/Frame :unit "FLOW-RISK" :kind "code" :atoms (list "riskTier") :owns (list "asl/tools/coord/risk.asl")
            :gates (list "bin/asl test asl/tools/coord/tests/riskTest.asl")
            :os "darwin" :toolchain "998d4f14e" :online (list "free" "paidCheap" "strong")
            :alias "ccBeam" :family "reflection" :rung "write" :attempt 1 :attempts 3
            :calls 11 :tokens 380000 :seconds 1700 :escalations 2 :requests 4
            :next (list "mimoPro" "kmK31Pro") :peers "")

fn textOf r: (Result String String) -> String
  (match r ((ok t) t) ((err _) ""))

fn errOf r: (Result String String) -> String
  (match r ((err e) e) ((ok _) ""))

fn testShape -> Bool
  (let [(t (textOf (fr/renderFrame (base))))]
    (do (assert (stringStartsWith? t "(:frame :task (:unit FLOW-RISK :kind code") "frame opens with the task")
        (assert (stringContains? t ":owns (asl/tools/coord/risk.asl)") "owns listed")
        (assert (stringContains? t ":gates (\"bin/asl test asl/tools/coord/tests/riskTest.asl\")") "gates quoted")
        (assert (stringContains? t ":lane (:alias ccBeam :family reflection :rung write :try 1/3)") "lane with attempt")
        (assert (stringContains? t ":bar redGreenRevert :peers none)") "bar and empty peers")
        (assert (stringContains? t ":options (escalate needCtx needOwns needTime split)") "request ops present")
        (assert (<= (fr/estimateTokens t) 120) "under the token bound")
        true))

fn testBudget -> Bool
  (let [(t (textOf (fr/renderFrame (base))))]
    (do (assert (stringContains? t ":budget (:calls 11 :tok 380000 :sec 1700 :esc 2 :req 4)") "budget fields in order")
        (assert (stringContains? t ":next (mimoPro kmK31Pro)") "next rung lanes")
        (assert (stringContains? (textOf (fr/renderFrame (fr/Frame :unit "U" :kind "code" :atoms (list) :owns (list) :gates (list) :os "linux" :toolchain "t" :online (list) :alias "a" :family "f" :rung "r" :attempt 2 :attempts 3 :calls 0 :tokens 0 :seconds 5 :escalations 0 :requests 0 :next (list) :peers ""))) ":budget (:calls 0 :tok 0 :sec 5 :esc 0 :req 0)") "zeros render")
        true))

fn testEgress -> Bool
  (let [(f (base))
        (memPath (fr/Frame :unit f.unit :kind f.kind :atoms f.atoms :owns (list ".asl/mem/work/x.asn") :gates f.gates :os f.os :toolchain f.toolchain :online f.online :alias f.alias :family f.family :rung f.rung :attempt 1 :attempts 3 :calls 1 :tokens 1 :seconds 1 :escalations 1 :requests 1 :next f.next :peers ""))
        (keyPeers (fr/Frame :unit f.unit :kind f.kind :atoms f.atoms :owns f.owns :gates f.gates :os f.os :toolchain f.toolchain :online f.online :alias f.alias :family f.family :rung f.rung :attempt 1 :attempts 3 :calls 1 :tokens 1 :seconds 1 :escalations 1 :requests 1 :next f.next :peers "sk-abcdefghijklmnopqrstuvwxyz"))]
    (do (assert (stringContains? (errOf (fr/renderFrame memPath)) "egress") ".asl/mem path refused")
        (assert (stringContains? (errOf (fr/renderFrame keyPeers)) "egress") "key-like peer text refused")
        (assert (fr/leaksEgress "x .asl/mem/y") "leak detector hits mem path")
        (assert (not (fr/leaksEgress "asl/agentLoop/frame.asl")) "ordinary path passes")
        true))

fn testSize -> Bool
  (let [(f (base))
        (long (fr/Frame :unit f.unit :kind f.kind :atoms f.atoms :owns (map (fn [(i Int64)] -> String (str "asl/pkg/module" i "/file" i ".asl")) (list 1 2 3 4 5 6 7 8 9 10 11 12)) :gates f.gates :os f.os :toolchain f.toolchain :online f.online :alias f.alias :family f.family :rung f.rung :attempt 1 :attempts 3 :calls 1 :tokens 1 :seconds 1 :escalations 1 :requests 1 :next f.next :peers ""))
        (clipped (fr/Frame :unit f.unit :kind f.kind :atoms f.atoms :owns f.owns :gates f.gates :os f.os :toolchain f.toolchain :online f.online :alias f.alias :family f.family :rung f.rung :attempt 1 :attempts 3 :calls 1 :tokens 1 :seconds 1 :escalations 1 :requests 1 :next f.next :peers (stringRepeat "z" 500)))]
    (do (assert (stringContains? (errOf (fr/renderFrame long)) "over 120") "oversized fixture refused with the bound")
        (assert (<= (fr/estimateTokens (textOf (fr/renderFrame clipped))) 120) "long peers clipped under the bound")
        true))

fn ! runTests -> Bool
  (do (assert (testShape) "shape")
      (assert (testBudget) "budget")
      (assert (testEgress) "egress")
      (assert (testSize) "size")
      true)
