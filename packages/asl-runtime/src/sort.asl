(module asl-runtime/sort :x [rtStableSort rtStableSortBy] :i [])

fn mergeStably left: (List Str) right: (List Str) cmp: (fn [(Str) (Str)] -> Bool) -> (List Str)
  (if (listEmpty? left) right (if (listEmpty? right) left (let [(lh (optionOr (listHead left) "")) (rh (optionOr (listHead right) "")) (lt (optionOr (listTail left) (list))) (rt (optionOr (listTail right) (list)))] (if (cmp lh rh) (cons lh (mergeStably lt right cmp)) (cons rh (mergeStably left rt cmp))))))

fn rtStableSortBy items: (List Str) cmp: (fn [(Str) (Str)] -> Bool) -> (List Str)
  (let [(len (listLength items))] (if (<= len 1) items (let [(mid (/ len 2)) (left (optionOr (listSlice items 0 mid) (list))) (right (optionOr (listSlice items mid len) (list)))] (mergeStably (rtStableSortBy left cmp) (rtStableSortBy right cmp) cmp))))

fn rtStableSort items: (List Str) -> (List Str)
  (rtStableSortBy items (fn [(a Str) (b Str)] -> Bool (<= a b)))
