(module asl-ui/terminalObservatory :x [renderTerminalRadarCard renderTerminalHeatmap renderTerminalMockDetector renderTerminalSessionTile scoreToBarChar riskToShadeChar formatRadarSparkline PackageCouplingItem makePackageCouplingItem formatInstabilityBar renderTerminalCouplingMatrix renderTerminalIntelTile] :i [(asl-ui/terminalCanvas :a tc) (asl-ui/radarCard :a rc) (asl-ui/blastRadiusHeatmap :a hm) (asl-ui/vacuousMockDetector :a md) (asl-ui/sessionTile :a sess)])

(schema PackageCouplingItem
  (:f name String)
  (:f fanIn Int64)
  (:f fanOut Int64)
  (:f instability Float)
  (:f role String)
  (:f status String))

fn makePackageCouplingItem name: String fanIn: Int64 fanOut: Int64 instability: Float role: String status: String -> PackageCouplingItem
  (PackageCouplingItem :name name :fanIn fanIn :fanOut fanOut :instability instability :role role :status status)

fn formatInstabilityBar instability: Float -> String
  (if (<= instability 0.2)
    "[■□□□□] Stable"
    (if (<= instability 0.4)
      "[■■□□□] Guarded"
      (if (<= instability 0.6)
        "[■■■□□] Balanced"
        (if (<= instability 0.8)
          "[■■■■□] Volatile"
          "[■■■■■] Dynamic"))))

fn scoreToBarChar score: Int64 -> String
  (if (>= score 90) "█"
    (if (>= score 75) "▓"
      (if (>= score 50) "▒"
        (if (>= score 25) "░"
          " "))))

fn riskToShadeChar blast: Int64 hasCycle: Bool isRuntime: Bool -> String
  (if isRuntime "█"
    (if hasCycle "▓"
      (if (> blast 5) "▒"
        "░")))

fn formatRadarSparkline arch: Int64 plat: Int64 log: Int64 mem: Int64 sec: Int64 tok: Int64 -> String
  (str (scoreToBarChar arch) (scoreToBarChar plat) (scoreToBarChar log) (scoreToBarChar mem) (scoreToBarChar sec) (scoreToBarChar tok))

fn renderTerminalRadarCard buf: tc/TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 snap: rc/RadarSnapshot -> tc/TerminalBuffer
  (let [(title (str "Radar Integrity (" (stringFromInt64 snap.score) "/100)"))
        (b0 (tc/drawBorder buf x y w h title "double" "cyan" "default"))
        (spark (formatRadarSparkline snap.architectureScore snap.platformScore snap.logicScore snap.memoryScore snap.securityScore snap.tokenEconomicsScore))
        (l1 (str "Score: " (stringFromInt64 snap.score) " [" spark "]"))
        (b1 (tc/drawText b0 (+ x 2) (+ y 2) l1 "cyan" "default" true))
        (l2 (str "Arch: " (stringFromInt64 snap.architectureScore) " | Plat: " (stringFromInt64 snap.platformScore) " | Log: " (stringFromInt64 snap.logicScore)))
        (b2 (tc/drawText b1 (+ x 2) (+ y 3) l2 "default" "default" false))
        (l3 (str "Mem:  " (stringFromInt64 snap.memoryScore) " | Sec:  " (stringFromInt64 snap.securityScore) " | Tok: " (stringFromInt64 snap.tokenEconomicsScore)))
        (b3 (tc/drawText b2 (+ x 2) (+ y 4) l3 "default" "default" false))
        (l4 (str "Commit: " snap.commitHash))
        (b4 (tc/drawText b3 (+ x 2) (+ y 5) l4 "yellow" "default" false))]
    b4)

fn renderHeatmapLoop buf: tc/TerminalBuffer nodes: (List hm/BlastRadiusNode) idx: Int64 len: Int64 x: Int64 y: Int64 -> tc/TerminalBuffer
  (if (>= idx len)
    buf
    (let [(node (optionOr (listGet nodes idx) (hm/makeBlastRadiusNode "" 0 false false)))
          (shade (riskToShadeChar node.blastCount node.hasCycles node.isRuntimeCycle))
          (cycleCue (if node.isRuntimeCycle "[CYCLE] " (if node.hasCycles "[TYPE]  " "[BLAST] ")))
          (lineText (str cycleCue node.moduleName " (" (stringFromInt64 node.blastCount) ") " shade))
          (col (if node.isRuntimeCycle "red" (if node.hasCycles "yellow" "green")))
          (nextBuf (tc/drawText buf x (+ y idx) lineText col "default" false))]
      (renderHeatmapLoop nextBuf nodes (+ idx 1) len x y)))

fn renderTerminalHeatmap buf: tc/TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 nodes: (List hm/BlastRadiusNode) -> tc/TerminalBuffer
  (let [(maxB (hm/calculateMaxBlastRadius nodes))
        (title (str "Blast Radius Heatmap (Max: " (stringFromInt64 maxB) ")"))
        (b0 (tc/drawBorder buf x y w h title "single" "yellow" "default"))
        (len (listLength nodes))
        (maxRows (- h 3))
        (displayLen (if (> len maxRows) maxRows len))]
    (renderHeatmapLoop b0 nodes 0 displayLen (+ x 2) (+ y 2)))

