(module asl-intel/tests/outlineBangTest
  :x [runTests]
  :i [(asl-intel :a intel)
      (asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)])

fn headerCaps rex: r/Rex s: String -> (List Int64)
  (let [(b (stringToBytes s))] (optionOr (r/rexSearch rex b (bytesLength b) 0) (list)))

fn grp rex: r/Rex s: String n: Int64 -> String
  (t/pyStrip (optionOr (r/rexGroup s (headerCaps rex s) n) "<none>"))

fn testOutlineNames -> Bool
  (let [(o (p/patOutlineFn!))]
    (do (assert (= (grp o "fn ! runShell! cmd: String -> Int64\n" 1) "runShell!") "outline: effect marker and trailing bang leave the name runShell!")
        (assert (= (grp o "fn privateDir? d: String -> Bool\n" 1) "privateDir?") "outline: question mark stays in the name")
        (assert (= (grp o "fn plain x: Int64 -> Int64\n" 1) "plain") "outline: plain name unchanged")
        (assert (= (grp o "fn ! runShell! cmd: String -> Int64\n" 2) "cmd: String") "outline: params exclude the bang")
        true))

fn testHeaderParams -> Bool
  (let [(h (p/patFnHeader!))]
    (do (assert (= (grp h "fn runShell! cmd: String -> Int64\n" 1) "runShell!") "header: trailing bang belongs to the name")
        (assert (= (grp h "fn runShell! cmd: String -> Int64\n" 2) "cmd: String") "header: params group has no bang")
        (assert (= (grp h "fn ! stubHostFor! cmd: String -> String\n" 2) "cmd: String") "header: marker plus bang keep params clean")
        (assert (= (grp h "fn privateDir? d: String -> Bool\n" 1) "privateDir?") "header: question mark stays in the name")
        true))

fn testOutlineOfRunAsl! -> Bool
  (let [(ctx (intel/makeCtx!))
        (o (intel/runIntel! ctx (list "outline" "asl/tools/fleet/run.asl")))]
    (do (assert (= o.code 0) (str "outline exits 0: " o.err))
        (assert (stringContains? o.out ":name \"runShell!\"") "outline of run.asl lists runShell! by real name")
        (assert (stringContains? o.out ":name \"privateDir?\"") "outline of run.asl lists privateDir? by real name")
        (assert (not (stringContains? o.out ":name \"! ")) "outline of run.asl has no marker-prefixed names")
        true))

fn ! runTests -> Bool
  (and (testOutlineNames) (and (testHeaderParams) (testOutlineOfRunAsl!)))
