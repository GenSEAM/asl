(module aslAgent/tests/leonServeTest
  :x [runTests]
  :i [(aslAgent/leonServe :a ls) (aslAgent/leonPool :a lp) (aslAgent/poolServe :a ps)
      (aslAgent/sessionPool :a sp) (asl-tools/fleet/run :a fr) (aslHarness/tests/agentLoopRecorderKit :a rk)])

; (:m :ref SE5B-LEON-SERVE :do "two scripted Leon runs submitted over the control socket as (:run ...) are declined with exit 125 because a script provider is not the hub ask path (the accepted hub case is leonPoolE2ETest); a run the check chain rejects is queued and has its receipt (exit 2) at once; the same unit id twice is refused; (:status) answers; (:stop) ends the loop. Client and server share this thread, as in poolServeTest")
fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! sh! cmd: String -> Bool
  (ok? (fr/shellOut cmd 20000))

fn ! prepRoot! root: String fixtureText: String -> Bool
  (and (sh! (str "/bin/mkdir -p " root "/tests/fixtures/agentLoop/mvp"))
    (and (ok? (fileWrite (str root "/.asl.config.asn") "(:aslConfig :agentLoop (:specCheck false))\n"))
      (and (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/edit.asn") fixtureText))
        (and (ok? (fileWrite (str root "/subject.txt") "before\n"))
          (sh! (str "cd " root " && git init -q -b main && git config user.name leonServe && git config user.email leon-serve@example.invalid && git add -- subject.txt && git commit -q -m initial"))))))

fn routedGateway -> String
  "(:gateway :v 2 :providers ((:provider :id fp :kind openai :base \"http://127.0.0.1:1\" :keyEnv FP_KEY)) :models ((:model :id wr :provider fp :name \"n1\" :temperature 0.8) (:model :id esc :provider fp :name \"n2\" :temperature 0.2)) :profiles ((:profile :id default :routes ((:intent any :chain (wr))))) :uses ((:use :for default :profile default)) :codeRoutes ((:codeRoute :id code :writer wr :escalate esc)))\n"

fn writeReply content: String -> String
  (str "(:step :op \"write\" :file \"w.txt\" :content \"" content "\")")

fn ! prepRouted! root: String -> Bool
  (and (sh! (str "/bin/mkdir -p " root "/tests/fixtures/agentLoop/mvp"))
    (and (ok? (fileWrite (str root "/.asl.config.asn") (str "(:aslConfig :agentLoop (:specCheck false :baseline false :gatewayConfig \"" root "/gw.asn\"))\n")))
      (and (ok? (fileWrite (str root "/gw.asn") (routedGateway)))
        (and (ok? (fileWrite (str root "/gate.sh") "grep -q good w.txt\n"))
          (and (ok? (fileWrite (str root "/tests/fixtures/agentLoop/mvp/routed.asn") (rk/scriptFixtureTextFromReplies! "routed" (list (writeReply "good")))))
            (and (ok? (fileWrite (str root "/subject.txt") "s\n"))
              (sh! (str "cd " root " && git init -q -b main && git config user.name leonServe && git config user.email leon-serve@example.invalid && git add -A && git commit -q -m initial"))))))))

fn routedForm -> String
  "(:agent :task \"write w.txt\" :backend \"script/routed\" :mode \"implement\" :intent \"code\" :owns (\"w.txt\") :gates (\"sh gate.sh\") :budget 20 :contextTokens 8000 :gateTimeout 30)"

fn editForm -> String
  "(:agent :task \"write then gate\" :backend \"script/edit\" :mode \"implement\" :owns (\"subject.txt\") :gates (\"grep -qx green subject.txt\"))"

fn badForm -> String
  "(:agent :task \"t\" :backend \"script/edit\" :contextTokens 100)"

fn runLine id: String form: String repo: String root: String -> String
  (str "(:run :unit " (ps/asnQuote id) " :form " (ps/asnQuote form) " :repo " (ps/asnQuote repo) " :root " (ps/asnQuote root) ")")

fn ! pump! s: ps/Serve book: (List (Pair String lp/Live)) until: (fn [ps/Serve] -> Bool) deadline: Int64 -> (Pair ps/Serve (List (Pair String lp/Live)))
  (if (or (until s) (>= (nowMs!) deadline)) (pair s book)
    (match (fdPoll (ps/serveWatch s) 10)
      ((err _) (pump! s book until deadline))
      ((ok ready)
        (let [(stepped (ps/serveStepG! s ready lp/leonTurn! book ls/openRun! lp/leonExit (nowMs!)))]
          (pump! (pairFirst stepped) (pairSecond stepped) until deadline)))))

fn ! readLine! fd: Int64 acc: String attempts: Int64 -> String
  (if (or (<= attempts 0) (stringContains? acc "\n")) acc
    (match (fdPoll (list (pair fd 1)) 20)
      ((err _) acc)
      ((ok r) (if (listEmpty? r) (readLine! fd acc (- attempts 1))
                (match (fdRead fd 65536)
                  ((ok chunk) (if (stringEmpty? chunk) acc (readLine! fd (str acc chunk) (- attempts 1))))
                  ((err _) acc))))))

fn ! ask! s: ps/Serve book: (List (Pair String lp/Live)) sock: String line: String -> (Pair (Pair ps/Serve (List (Pair String lp/Live))) String)
  (match (unixConnect sock)
    ((err e) (pair (pair s book) (str "CONNECTFAILED " e)))
    ((ok fd)
      (let [(sent (fdWrite fd (str line "\n")))
            (out (pump! s book (fn [(x ps/Serve)] -> Bool false) (+ (nowMs!) 150)))
            (text (readLine! fd "" 150))
            (closed (fdClose fd))]
        (pair out (stringTrim text)))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/leonServeTest.XXXXXX" 5000) "")))
        (repo (resultOr (realPath ".") "."))
        (editText (resultOr (fileReadString "asl/packages/asl-agent/tests/fixtures/liveLoop/edit.asn") ""))
        (rootA (str temp "/eA"))
        (rootB (str temp "/eB"))
        (rootC (str temp "/rC"))
        (prepared (and (prepRoot! rootA editText) (and (prepRoot! rootB editText) (prepRouted! rootC))))
        (ctl (str temp "/ctl.sock"))
        (rdir (str temp "/receipts"))
        (made (and (ok? (dirCreate rdir)) (ok? (dirCreate (str temp "/spill")))))
        (listener (resultOr (unixListen ctl) -1))
        (s0 (ps/newServe listener (sp/newPool (str temp "/none.sock") 4 16 60000 (str temp "/spill")) rdir))
        (r1 (ask! s0 (list) ctl (runLine "e1" (editForm) repo rootA)))
        (r2 (ask! (pairFirst (pairFirst r1)) (pairSecond (pairFirst r1)) ctl (runLine "e2" (editForm) repo rootB)))
        (r3 (ask! (pairFirst (pairFirst r2)) (pairSecond (pairFirst r2)) ctl (runLine "e1" (editForm) repo rootA)))
        (r4 (ask! (pairFirst (pairFirst r3)) (pairSecond (pairFirst r3)) ctl (runLine "bad" (badForm) repo rootA)))
        (r4b (ask! (pairFirst (pairFirst r4)) (pairSecond (pairFirst r4)) ctl (runLine "rt" (routedForm) repo rootC)))
        (r5 (ask! (pairFirst (pairFirst r4b)) (pairSecond (pairFirst r4b)) ctl "(:status)"))
        (w (pump! (pairFirst (pairFirst r5)) (pairSecond (pairFirst r5))
             (fn [(x ps/Serve)] -> Bool (and (fileExists? (ps/receiptPath rdir "e1")) (fileExists? (ps/receiptPath rdir "e2")))) (+ (nowMs!) 120000)))
        (r6 (ask! (pairFirst w) (pairSecond w) ctl "(:stop)"))
        (recE1 (resultOr (fileReadString (ps/receiptPath rdir "e1")) ""))
        (recE2 (resultOr (fileReadString (ps/receiptPath rdir "e2")) ""))
        (recRt (resultOr (fileReadString (ps/receiptPath rdir "rt")) ""))
        (recBad (resultOr (fileReadString (ps/receiptPath rdir "bad")) ""))
        (closed (do (fdClose listener) true))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert prepared "fixture roots prepared")
      (assert (and (stringContains? (pairSecond r1) "(:queued :unit \"e1\")") (stringContains? (pairSecond r2) "(:queued :unit \"e2\")")) (str "both runs queued: " (pairSecond r1) " / " (pairSecond r2)))
      (assert (stringContains? (pairSecond r3) ":why \"duplicate\"") (str "the same unit id is refused: " (pairSecond r3)))
      (assert (and (stringContains? recBad ":exit 2") (stringContains? recBad "ERR_INVALID_ARG")) (str "a rejected run has its receipt at once: " recBad))
      (assert (and (stringContains? recRt ":exit 125") (stringContains? recRt ":declined")) (str "a routed run is declined with exit 125: " recRt))
      (assert (stringContains? (pairSecond r5) ":slots 4") (str "status answers: " (pairSecond r5)))
      (assert (and (stringContains? recE1 ":exit 125") (stringContains? recE2 ":exit 125") (stringContains? recE1 ":declined")) (str "script-provider runs are declined with exit 125 (a hub run is accepted in leonPoolE2ETest):\n" recE1 "\n" recE2))
      (assert (stringContains? (pairSecond r6) "(:stopping)") (str "stop answers: " (pairSecond r6)))
      (assert removed "temp dir removed")
      true))
