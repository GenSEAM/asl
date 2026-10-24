(module asl-ir/tests/builtinEntryTest :x [runTests] :i [(asl-ir/types :a ty)])

fn sameEntry a: ty/SsaBuiltin b: ty/SsaBuiltin -> Bool
  (and (and (= a.name b.name) (= a.symbol b.symbol)) (and (= a.kind b.kind) (and (= (listLength a.args) (listLength b.args)) (= a.result b.result))))

fn viaTable name: String arity: Int64 -> (Option ty/SsaBuiltin)
  (listHead (filter (fn [(b ty/SsaBuiltin)] -> Bool (and (= b.name name) (= (listLength b.args) arity))) (ty/builtinEntries)))

fn agrees name: String arity: Int64 -> Bool
  (match (ty/builtinEntry name arity)
    ((none) (listEmpty? (filter (fn [(b ty/SsaBuiltin)] -> Bool (and (= b.name name) (= (listLength b.args) arity))) (ty/builtinEntries))))
    ((some got) (match (viaTable name arity) ((some want) (sameEntry got want)) ((none) false))))

fn ! runTests -> Bool
  (let [(rows (ty/builtinEntries))
        (bad (filter (fn [(b ty/SsaBuiltin)] -> Bool (not (and (agrees b.name (listLength b.args)) (and (agrees b.name 0) (and (agrees b.name 7) (agrees b.name (+ (listLength b.args) 1))))))) rows))]
    (do
      (assert (= (listLength rows) 50) "builtinEntries has 50 rows, each covered")
      (assert (listEmpty? bad) (str "builtinEntry agrees with the filter over builtinEntries for every row at its arity and at 0, 7, arity+1: " (stringJoin (map (fn [(b ty/SsaBuiltin)] -> String b.name) bad) " ")))
      (assert (match (ty/builtinEntry "nopeNoSuch" 1) ((none) true) (_ false)) "an unknown name has no entry")
      true))
