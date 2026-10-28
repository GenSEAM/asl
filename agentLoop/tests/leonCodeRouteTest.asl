(module asl/agentLoop/tests/leonCodeRouteTest
  :x [runTests]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/tests/gitInitKit :a kit) (aslHarness/tests/agentLoopRecorderKit :a rk) (asl-tools/fleet/run :a fr)])

; (:m :ref CODE-WIRE-20261028 :do "a code-intent scripted run whose gateway config declares a codeRoute: the gate fails on the first two writer answers and passes on the third, so one turn makes three writer calls (journal :codeRoute trail); the route checks run in a scratch copy, so the real tree holds the write only once the turn applies the final answer (the gate logs whether the real w.txt exists); three failed writer answers escalate and the escalation alias passes; the same run without a declared route takes the plain path, three turns of one call each and no :codeRoute line")

fn ! freshRoot! tag: String -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/leonCodeRouteTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)) "_" tag)
        made (dirCreate path)]
    (resultOr (realPath path) path))

fn gateScript root: String -> String
  (str "if [ -f .git ]\nthen\necho worktree >> " root "/kind\nelse\necho copy >> " root "/kind\nfi\n" "if [ -f " root "/w.txt ]\nthen\necho present >> " root "/log\nelse\necho absent >> " root "/log\nfi\nif grep -q good w.txt\nthen\necho '(:gate :asserts 1 :failed 0)'\nelse\necho \"BOOM:$(cat w.txt)\"\necho '(:gate :asserts 1 :failed 1)'\nexit 1\nfi\n")

fn gatewayText -> String
  "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id wr :provider fp :name \"n1\" :temperature 0.8) (:model :id esc :provider fp :name \"n2\" :temperature 0.2)) :profiles ((:profile :id default :routes ((:intent any :chain (wr))))) :uses ((:use :for default :profile default)) :codeRoutes ((:codeRoute :id code :writer wr :escalate esc)))\n"

fn gatewayPlain -> String
  "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id wr :provider fp :name \"n1\" :temperature 0.8)) :profiles ((:profile :id default :routes ((:intent any :chain (wr))))) :uses ((:use :for default :profile default)))\n"

fn writeReply content: String -> String
  (str "(:step :op \"write\" :file \"w.txt\" :content \"" content "\")")

fn ! journalOf! root: String -> String
  (let [dir (str root "/.asl/run/agentLoop")
        name (optionOr (listHead (filter (fn [n] (stringEndsWith? n ".journal")) (resultOr (dirList dir) (list)))) "")]
    (if (stringEmpty? name) "" (resultOr (fileReadString (str dir "/" name)) "")))

fn ! runCase! tag: String gateway: String replies: (List String) useGit: Bool -> (List String)
  (let [root (freshRoot! tag)
        _cfg (fileWrite (str root "/.asl.config.asn") (str "(:aslConfig :agentLoop (:specCheck false :baseline false :gatewayConfig \"" root "/gw.asn\"))\n"))
        _gw (fileWrite (str root "/gw.asn") gateway)
        _gate (fileWrite (str root "/gate.sh") (gateScript root))
        _subject (fileWrite (str root "/subject.txt") "s\n")
        _git (if useGit (kit/initGitRepo! root "leonCodeRouteTest" "code-route@example.invalid") true)
        dir (str root "/tests/fixtures/agentLoop/mvp")
        _dir (dirCreate dir)
        _fix (fileWrite (str dir "/" tag ".asn") (rk/scriptFixtureTextFromReplies! tag replies))
        form (str "(:agent :task \"write w.txt\" :backend \"script/" tag "\" :root \"" root "\" :mode \"implement\" :intent \"code\" :owns (\"w.txt\") :gates (\"sh gate.sh\") :budget 20 :contextTokens 8000 :gateTimeout 30)")
        exit (m/main (list form))
        journal (journalOf! root)
        log (resultOr (fileReadString (str root "/log")) "")
        kind (resultOr (fileReadString (str root "/kind")) "")
        trees (if useGit (resultOr (fr/shellOut (str "git -C '" root "' worktree list") 30000) "") "")
        _gone (pathRemove root)]
    (list journal log kind trees))

fn nth0 xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

fn ! runTests -> Bool
  (let [three (list (writeReply "bad1") (writeReply "bad2") (writeReply "good"))
        rr (runCase! "routed" (gatewayText) three true)
        routed (nth0 rr 0)
        log (nth0 rr 1)
        kind (nth0 rr 2)
        trees (nth0 rr 3)
        copyRun (runCase! "copy" (gatewayText) three false)
        plain (nth0 (runCase! "plain" (gatewayPlain) three true) 0)
        escalated (nth0 (runCase! "esc" (gatewayText) (list (writeReply "bad1") (writeReply "bad2") (writeReply "bad3") (writeReply "good")) true) 0)]
    (do
      (assert (stringContains? routed "(:codeRoute :turn 1 :passed true :stage \"writer\" :calls 3") "a declared route makes three writer calls in the first turn")
      (assert (stringContains? routed ":trail (\"wr:fail\" \"wr:fail\" \"wr:pass\")") "two failed gates then a pass, all on the writer alias")
      (assert (not (stringContains? routed "(:turn 2 ")) "the route's third answer ends the run in one turn")
      (assert (stringContains? routed "(:result :status :ok") "the run ends ok")
      (assert (stringStartsWith? log "absent\nabsent\nabsent\npresent\n") "the three route checks ran in a scratch copy: the real tree held the write only when the turn applied the final answer")
      (assert (stringStartsWith? kind "worktree\nworktree\nworktree\n") (str "in a git root the route checks ran in a git worktree scratch"))
      (assert (= (listLength (filter (fn [l] (not (stringEmpty? l))) (stringLines trees))) 1) "no scratch worktree record is left in the root")
      (assert (stringStartsWith? (nth0 copyRun 2) "copy\ncopy\ncopy\n") "a root that is not a git repo falls back to a cp -a copy")
      (assert (stringContains? (nth0 copyRun 0) ":calls 3") "the copy fallback judges the same three answers")
      (assert (stringContains? escalated ":stage \"escalation\" :calls 4 :trail (\"wr:fail\" \"wr:fail\" \"wr:fail\" \"esc:pass\")") "three failed writer answers go to the escalation alias, which passes")
      (assert (not (stringContains? plain "(:codeRoute")) "no declared route, no route line")
      (assert (stringContains? plain "(:turn 3 :reply") "no declared route: the plain path needs three turns for the same replies")
      true))
