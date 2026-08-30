(module bench/histogram
  :doc "Most frequent letters in a space-separated string (HumanEval/111)."
  :export [histogram])

(defun tally [(m (Map String Int64)) (w String)] -> (Map String Int64)
  :doc "Increment the count for one letter."
  (match (map-get m w)
    ((some n) (map-set m w (+ n 1)))
    ((none)   (map-set m w 1))))

(defun histogram [(text String)] -> (Map String Int64)
  :doc "Letters occurring most often, with their counts. Empty input yields an empty map."
  (let [(words (filter (fn [(w String)] -> Bool (not (string-empty? w)))
                       (string-split (string-trim text) " ")))
        (counts (fold tally (map-empty) words))]
    (match (list-max (map-values counts))
      ((none) (map-empty))
      ((some top)
       (map-from-pairs
         (filter (fn [(p (Pair String Int64))] -> Bool (= (.-second p) top))
                 (map-pairs counts)))))))
