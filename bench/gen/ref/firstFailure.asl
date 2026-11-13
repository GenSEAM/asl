fn firstFailure checks: (List (Pair String Bool)) -> (Option String)
  (optionMap pairFirst (listFind (fn [c] (not (pairSecond c))) checks))
