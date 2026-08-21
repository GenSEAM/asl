(module bench/histogram
  :doc "Most frequent letters in a space-separated string (HumanEval/111)."
  :export [histogram])

(defun histogram [(text String)] -> (Map String Int64)
  :doc "Letters occurring most often, with their counts."
  (let [(words (filter (fn [(w String)] -> Bool (not (string-empty? w)))
                       (string-split (string-trim text) " ")))
        (counts (fold (fn [(m (Map String Int64)) (w String)] -> (Map String Int64)
                        (map-set m w (+ (option-or (map-get m w) 0) 1)))
                      (map-empty) words))]
    (match (list-max (map-values counts))
      ((none) (map-empty))
      ((some top)
       (map-from-pairs
         (filter (fn [(p (Pair String Int64))] -> Bool (= (.-second p) top))
                 (map-pairs counts)))))))
