fn runLenFrom text: String c: String i: Int64 n: Int64 -> Int64
  (cond ((>= i (stringLength text)) n)
        (else
          (let [(c2 (optionOr (stringSlice text i (+ i 1)) ""))]
            (cond ((stringContains? c c2) (runLenFrom text c (+ i 1) (+ n 1)))
                  (else n)))))

fn runFrom text: String i: Int64 -> (List (Pair String Int64))
  (cond ((>= i (stringLength text)) (list))
        (else
          (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
            (let [(n (runLenFrom text c (+ i 1) 1))]
              (listAppend (list (pair c n)) (runFrom text (+ i n)))))))

fn runLengthEncode text: String -> (List (Pair String Int64))
  (runFrom text 0)
