(module asl-lint/clone
  :d "AgentScript native structural clone, AST fingerprinting, and copy-paste detection."
  :x [CloneType CloneGroup CloneVerdict
           is-clone-excessive compute-duplication-ratio min-clone-node-threshold])

(dfe CloneType
  (:c exact-clone      [] "Identical AST subtree including variable names and literals")
  (:c structural-clone [] "Structurally equivalent subtree with renamed local variables"))

(dfs CloneGroup
  (:f hash String "Structural fingerprint hash of the normalized subtree")
  (:f node-count Int64 "Number of AST nodes in each subtree instance")
  (:f occurrences Int64 "Number of duplicate occurrences across codebase")
  (:f clone-type CloneType "Exact or structural clone classification"))

(dfs CloneVerdict
  (:f duplicate-nodes Int64 "Total nodes duplicated across non-primary instances")
  (:f total-nodes Int64 "Total AST nodes in the analyzed files")
  (:f duplication-ratio Float "Ratio of duplicate nodes (0.0 to 1.0)")
  (:f is-excessive Bool "True if duplication ratio exceeds quality threshold"))

(df min-clone-node-threshold [] -> Int64
  :d "Minimum subtree node size to be considered a meaningful clone candidate."
  6)

(df is-clone-excessive [(ratio Float) (threshold Float)] -> Bool
  :d "Returns true if duplication ratio exceeds allowable quality limit."
  (> ratio threshold))

(df compute-duplication-ratio [(dup-nodes Int64) (total-nodes Int64)] -> Float
  :d "Calculates float duplication ratio between 0.0 and 1.0."
  (if (<= total-nodes 0)
    0.0
    (/ (int64-to-float64 dup-nodes) (int64-to-float64 total-nodes))))
