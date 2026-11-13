fn mergeSorted a: (List Int64) b: (List Int64) -> (List Int64)
  (match (listHead a)
    ((none) b)
    ((some x)
      (match (listHead b)
        ((none) a)
        ((some y)
          (cond
            ((<= x y)
              (listAppend (list x) (mergeSorted (optionOr (listTail a) (list)) b)))
            (else
              (listAppend (list y) (mergeSorted a (optionOr (listTail b) (list))))))))))
