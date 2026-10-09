(module aslHarness/browserVectorEngine :x [VectorEngine SpatialBox AsnVectorTree transpileAsnToDom extractSpatialVdom makeSpatialBox makeVectorEngine makeVectorTree] :i [])

(schema SpatialBox (:f x F64) (:f y F64) (:f width F64) (:f height F64) (:f label Str))

(schema AsnVectorTree (:f rootTag Str) (:f viewbox Str) (:f elementCount I64) (:f rawAsn Str))

(schema VectorEngine (:f maxFps I64) (:f emitCanvas Bool) (:f sub2msBudget Bool))

fn makeSpatialBox x: F64 y: F64 w: F64 h: F64 lbl: Str -> SpatialBox
  (SpatialBox :x x :y y :width w :height h :label lbl)

fn makeVectorTree root: Str vb: Str count: I64 asn: Str -> AsnVectorTree
  (AsnVectorTree :rootTag root :viewbox vb :elementCount count :rawAsn asn)

fn makeVectorEngine fps: I64 canvas: Bool budget: Bool -> VectorEngine
  (VectorEngine :maxFps fps :emitCanvas canvas :sub2msBudget budget)

fn transpileAsnToDom tree: AsnVectorTree engine: VectorEngine -> Str
  (let [(asn tree.rawAsn) (vb tree.viewbox)] (cond ((stringEmpty? asn) "<svg></svg>") (engine.emitCanvas (str "ctx.beginPath(); // canvas 2D stream from " tree.rootTag)) (true (let [(s1 (stringReplace asn "(:svg" (str "<svg viewBox=\"" vb "\">"))) (s2 (stringReplace s1 "(:rc" "<rect")) (s3 (stringReplace s2 "(:circ" "<circle")) (s4 (stringReplace s3 "(:p" "<path")) (s5 (stringReplace s4 ":f" "fill")) (s6 (stringReplace s5 ":s" "stroke")) (s7 (stringReplace s6 ")" "/>"))] (str s7 "</svg>")))))

fn extractSpatialVdom tree: AsnVectorTree -> SpatialBox
  (let [(asn tree.rawAsn)] (cond ((stringContains? asn ":rc") (makeSpatialBox 0.0 0.0 100.0 100.0 "rect")) ((stringContains? asn ":circ") (makeSpatialBox 50.0 50.0 50.0 50.0 "circle")) (true (makeSpatialBox 0.0 0.0 800.0 600.0 tree.rootTag))))
