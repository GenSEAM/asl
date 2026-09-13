"The worked example from AGENT_SPEC_CORE.md section 7."

(df runLength [(chars (List String)) (cur String) (n Int64) (best (Pair String Int64))]
        -> (Pair String Int64)
  (match chars
    ((list)
     (if (> n (.-second best)) (pair cur n) best))
    ((cons h t)
     (if (= h cur)
       (runLength t cur (+ n 1) best)
       (let [(best2 (if (> n (.-second best)) (pair cur n) best))]
         (runLength t h 1 best2))))))

(df longestRun [(s String)] -> (Option (Pair String Int64))
  (match (string-chars s)
    ((list)     (none))
    ((cons h t) (some (runLength t h 1 (pair h 1))))))
