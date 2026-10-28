(module aslGateway/tests/serverAuthRefuseTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref AUDIT12-B6 :do "serve auth must not fail open: a (:gateway :secretsFile) naming a missing file, a non-string :secretsFile, and a config that does not parse each stop the gateway before it listens, naming the cause, instead of serving unauthenticated")
fn ! settle! g: fr/Guarded tries: Int64 -> Bool
  (let [(st (fr/guardAdvance! g))]
    (match st.out
      ((some _) true)
      ((none) (if (<= tries 0) false (do (fdPoll (fr/guardFds st.guard) 20) (settle! st.guard (- tries 1)))))))

fn ! scratch! -> String
  (let [(d (str "/tmp/gwAuthRefuse-" (procSelf) "-" (nowNs)))
        (_ (dirCreate d))
        (_2 (dirCreate (str d "/.asl")))]
    d)

fn ! dropAll! dir: String -> Bool
  (let [(_ (map (fn [(sub String)] -> Bool (ok? (pathRemove (str dir "/" sub)))) (list ".asl/gateway.asn" ".asl" "ready" "gateway.err")))]
    (ok? (pathRemove dir)))

fn ! refusal! config: String -> (Pair Bool String)
  (let [(dir (scratch!))
        (_ (fileWrite (str dir "/.asl/gateway.asn") config))
        (readyPath (str dir "/ready"))
        (host (optionOr (envGet "ASL_HOST") (resultOr (realPath "bin/asl") "bin/asl")))
        (cache (str "ASL_NATIVE_CLI_CACHE=" (optionOr (envGet "ASL_NATIVE_CLI_CACHE") (str (optionOr (envGet "HOME") "/tmp") "/.asl/run/nativeCli"))))
        (argv (list "/bin/sh" "-c" (str "exec " host " run asl/packages/asl-gateway/src/server.asl serve --port 0 --upstream http://127.0.0.1:9/v1 --ready " readyPath " 2>" dir "/gateway.err")))
        (env (fr/childEnv (list (str "HOME=" dir) (str "ASL_GATEWAY_ROOT=" dir) (str "ASL_CALIBRATION_INDEX=" dir "/absent.asn") cache)))]
    (match (fr/guardStart! argv "." env (fr/limits 120 40))
      ((err po) (do (dropAll! dir) (pair false po.stderr)))
      ((ok g)
        (let [(ended (settle! g 3000))
              (_2 (if ended true (do (fr/killTree! g.run.pid) true)))
                            (listened (fileExists? readyPath))
                            (err (resultOr (fileReadString (str dir "/gateway.err")) ""))
              (_3 (dropAll! dir))]
          (pair (and ended (not listened)) err)))))

fn ! runTests -> Bool
  (let [(missing (refusal! "(:gateway :v 2 :secretsFile \"/tmp/gwAuthRefuse-no-such-file.asn\" :providers () :models () :profiles () :uses ())\n"))
        (nonString (refusal! "(:gateway :v 2 :secretsFile 42 :providers () :models () :profiles () :uses ())\n"))
        (broken (refusal! "(:gateway :v 2 :secretsFile \"x\" :providers (\n"))]
    (do
      (assert (and (pairFirst missing) (stringContains? (pairSecond missing) "ERR_SECRETS_MISSING")) (str "a missing :secretsFile file refuses to start and leaves no ready file: " (pairSecond missing)))
      (assert (and (pairFirst nonString) (stringContains? (pairSecond nonString) "ERR_SECRETS_CONFIG")) (str "a non-string :secretsFile refuses to start: " (pairSecond nonString)))
      (assert (pairFirst broken) (str "a config that does not parse refuses to start: " (pairSecond broken)))
      true))
