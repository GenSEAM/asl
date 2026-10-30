(module asl/agentLoop/tests/hubRetryTest
  :x [runTests]
  :i [(asl/agentLoop/providers :a pv) (asl-tools/fleet/run :a fr) (asl-json/json :a j)])

; (:m :ref HUB-QUEUE-PACED :do "a hub 429 with Retry-After N is a wait for the caller: the turn sleeps N seconds and reposts, bounded by the queue timeout; a Retry-After beyond that budget is an ordinary error and is not retried")
fn ! waitFile! path: String attempts: Int64 -> Bool
  (if (<= attempts 0) false
    (if (fileExists? path) true (do (sleepMs 20) (waitFile! path (- attempts 1)))))

fn cfgFor temp: String -> pv/VendorConfig
  (pv/VendorConfig :vendor "agy" :mode "scout" :rootDir temp :model "" :timeout 20 :queueTimeout 20 :sessionId "s1" :intent "auto" :timeoutSet true
    :env (pv/ProviderEnv :gatewayUrl "http://127.0.0.1:1/v1/chat/completions" :inProcess false :profile "" :gatewayConfig (str temp "/.asl/gateway.asn") :tmpDir (str temp "/tmp") :childEnv (mapEmpty))
    :link none :turn 0 :tools (list))

fn replyText t: pv/Turn -> String
  (match t.reply ((ok (some s)) s) ((ok (none)) "<none>") ((err e) (str "<err " (pv/errorMessage e) ">")))

fn countOf text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/hubRetryTest.XXXXXX" 5000) "")))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (here (resultOr (realPath ".") "."))
        (stub (resultOr (realPath "asl/agentLoop/tests/hubRetryStub.asl") ""))
        (sockA (str temp "/a.sock"))
        (sockB (str temp "/b.sock"))
        (made (ok? (dirCreate (str temp "/.asl"))))
        (cacheRow (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) cacheRow))
        (runA (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sockA " " temp "/seenA.txt retry 1>" temp "/a.out 2>" temp "/a.err")) here env)))
        (runB (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sockB " " temp "/seenB.txt long 1>" temp "/b.out 2>" temp "/b.err")) here env)))
        (pidA (match runA ((ok r) r.pid) ((err _) 0)))
        (pidB (match runB ((ok r) r.pid) ((err _) 0)))
        (upA (and (> pidA 0) (waitFile! sockA 1500)))
        (upB (and (> pidB 0) (waitFile! sockB 1500)))
        (hubA (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sockA "\" :class \"lead\")\n")))
        (t0 (/ (monotonicNs) 1000000))
        (t1 (pv/nextTurn! (pv/vendorProvider (cfgFor temp)) "sys" "user"))
        (elapsedMs (- (/ (monotonicNs) 1000000) t0))
        (seenA (resultOr (fileReadString (str temp "/seenA.txt")) ""))
        (hubB (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sockB "\" :class \"lead\")\n")))
        (t2 (pv/nextTurn! (pv/vendorProvider (cfgFor temp)) "sys" "user"))
        (seenB (resultOr (fileReadString (str temp "/seenB.txt")) ""))
        (killed (do (if (> pidA 0) (fr/killTree! pidA) 0) (if (> pidB 0) (fr/killTree! pidB) 0) true))
        (pipes (do (match runA ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)) (match runB ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)) true))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do (assert (and made upA upB) "both stand-in hubs listen")
        (assert (= (replyText t1) "text ok") (str "a 429 with Retry-After 2 is waited out and the repost succeeds: " (replyText t1)))
        (assert (= (countOf seenA "POST /v1/chat/completions") 2) (str "exactly one repost: " seenA))
        (assert (>= elapsedMs 2000) (str "the repost came after at least the Retry-After seconds: " (stringFromInt64 elapsedMs) " ms"))
        (assert (< elapsedMs 15000) (str "and not unboundedly later: " (stringFromInt64 elapsedMs) " ms"))
        (assert (stringContains? (replyText t2) "HTTP error 429") (str "a Retry-After beyond the queue timeout stays an error: " (replyText t2)))
        (assert (= (countOf seenB "POST /v1/chat/completions") 1) (str "and is not reposted: " seenB))
        (assert (and killed (and pipes removed)) "the stand-ins, their pipes and the temp dir are cleaned up")
        true))
