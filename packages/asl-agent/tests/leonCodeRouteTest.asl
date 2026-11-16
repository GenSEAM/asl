(module aslAgent/tests/leonCodeRouteTest
  :x [runTests]
  :i [(aslAgent/main :a m) (aslAgent/tests/gitInitKit :a kit) (aslHarness/tests/agentLoopRecorderKit :a rk) (asl-tools/fleet/run :a fr)])

; (:m :ref CODE-WIRE-20261028 :do "a code-intent scripted run whose gateway config declares a codeRoute: the gate fails on the first two writer answers and passes on the third, so one turn makes three writer calls (journal :codeRoute trail); the route checks run in a scratch copy, so the real tree holds the write only once the turn applies the final answer (the gate logs whether the real w.txt exists); three failed writer answers escalate and the escalation alias passes; the same run without a declared route takes the plain path, three turns of one call each and no :codeRoute line")

fn ! freshRoot! tag: String -> String
  (let [base (optionOr (envGet "TMPDIR") "/tmp")
        path (str base "/leonCodeRouteTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (nowNs)) "_" tag)
        made (dirCreate path)]
    (resultOr (realPath path) path))

; (:m :ref NODE-BASE-RED :do "a route check runs its gate jailed to the scratch copy, which can neither see nor write the real root (bwrap binds back only the scratch under a private /tmp, seatbelt denies writes outside it), so the scratch gate only marks its scratch and naps a second; what the real tree held during each check, and the scratch's kind, is read from outside the jail by routeWatch!. The gate on the real tree still logs there itself")
fn gateScript root: String -> String
  (str "if [ \"$(pwd -P)\" = '" root "' ]\nthen\nif [ -f " root "/w.txt ]\nthen\necho present >> " root "/log\nelse\necho absent >> " root "/log\nfi\nelse\ntouch .routeGate\nsleep 1\nfi\n" "if grep -q good w.txt\nthen\necho '(:gate :asserts 1 :failed 0)'\nelse\necho \"BOOM:$(cat w.txt)\"\necho '(:gate :asserts 1 :failed 1)'\nexit 1\nfi\n")

; (:m :ref NODE-BASE-RED :do "outside the jail: each leonRoute_<pid>_ scratch whose gate has marked it is logged once, with whether the real root held w.txt at that moment and whether the scratch is a git worktree (.git is a file) or a copy")
fn ! routeWatch! root: String prefix: String out: String stop: String seen: (List String) deadlineNs: Int64 -> Int64
  (if (or (fileExists? stop) (>= (monotonicNs) deadlineNs))
    0
    (let [base (optionOr (envGet "TMPDIR") "/tmp")
          fresh (filter (fn [n] (and (stringStartsWith? n prefix) (and (not (listContains? seen n)) (fileExists? (str base "/" n "/.routeGate"))))) (resultOr (dirList base) (list)))
          logged (map (fn [n] (fileAppend out (str (if (fileExists? (str root "/w.txt")) "present" "absent") " " (if (match (fileStat (str base "/" n "/.git")) ((ok st) st.isFile) ((err _) false)) "worktree" "copy") "\n"))) fresh)
          napped (sleepMs 20)]
      (routeWatch! root prefix out stop (listAppend seen fresh) deadlineNs)))

fn ! watchColumn! out: String col: Int64 -> String
  (stringJoin (map (fn [l] (str (optionOr (listGet (stringSplit l " ") col) "") "\n")) (filter (fn [l] (not (stringEmpty? l))) (stringLines (resultOr (fileReadString out) "")))) "")

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
        out (str root ".routeWatch")
        stop (str root ".routeStop")
        prefix (str "leonRoute_" (stringFromInt64 (procSelf)) "_")
        watcher (fr/forkLimited! (str root ".watch.log") (fr/limits 600 4) (fn [] -> Int64 (routeWatch! root prefix out stop (list) (+ (monotonicNs) 590000000000))))
        exit (m/main (list form))
        _stop (fileWrite stop "")
        _end (match watcher ((ok f) (fr/forkKill! f "done")) ((err _) (fr/ForkEnd :exit -1 :verdict "" :desc 0 :note "")))
        journal (journalOf! root)
        log (str (watchColumn! out 0) (resultOr (fileReadString (str root "/log")) ""))
        kind (watchColumn! out 1)
        trees (if useGit (resultOr (fr/shellOut (str "git -C '" root "' worktree list") 30000) "") "")
        _gone (map pathRemove (list root out stop (str root ".watch.log")))]
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
