(module asl-forms/tests/noAgentImportTest
  :x [runTests]
  :i [])

; (:m :ref FORMS-AGENT-CYCLE-GATE :do "asl-forms is below the agent: no asl-forms src module imports an asl-agent package (asl-agent, asl-agent-core, asl-agent-bus) and its manifest lists none as a dependency; ULOWS removed such a bus cycle (fb55bc7ea) and nothing pinned it. The scan reads each src file's module header (up to the first blank line) and flags any import whose package name starts with asl-agent; a scratch fixture with a planted import proves the scan sees it")
fn headerOf text: String -> String
  (match (stringIndexOf text "(module")
    ((none) "")
    ((some at)
      (let [(rest (optionOr (stringSlice text at (stringLength text)) ""))]
        (match (stringIndexOf rest "\n\n")
          ((some end) (optionOr (stringSlice rest 0 end) rest))
          ((none) rest)))))

fn agentImportsIn text: String -> (List String)
  (filter (fn [(piece String)] -> Bool (stringStartsWith? piece "asl-agent"))
          (map (fn [(chunk String)] -> String (optionOr (listHead (stringSplit chunk " ")) ""))
               (optionOr (listTail (stringSplit (headerOf text) "(")) (list))))

fn ! offenders dir: String -> (List String)
  (match (dirList dir)
    ((err _) (list "unreadable"))
    ((ok names)
      (listFlatMap (fn [(n String)] -> (List String)
                     (if (stringEndsWith? n ".asl")
                       (map (fn [(i String)] -> String (str n " imports " i)) (agentImportsIn (resultOr (fileReadString (str dir "/" n)) "")))
                       (list)))
                   (listSort names))))

fn ! manifestAgentDeps -> (List String)
  (let [(text (resultOr (fileReadString "asl/packages/asl-forms/manifest.asn") ""))
        (deps (optionOr (listGet (stringSplit text ":dependencies [") 1) ""))
        (inside (optionOr (listHead (stringSplit deps "]")) ""))]
    (filter (fn [(d String)] -> Bool (stringContains? d "asl-agent")) (stringSplit inside " ")))

fn ! plantFixture -> (List String)
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/noAgentImportTest-" (stringFromInt64 (procSelf))))
        (made (dirCreate dir))
        (wrote (fileWrite (str dir "/planted.asl") "(module asl-forms/planted\n  :x [f]\n  :i [(asl-agent-bus/bus :a b) (asl-forms/kernel :a k)])\n\nfn f -> Int64\n  1\n"))
        (clean (fileWrite (str dir "/clean.asl") "(module asl-forms/clean\n  :x [g]\n  :i [(asl-forms/kernel :a k)])\n\n; (asl-agent mentioned in a comment after the header)\nfn g -> Int64\n  2\n"))
        (found (offenders dir))
        (_ (pathRemove dir))]
    (if (and (ok? made) (and (ok? wrote) (ok? clean))) found (list "fixture not written")))

fn ! runTests -> Bool
  (let [(real (offenders "asl/packages/asl-forms/src"))
        (planted (plantFixture))]
    (do (assert (not (listContains? real "unreadable")) "asl-forms/src is readable")
        (assert (listEmpty? real) (str "asl-forms src imports an asl-agent package: " (stringJoin real "; ")))
        (assert (listEmpty? (manifestAgentDeps)) (str "asl-forms manifest depends on an asl-agent package: " (stringJoin (manifestAgentDeps) " ")))
        (assert (= planted (list "planted.asl imports asl-agent-bus/bus")) (str "a planted import is found and a comment after the header is not: " (stringJoin planted "; ")))
        (assert (= (agentImportsIn "(module m :i [(asl-agent/x :a x) (asl-agent-core/y :a y)])") (list "asl-agent/x" "asl-agent-core/y")) "every asl-agent* package name is flagged")
        true))
