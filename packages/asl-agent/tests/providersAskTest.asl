(module aslAgent/tests/providersAskTest
  :x [runTests]
  :i [(aslAgent/providers :a pv) (asl-tools/fleet/run :a fr)])

; (:m :ref SE1-PROVIDER-SPLIT :do "nextTurnAsk! with a hub socket in hub.asn posts nothing and returns askHub carrying the body and headers that nextTurn! then really posts to a stand-in hub (X-Asl-Unit, X-Asl-Class, the model body), counts the turn, and nextTurnReply of the stand-in's own raw reply gives the same text as the blocking turn; a script provider and a hub-less config give askDone equal to nextTurn!; a 503 raw reply is hubBusy?")
fn envFor temp: String -> pv/ProviderEnv
  (pv/ProviderEnv :gatewayUrl "http://127.0.0.1:1/v1/chat/completions" :inProcess false :profile "" :gatewayConfig (str temp "/.asl/gateway.asn")
    :tmpDir (str temp "/tmp") :childEnv (mapEmpty))

fn cfgFor temp: String -> pv/VendorConfig
  (pv/VendorConfig :vendor "agy" :mode "scout" :rootDir temp :model "" :timeout 20 :queueTimeout 20 :sessionId "s1" :intent "auto" :timeoutSet true
    :env (envFor temp) :link none :turn 0)

fn replyOf t: pv/Turn -> String
  (match t.reply ((ok (some s)) s) ((ok (none)) "") ((err e) (pv/errorMessage e)))

fn ! waitFile! path: String attempts: Int64 -> Bool
  (if (<= attempts 0) false
    (if (fileExists? path) true (do (sleepMs 20) (waitFile! path (- attempts 1)))))

fn rawOk -> String
  "HTTP/1.1 200 OK\r\nContent-Type: application/asn+sexpr\r\nContent-Length: 34\r\nConnection: close\r\n\r\n(:reply :content \"hello from hub\")"

fn raw503 -> String
  "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/asn+sexpr\r\nContent-Length: 39\r\nConnection: close\r\n\r\n(:error :status 503 :reason \"hub busy\")"

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/providersAskTest.XXXXXX" 5000) "")))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (stub (resultOr (realPath "asl/packages/asl-agent/tests/hubStub.asl") ""))
        (sock (str temp "/hub.sock"))
        (made (dirCreate (str temp "/.asl")))
        (script (pv/scriptProvider "s" (list "r1" "r2") 0))
        (scriptAsk (pv/nextTurnAsk! script "sys" "user"))
        (scriptBlocking (pv/nextTurn! script "sys" "user"))
        (hubA (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sock "\" :class \"lead\")\n")))
        (p0 (pv/vendorProvider (cfgFor temp)))
        (ask (pv/nextTurnAsk! p0 "sys" "user"))
        (cacheRow (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))))
        (running (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sock " " temp "/seen.txt 1>" temp "/stub.out 2>" temp "/stub.err"))
                               (resultOr (realPath ".") ".")
                               (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) cacheRow))))
        (pid (match running ((ok r) r.pid) ((err _) 0)))
        (up (and (> pid 0) (waitFile! sock 12000)))
        (blocking (if up (pv/nextTurn! p0 "sys" "user") (pv/Turn :provider p0 :reply (ok none) :meta (pv/emptyMeta))))
        (seen (if up (do (waitFile! (str temp "/seen.txt") 250) (resultOr (fileReadString (str temp "/seen.txt")) "")) ""))
        (killed (if (> pid 0) (do (fr/killTree! pid) true) false))
        (pipes (match running ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)))
        (noHubA (pathRemove (str temp "/.asl/hub.asn")))
        (plainAsk (pv/nextTurnAsk! p0 "sys" "user"))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do
      (assert (match scriptAsk ((pv/askDone t) (= (replyOf t) (replyOf scriptBlocking))) ((pv/askHub _ _) false)) "a script provider is askDone with the blocking turn's reply")
      (assert up "the stand-in hub is listening")
      (assert (match ask ((pv/askHub p call) (and (= call.sock sock) (stringContains? call.body "\"messages\""))) ((pv/askDone _) false)) "with a hub socket the ask carries the socket and the model body and posts nothing")
      (assert (match ask
                ((pv/askHub p call) (and (stringContains? seen call.body) (listAll? (fn [(h (Pair String String))] -> Bool (stringContains? (stringLower seen) (stringLower (str (pairFirst h) ": " (pairSecond h))))) call.headers)))
                ((pv/askDone _) false))
              (str "the body and every header of the ask are what the blocking turn posted: " seen))
      (assert (match ask ((pv/askHub p call) (and (stringContains? (stringLower seen) "x-asl-class: lead") (stringContains? (stringLower seen) "x-asl-unit: s1"))) ((pv/askDone _) false)) "class and unit headers are in the ask")
      (assert (match ask ((pv/askHub p call) (= (replyOf (pv/nextTurnReply p (rawOk))) "hello from hub")) ((pv/askDone _) false)) "nextTurnReply of the hub's raw reply is the reply text")
      (assert (= (replyOf (pv/nextTurnReply p0 (rawOk))) (replyOf blocking)) "the reply text equals the blocking turn's")
      (assert (match ask ((pv/askHub p call) (not (pv/hubBusy? (pv/nextTurnReply p (rawOk))))) ((pv/askDone _) false)) "a 200 is not busy")
      (assert (pv/hubBusy? (pv/nextTurnReply p0 (raw503))) "a 503 raw reply is hubBusy?")
      (assert (match plainAsk ((pv/askDone _) true) ((pv/askHub _ _) false)) "without hub.asn the ask is askDone (the gateway path is not deferred)")
      (assert (and killed (and pipes removed)) "the stand-in, its pipes and the temp dir are cleaned up")
      true))
