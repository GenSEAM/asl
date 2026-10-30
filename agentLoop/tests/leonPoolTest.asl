(module asl/agentLoop/tests/leonPoolTest
  :x [runTests]
  :i [(asl/agentLoop/main :a m) (asl/agentLoop/leonPool :a lp) (asl/agentLoop/sessionPool :a sp)
      (asl/agentLoop/providers :a pv) (asl-tools/fleet/run :a fr) (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref SE3F-POOL-PARITY :do "the same scripted case goes once through the blocking path (mainWithRoots) and once through the pool driver in one process and their journals are byte-identical once the session id, the root path and the per-write receipt ids are masked: a write then gate run (edit), a transient provider error that is retried (retry, journal has the (:retry ...) row), a parent that is gone (parentGone), a code-routed turn with three writer calls (routed, journal has the (:codeRoute ...) row); a check-chain rejection gives the same receipt text and exit; 8 runs share one pool and all end ok")
(schema Out
  (:f exit Int64)
  (:f stdout String)
  (:f journal String))

fn ! sh! cmd: String -> Bool
  (ok? (fr/shellOut cmd 20000))

fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn fieldAfter text: String key: String -> String
  (match (stringIndexOf text key)
    ((none) "")
    ((some at)
      (let [(rest (optionOr (stringSlice text (+ at (stringLength key)) (stringLength text)) ""))]
        (match (stringIndexOf rest "\"") ((some e) (optionOr (stringSlice rest 0 e) "")) ((none) "")))))

; (:m :ref SE3-POOL-DRIVER :do "a receipt id is a fresh hash per write, so it is masked; every other byte of the journal is compared")
fn quoteChar? c: String -> Bool
  (or (= c "\\") (= c "\""))

fn skipQuotes text: String at: Int64 -> Int64
  (if (quoteChar? (optionOr (stringSlice text at (+ at 1)) "")) (skipQuotes text (+ at 1)) at)

fn maskIds text: String -> String
  (match (stringIndexOf text ":receipt :id ")
    ((none) text)
    ((some at)
      (let [(from (skipQuotes text (+ at 13)))]
        (str (optionOr (stringSlice text 0 from) "") "IDMASKED" (maskIds (optionOr (stringSlice text (+ from 16) (stringLength text)) ""))))))

fn journalOf root: String sid: String -> String
  (maskIds (stringReplace (stringReplace (resultOr (fileReadString (str root "/.asl/run/agentLoop/" sid ".journal")) "") sid "SID") root "ROOT"))

fn onlyIn a: String b: String -> (List String)
  (let [(other (stringSplit b "\n"))]
    (filter (fn [(l String)] -> Bool (not (listContains? other l))) (stringSplit a "\n")))

fn sidOfPath path: String -> String
  (stringReplace (optionOr (listLast (stringSplit path "/")) "") ".journal" "")

fn ! prepBase! root: String fixture: String fixtureText: String extra: (List (Pair String String)) addAll: Bool -> Bool
  (and (sh! (str "/bin/mkdir -p " root "/tests/fixtures/agentLoop/mvp"))
    (and (ok? (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n"))
      (and (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/" fixture ".asn") fixtureText))
        (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
          (and (listAll? (fn [(e (Pair String String))] -> Bool (ok? (fileWrite (str root "/" (pairFirst e)) (pairSecond e)))) extra)
            (sh! (str "cd " root " && git init -q -b main && git config user.name leonPool && git config user.email leon-pool@example.invalid && git add " (if addAll "-A" "-- subject.txt") " && git commit -q -m initial")))))))

fn ! blocked! repoRoot: String root: String form: String -> Out
  (let [(r (m/mainWithRoots (list form) repoRoot root))
        (sid (fieldAfter r.stdout ":session \""))]
    (Out :exit r.exitCode :stdout r.stdout :journal (if (stringEmpty? sid) "" (journalOf root sid))))

fn ! pump! p: sp/Pool book: (List (Pair String lp/Live)) deadline: Int64 -> (Pair sp/Pool (List (Pair String lp/Live)))
  (if (or (sp/poolIdle? p) (>= (nowMs!) deadline)) (pair p book)
    (match (fdPoll (sp/poolWatch p) 10)
      ((err _) (pump! p book deadline))
      ((ok ready)
        (let [(stepped (sp/poolStepG! p ready lp/leonTurn! book (nowMs!)))]
          (pump! (pairFirst stepped) (pairSecond stepped) deadline)))))

fn ! pooled! temp: String repoRoot: String root: String form: String -> Out
  (let [(id (stringReplace root "/" "_"))
        (opened (lp/leonOpen! (list) id form repoRoot root (pv/providerEnv! root)))]
    (match (pairSecond opened)
      ((some r) (Out :exit r.exitCode :stdout r.stdout :journal ""))
      ((none)
        (let [(pool (sp/poolSubmit! (sp/newPool (str temp "/none.sock") 4 16 60000 (str temp "/spill")) id id (nowMs!)))
              (out (pump! pool (pairFirst opened) (+ (nowMs!) 120000)))
              (live (listFind (fn [(e (Pair String lp/Live))] -> Bool (= (pairFirst e) id)) (pairSecond out)))]
          (match live
            ((some e) (Out :exit (pairSecond e).exit :stdout "" :journal (journalOf root (sidOfPath (pairSecond e).sess.path))))
            ((none) (Out :exit -1 :stdout "" :journal "")))))))

fn diffMsg tag: String a: Out b: Out -> String
  (str tag ": journals differ, blocking " (stringFromInt64 (stringLength a.journal)) " chars, pool " (stringFromInt64 (stringLength b.journal)) " chars\n--- only blocking\n" (stringJoin (onlyIn a.journal b.journal) "\n") "\n--- only pool\n" (stringJoin (onlyIn b.journal a.journal) "\n"))

fn editForm -> String
  "(:agent :task \"write then gate\" :backend \"script/edit\" :mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\"))"

fn retryForm -> String
  "(:agent :task \"retry then done\" :backend \"script/retry\" :mode \"implement\" :budget 2)"

fn goneForm -> String
  "(:agent :task \"write then gate\" :backend \"script/edit\" :mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\") :parentPid 2147483000)"

fn badForm -> String
  "(:agent :task \"t\" :backend \"script/edit\" :contextTokens 100)"

fn routedForm -> String
  "(:agent :task \"write w.txt\" :backend \"script/routed\" :mode \"implement\" :intent \"code\" :owns (\"w.txt\") :gates (\"sh gate.sh\") :budget 20 :contextTokens 8000 :gateTimeout 30)"

fn retryFixture -> String
  "(:script :id \"leonPoolRetry\" :mode :implement\n  :turns (\n    (:turn :num 1 :error \"ERR_VENDOR\")\n    (:turn :num 2 :reply \"(:done)\")\n  )\n)\n"

fn routedGate root: String -> String
  (str "if grep -q good w.txt\nthen\necho '(:gate :asserts 1 :failed 0)'\nelse\necho \"BOOM:$(cat w.txt)\"\necho '(:gate :asserts 1 :failed 1)'\nexit 1\nfi\n")

fn routedGateway -> String
  "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id wr :provider fp :name \"n1\" :temperature 0.8) (:model :id esc :provider fp :name \"n2\" :temperature 0.2)) :profiles ((:profile :id default :routes ((:intent any :chain (wr))))) :uses ((:use :for default :profile default)) :codeRoutes ((:codeRoute :id code :writer wr :escalate esc)))\n"

fn writeReply content: String -> String
  (str "(:step :op \"write\" :file \"w.txt\" :content \"" content "\")")

fn ! prepRouted! root: String -> Bool
  (prepBase! root "routed" (rk/scriptFixtureTextFromReplies! "routed" (list (writeReply "bad1") (writeReply "bad2") (writeReply "good")))
    (list (pair "gate.sh" (routedGate root)) (pair "gw.asn" (routedGateway)) (pair ".asl.config.asn" (str "(:aslConfig :agentLoop (:specCheck false :baseline false :gatewayConfig \"" root "/gw.asn\"))\n"))) true)

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/leonPoolTest.XXXXXX" 5000) "")))
        (repoRoot (resultOr (realPath ".") "."))
        (editText (resultOr (fileReadString "asl/agentLoop/tests/fixtures/liveLoop/edit.asn") ""))
        (made (dirCreate (str temp "/spill")))
        (editPrep (and (prepBase! (str temp "/editA") "edit" editText (list) false) (prepBase! (str temp "/editB") "edit" editText (list) false)))
        (editA (blocked! repoRoot (str temp "/editA") (editForm)))
        (editB (pooled! temp repoRoot (str temp "/editB") (editForm)))
        (retryPrep (and (prepBase! (str temp "/retryA") "retry" (retryFixture) (list) false) (prepBase! (str temp "/retryB") "retry" (retryFixture) (list) false)))
        (retryA (blocked! repoRoot (str temp "/retryA") (retryForm)))
        (retryB (pooled! temp repoRoot (str temp "/retryB") (retryForm)))
        (gonePrep (and (prepBase! (str temp "/goneA") "edit" editText (list) false) (prepBase! (str temp "/goneB") "edit" editText (list) false)))
        (goneA (blocked! repoRoot (str temp "/goneA") (goneForm)))
        (goneB (pooled! temp repoRoot (str temp "/goneB") (goneForm)))
        (badA (blocked! repoRoot (str temp "/editA") (badForm)))
        (badB (pooled! temp repoRoot (str temp "/editB") (badForm)))
        (routedPrep (and (prepRouted! (str temp "/routedA")) (prepRouted! (str temp "/routedB"))))
        (routedA (blocked! repoRoot (str temp "/routedA") (routedForm)))
        (routedB (pooled! temp repoRoot (str temp "/routedB") (routedForm)))
        (manyRoots (map (fn [(i Int64)] -> String (str temp "/many" (stringFromInt64 i))) (range 0 8)))
        (manyPrep (listAll? (fn [(r String)] -> Bool (prepBase! r "edit" editText (list) false)) manyRoots))
        (manyPool (fold (fn [(acc (Pair sp/Pool (List (Pair String lp/Live)))) (root String)] -> (Pair sp/Pool (List (Pair String lp/Live)))
                          (let [(id (stringReplace root "/" "_"))
                                (opened (lp/leonOpen! (pairSecond acc) id (editForm) repoRoot root (pv/providerEnv! root)))]
                            (match (pairSecond opened)
                              ((some _) (pair (pairFirst acc) (pairFirst opened)))
                              ((none) (pair (sp/poolSubmit! (pairFirst acc) id id (nowMs!)) (pairFirst opened))))))
                    (pair (sp/newPool (str temp "/none.sock") 8 64 60000 (str temp "/spill")) (list)) manyRoots))
        (manyOut (pump! (pairFirst manyPool) (pairSecond manyPool) (+ (nowMs!) 300000)))
        (manyExits (map (fn [(r String)] -> Int64 (lp/leonExit (pairSecond manyOut) (stringReplace r "/" "_"))) manyRoots))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (and editPrep retryPrep gonePrep routedPrep manyPrep) "fixture roots prepared")
      (assert (and (= editA.exit 0) (= editA.exit editB.exit) (not (stringEmpty? editA.journal))) (str "edit: both end ok " (stringFromInt64 editA.exit) " " (stringFromInt64 editB.exit)))
      (assert (= editA.journal editB.journal) (diffMsg "edit" editA editB))
      (assert (and (stringContains? retryA.journal "(:retry :turn 1 :attempt 1)") (= retryA.exit retryB.exit)) (str "retry: the blocking journal carries the retry row, exits " (stringFromInt64 retryA.exit) "/" (stringFromInt64 retryB.exit) "\n" retryA.journal))
      (assert (= retryA.journal retryB.journal) (diffMsg "retry" retryA retryB))
      (assert (and (stringContains? goneA.journal ":parentGone") (= goneA.exit goneB.exit)) (str "parentGone: the blocking journal carries the signal, exits " (stringFromInt64 goneA.exit) "/" (stringFromInt64 goneB.exit)))
      (assert (= goneA.journal goneB.journal) (diffMsg "parentGone" goneA goneB))
      (assert (and (stringContains? badA.stdout "ERR_INVALID_ARG") (= badA.stdout badB.stdout) (= badA.exit badB.exit)) (str "check chain: same rejection\n" badA.stdout "\n--- pool\n" badB.stdout))
      (assert (and (stringContains? routedA.journal "(:codeRoute :turn 1 :passed true") (= routedA.exit routedB.exit)) (str "routed: the blocking journal carries the route row, exits " (stringFromInt64 routedA.exit) "/" (stringFromInt64 routedB.exit) "\n" routedA.journal))
      (assert (= routedA.journal routedB.journal) (diffMsg "routed" routedA routedB))
      (assert (and (= (listLength manyExits) 8) (listAll? (fn [(x Int64)] -> Bool (= x 0)) manyExits)) "8 runs in one pool all ended with exit 0")
      (assert removed "temp dir removed")
      true))
