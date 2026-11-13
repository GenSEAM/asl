(module ws/asl/tools/gateway/claudeSmoke
  :x [main]
  :i [(asl/packages/asl-gateway/src/federation :a f) (asl/packages/asl-gateway/src/secrets :a s) (asl-tools/fleet/run :a fr) (asl/packages/asl-gateway/tests/gatewayStartKit :a sk)])

; (:m :ref GW-CLAUDE-SESSIONS-MAC :do "asl run asl/tools/gateway/claudeSmoke.asl: one live smoke of the claude :sessions route; one gateway child under fleet/run.asl (300 s, 40 descendants, real HOME for the claude login), two turns of one tiny prompt on one session key through the federation client, prints only status, token counts and whether the vendor session id was reused; two claude calls, then the child tree is killed")

fn ! settle! g: fr/Guarded tries: Int64 -> Bool
  (let [(st (fr/guardAdvance! g))]
    (match st.out
      ((some _) true)
      ((none) (if (<= tries 0) false (do (fdPoll (fr/guardFds st.guard) 20) (settle! st.guard (- tries 1)))))))

; (:m :do "the number after a quoted key in a reply body, -1 when absent")
fn numAfter text: String key: String -> Int64
  (match (listHead (listDrop (stringSplit text (str "\"" key "\":")) 1))
    ((none) -1)
    ((some rest) (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest ",")) "") "}")) ""))) -1)))

fn ! sessionIdOf! home: String key: String -> String
  (let [(dir (str home "/.asl/run/sessions"))
        (hits (filter (fn [(t String)] -> Bool (stringContains? t key))
                      (map (fn [(n String)] -> String (resultOr (fileReadString (str dir "/" n)) "")) (resultOr (dirList dir) (list)))))]
    (match (listHead hits)
      ((none) "")
      ((some t) (optionOr (listHead (stringSplit (optionOr (listHead (listDrop (stringSplit t ":sessionId \"") 1)) "") "\"")) ""))))

fn turnBody prior: String user: String -> String
  (str "{\"model\":\"claude/opus\",\"messages\":[" prior "{\"role\":\"user\",\"content\":\"" user "\"}]}")

fn ! post! store: s/SecretStore port: Int64 key: String prior: String user: String -> String
  (let [(rg (f/RemoteGateway :id "smoke" :base (str "http://127.0.0.1:" (stringFromInt64 port)) :secret (f/serveTokenId) :aslGateway true))
        (env (mapFromPairs (list (pair "PATH" (optionOr (envGet "PATH") "/usr/bin:/bin")))))]
    (f/remoteForward! store rg (turnBody prior user) (list (pair "X-ASL-Session" key)) env 120.0))

fn summary r: String -> String
  (str "(:status " (if (stringStartsWith? r "(:remoteReply :provider smoke :status 200") "200" "other")
       " :in " (stringFromInt64 (numAfter r "inputTokens")) " :out " (stringFromInt64 (numAfter r "outputTokens")) ")")

fn ! main args: (List String) -> (Result Int64 String)
  (let [(home (optionOr (envGet "HOME") ""))
        (key (str "smoke" (stringFromInt64 (procSelf))))
        (dir (str "/tmp/gwClaudeSmoke-" key))
        (_a (dirCreate dir))
        (ready (str dir "/ready"))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (cache (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str home "/.asl/run/nativeCli"))))
        (argv (list "/bin/sh" "-c" (str "exec " host " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream http://127.0.0.1:1/v1 --ready " ready " 2>" dir "/gateway.err")))
        (started (fr/guardStart! argv "." (fr/childEnv (list (str "HOME=" home) cache)) (fr/limits 300 40)))]
    (match started
      ((err po) (do (println (str "(:smoke :err gatewayStart :exit " (stringFromInt64 po.exitCode) ")")) (ok 1)))
      ((ok g)
        (let [(port (sk/waitPort! ready g.run.pid))
              (loaded (s/secretsLoad! (str home "/.asl/secrets.asn")))]
          (match loaded
            ((err e) (do (fr/killTree! g.run.pid) (settle! g 100) (println "(:smoke :err secretsLoad)") (ok 1)))
            ((ok store)
              (let [(r1 (if (> port 0) (post! store port key "" "Reply with the single word ok.") ""))
                    (id1 (sessionIdOf! home key))
                    (r2 (if (> port 0) (post! store port key "{\"role\":\"user\",\"content\":\"Reply with the single word ok.\"},{\"role\":\"assistant\",\"content\":\"ok\"}," "Reply with the single word ok again.") ""))
                    (id2 (sessionIdOf! home key))
                    (_k (do (fr/killTree! g.run.pid) (settle! g 100)))]
                (do (println (str "(:smoke :port " (if (> port 0) "up" "down") " :turn1 " (summary r1) " :turn2 " (summary r2)
                                  " :sessionBound " (if (stringEmpty? id1) "false" "true") " :sessionSame " (if (and (not (stringEmpty? id1)) (= id1 id2)) "true" "false") ")"))
                    (ok (if (and (> port 0) (stringContains? r1 "status 200") (stringContains? r2 "status 200")) 0 1))))))))))
