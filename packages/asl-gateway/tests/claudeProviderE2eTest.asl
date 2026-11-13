(module aslGateway/tests/claudeProviderE2eTest
  :x [runTests]
  :i [(aslGateway/tests/gatewayStartKit :a sk) (federation :a f) (secrets :a s) (asl-tools/fleet/run :a fr)])

; (:m :ref GW-CLAUDE-PROVIDER-E2E :do "a real asl-gateway process (the Mac side) serves the claude CLI provider with a stub claude binary and a :sessions vendor row: a federation client (node2 Leon's hop) and a second plain client post through it; the client's X-ASL-Session is bound to the vendor session id, so the second turn passes --resume with the id the first turn answered with, a different session key starts a fresh vendor session, and every reply comes back through the bearer-checked federation hop")
fn ! nowMs! -> Int64
  (/ (monotonicNs) 1000000)

fn ! scratch! -> String
  (let [(d (str "/tmp/gwClaudeE2e-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))
        (_2 (dirCreate (str d "/.asl")))]
    d)

fn ! drop! dir: String -> Bool
  (let [(sub (str dir "/.asl"))
        (_ (map (fn [(n String)] -> Bool (ok? (pathRemove (str sub "/" n)))) (resultOr (dirList sub) (list))))
        (_2 (pathRemove sub))
        (_3 (map (fn [(n String)] -> Bool (ok? (pathRemove (str dir "/" n)))) (resultOr (dirList dir) (list))))]
    (ok? (pathRemove dir)))

fn ! cacheEnvRow! -> String
  (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli")))

fn ! hostExe! -> String
  (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl"))

fn ! settle! g: fr/Guarded tries: Int64 -> Bool
  (let [(st (fr/guardAdvance! g))]
    (match st.out
      ((some _) true)
      ((none) (if (<= tries 0) false (do (fdPoll (fr/guardFds st.guard) 20) (settle! st.guard (- tries 1)))))))

fn ! writeSecretsFile! path: String text: String -> Bool
  (do (fileWrite path text) (fileChmod path 384) true)

; (:m :do "the stub speaks claude -p --output-format json: the prompt is the last argument, --resume ID resumes, the reply names the session id")
fn stubScript -> String
  (stringJoin (list "#!/bin/sh"
                    "d=$(dirname \"$0\")"
                    "echo \"ARGV $*\" >> \"$d/calls.log\""
                    "rid=; prev=; prompt="
                    "for a in \"$@\"; do if [ \"$prev\" = \"--resume\" ]; then rid=\"$a\"; fi; prev=\"$a\"; prompt=\"$a\"; done"
                    "if [ -z \"$rid\" ]; then n=$(( $(cat \"$d/counter\" 2>/dev/null || echo 0) + 1 )); echo $n > \"$d/counter\"; id=\"stub-$n\"; kind=new; else id=\"$rid\"; kind=resumed; fi"
                    "printf '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"stub:%s:%s\",\"session_id\":\"%s\",\"usage\":{\"input_tokens\":3,\"output_tokens\":2}}\\n' \"$kind\" \"$prompt\" \"$id\""
                    "") "\n")

fn configText bin: String -> String
  (str "(:gateway :v 2 :providers () :models ((:model :id cl :provider claude :name \"opus\")) :profiles ((:profile :id default :routes ((:intent any :chain (cl))))) :uses ((:use :for default :profile default))"
       " :sessions ((:vendor \"claude\" :bin \"" bin "\" :first (\"-p\" \"--output-format\" \"json\") :resume (\"-p\" \"--output-format\" \"json\" \"--resume\" \"{id}\") :idFrom \"session_id\" :replyFrom \"result\")))\n")

fn turn prior: String user: String -> String
  (str "{\"model\":\"claude/opus\",\"messages\":[" prior "{\"role\":\"user\",\"content\":\"" user "\"}]}")

fn ! post! store: s/SecretStore port: Int64 secret: String session: String prior: String user: String -> String
  (let [(rg (f/RemoteGateway :id "mac" :base (str "http://127.0.0.1:" (stringFromInt64 port)) :secret secret))
        (env (mapFromPairs (list (pair "PATH" (optionOr (envGet "PATH") "/usr/bin:/bin")))))]
    (f/remoteForward! store rg (turn prior user) (list (pair "X-ASL-Session" session)) env 60.0))

fn ! runTests -> Bool
  (let [(dir (scratch!))
        (bin (str dir "/claude-stub.sh"))
        (_a (writeSecretsFile! bin (stubScript)))
        (_b (fileChmod bin 493))
        (_c (fileWrite (str dir "/.asl/gateway.asn") (configText bin)))
        (_d (writeSecretsFile! (str dir "/.asl/secrets.asn") "(:secret :id gatewayServeToken :value \"tok-SERVE-5b17c2e9\")\n"))
        (clientFile (str dir "/client.asn"))
        (_e (writeSecretsFile! clientFile "(:secret :id goodToken :value \"tok-SERVE-5b17c2e9\")\n"))
        (readyPath (str dir "/ready"))
        (argv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream http://127.0.0.1:1/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") (str "CLAUDE_BIN=" bin) (cacheEnvRow!))))
        (warmArgv (list "/bin/sh" "-c" (str "exec " (hostExe!) " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream http://127.0.0.1:1/v1 --ready " dir "/ready0 2>" dir "/warm.err")))
        (warm (fr/guardStart! warmArgv "." env (fr/limits 600 40)))
        (warmPort (match warm
                    ((ok wg) (let [(p (sk/waitPortErr! (str dir "/ready0") wg.run.pid (str dir "/warm.err")))] (do (fr/killTree! wg.run.pid) (settle! wg 100) p)))
                    ((err _) 0)))
        (started (if (> warmPort 0) (fr/guardStart! argv "." env (fr/limits 180 40)) (err (fr/ProcOut :exitCode 1 :stdout "" :stderr (str "warm start failed: " (resultOr (fileReadString (str dir "/warm.err")) "")) :timedOut false))))]
    (match started
      ((err po) (do (drop! dir) (assert false (str "host gateway did not start: " po.stderr)) false))
      ((ok g)
        (let [(port (sk/waitPort! readyPath g.run.pid))
              (loaded (s/secretsLoad! clientFile))]
          (match loaded
            ((err e) (do (assert false (str "client secrets: " e)) false))
            ((ok store)
              (let [(r1 (post! store port "goodToken" "sess-A" "" "hello"))
                    (r2 (post! store port "goodToken" "sess-A" "{\"role\":\"user\",\"content\":\"hello\"},{\"role\":\"assistant\",\"content\":\"stub:new:hello\"}," "again"))
                    (r3 (post! store port "goodToken" "sess-B" "" "other"))
                    (calls (resultOr (fileReadString (str dir "/calls.log")) ""))
                    (killed (do (fr/killTree! g.run.pid) (settle! g 100)))
                    (errText (resultOr (fileReadString (str dir "/gateway.err")) ""))
                    (cleaned (drop! dir))
                    (all (str r1 r2 r3))]
                (do
                  (assert (> port 0) (str "the host gateway wrote its ready file: " errText))
                  (assert (stringStartsWith? r1 "(:remoteReply :provider mac :status 200") (str "the federation hop carries the first reply: " r1))
                  (assert (stringContains? r1 "stub:new:hello") (str "the first turn reached the claude provider and started a vendor session: " r1))
                  (assert (stringContains? r2 "stub:resumed:again") (str "the second turn of the same session key resumes the vendor session: " r2))
                  (assert (stringContains? calls "--resume stub-1") (str "and passes the id the first turn answered with: " calls))
                  (assert (stringContains? r3 "stub:new:other") (str "a different session key starts its own vendor session: " r3))
                  (assert (= (listLength (filter (fn [(l String)] -> Bool (stringContains? l "--resume")) (stringSplit calls "\n"))) 1) (str "exactly one call resumed: " calls))
                  (assert (not (stringContains? all "tok-SERVE-5b17c2e9")) "no receipt shows the serve token")
                  (assert killed "the gateway process tree is stopped")
                  (and killed cleaned)))))))))
