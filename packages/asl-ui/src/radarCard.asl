(module asl-ui/radarCard :x [RadarAxisScore makeRadarAxisScore RadarSnapshot makeRadarSnapshot renderRadarCard calculateRadarPoints formatAxisLabel] :i [(asl-ui/vnode :a ui) (asl-ui/tokens :a tokens) (asl-ui/theme :a theme)])

(schema RadarAxisScore (:f axis String) (:f score Int64) (:f snapshotHash String) (:f receiptId String))

(schema RadarSnapshot (:f score Int64) (:f architectureScore Int64) (:f platformScore Int64) (:f logicScore Int64) (:f memoryScore Int64) (:f securityScore Int64) (:f tokenEconomicsScore Int64) (:f commitHash String))

fn makeRadarAxisScore axis: String score: Int64 snapshotHash: String receiptId: String -> RadarAxisScore
  (RadarAxisScore :axis axis :score score :snapshotHash snapshotHash :receiptId receiptId)

fn makeRadarSnapshot arch: Int64 plat: Int64 log: Int64 mem: Int64 sec: Int64 tok: Int64 commit: String -> RadarSnapshot
  (let [(overall (/ (+ (+ (+ (+ (+ arch plat) log) mem) sec) tok) 6))] (RadarSnapshot :score overall :architectureScore arch :platformScore plat :logicScore log :memoryScore mem :securityScore sec :tokenEconomicsScore tok :commitHash commit))

fn calculateRadarPoints snap: RadarSnapshot -> String
  (let [(s0 snap.architectureScore) (s1 snap.platformScore) (s2 snap.logicScore) (s3 snap.memoryScore) (s4 snap.securityScore) (s5 snap.tokenEconomicsScore) (x0 150) (y0 (- 150 s0)) (x1 (+ 150 (/ (* s1 866) 1000))) (y1 (- 150 (/ (* s1 500) 1000))) (x2 (+ 150 (/ (* s2 866) 1000))) (y2 (+ 150 (/ (* s2 500) 1000))) (x3 150) (y3 (+ 150 s3)) (x4 (- 150 (/ (* s4 866) 1000))) (y4 (+ 150 (/ (* s4 500) 1000))) (x5 (- 150 (/ (* s5 866) 1000))) (y5 (- 150 (/ (* s5 500) 1000)))] (str (stringFromInt64 x0) "," (stringFromInt64 y0) " " (stringFromInt64 x1) "," (stringFromInt64 y1) " " (stringFromInt64 x2) "," (stringFromInt64 y2) " " (stringFromInt64 x3) "," (stringFromInt64 y3) " " (stringFromInt64 x4) "," (stringFromInt64 y4) " " (stringFromInt64 x5) "," (stringFromInt64 y5)))

fn formatAxisLabel name: String score: Int64 -> String
  (str name " (" (stringFromInt64 score) ")")

fn renderRadarSvgContent snap: RadarSnapshot -> String
  (let [(pts (calculateRadarPoints snap))] (str "<svg viewBox=\"0 0 300 300\" class=\"sds1-radar-svg\">\n" "  <polygon points=\"150,50 237,100 237,200 150,250 63,200 63,100\" fill=\"none\" stroke=\"#1e293b\" stroke-width=\"1\"/>\n" "  <polygon points=\"" pts "\" fill=\"rgba(16,185,129,0.25)\" stroke=\"#10b981\" stroke-width=\"2\"/>\n" "</svg>"))

fn renderRadarCard snap: RadarSnapshot -> ui/VNode
  (let [(titleText (str "Codebase Integrity Radar (" (stringFromInt64 snap.score) "/100)")) (titleNode (ui/makeText titleText "radar-title")) (svgContent (renderRadarSvgContent snap)) (svgAttrs (mapSet (mapEmpty) "class" "radar-svg-container")) (svgNode (ui/makeVNode "svg-wrapper" "radar-svg" svgContent svgAttrs (list) 300 300 true)) (cardAttrs (mapSet (mapSet (mapEmpty) "class" "sds1-radar-card") "data-commit" snap.commitHash))] (ui/makeContainer "radar-card-root" cardAttrs (list titleNode svgNode)))
