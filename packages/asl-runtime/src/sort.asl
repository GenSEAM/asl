(module asl-runtime/sort
  :d "Pure AgentScript stable sorting algorithms for list collections"
  :x [rtStableSort
      rtStableSortBy]
  :i [])

(df mergeStably [(left (List Str)) (right (List Str)) (cmp (fn [(Str) (Str)] -> Bool))] -> (List Str)
  :d "Merges two pre-sorted lists preserving relative order of equivalent elements."
  (if (list-empty? left)
      right
      (if (list-empty? right)
          left
          (let [(lh (option-or (list-head left) ""))
                (rh (option-or (list-head right) ""))
                (lt (option-or (list-tail left) (list)))
                (rt (option-or (list-tail right) (list)))]
            (if (cmp lh rh)
                (list-cons lh (mergeStably lt right cmp))
                (list-cons rh (mergeStably left rt cmp)))))))

(df rtStableSortBy [(items (List Str)) (cmp (fn [(Str) (Str)] -> Bool))] -> (List Str)
  :d "Stably sorts a list of strings using a custom comparison predicate."
  (let [(len (list-length items))]
    (if (<= len 1)
        items
        (let [(mid (/ len 2))
              (left (option-or (list-slice items 0 mid) (list)))
              (right (option-or (list-slice items mid len) (list)))]
          (mergeStably (rtStableSortBy left cmp)
                       (rtStableSortBy right cmp)
                       cmp)))))

(df rtStableSort [(items (List Str))] -> (List Str)
  :d "Stably sorts a list of strings in ascending lexicographical order."
  (rtStableSortBy items (fn [(a Str) (b Str)] -> Bool (<= a b))))
