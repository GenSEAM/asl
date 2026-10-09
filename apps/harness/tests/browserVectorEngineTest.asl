(module aslHarness/browserVectorEngineTest :x [testSpatialBoxCreation testAsnVectorTreeInitialization testTranspileAsnToDomSvg testTranspileCanvasStream testExtractSpatialVdom runTests] :i [(browserVectorEngine :a bve)])

fn testSpatialBoxCreation -> Bool
  (let [(b (bve/makeSpatialBox 10.0 20.0 150.0 80.0 "button"))] (assert (= b.x 10.0) "Box X coordinate must match") (assert (= b.y 20.0) "Box Y coordinate must match") (assert (= b.width 150.0) "Box width must match") (assert (= b.label "button") "Box label must match") true)

fn testAsnVectorTreeInitialization -> Bool
  (let [(tree (bve/makeVectorTree "svg" "0 0 100 100" 2 "(:svg (:rc :x 0 :y 0))"))] (assert (= tree.rootTag "svg") "Root tag must match svg") (assert (= tree.viewbox "0 0 100 100") "Viewbox must match specification") (assert (= tree.elementCount 2) "Element count must equal 2") (assert (> (stringLength tree.rawAsn) 0) "Raw ASN must be non-empty") true)

fn testTranspileAsnToDomSvg -> Bool
  (let [(eng (bve/makeVectorEngine 60 false true)) (tree (bve/makeVectorTree "svg" "0 0 500 500" 1 "(:svg (:rc :f red))")) (dom (bve/transpileAsnToDom tree eng))] (assert (stringContains? dom "<svg") "DOM output must contain svg element") (assert (stringContains? dom "viewBox=\"0 0 500 500\"") "DOM output must contain viewBox") (assert (stringContains? dom "<rect") "DOM output must convert :rc to rect") (assert (stringContains? dom "</svg>") "DOM output must close svg container") true)

fn testTranspileCanvasStream -> Bool
  (let [(eng (bve/makeVectorEngine 60 true true)) (tree (bve/makeVectorTree "canvas" "0 0 800 600" 1 "(:canvas (:path))")) (stream (bve/transpileAsnToDom tree eng))] (assert (stringContains? stream "ctx.beginPath()") "Canvas stream must invoke beginPath") (assert (stringContains? stream "canvas") "Canvas stream must reference root tag") (assert eng.emitCanvas "Engine must have emit-canvas active") true)

fn testExtractSpatialVdom -> Bool
  (let [(treeRc (bve/makeVectorTree "svg" "0 0 100 100" 1 "(:svg (:rc))")) (treeCirc (bve/makeVectorTree "svg" "0 0 100 100" 1 "(:svg (:circ))")) (boxRc (bve/extractSpatialVdom treeRc)) (boxCirc (bve/extractSpatialVdom treeCirc))] (assert (= boxRc.label "rect") "Rect tree must produce rect box") (assert (= boxRc.width 100.0) "Rect width must be 100.0") (assert (= boxCirc.label "circle") "Circ tree must produce circle box") (assert (= boxCirc.x 50.0) "Circle X position must be 50.0") true)

fn runTests -> Bool
  (and (testSpatialBoxCreation) (and (testAsnVectorTreeInitialization) (and (testTranspileAsnToDomSvg) (and (testTranspileCanvasStream) (testExtractSpatialVdom)))))
