fn chunk xs: (List Int64) size: Int64 -> (List (List Int64))
  (if (listEmpty? xs)
    (list)
    (listAppend (list (listTake xs size)) (chunk (listDrop xs size) size)))
