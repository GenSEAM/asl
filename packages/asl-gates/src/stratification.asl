(module asl-gates/stratification
  :d "Pure AgentScript 4-tier architectural layer stratification engine and boundary checker."
  :x [LayerTier
      StratificationReport
      moduleLayer
      verifyLayerBoundary
      isKernelClean?
      auditStratification]
  :i [])

(dfs LayerTier
  (:f tier I64 "Architectural layer tier level (0 to 3)")
  (:f name Str "Canonical layer tier name")
  (:f role Str "Architectural role and boundary description"))

(dfs StratificationReport
  (:f scope Str "Evaluated module or dependency scope")
  (:f stratified Bool "Whether dependency direction strictly satisfies Layer(u) >= Layer(v)")
  (:f leakages I64 "Number of upward or inward layer leakage violations")
  (:f layers I64 "Number of distinct architectural layers evaluated")
  (:f healthy Bool "Overall architectural health status"))

(df extractPkg [(parts (List Str)) (defaultName Str)] -> Str
  :d "Extracts the package identifier from path segments."
  (if (and (>= (list-length parts) 3)
           (and (= (option-or (list-get parts 0) "") "asl")
                (= (option-or (list-get parts 1) "") "packages")))
    (option-or (list-get parts 2) defaultName)
    (if (and (>= (list-length parts) 2)
             (= (option-or (list-get parts 0) "") "packages"))
      (option-or (list-get parts 1) defaultName)
      (option-or (list-get parts 0) defaultName))))

(df isLayer3Pkg? [(p Str)] -> Bool
  :d "Checks if package belongs to Layer 3 (Supervision & Tooling)"
  (list-contains? (list "asl-harness" "harness"
                        "asl-gates" "gates"
                        "asl-lint" "lint"
                        "asl-checker" "checker"
                        "asl-cli" "cli"
                        "asl-pack" "pack"
                        "asl-bridge" "bridge"
                        "asl-plugin" "plugin"
                        "bench" "tools")
                  p))

(df isLayer2Pkg? [(p Str)] -> Bool
  :d "Checks if package belongs to Layer 2 (Agent Intent)"
  (list-contains? (list "asl-agent" "agent"
                        "agent-bus" "agent-core"
                        "asl-teleology" "teleology"
                        "asl-router" "router"
                        "asl-crawler" "crawler"
                        "asl-bus" "bus")
                  p))

(df isLayer1Pkg? [(p Str)] -> Bool
  :d "Checks if package belongs to Layer 1 (Resident Engine)"
  (list-contains? (list "asl-engine" "engine"
                        "asl-vfs" "vfs"
                        "asl-vdom" "vdom"
                        "asl-intel" "intel"
                        "asl-mem" "mem"
                        "asl-egraph" "egraph")
                  p))

(df moduleLayer [(name Str)] -> I64
  :d "Maps package name, module path, or identifier to architectural layer tier (0..3)."
  (let [(n (string-trim name))
        (parts (string-split n "/"))
        (pkg (extractPkg parts n))]
    (if (isLayer3Pkg? pkg)
      3
      (if (isLayer2Pkg? pkg)
        2
        (if (isLayer1Pkg? pkg)
          1
          0)))))

(df verifyLayerBoundary [(srcLayer I64) (dstLayer I64)] -> Bool
  :d "Enforces downward-only dependency invariant Layer(u) >= Layer(v). Returns false for illegal upward dependencies."
  (>= srcLayer dstLayer))

(df isKernelClean? [(content Str)] -> Bool
  :d "Audits Layer 0 source code to guarantee zero agent identity leakage and zero host bridge leakage."
  (let [(trimmed (string-trim content))]
    (not (or (string-contains? trimmed "@scout")
             (or (string-contains? trimmed "@coder")
                 (or (string-contains? trimmed "@reviewer")
                     (or (string-contains? trimmed "asl-bridge")
                         (string-contains? trimmed "asl-plugin"))))))))

(df auditStratification [(srcMod Str) (dstMod Str)] -> StratificationReport
  :d "Evaluates dependency edge between two modules and produces a StratificationReport."
  (let [(lSrc (moduleLayer srcMod))
        (lDst (moduleLayer dstMod))
        (valid (verifyLayerBoundary lSrc lDst))]
    (if valid
      (StratificationReport
        :scope (str srcMod "->" dstMod)
        :stratified true
        :leakages 0
        :layers 4
        :healthy true)
      (StratificationReport
        :scope (str srcMod "->" dstMod)
        :stratified false
        :leakages (- lDst lSrc)
        :layers 4
        :healthy false))))
