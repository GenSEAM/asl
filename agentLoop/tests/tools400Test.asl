(module asl/agentLoop/tests/tools400Test
  :x [runTests]
  :i [(asl/agentLoop/providers :a pv) (asl-tools/fleet/run :a fr) (asl-json/json :a j)])

; (:m :ref TOOLS-400-FALLBACK :do "a route that answers 400 to a request carrying tools: the turn is retried once without tools and succeeds in the text protocol, the provider is remembered as no-tools so the next turn sends none, and a 400 without tools is an ordinary error with no retry")
fn ! waitFile! path: String attempts: Int64 -> Bool
  (if (<= attempts 0) false
    (if (fileExists? path) true (do (sleepMs 20) (waitFile! path (- attempts 1)))))

fn cfgFor temp: String sid: String tools: (List j/Json) -> pv/VendorConfig
  (pv/VendorConfig :vendor "agy" :mode "scout" :rootDir temp :model "" :timeout 20 :queueTimeout 20 :sessionId sid :intent "auto" :timeoutSet true
    :env (pv/ProviderEnv :gatewayUrl "http://127.0.0.1:1/v1/chat/completions" :inProcess false :profile "" :gatewayConfig (str temp "/.asl/gateway.asn") :tmpDir (str temp "/tmp") :childEnv (mapEmpty))
    :link none :turn 0 :tools tools)

fn toolSchema -> j/Json
  (j/jobj (list (pair "type" (j/jstr "function")) (pair "function" (j/jobj (list (pair "name" (j/jstr "step")) (pair "description" (j/jstr "run a step")))))))

fn replyText t: pv/Turn -> String
  (match t.reply ((ok (some s)) s) ((ok (none)) "<none>") ((err e) (str "<err " (pv/errorMessage e) ">")))

fn countOf text: String needle: String -> Int64
  (listLength (stringSplit text needle)) 

fn ! runTests -> Bool
  (let [(temp (stringTrim (resultOr (fr/shellOut "/usr/bin/mktemp -d /tmp/tools400Test.XXXXXX" 5000) "")))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (here (resultOr (realPath ".") "."))
        (stub (resultOr (realPath "asl/agentLoop/tests/tools400Stub.asl") ""))
        (sockA (str temp "/a.sock"))
        (sockB (str temp "/b.sock"))
        (sockC (str temp "/c.sock"))
        (made (ok? (dirCreate (str temp "/.asl"))))
        (cacheRow (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "/usr/bin:/bin")) (str "HOME=" temp) cacheRow))
        (runA (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sockA " " temp "/seenA.txt tools 1>" temp "/a.out 2>" temp "/a.err")) here env)))
        (runB (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sockB " " temp "/seenB.txt always 1>" temp "/b.out 2>" temp "/b.err")) here env)))
        (runC (fr/spawn 0 (fr/job (list "/bin/sh" "-c" (str "exec " host " run " stub " " sockC " " temp "/seenC.txt context 1>" temp "/c.out 2>" temp "/c.err")) here env)))
        (pidC (match runC ((ok r) r.pid) ((err _) 0)))
        (pidA (match runA ((ok r) r.pid) ((err _) 0)))
        (pidB (match runB ((ok r) r.pid) ((err _) 0)))
        (upA (and (> pidA 0) (waitFile! sockA 1500)))
        (upB (and (> pidB 0) (waitFile! sockB 1500)))
        (upC (and (> pidC 0) (waitFile! sockC 1500)))
        (hubA (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sockA "\" :class \"lead\")\n")))
        (p0 (pv/vendorProvider (cfgFor temp "s1" (list (toolSchema)))))
        (t1 (pv/nextTurn! p0 "sys" "user"))
        (seenAfter1 (resultOr (fileReadString (str temp "/seenA.txt")) ""))
        (t2 (pv/nextTurn! t1.provider "sys" "user2"))
        (seenAfter2 (resultOr (fileReadString (str temp "/seenA.txt")) ""))
        (hubB (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sockB "\" :class \"lead\")\n")))
        (plain (pv/vendorProvider (cfgFor temp "s1" (list))))
        (t3 (pv/nextTurn! plain "sys" "user"))
        (seenB (resultOr (fileReadString (str temp "/seenB.txt")) ""))
        (journal1 (resultOr (fileReadString (str temp "/.asl/run/agentLoop/s1.journal")) ""))
        (hubC (fileWrite (str temp "/.asl/hub.asn") (str "(:hub :sock \"" sockC "\" :class \"lead\")\n")))
        (big (pv/vendorProvider (cfgFor temp "s2" (list (toolSchema)))))
        (t4 (pv/nextTurn! big "sys" "user"))
        (seenC (resultOr (fileReadString (str temp "/seenC.txt")) ""))
        (journal2 (resultOr (fileReadString (str temp "/.asl/run/agentLoop/s2.journal")) ""))
        (killed (do (if (> pidC 0) (fr/killTree! pidC) 0) (if (> pidA 0) (fr/killTree! pidA) 0) (if (> pidB 0) (fr/killTree! pidB) 0) true))
        (pipes (do (match runA ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)) (match runB ((ok r) (do (fdClose r.outFd) (fdClose r.errFd) true)) ((err _) true)) true))
        (removed (ok? (fr/shellOut (str "/bin/rm -rf " temp) 5000)))]
    (do (assert (and made (and upA (and upB upC))) "both stand-in hubs listen")
        (assert (= (replyText t1) "text ok") (str "the 400 on tools is retried without them and the turn succeeds: " (replyText t1)))
        (assert (= (countOf seenAfter1 "POST /v1/chat/completions") 3) (str "turn one posted twice (the tools request, then the retry): " seenAfter1))
        (assert (stringContains? (optionOr (listGet (stringSplit seenAfter1 "----") 0) "") "\"tools\"") "the first request carried tools")
        (assert (not (stringContains? (optionOr (listGet (stringSplit seenAfter1 "----") 1) "") "\"tools\"")) "the retry carried none")
        (assert (= (replyText t2) "text ok") "the next turn succeeds too")
        (assert (= (countOf seenAfter2 "POST /v1/chat/completions") 4) (str "the next turn posts once, without tools, because the route is remembered: " seenAfter2))
        (assert (stringContains? (replyText t3) "HTTP error 400") (str "a 400 without tools stays an error: " (replyText t3)))
        (assert (= (countOf seenB "POST /v1/chat/completions") 2) (str "and is not retried: " seenB))
        (assert (stringContains? journal1 "(:fallback :noTools true :model \"profile\" :status 400 :reason \"Hub HTTP error 400") (str "the fallback is journaled with model, status and the error: " journal1))
        (assert (= (countOf journal1 "(:fallback") 2) (str "one fallback row for the session, not one per turn: " journal1))
        (assert (stringContains? (replyText t4) "HTTP error 400") (str "a 400 naming a context limit is an error: " (replyText t4)))
        (assert (= (countOf seenC "POST /v1/chat/completions") 2) (str "and is not retried: " seenC))
        (assert (not (stringContains? journal2 "(:fallback")) (str "and writes no fallback row: " journal2))
        (assert (and killed (and pipes removed)) "the stand-ins, their pipes and the temp dir are cleaned up")
        true))
