(module asl-checker/effectWorklistTest :x [runTests] :i [(ast :a a) (resolve :a r)])

fn summaryOf src: String path: String imports: (Map String String) -> r/ModuleSummary
  (match (a/parse src)
    ((err _) (r/emptyModuleSummary))
    ((ok forms) (with (r/collectSummary forms path) :imports imports)))

fn effectOf m: r/ModuleSummary name: String -> Bool
  (match (mapGet m.funs name) ((some f) f.effect) ((none) false))

fn witnessOf m: r/ModuleSummary name: String -> String
  (match (mapGet m.funs name) ((some f) f.witness) ((none) "?"))

fn refined deps: (Map String r/ModuleSummary) top: r/ModuleSummary path: String -> r/ModuleSummary
  (let [(res (r/refineEffects top (r/depIndexOf deps)))] (pairFirst res))

fn runTests -> Bool
  (let [(cMod (summaryOf "(module c) (fn leaf [] -> Int64 (do (fileWrite \"x\" \"y\") 1))" "c.asl" (mapEmpty)))
        (bMod (summaryOf "(module b) (fn mid [] -> Int64 (c/leaf)) (fn pureB [] -> Int64 3)" "b.asl" (mapSet (mapEmpty) "c" "c.asl")))
        (aMod (summaryOf "(module a) (fn top [] -> Int64 (b/mid)) (fn ping [] -> Int64 (pong)) (fn pong [] -> Int64 (do (ping) (b/mid))) (fn selfA [] -> Int64 (selfA)) (fn pureTop [] -> Int64 (+ (b/pureB) 1))" "a.asl" (mapSet (mapEmpty) "b" "b.asl")))
        (deps (mapSet (mapSet (mapEmpty) "c.asl" cMod) "b.asl" bMod))
        (out (refined deps aMod "a.asl"))]
    (do (assert (effectOf out "top") "three-module chain ending in fileWrite makes the top fn effectful")
        (assert (= (witnessOf out "top") "fileWrite") "chain witness is the builtin at the end")
        (assert (effectOf out "ping") "mutual recursion member reaching an effect through its partner is effectful")
        (assert (effectOf out "pong") "mutual recursion partner calling an effectful import is effectful")
        (assert (= (witnessOf out "ping") "fileWrite") "mutual recursion witness traces to the builtin")
        (refute (effectOf out "selfA") "self recursion alone stays pure")
        (refute (effectOf out "pureTop") "a fn calling only pure fns stays pure")
        (assert (= (witnessOf out "pureTop") "") "pure fn has no witness")
        true))
