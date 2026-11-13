(module aslBench/gen/tests/linkCorrelationTest
  :x [runTests]
  :i [(aslBench/gen/core :a gc)
      (aslBench/gen/run :a run)
      (aslGateway/server :a gs)
      (asl-tools/fleet/run :a fr)])

; (:m :ref GENRUN-CROSSWIRE :do "a call that passes its limit leaves its request in flight on the in-process gateway link, and the link hands the next finished answer to whichever call is waiting: over the real link and curl against a stand-in upstream (fixtures/slowUpstream.asl, started through fleet/run, 20 s deadline, 4 answers at most) the call for task alpha passes a 400 ms limit, and the call for task beta that follows must get the answer to beta, never the late answer to alpha")

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
  (if (stringStartsWith? dir (str (scratchBase) "/aslBenchGenLink-")) (removeTree! dir) false)

fn ! waitFile! p: String tries: Int64 -> String
  (if (<= tries 0) ""
    (match (fileReadString p)
      ((ok t) (if (stringEmpty? (stringTrim t)) (do (sleepMs 50) (waitFile! p (- tries 1))) (stringTrim t)))
      ((err _) (do (sleepMs 50) (waitFile! p (- tries 1))))))

fn reqFor task: String -> gc/Req
  (gc/Req :model "m1" :arm "asl" :task task :rep 1 :turn 1 :system "card" :messages (list (pair "user" (str "solve MARK-" task " now"))) :maxTokens 50)

fn failedReply why: String -> gc/Reply
  (gc/Reply :text "" :tokIn 0 :tokOut 0 :served "" :error why)

fn ! testLateReply -> Bool
  (let [(here (resultOr (realPath ".") "."))
        (dir (str (scratchBase) "/aslBenchGenLink-" (stringFromInt64 (procSelf)) "-" (stringFromInt64 (nowNs))))
        (made (dirCreate dir))
        (made2 (dirCreate (str dir "/.asl")))
        (portFile (str dir "/port"))
        (g (fr/guardStart! (list (str here "/bin/asl") "run" (str here "/asl/bench/gen/tests/fixtures/slowUpstream.asl") portFile "1500" "4" "20") here (fr/childEnv (list)) (fr/limits 40 20)))
        (port (match g ((ok _) (waitFile! portFile 600)) ((err _) "")))
        (wroteCfg (fileWrite (str dir "/.asl/gateway.asn") (str (configText dir (str "http://127.0.0.1:" port "/v1")) "\n")))
        (calls (if (stringEmpty? port)
                 (pair (pair (failedReply "no port") (failedReply "no port")) false)
                 (match (gs/linkOpen! (mapSet (testEnv) "HOME" dir) dir dir (list))
                   ((err e) (pair (pair (failedReply (str "linkOpen: " e)) (failedReply (str "linkOpen: " e))) false))
                   ((ok l)
                     (let [(first (run/liveCallWith! l (reqFor "alpha") 2 400 50))
                           (second (run/liveCallWith! (pairFirst first) (reqFor "beta") 1 6000 50))]
                       (pair (pair (pairSecond first) (pairSecond second)) (run/linkIdle? (pairFirst second))))))))
        (alpha (pairFirst (pairFirst calls)))
        (beta (pairSecond (pairFirst calls)))
        (idleAfter (pairSecond calls))
        (out (match g ((ok gd) (fr/guardLoop gd)) ((err o) o)))
        (stubGone (fr/stubRemove!))
        (dropped (drop! dir))]
    (assert (and (ok? g) (not (stringEmpty? port))) (str "the stand-in upstream started and wrote its port: " port))
    (assert (or (not (stringEmpty? alpha.error)) (= alpha.text "ans:alpha")) (str "the call for alpha fails on its limit or holds the answer to alpha: " alpha.text " / " alpha.error))
    (assert (and (>= alpha.abandoned 1) (and (= alpha.abandonedOut (* alpha.abandoned 50)) (> alpha.abandonedIn 0)))
            (str "a call that passed its limit is reported abandoned with its prompt and max tokens as the estimate: " (stringFromInt64 alpha.abandoned) " " (stringFromInt64 alpha.abandonedIn) " " (stringFromInt64 alpha.abandonedOut)))
    (assert (= beta.abandoned 0) "a call that got its answer abandons nothing")
    (assert (!= beta.text "ans:alpha") (str "the late answer to alpha is never read by the call for beta: " beta.text " / " beta.error))
    (assert (and (stringEmpty? beta.error) (= beta.text "ans:beta")) (str "the call for beta holds the answer to beta: " beta.text " / " beta.error))
    (assert (= out.exitCode 0) (str "the stand-in upstream ended by itself with exit 0: " (stringFromInt64 out.exitCode) " " out.stderr))
    (assert idleAfter "a call that got its answer leaves the link idle, so it is reused and keeps its breaker state")
    (assert dropped "the scratch home is removed")
    true)

fn ! runTests -> Bool
  (testLateReply)
