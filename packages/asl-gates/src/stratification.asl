(module asl-gates/stratification :x [LayerTier StratificationReport moduleLayer verifyLayerBoundary isKernelClean? auditStratification] :i [])

(schema LayerTier (:f tier I64) (:f name Str) (:f role Str))

(schema StratificationReport (:f scope Str) (:f stratified Bool) (:f leakages I64) (:f layers I64) (:f healthy Bool))

fn extractPkg parts: (List Str) defaultName: Str -> Str
  (if (and (>= (listLength parts) 3) (and (= (optionOr (listGet parts 0) "") "asl") (= (optionOr (listGet parts 1) "") "packages"))) (optionOr (listGet parts 2) defaultName) (if (and (>= (listLength parts) 2) (= (optionOr (listGet parts 0) "") "packages")) (optionOr (listGet parts 1) defaultName) (optionOr (listGet parts 0) defaultName)))

fn isLayer3Pkg? p: Str -> Bool
  (listContains? (list "asl-harness" "harness" "asl-gates" "gates" "asl-lint" "lint" "asl-checker" "checker" "asl-cli" "cli" "asl-pack" "pack" "asl-bridge" "bridge" "asl-plugin" "plugin" "bench" "tools") p)

fn isLayer2Pkg? p: Str -> Bool
  (listContains? (list "asl-agent" "agent" "agent-bus" "agent-core" "asl-teleology" "teleology" "asl-router" "router" "asl-crawler" "crawler" "asl-bus" "bus") p)

fn isLayer1Pkg? p: Str -> Bool
  (listContains? (list "asl-engine" "engine" "asl-vfs" "vfs" "asl-vdom" "vdom" "asl-intel" "intel" "asl-mem" "mem" "asl-egraph" "egraph") p)

fn moduleLayer name: Str -> I64
  (let [(n (stringTrim name)) (parts (stringSplit n "/")) (pkg (extractPkg parts n))] (if (isLayer3Pkg? pkg) 3 (if (isLayer2Pkg? pkg) 2 (if (isLayer1Pkg? pkg) 1 0))))

fn verifyLayerBoundary srcLayer: I64 dstLayer: I64 -> Bool
  (>= srcLayer dstLayer)

fn isKernelClean? content: Str -> Bool
  (let [(trimmed (stringTrim content))] (not (or (stringContains? trimmed "@scout") (or (stringContains? trimmed "@coder") (or (stringContains? trimmed "@reviewer") (or (stringContains? trimmed "asl-bridge") (stringContains? trimmed "asl-plugin")))))))

fn auditStratification srcMod: Str dstMod: Str -> StratificationReport
  (let [(lSrc (moduleLayer srcMod)) (lDst (moduleLayer dstMod)) (valid (verifyLayerBoundary lSrc lDst))] (if valid (StratificationReport :scope (str srcMod "->" dstMod) :stratified true :leakages 0 :layers 4 :healthy true) (StratificationReport :scope (str srcMod "->" dstMod) :stratified false :leakages (- lDst lSrc) :layers 4 :healthy false)))
