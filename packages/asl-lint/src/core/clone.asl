(module asl-lint/clone :x [CloneType CloneGroup CloneVerdict isCloneExcessive computeDuplicationRatio minCloneNodeThreshold])

(enum CloneType (:c exactClone [] "Identical AST subtree including variable names and literals") (:c structuralClone [] "Structurally equivalent subtree with renamed local variables"))

(schema CloneGroup (:f hash String) (:f nodeCount Int64) (:f occurrences Int64) (:f cloneType CloneType))

(schema CloneVerdict (:f duplicateNodes Int64) (:f totalNodes Int64) (:f duplicationRatio Float) (:f isExcessive Bool))

fn minCloneNodeThreshold -> Int64
  6

fn isCloneExcessive ratio: Float threshold: Float -> Bool
  (> ratio threshold)

fn computeDuplicationRatio dupNodes: Int64 totalNodes: Int64 -> Float
  (if (<= totalNodes 0) 0.0 (/ (int64ToFloat64 dupNodes) (int64ToFloat64 totalNodes)))
