(module aslAgent/tests/providersHubTest
  :x [runTests]
  :i [(aslAgent/providers :a pv) (asl-tools/fleet/run :a fr)])

; (:m :ref ORCH-LEON-CLIENT :do "Leon reads the hub transport from HOME/.asl/hub.asn: a :sock gets the chat with X-Asl-Class and X-Asl-Unit, a dead socket is retried at :backoffMs doubling until :downAfterMs and then ERR_GATEWAY_DOWN, :fallback inProcess leaves the hub path when it is down, and with no hub.asn the older HTTP path (ERR_GATEWAY_OFFLINE on a dead URL) is unchanged")
fn envFor temp: String -> pv/ProviderEnv
  (pv/ProviderEnv :gatewayUrl "http://127.0.0.1:1/v1/chat/completions" :inProcess false :profile "" :gatewayConfig (str temp "/.asl/gateway.asn")
    :tmpDir (str temp "/tmp") :childEnv (mapEmpty))

fn cfgFor temp: String -> pv/VendorConfig
  (pv/VendorConfig :vendor "agy" :mode "scout" :rootDir temp :model "" :timeout 20 :queueTimeout 20 :sessionId "s1" :intent "auto" :timeoutSet true
    :env (envFor temp) :link none :turn 0)

fn ! turnOf! temp: String -> pv/Turn
  (pv/nextTurn! (pv/vendorProvider (cfgFor temp)) "sys" "user")

fn codeOf t: pv/Turn -> String
  (match t.reply ((err e) (pv/errorCode e)) ((ok _) "ok"))

fn replyOf t: pv/Turn -> String
  (match t.reply ((ok (some s)) s) ((ok (none)) "") ((err e) (pv/errorMessage e)))

fn ! waitFile! path: String attempts: Int64 -> Bool
  (if (<= attempts 0) false
    (if (fileExists? path) true (do (sleepMs 20) (waitFile! path (- attempts 1)))))

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/providersHubTest.XXXXXX" 5000) "")))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (stub (resultOr (realPath "asl/packages/asl-agent/tests/hubStub.asl") ""))
        (sock (str temp "/hub.sock"))
        (made (dirCreate (str temp "/.asl")))
        (none_ (turnOf! temp))
        (noneCode (codeOf none_))
        (hubA (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sock "\" :class \"lead\")\n")))
        (cacheRow (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))))
        (running (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sock " " temp "/seen.txt 1>" temp "/stub.out 2>" temp "/stub.err"))
                               (resultOr (realPath ".") ".")
                               (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) cacheRow))))
        (pid (match running ((ok r) r.pid) ((err _) 0)))
        (up (and (> pid 0) (waitFile! sock 1500)))
        (viaHub (if up (turnOf! temp) none_))
        (seen (if up (do (waitFile! (str temp "/seen.txt") 250) (resultOr (fileReadString (str temp "/seen.txt")) "")) ""))
        (killed (if (> pid 0) (do (fr/killTree! pid) true) false))
        (pipes (match running ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (deadHub (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" temp "/none.sock\" :backoffMs 20 :downAfterMs 100)\n")))
        (t0 (monotonicNs))
        (down (turnOf! temp))
        (downMs (/ (- (monotonicNs) t0) 1000000))
        (fallbackHub (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" temp "/none.sock\" :backoffMs 20 :downAfterMs 100 :fallback inProcess)\n")))
        (fell (turnOf! temp))
        (busySock (str temp "/busy.sock"))
        (busyHub (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" busySock "\" :backoffMs 20 :downAfterMs 3000)\n")))
        (busyRun (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " busySock " " temp "/busySeen.txt busy 1>" temp "/busy.out 2>" temp "/busy.err"))
                               (resultOr (realPath ".") ".")
                               (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) cacheRow))))
        (busyPid (match busyRun ((ok r) r.pid) ((err _) 0)))
        (busyUp (and (> busyPid 0) (waitFile! busySock 1500)))
        (busyTurn (if busyUp (turnOf! temp) none_))
        (busyKilled (if (> busyPid 0) (do (fr/killTree! busyPid) true) false))
        (busyPipes (match busyRun ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (stubErr (resultOr (fileReadString (str temp "/stub.err")) ""))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (= noneCode "ERR_GATEWAY_OFFLINE") (str "without hub.asn the HTTP gateway path is used and a dead URL is offline: " noneCode))
      (assert up (str "the stand-in hub is listening: " stubErr))
      (assert (= (codeOf viaHub) "ok") (str "a chat through the hub socket returns the hub reply: " (replyOf viaHub)))
      (assert (= (replyOf viaHub) "hello from hub") (str "the hub reply text reaches the caller: " (replyOf viaHub)))
      (assert (stringContains? seen "POST /v1/chat/completions") (str "the call was posted to the hub socket: " seen))
      (assert (stringContains? (stringLower seen) "x-asl-class: lead") (str "X-Asl-Class comes from hub.asn: " seen))
      (assert (stringContains? (stringLower seen) "x-asl-unit: s1") (str "X-Asl-Unit carries the session: " seen))
      (assert (stringContains? (stringLower seen) "x-asl-session: s1") (str "X-ASL-Session is still sent: " seen))
      (assert (= (codeOf down) "ERR_GATEWAY_DOWN") (str "a dead hub socket ends in ERR_GATEWAY_DOWN: " (codeOf down) " " (replyOf down)))
      (assert (>= downMs 60) (str "the dead socket was retried with backoff before giving up, took " (stringFromInt64 downMs) " ms"))
      (assert (not (= (codeOf fell) "ERR_GATEWAY_DOWN")) (str "with :fallback inProcess a down hub leaves the hub path: " (codeOf fell)))
      (assert busyUp "the busy stand-in is listening")
      (assert (= (replyOf busyTurn) "hello from hub") (str "a 503 from the hub is a wait, the retry gets the reply: " (codeOf busyTurn) " " (replyOf busyTurn)))
      (assert (and busyKilled busyPipes) "the busy stand-in is cleaned up")
      (assert (and killed (and pipes removed)) "the stand-in, its pipes and the temp dir are cleaned up")
      true))
