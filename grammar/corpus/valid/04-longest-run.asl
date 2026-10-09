"The worked example from asl/agentSpecCore.md section 7, with its list patterns"

"taken apart through listHead and listTail and its pair through mt, since"

"lists are not patterns and a pair has no .-second field."

fn runLength chars: (List String) cur: String n: Int64 best: (Pair String Int64) -> (Pair String Int64)
  (let [(better (match best ((pair c k) (if (> n k) (pair cur n) best)))) (rest (optionOr (listTail chars) (list)))] (match (listHead chars) ((none) better) ((some h) (if (= h cur) (runLength rest cur (+ n 1) best) (runLength rest h 1 better)))))

fn longestRun s: String -> (Option (Pair String Int64))
  (let [(cs (stringChars s))] (match (listHead cs) ((none) (none)) ((some h) (some (runLength (optionOr (listTail cs) (list)) h 1 (pair h 1))))))
