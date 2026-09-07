(module asl-gates/stratification
  :d "Pure AgentScript 4-tier architectural layer stratification engine and boundary checker."
  :x [LayerTier
      StratificationReport
      module-layer
      verify-layer-boundary
      is-kernel-clean?
      audit-stratification]
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

(df module-layer [(name Str)] -> I64
  :d "Maps package name, module path, or identifier to architectural layer tier (0..3)."
  (let [(n (string-trim name))]
    (if (or (string-contains? n "asl-bridge")
            (or (string-contains? n "asl-plugin")
                (or (string-contains? n "asl-sh")
                    (or (string-contains? n "asl-cli")
                        (or (string-contains? n "asl-gates")
                            (or (string-contains? n "browser-plugin")
                                (or (string-contains? n "bridges/")
                                    (or (string-contains? n "bin/")
                                        (or (string-contains? n "vdom")
                                            (string-contains? n "gsa"))))))))))
      3
      (if (or (string-contains? n "crawler")
              (or (string-contains? n "web-api-search")
                  (or (string-contains? n "asl-registry")
                      (or (string-contains? n "voice")
                          (or (string-contains? n "asl-mem")
                              (or (= n "mem")
                                  (or (string-contains? n "mem/")
                                      (or (string-contains? n "/mem/")
                                          (string-contains? n "config")))))))))
        2
        (if (or (string-contains? n "agent-bus")
                (or (string-contains? n "agent-core")
                    (or (string-contains? n "harness")
                        (string-contains? n "asl-contracts"))))
          1
          0)))))

(df verify-layer-boundary [(src-layer I64) (dst-layer I64)] -> Bool
  :d "Enforces downward-only dependency invariant Layer(u) >= Layer(v). Returns false for illegal upward dependencies."
  (>= src-layer dst-layer))

(df is-kernel-clean? [(content Str)] -> Bool
  :d "Audits Layer 0 source code to guarantee zero agent identity leakage and zero host bridge leakage."
  (let [(trimmed (string-trim content))]
    (not (or (string-contains? trimmed "@scout")
             (or (string-contains? trimmed "@coder")
                 (or (string-contains? trimmed "@reviewer")
                     (or (string-contains? trimmed "asl-bridge")
                         (string-contains? trimmed "asl-plugin"))))))))

(df audit-stratification [(src-mod Str) (dst-mod Str)] -> StratificationReport
  :d "Evaluates dependency edge between two modules and produces a StratificationReport."
  (let [(l-src (module-layer src-mod))
        (l-dst (module-layer dst-mod))
        (valid (verify-layer-boundary l-src l-dst))]
    (if valid
      (StratificationReport
        :scope (str src-mod "->" dst-mod)
        :stratified true
        :leakages 0
        :layers 4
        :healthy true)
      (StratificationReport
        :scope (str src-mod "->" dst-mod)
        :stratified false
        :leakages (- l-dst l-src)
        :layers 4
        :healthy false))))
