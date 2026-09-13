(module asl-lint/clone
  :d "AgentScript native structural clone, AST fingerprinting, and copy-paste detection."
  :x [CloneType CloneGroup CloneVerdict
           isCloneExcessive computeDuplicationRatio minCloneNodeThreshold])

(dfe CloneType
  (:c exactClone      [] "Identical AST subtree including variable names and literals")
  (:c structuralClone [] "Structurally equivalent subtree with renamed local variables"))

(dfs CloneGroup
  (:f hash String "Structural fingerprint hash of the normalized subtree")
  (:f nodeCount Int64 "Number of AST nodes in each subtree instance")
  (:f occurrences Int64 "Number of duplicate occurrences across codebase")
  (:f cloneType CloneType "Exact or structural clone classification"))

(dfs CloneVerdict
  (:f duplicateNodes Int64 "Total nodes duplicated across non-primary instances")
  (:f totalNodes Int64 "Total AST nodes in the analyzed files")
  (:f duplicationRatio Float "Ratio of duplicate nodes (0.0 to 1.0)")
  (:f isExcessive Bool "True if duplication ratio exceeds quality threshold"))

(df minCloneNodeThreshold [] -> Int64
  :d "Minimum subtree node size to be considered a meaningful clone candidate."
  6)

(df isCloneExcessive [(ratio Float) (threshold Float)] -> Bool
  :d "Returns true if duplication ratio exceeds allowable quality limit."
  (> ratio threshold))

(df computeDuplicationRatio [(dupNodes Int64) (totalNodes Int64)] -> Float
  :d "Calculates float duplication ratio between 0.0 and 1.0."
  (if (<= totalNodes 0)
    0.0
    (/ (int64-to-float64 dupNodes) (int64-to-float64 totalNodes))))
