(module aslGateway/tests/linkCorrelationTest
  :x [runTests]
  :i [(server :a srv)
      (asl-tools/fleet/run :a fr)])

; (:m :ref GW-LINK-CORRELATION :do "each in-process link call has its own connection id, so an answer reaches only the call that asked: over the real linkSend! and curl against a stand-in upstream (fixtures/slowUpstream.asl, started through fleet/run, 20 s deadline, 3 answers at most, the first one 3000 ms late) the call tagged alpha passes a 400 ms limit, the call tagged beta that follows gets the answer to beta, the late answer to alpha is dropped and its usage row still carries the tag alpha")

fn configText dir: String base: String -> String
  (str "(:gateway :v 2 :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id stand :kind openai :base \"" base "\" :keyEnv \"STAND_TEST_KEY\"))"
       " :models ((:model :id m1 :provider stand :name \"plain-1\" :timeoutSec 8))"
       " :intents ((:intent :id code))"
       " :profiles ((:profile :id default :routes ((:intent code :chain (m1)))))"
       " :uses ((:use :for default :profile default)))")

fn testEnv -> (Map String String)
  (mapSet (mapEmpty) "STAND_TEST_KEY" "test-key")

fn ! scratchBase -> String
  (let [(t (optionOr (envGet "TMPDIR") "/tmp"))] (if (stringEndsWith? t "/") (optionOr (stringSlice t 0 (- (stringLength t) 1)) t) t))

; (:m :do "removes a scratch tree in process (no rm child)")
fn ! removeTree! p: String -> Bool
  (match (fileLstat p)
    ((err _) true)
    ((ok st)
      (if (and st.isDir (not st.isSymlink))
        (let [(kids (match (dirList p) ((ok names) (filter (fn [(n String)] -> Bool (and (!= n ".") (!= n ".."))) names)) ((err _) (list))))
              (gone (fold (fn [(a Bool) (n String)] -> Bool (and (removeTree! (str p "/" n)) a)) true kids))]
          (and gone (ok? (pathRemove p))))
        (ok? (pathRemove p)))))

fn ! drop! dir: String -> Bool
  (if (stringStartsWith? dir (str (scratchBase) "/gwLinkCorrelation-")) (removeTree! dir) false)

fn ! waitFile! p: String tries: Int64 -> String
  (if (<= tries 0) ""
    (match (fileReadString p)
      ((ok t) (if (stringEmpty? (stringTrim t)) (do (sleepMs 50) (waitFile! p (- tries 1))) (stringTrim t)))
      ((err _) (do (sleepMs 50) (waitFile! p (- tries 1))))))

fn ! ask! l: srv/GatewayLoop task: String timeoutMs: Int64 -> (Pair srv/GatewayLoop String)
  (let [(sent (srv/linkSend! l "POST" "/v1/chat/completions"
                (list (pair "Content-Type" "application/json") (pair "Accept" "application/json") (pair "X-ASL-Intent" "code") (pair "X-ASL-Tag" task))
                (str "{\"messages\":[{\"role\":\"user\",\"content\":\"solve MARK-" task " now\"}],\"max_tokens\":10}") timeoutMs))]
    (pair (pairFirst sent) (match (pairSecond sent) ((ok raw) raw) ((err e) (str "sendError " e)))))

; (:m :do "counts the ledger rows of one tag that carry the stand-in's usage (7 in, 3 out) and outcome ok")
fn rowsWith text: String tag: String -> Int64
  (listLength (filter (fn [(line String)] -> Bool (and (stringContains? line (str ":tag \"" tag "\"")) (and (stringContains? line ":in 7 ") (and (stringContains? line ":out 3 ") (stringContains? line ":outcome \"ok\""))))) (stringSplit text "\n")))

(schema Seen
  (:f alpha String)
  (:f beta String)
  (:f gamma String)
  (:f inFlight Int64)
  (:f conns Int64)
  (:f outbox Int64)
  (:f ledger String))

fn failedSeen why: String -> Seen
  (Seen :alpha why :beta why :gamma why :inFlight 0 :conns -1 :outbox -1 :ledger "")

fn ! testLateReply -> Bool
  (let [(here (resultOr (realPath ".") "."))
        (dir (str (scratchBase) "/gwLinkCorrelation-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate dir))
        (made2 (dirCreate (str dir "/.asl")))
        (portFile (str dir "/port"))
        (g (fr/guardStart! (list (str here "/bin/asl") "run" (str here "/asl/packages/asl-gateway/tests/fixtures/slowUpstream.asl") portFile "3000" "3" "20") here (fr/childEnv (list)) (fr/limits 40 20)))
        (port (match g ((ok _) (waitFile! portFile 600)) ((err _) "")))
        (wroteCfg (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir (str "http://127.0.0.1:" port "/v1")) "\n")))
        (seen (if (stringEmpty? port) (failedSeen "no port")
                (match (srv/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
                  ((err e) (failedSeen (str "linkOpen: " e)))
                  ((ok l)
                    (let [(first (ask! l "alpha" 400))
                          (held (pairFirst first))
                          (second (ask! held "beta" 8000))
                          (third (ask! (pairFirst second) "gamma" 8000))
                          (end (pairFirst third))]
                      (Seen :alpha (pairSecond first) :beta (pairSecond second) :gamma (pairSecond third)
                            :inFlight (listLength held.conns) :conns (listLength end.conns) :outbox (listLength end.outbox)
                            :ledger (resultOr (fileReadString (str dir "/calls.asn")) "")))))))
        (out (match g ((ok gd) (fr/guardLoop gd)) ((err o) o)))
        (stubGone (fr/stubRemove!))
        (stubLeft (fr/stubDirsOwnedBy (procSelf)))
        (dropped (drop! dir))]
    (do (assert (and stubGone (listEmpty? stubLeft)) (str "the stand-in host dir of this run is removed before any assert: " (stringJoin stubLeft " ")))
        (assert (and (ok? g) (not (stringEmpty? port))) (str "the stand-in upstream started and wrote its port: " port))
        (assert (stringContains? seen.alpha "timed out") (str "the call for alpha ends at its 400 ms limit: " seen.alpha))
        (assert (= seen.inFlight 1) (str "the request for alpha is still in flight when its call returns: " (stringFromInt64 seen.inFlight)))
        (assert (not (stringContains? seen.beta "ans:alpha")) (str "the late answer to alpha is never read by the call for beta: " seen.beta))
        (assert (stringContains? seen.beta "ans:beta") (str "the call for beta holds the answer to beta: " seen.beta))
        (assert (and (stringContains? seen.gamma "ans:gamma") (not (stringContains? seen.gamma "ans:alpha"))) (str "a third call holds its own answer too: " seen.gamma))
        (assert (and (= seen.conns 0) (= seen.outbox 0)) (str "the late answer to alpha is dropped, no request or answer stays on the link: conns " (stringFromInt64 seen.conns) " outbox " (stringFromInt64 seen.outbox)))
        (assert (= (rowsWith seen.ledger "alpha") 1) (str "the late answer to alpha is charged once, with its tokens, on a usage row tagged alpha: " seen.ledger))
        (assert (and (= (rowsWith seen.ledger "beta") 1) (= (rowsWith seen.ledger "gamma") 1)) (str "beta and gamma each have their own usage row: " seen.ledger))
        (assert (= out.exitCode 0) (str "the stand-in upstream ended by itself with exit 0: " (stringFromInt64 out.exitCode) " " out.stderr))
        (assert dropped "the scratch home is removed")
        true))

fn ! runTests -> Bool
  (testLateReply)