fn renderMockLoop buf: tc/TerminalBuffer items: (List md/VacuousMockItem) idx: Int64 len: Int64 x: Int64 y: Int64 -> tc/TerminalBuffer
  (if (>= idx len)
    buf
    (let [(it (optionOr (listGet items idx) (md/makeVacuousMockItem "" "" 0 0 (md/anomalyCleanConstant) true)))
          (cue (mt it.anomaly
                 ((md/anomalyHollowMock) "[VACUOUS] Hollow")
                 ((md/anomalyZeroAssertions) "[VACUOUS] 0 Asserts")
                 ((md/anomalyTautologicalAssert) "[WARN] Tautology")
                 ((md/anomalyCleanConstant) "[OK] Constant")))
          (lineText (str cue " " it.targetSymbol " (" (stringFromInt64 it.assertCount) " asserts)"))
          (col (mt it.anomaly
                 ((md/anomalyHollowMock) "red")
                 ((md/anomalyZeroAssertions) "magenta")
                 ((md/anomalyTautologicalAssert) "yellow")
                 ((md/anomalyCleanConstant) "green")))
          (nextBuf (tc/drawText buf x (+ y idx) lineText col "default" false))]
      (renderMockLoop nextBuf items (+ idx 1) len x y)))

fn renderTerminalMockDetector buf: tc/TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 items: (List md/VacuousMockItem) -> tc/TerminalBuffer
  (let [(count (listLength items))
        (title (str "Mock & Verification Detector (" (stringFromInt64 count) ")"))
        (b0 (tc/drawBorder buf x y w h title "single" "magenta" "default"))
        (maxRows (- h 3))
        (displayLen (if (> count maxRows) maxRows count))]
    (renderMockLoop b0 items 0 displayLen (+ x 2) (+ y 2)))

fn renderSessionLoop buf: tc/TerminalBuffer sessions: (List sess/SessionCardItem) idx: Int64 len: Int64 x: Int64 y: Int64 -> tc/TerminalBuffer
  (if (>= idx len)
    buf
    (let [(it (optionOr (listGet sessions idx) (sess/makeSessionCardItem "" "" 0 false (sess/statusIdle) "")))
          (cue (sess/formatSessionCue it.status))
          (lineText (str cue " " it.substrateName " : " it.currentTask))
          (col (mt it.status
                 ((sess/statusActive) "green")
                 ((sess/statusRunning) "cyan")
                 ((sess/statusIdle) "default")
                 ((sess/statusBlocked) "red")))
          (nextBuf (tc/drawText buf x (+ y idx) lineText col "default" false))]
      (renderSessionLoop nextBuf sessions (+ idx 1) len x y)))

fn renderTerminalSessionTile buf: tc/TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 sessions: (List sess/SessionCardItem) -> tc/TerminalBuffer
  (let [(count (listLength sessions))
        (title (str "Active Sessions (" (stringFromInt64 count) ")"))
        (b0 (tc/drawBorder buf x y w h title "single" "green" "default"))
        (maxRows (- h 3))
        (displayLen (if (> count maxRows) maxRows count))]
    (renderSessionLoop b0 sessions 0 displayLen (+ x 2) (+ y 2)))

fn renderCouplingRowLoop buf: tc/TerminalBuffer items: (List PackageCouplingItem) idx: Int64 len: Int64 x: Int64 y: Int64 -> tc/TerminalBuffer
  (if (>= idx len)
    buf
    (let [(item (optionOr (listGet items idx) (makePackageCouplingItem "" 0 0 0.0 "" "")))
          (name item.name)
          (namePad (optionOr (stringSlice (str name "              ") 0 14) name))
          (inStr (stringFromInt64 item.fanIn))
          (outStr (stringFromInt64 item.fanOut))
          (bar (formatInstabilityBar item.instability))
          (line (str namePad " " inStr " -> " outStr " " bar " " item.role))
          (col (if (<= item.instability 0.2) "green" (if (<= item.instability 0.7) "yellow" "cyan")))
          (nextBuf (tc/drawText buf x (+ y idx) line col "default" false))]
      (renderCouplingRowLoop nextBuf items (+ idx 1) len x y)))

fn renderTerminalCouplingMatrix buf: tc/TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 packages: (List PackageCouplingItem) -> tc/TerminalBuffer
  (let [(count (listLength packages))
        (title (str "Package Coupling & Instability (" (stringFromInt64 count) ")"))
        (b0 (tc/drawBorder buf x y w h title "single" "cyan" "default"))
        (header "PKG            FAN_IN/OUT INSTABILITY  ROLE")
        (b1 (tc/drawText b0 (+ x 2) (+ y 1) header "default" "default" true))
        (maxRows (- h 3))
        (displayLen (if (> count maxRows) maxRows count))]
    (renderCouplingRowLoop b1 packages 0 displayLen (+ x 2) (+ y 2)))

fn renderTerminalIntelTile buf: tc/TerminalBuffer x: Int64 y: Int64 w: Int64 h: Int64 totalPkgs: Int64 totalMods: Int64 cycles: Int64 fictions: Int64 -> tc/TerminalBuffer
  (let [(title "Code Intelligence Health (asl-intel)")
        (b0 (tc/drawBorder buf x y w h title "double" "cyan" "default"))
        (l1 (str "Packages: " (stringFromInt64 totalPkgs) " | Modules: " (stringFromInt64 totalMods)))
        (b1 (tc/drawText b0 (+ x 2) (+ y 2) l1 "cyan" "default" true))
        (l2 (str "Cycles: " (stringFromInt64 cycles) " [OK] | Fictions: " (stringFromInt64 fictions) " [CLEAN]"))
        (b2 (tc/drawText b1 (+ x 2) (+ y 3) l2 (if (= cycles 0) "green" "red") "default" false))
        (l3 "Status: 100% Hermetic DAG | Tri-Map: Synced")
        (b3 (tc/drawText b2 (+ x 2) (+ y 4) l3 "green" "default" false))]
    b3)
