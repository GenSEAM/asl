(module ws/asl/tools/observe/tests/bangDefsTest
  :x [runTests]
  :i [(ws/asl/tools/observe/aslIndex :a ai)])

; (:m :ref OBSERVE-CALLERS-BANG-MISS :do "a bang glued to its name (fn !glued g) stays that token as the def name: only a lone ! is the effect marker; an effect fn written fn ! name! args is indexed under its own name, not under the effect marker, so a callers query for a bang symbol finds its def and a plain fn keeps working")
fn ! runTests -> Bool
  (let [(root (str (resultOr (realPath ".") ".") "/.asl/cache/bangDefsTest-" (stringFromInt64 (procSelf))))
        (_ (dirCreate (str (resultOr (realPath ".") ".") "/.asl/cache")))
        (_ (dirCreate root))
        (wrote (fileWrite (str root "/m.asl") "(module m\n  :x [plain effectful! checked?]\n  :i [])\n\nfn plain x: Int64 -> Int64\n  x\n\nfn ! effectful! cmd: String -> Int64\n  1\n\nfn ! checked? cmd: String -> Bool\n  true\n\nfn !glued g: Int64 -> Int64\n  g"))
        (names (ai/defNames (ai/buildAslIndex! root (list "m.asl") "")))
        (_ (pathRemove (str root "/m.asl")))
        (_ (pathRemove root))]
    (do (assert (ok? wrote) "fixture: the module is written")
        (assert (listContains? names "plain") (str "a plain fn is indexed: " (stringJoin names ",")))
        (assert (listContains? names "effectful!") (str "fn ! name! is indexed under name!: " (stringJoin names ",")))
        (assert (listContains? names "checked?") (str "fn ! name? is indexed under name?: " (stringJoin names ",")))
        (assert (not (listContains? names "!")) (str "the effect marker is never a def name: " (stringJoin names ",")))
        (assert (listContains? names "!glued") (str "a bang glued to its name (fn !glued) is the name token itself, not a lone marker: " (stringJoin names ",")))
        (assert (not (listContains? names "g")) (str "and the def is not skipped to the arg token: " (stringJoin names ",")))
        true))
