(module asl/tools/tests/aslToolsEdgeTest
  :x [runTests]
  :i [(asl-tools/vcs/git :a vg)])

; (:m :ref ASL-IMPORTS-TOOLS :do "asl/ is planned to split into its own repo, so no .asl file under asl/ may import a tools/ module in its module header; this scans every tracked asl/**/*.asl header and fails on an edge the allowlist does not name, and on an allowlist row that no longer exists, so the list only shrinks")

fn headerEnd chars: (List String) depth: Int64 n: Int64 inStr: Bool esc: Bool -> Int64
  (match (listHead chars)
    ((none) n)
    ((some c)
      (let [(rest (optionOr (listTail chars) (list)))]
        (cond
          (esc (headerEnd rest depth (+ n 1) inStr false))
          ((and inStr (= c "\\")) (headerEnd rest depth (+ n 1) true true))
          ((= c "\"") (headerEnd rest depth (+ n 1) (not inStr) false))
          (inStr (headerEnd rest depth (+ n 1) true false))
          ((= c "(") (headerEnd rest (+ depth 1) (+ n 1) false false))
          ((= c ")") (if (= depth 1) (+ n 1) (headerEnd rest (- depth 1) (+ n 1) false false)))
          (else (headerEnd rest depth (+ n 1) false false))))))

fn headerOf text: String -> String
  (match (stringIndexOf text "(module")
    ((none) "")
    ((some i)
      (let [(tail (optionOr (stringSlice text i (min (stringLength text) (+ i 8000))) ""))]
        (optionOr (stringSlice tail 0 (headerEnd (stringChars tail) 0 0 false false)) ""))))

fn toolsImports header: String -> (List String)
  (map (fn [(p String)] -> String (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit p " ")) "") ")")) ""))
       (listDrop (stringSplit header "(tools/") 1))

fn allowed -> (List String)
  (list
    "asl/packages/asl-agent/src/remoteOps.asl|tools/remote/form"
    "asl/packages/asl-agent/src/remoteOps.asl|tools/remote/transport"
    "asl/packages/asl-agent/src/remoteOps.asl|tools/remote/vps"
    "asl/packages/asl-agent/tests/leonRemoteToolsTest.asl|tools/remote/transport"
    "asl/packages/asl-agent/tests/poolServeFormTest.asl|tools/fleet/freePool"
    "asl/packages/asl-agent/tests/poolServeFormTest.asl|tools/fleet/leonClient"
    "asl/tools/coord/conductor.asl|tools/fleet/freePool"
    "asl/tools/coord/conductor.asl|tools/fleet/leonClient"
    "asl/tools/coord/janitor.asl|tools/remote/form"
    "asl/tools/coord/tests/condRestartTest.asl|tools/remote/coordDeps"
    "asl/tools/coord/tests/condRestartTest.asl|tools/remote/vps"
    "asl/tools/coord/tests/gateGuardTest.asl|tools/fleet/freePool")

fn ! edgesOf! path: String -> (List String)
  (map (fn [(m String)] -> String (str path "|tools/" m))
       (toolsImports (headerOf (resultOr (fileReadString path) ""))))

fn ! runTests -> Bool
  (let [(ls (vg/gitRun! "." (list "ls-files" "asl") 120))
        (files (filter (fn [(f String)] -> Bool (stringEndsWith? f ".asl")) (stringLines ls.out)))
        (edges (fold (fn [(acc (List String)) (f String)] -> (List String) (listAppend acc (edgesOf! f))) (list) files))
        (fresh (filter (fn [(e String)] -> Bool (not (listContains? (allowed) e))) edges))
        (gone (filter (fn [(a String)] -> Bool (not (listContains? edges a))) (allowed)))]
    (do
      (assert (= (toolsImports (headerOf "(module m\n  :i [(asl-x/y :a y) (tools/fleet/model :a fm)\n      (tools/remote/vps :a v)])\nfn f -> Bool\n  (str \"(tools/zzz :a z)\")\n")) (list "fleet/model" "remote/vps")) "header imports of tools/ are found, a string in a body is not")
      (assert (listEmpty? (toolsImports (headerOf "(module m\n  :i [(asl-x/y :a y)])\n"))) "a header with only asl imports has no tools edge")
      (assert (= ls.exit 0) "git ls-files asl runs")
      (assert (> (listLength files) 100) "the scan sees the asl tree")
      (assert (listEmpty? fresh) (str "new asl/ to tools/ import edges (asl/ must not depend on tools/): " (stringJoin fresh ", ")))
      (assert (listEmpty? gone) (str "allowlist rows whose edge no longer exists, delete them: " (stringJoin gone ", ")))
      true))
