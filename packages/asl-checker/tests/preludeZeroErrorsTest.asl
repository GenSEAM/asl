(module asl-checker/preludeZeroErrorsTest :x [runTests RunTests] :i [(check :a c) (types :a ty)])

; (:m :ref CHKFIX :do "pins asl/prelude/prelude.asl itself at zero checker diagnostics, a property that previously held for none of 16 positions (8 Map-vs-PreludeMap aliasing in mapEmpty/mapSet/mapRemove/mapGet, 2 int32ToInt64/int64ToInt32 width-cast, 4 checkedDiv/checkedMod float-vs-int branch-substitution leakage, 2 base64 (+ 0 0) else-branch not typed Unit); unifyTest.asl's testMapPreludeMapAlias/testInt32Int64Alias pin the narrow unify.asl fix in isolation, this test pins the actual file end to end so a future prelude.asl edit that reopens any of these or a new class of mismatch is caught here directly, not only inferred from checkerTest/preludeValues staying green")
fn diagnosticsText ds: (List ty/Diagnostic) -> String
  (stringJoin (map (fn [(d ty/Diagnostic)] -> String (str d.code " " d.message)) ds) "; ")

fn ! testPreludeChecksClean! -> Bool
  (let [(ds (resultOr (c/checkFile! "asl/prelude/prelude.asl" (list ".")) (list (ty/Diagnostic :code "ERR_IO" :message "checkFile! failed to read asl/prelude/prelude.asl" :msg "checkFile! failed to read asl/prelude/prelude.asl" :line 0 :col 0 :path "asl/prelude/prelude.asl"))))]
    (do (assert (listEmpty? ds) (str "asl/prelude/prelude.asl must check with zero diagnostics: " (diagnosticsText ds))) true))

fn ! runTests -> Bool
  (do (assert (testPreludeChecksClean!) "asl/prelude/prelude.asl checks clean (CHKFIX item 5)") true)

fn ! RunTests -> Bool
  (runTests)
