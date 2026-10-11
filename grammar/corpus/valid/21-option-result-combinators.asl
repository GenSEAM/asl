(module parse/resolve :x [resolve])

fn resolve raw: String fallback: Int64 -> String
  (let [(doubled (optionMap (fn [n] (* n 2)) (stringToInt64 raw))) (added (resultMap (fn [n] (+ n 1)) (optionToResult doubled (str "bad:" raw)))) (r (resultMapErr (fn [e] (str "E<" e ">")) added))] (stringJoin (list (match r ((ok v) (str "ok:" (stringFromInt64 v))) ((err e) (str "err:" e))) (resultOr (resultMap (fn [v] (stringFromInt64 v)) r) "FB") (stringFromInt64 (optionOr (resultToOption r) fallback))) "|"))
