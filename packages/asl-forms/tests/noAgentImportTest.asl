(module asl-forms/tests/noAgentImportTest
  :x [runTests]
  :i [])

; (:m :ref FORMS-AGENT-CYCLE-GATE :do "asl-forms is below the agent: no asl-forms src module imports an agent package and its manifest lists none as a dependency; ULOWS removed a bus cycle (fb55bc7ea, the import was (aslAgent/bus :a bus)) and nothing pinned it. Module and package names are camel (aslAgent, aslAgentBus, aslAgentCore) and some manifest dependencies are kebab (asl-agent-core): both prefixes are flagged. The scan reads each src file's whole module form, balanced to its closing paren whatever blank lines or comments sit inside, never the code after it; a scratch fixture with a planted import proves the scan sees it")
fn agentName? name: String -> Bool
  (or (stringStartsWith? name "aslAgent") (stringStartsWith? name "asl-agent"))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn formEnd s: String i: Int64 depth: Int64 inStr: Bool -> Int64
  (if (>= i (stringLength s)) i
    (let [(c (charAt s i))]
      (cond
        (inStr (formEnd s (+ i 1) depth (not (= c "\""))))
        ((= c "\"") (formEnd s (+ i 1) depth true))
        ((= c "(") (formEnd s (+ i 1) (+ depth 1) false))
        ((= c ")") (if (= depth 1) (+ i 1) (formEnd s (+ i 1) (- depth 1) false)))
        (else (formEnd s (+ i 1) depth false)))))

fn headerOf text: String -> String
  (match (stringIndexOf text "(module")
    ((none) "")
    ((some at) (optionOr (stringSlice text at (formEnd text at 0 false)) "")))

fn importsPart header: String -> String
  (optionOr (listGet (stringSplit header ":i [") 1) "")

fn agentImportsIn text: String -> (List String)
  (filter agentName?
          (map (fn [(chunk String)] -> String (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit chunk ")")) "") " ")) ""))
               (optionOr (listTail (stringSplit (importsPart (headerOf text)) "(")) (list))))

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
    (filter agentName? (map (fn [(d String)] -> String (stringReplace d "\"" "")) (stringSplit inside " "))))

fn ! plantFixture -> (List String)
  (let [(dir (str (optionOr (envGet "TMPDIR") "/tmp") "/noAgentImportTest-" (stringFromInt64 (procSelf))))
        (made (dirCreate dir))
        (camel (fileWrite (str dir "/camel.asl") "(module asl-forms/camel\n  :x [f]\n\n  ; blank line inside the header\n  :i [(asl-forms/kernel :a k)\n      (aslAgent/bus :a bus)])\n\nfn f -> Int64\n  1\n"))
        (kebab (fileWrite (str dir "/kebab.asl") "(module asl-forms/kebab :x [f] :i [(asl-agent-core/core :a c)])\n\nfn f -> Int64\n  1\n"))
        (clean (fileWrite (str dir "/clean.asl") "(module asl-forms/clean\n  :x [g]\n  :i [(asl-forms/kernel :a k) (aslGateway/bus :a b)])\n\n; (aslAgent/bus :a bus) mentioned after the header\nfn g -> Int64\n  2\n"))
        (found (offenders dir))
        (_ (pathRemove dir))]
    (if (and (ok? made) (and (ok? camel) (and (ok? kebab) (ok? clean)))) found (list "fixture not written")))

fn ! runTests -> Bool
  (let [(real (offenders "asl/packages/asl-forms/src"))
        (planted (plantFixture))]
    (do (assert (not (listContains? real "unreadable")) "asl-forms/src is readable")
        (assert (listEmpty? real) (str "asl-forms src imports an agent package: " (stringJoin real "; ")))
        (assert (listEmpty? (manifestAgentDeps)) (str "asl-forms manifest depends on an agent package: " (stringJoin (manifestAgentDeps) " ")))
        (assert (= planted (list "camel.asl imports aslAgent/bus" "kebab.asl imports asl-agent-core/core")) (str "planted camel and kebab imports are found, the comment after the header and aslGateway are not: " (stringJoin planted "; ")))
        (assert (= (agentImportsIn "(module m :i [(aslAgent/x :a x) (aslAgentCore/y :a y) (aslAgentBus/z :a z)])") (list "aslAgent/x" "aslAgentCore/y" "aslAgentBus/z")) "aslAgent, aslAgentCore and aslAgentBus are all flagged")
        (assert (= (headerOf "(module m :x [a] :i [])\n\n(fn)") "(module m :x [a] :i [])") "the header ends at the module form's closing paren")
        true))
