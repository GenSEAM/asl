(module asl-intel/tests/outlineBangTest
  :x [runTests]
  :i [(asl-intel :a intel)
      (asl-intel/text :a t)
      (asl-intel/rx :a r)
      (asl-intel/pats :a p)
      (asl-intel/host :a h)])

fn headerCaps rex: r/Rex s: String -> (List Int64)
  (let [(b (stringToBytes s))] (optionOr (r/rexSearch rex b (bytesLength b) 0) (list)))

fn grp rex: r/Rex s: String n: Int64 -> String
  (t/pyStrip (optionOr (r/rexGroup s (headerCaps rex s) n) "<none>"))

fn testOutlineNames -> Bool
  (let [(o (p/patOutlineFn!))]
    (do (assert (= (grp o "fn ! runShell! cmd: String -> Int64\n" 1) "runShell!") "outline: effect marker and trailing bang leave the name runShell!")
        (assert (= (grp o "fn privateDir? d: String -> Bool\n" 1) "privateDir?") "outline: question mark stays in the name")
        (assert (= (grp o "fn plain x: Int64 -> Int64\n" 1) "plain") "outline: plain name unchanged")
        (assert (= (grp o "fn !report x: Int64 -> Int64\n" 1) "!report") "outline: a glued bang is the name")
        (assert (= (grp o "fn ! spaced x: Int64 -> Int64\n" 1) "spaced") "outline: a lone bang token is the marker")
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

; (:m :ref INTEL-GLUED-BANG-NAME :do "one fixture with fn !report (glued: the symbol is named !report) and fn ! spaced (lone marker token: the symbol is named spaced): outline, query, stubs, graph and vacuity report the same names, !report and spaced, never report or ! spaced")
fn fixtureText -> String
  "(module fx/bang :x [report spaced runTests])\n\nfn !report x: Int64 -> Int64\n  0\n\nfn ! sepOne a: Int64 -> Int64\n  (+ a 1)\n\nfn ! spaced y: Int64 -> Int64\n  0\n\nfn ! sepTwo a: Int64 -> Int64\n  (+ a 1)\n\nfn ! runTests -> Bool\n  true\n"

fn ! boundedMkdir path: String -> Bool
  (ok? (dirCreate path))

fn ! agreeOn! sub: String args: (List String) -> String
  (let [(dir (str (resultOr (realPath "/tmp") "/tmp") "/aslBangSplit." (stringFromInt64 (procSelf))))
        (src (str dir "/asl/packages/fx/src"))
        (_m (boundedMkdir src))
        (_w (fileWrite (str src "/bang.asl") (fixtureText)))
        (ctx (h/Ctx :home dir :cwd dir :aslRoot "" :env (none)))
        (o (intel/runIntel! ctx (cons sub args)))
        (_r (pathRemove dir))]
    (str o.out o.err))

fn ! testOpsAgree -> Bool
  (let [(outline (agreeOn! "outline" (list "asl/packages/fx/src/bang.asl")))
        (query (agreeOn! "query" (list "report")))
        (queryB (agreeOn! "query" (list "spaced")))
        (stubs (agreeOn! "stubs" (list "--asn")))
        (graph (agreeOn! "graph" (list "--json")))
        (vac (agreeOn! "vacuity" (list "--asn")))]
    (do (assert (stringContains? outline ":name \"!report\"") (str "outline: !report: " outline))
        (assert (stringContains? outline ":name \"spaced\"") (str "outline: spaced: " outline))
        (assert (not (stringContains? outline ":name \"report\"")) "outline: the glued marker is part of the name")
        (assert (stringContains? query ":symbol \"!report\"") (str "query: !report: " query))
        (assert (stringContains? queryB ":symbol \"spaced\"") (str "query: spaced: " queryB))
                (assert (not (stringContains? queryB "\"! spaced\"")) "query: no spaced marker in the name")
        (assert (stringContains? stubs "!report") (str "stubs: !report: " stubs))
        (assert (not (stringContains? stubs "! spaced")) "stubs: no spaced marker in the name")
        (assert (stringContains? graph "\"symbol\": \"!report\"") (str "graph: !report: " graph))
        (assert (stringContains? graph "\"symbol\": \"spaced\"") (str "graph: spaced: " graph))
        (assert (stringContains? vac "runTests") (str "vacuity: runTests: " vac))
        (assert (not (stringContains? vac "! runTests")) "vacuity: no marker in the name")
        true))

fn ! runTests -> Bool
  (and (testOutlineNames) (and (testHeaderParams) (and (testOutlineOfRunAsl!) (testOpsAgree))))
