(module asl-forms/tests/noAgentImportTest
  :x [runTests]
  :i [])

; (:m :ref FORMS-AGENT-CYCLE-GATE :do "asl-forms is below the agent: no asl-forms src module imports an agent package and its manifest lists none as a dependency; ULOWS removed a bus cycle (fb55bc7ea, the import was (aslAgent/bus :a bus)) and nothing pinned it. Module and package names are camel (aslAgent, aslAgentBus, aslAgentCore) and some manifest dependencies are kebab (asl-agent-core): both prefixes are flagged. The scan reads each src file's whole module form, balanced to its closing paren whatever blank lines or comments sit inside, never the code after it; a scratch fixture with a planted import proves the scan sees it")
fn agentName? name: String -> Bool
  (or (stringStartsWith? name "aslAgent") (stringStartsWith? name "asl-agent"))

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

; (:m :ref FORMS-CYCLE-GATE-LOWS :do "inside a string a backslash skips the next character, so an escaped quote does not close it and a paren after it cannot end the header early")
fn formEnd s: String i: Int64 depth: Int64 inStr: Bool -> Int64
  (if (>= i (stringLength s)) i
    (let [(c (charAt s i))]
      (cond
        ((and inStr (= c "\\")) (formEnd s (+ i 2) depth true))
        (inStr (formEnd s (+ i 1) depth (not (= c "\""))))
        ((= c "\"") (formEnd s (+ i 1) depth true))
        ((= c "(") (formEnd s (+ i 1) (+ depth 1) false))
        ((= c ")") (if (= depth 1) (+ i 1) (formEnd s (+ i 1) (- depth 1) false)))
        (else (formEnd s (+ i 1) depth false)))))

fn headerOf text: String -> String
  (match (stringIndexOf text "(module")
    ((none) "")
    ((some at) (optionOr (stringSlice text at (formEnd text at 0 false)) "")))

fn blank? c: String -> Bool
  (or (= c " ") (or (= c "\n") (or (= c "\t") (= c "\r"))))

fn skipBlank s: String i: Int64 -> Int64
  (if (and (< i (stringLength s)) (blank? (charAt s i))) (skipBlank s (+ i 1)) i)

; (:m :ref FORMS-CYCLE-GATE-LOWS :do "the text after the header's :i key: ':i' standing after whitespace, then any whitespace run (space, newline or tab, or none: ':i[' is a header check accepts, FORMS-CYCLE-GATE-LOWS2), then '['; ':in', ':index' or ':impl' do not match; empty when the header has no :i list")
fn importsAt header: String i: Int64 -> String
  (if (>= i (stringLength header)) ""
    (if (and (= (optionOr (stringSlice header i (+ i 2)) "") ":i") (and (> i 0) (and (blank? (charAt header (- i 1))) (or (blank? (charAt header (+ i 2))) (= (charAt header (+ i 2)) "[")))))
      (let [(j (skipBlank header (+ i 2)))]
        (if (= (charAt header j) "[") (optionOr (stringSlice header (+ j 1) (stringLength header)) "") (importsAt header (+ i 1))))
      (importsAt header (+ i 1))))

fn importsPart header: String -> String
  (importsAt header 0)

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
        (nl (fileWrite (str dir "/nl.asl") "(module asl-forms/nl\n  :x [f]\n  :i\n    [(aslAgent/bus :a bus)])\n\nfn f -> Int64\n  1\n"))
        (tab (fileWrite (str dir "/tab.asl") "(module asl-forms/tab :x [f] :i\t[(aslAgent/bus :a bus)])\n\nfn f -> Int64\n  1\n"))
        (tight (fileWrite (str dir "/tight.asl") "(module asl-forms/tight :x [f] :i[(aslAgent/bus :a bus)])\n\nfn f -> Int64\n  1\n"))
        (esc (fileWrite (str dir "/esc.asl") "(module asl-forms/esc\n  :doc \"say \\\") hi\"\n  :i [(aslAgent/bus :a bus)])\n\nfn f -> Int64\n  1\n"))
        (words (fileWrite (str dir "/words.asl") "(module asl-forms/words :x [f] :index [(aslAgent/bus :a bus)] :impl [(aslAgent/bus :a bus)] :index[(aslAgent/bus :a bus)] :impl[(aslAgent/bus :a bus)])\n\nfn f -> Int64\n  1\n"))
        (found (offenders dir))
        (_ (pathRemove dir))]
    (if (and (ok? made) (and (ok? camel) (and (ok? kebab) (and (ok? clean) (and (ok? nl) (and (ok? tab) (and (ok? tight) (and (ok? esc) (ok? words))))))))) found (list "fixture not written")))

fn ! runTests -> Bool
  (let [(real (offenders "asl/packages/asl-forms/src"))
        (planted (plantFixture))]
    (do (assert (not (listContains? real "unreadable")) "asl-forms/src is readable")
        (assert (listEmpty? real) (str "asl-forms src imports an agent package: " (stringJoin real "; ")))
        (assert (listEmpty? (manifestAgentDeps)) (str "asl-forms manifest depends on an agent package: " (stringJoin (manifestAgentDeps) " ")))
        (assert (= planted (list "camel.asl imports aslAgent/bus" "esc.asl imports aslAgent/bus" "kebab.asl imports asl-agent-core/core" "nl.asl imports aslAgent/bus" "tab.asl imports aslAgent/bus" "tight.asl imports aslAgent/bus")) (str "planted camel and kebab imports are found, the newline, tab and escaped-quote headers are found too, the comment after the header, aslGateway and :index or :impl keys are not: " (stringJoin planted "; ")))
        (assert (= (agentImportsIn "(module m :i [(aslAgent/x :a x) (aslAgentCore/y :a y) (aslAgentBus/z :a z)])") (list "aslAgent/x" "aslAgentCore/y" "aslAgentBus/z")) "aslAgent, aslAgentCore and aslAgentBus are all flagged")
        (assert (= (headerOf "(module m :x [a] :i [])\n\n(fn)") "(module m :x [a] :i [])") "the header ends at the module form's closing paren")
        true))
