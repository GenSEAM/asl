(module asl-lint/clone
  :doc "AgentScript native structural clone, AST fingerprinting, and copy-paste detection."
  :export [CloneType CloneGroup CloneVerdict
           is-clone-excessive compute-duplication-ratio min-clone-node-threshold])

(defenum CloneType
  (:case exact-clone      [] "Identical AST subtree including variable names and literals")
  (:case structural-clone [] "Structurally equivalent subtree with renamed local variables"))

(defschema CloneGroup
  (:field hash String "Structural fingerprint hash of the normalized subtree")
  (:field node-count Int64 "Number of AST nodes in each subtree instance")
  (:field occurrences Int64 "Number of duplicate occurrences across codebase")
  (:field clone-type CloneType "Exact or structural clone classification"))

(defschema CloneVerdict
  (:field duplicate-nodes Int64 "Total nodes duplicated across non-primary instances")
  (:field total-nodes Int64 "Total AST nodes in the analyzed files")
  (:field duplication-ratio Float "Ratio of duplicate nodes (0.0 to 1.0)")
  (:field is-excessive Bool "True if duplication ratio exceeds quality threshold"))

(defun min-clone-node-threshold [] -> Int64
  :doc "Minimum subtree node size to be considered a meaningful clone candidate."
  6)

(defun is-clone-excessive [(ratio Float) (threshold Float)] -> Bool
  :doc "Returns true if duplication ratio exceeds allowable quality limit."
  (> ratio threshold))

(defun compute-duplication-ratio [(dup-nodes Int64) (total-nodes Int64)] -> Float
  :doc "Calculates float duplication ratio between 0.0 and 1.0."
  (if (<= total-nodes 0)
    0.0
    (/ (int64-to-float64 dup-nodes) (int64-to-float64 total-nodes))))
