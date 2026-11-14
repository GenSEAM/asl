(module aslBench/gen/tests/abandonTest
  :x [runTests]
  :i [(aslBench/gen/core :a gc)
      (aslBench/gen/run :a run)
      (aslGateway/server :a gs)])

; (:m :ref GENRUN-CROSSWIRE :do "a request abandoned at its limit is still billed by the provider: its estimate (prompt tokens sent plus max tokens out, the reserve of one call) is added to the spend, written in the row as (:abandoned (:n N :estUsd X)), counted again on resume, and a cap just above it stops the run before the next call; the request tells the caller how many sends the cap still covers")

fn abandoning tokIn: Int64 tokOut: Int64 -> (fn [Int64 gc/Req] -> (Pair Int64 gc/Reply))
  (fn [(seen Int64) (r gc/Req)] -> (Pair Int64 gc/Reply)
    (pair r.sendsLeft (gc/Reply :text "" :tokIn 0 :tokOut 0 :served "" :error "link: in-process gateway request timed out"
                                :abandoned 2 :abandonedIn tokIn :abandonedOut tokOut)))

fn configText dir: String base: String -> String
  (str "(:gateway :v 2 :ledgerPath \"" dir "/calls.asn\" :sharedUsagePath \"" dir "/shared.asn\""
       " :providers ((:provider :id stand :kind openai :base \"" base "\" :keyEnv \"STAND_TEST_KEY\"))"
       " :models ((:model :id m1 :provider stand :name \"plain-1\" :timeoutSec 8))"
       " :intents ((:intent :id code))"
       " :profiles ((:profile :id default :routes ((:intent code :chain (m1)))))"
       " :uses ((:use :for default :profile default)))")

; (:m :ref GENRUN-READYLINK-REMOVE :do "the link kept after an abandoned call is the same loop: readyLink! returns it untouched although it still holds the abandoned call's outbox, so the next call goes out on that same link with no reopen, and the late answer is discarded by its own id rather than read by the next call")
fn ! reconsiderLink l: gs/GatewayLoop -> Bool
  (match (run/readyLink! (with l :outbox (list (pair 0 "late alpha answer"))))
    ((err _) false)
    ((ok same)
      (match (run/readyLink! same)
        ((err _) false)
        ((ok again)
          (and (= again.startMs l.startMs)
               (and (some? again.wiringText)
                    (and (= (listLength again.outbox) 1) (not (run/linkIdle? again)))))))))

fn ! runTests -> Bool
  (let [(given (optionOr (envGet "ASL_CLI_ROOT") "."))
        (root (resultOr (realPath given) given))
        (work (resultOr (realPath (let [(d (str (optionOr (envGet "TMPDIR") "/tmp") "/aslBenchGenAbandon-" (stringFromInt64 (nowNs))))
                                        (made (dirCreate d))]
                                    d))
                        ""))
        (tasks (filter (fn [(t gc/Task)] -> Bool (listContains? (list "gcd" "maxOf") t.id)) (resultOr (gc/loadTasks root) (list))))
        (cards (resultOr (gc/loadCardsFor root (list "asl")) (list)))
        (trials (gc/planTrials (list "fake") (list "asl") tasks 1 7))
        (est (gc/callCost (gc/Config :root root :aslBin "" :work work :out "" :repairs 0 :maxTokens 1200 :priceIn 150000 :priceOut 600000 :capPico 0 :checkFirst true) 600 2400))
        (wide (gc/Config :root root :aslBin (str root "/bin/asl") :work work :out (str work "/wide.asn") :repairs 1 :maxTokens 1200
                         :priceIn 150000 :priceOut 600000 :capPico 1000000000000 :checkFirst true))
        (tight (with wide :out (str work "/tight.asn") :capPico (+ est 1)))
        (wroteWide (fileWrite wide.out ""))
        (wroteTight (fileWrite tight.out ""))
        (madeAsl (dirCreate (str work "/.asl")))
        (wroteCfg (fileWrite (str work "/.asl/gateway.asn") (str (configText work "http://127.0.0.1:1/v1") "\n")))
        (opened (gs/linkOpen! (mapSet (mapSet (mapEmpty) "HOME" work) "STAND_TEST_KEY" "test-key") work work (list)))
        (ranWide (gc/runAll! wide cards trials "" 0 (abandoning 600 2400) 0))
        (wideText (resultOr (fileReadString wide.out) ""))
        (ranTight (gc/runAll! tight cards trials "" 0 (abandoning 600 2400) 0))
        (tightText (resultOr (fileReadString tight.out) ""))
        (rsWide (pairSecond ranWide))
        (rsTight (pairSecond ranTight))
        (cleaned (gc/removeDir! work))]
    (assert (and (= (listLength trials) 2) (> est 0)) "two trials and a non-zero estimate")
    (assert (= rsWide.spent (* 2 est)) (str "each trial whose call was abandoned raises the spend by the estimate: " (stringFromInt64 rsWide.spent) " of " (stringFromInt64 (* 2 est))))
    (assert (stringContains? wideText (str ":costPico " (stringFromInt64 est) " :abandoned (:n 2 :estUsd " (gc/asnQuote (gc/usdText est)) ")")) (str "the failed row carries the abandoned count and estimate: " (gc/clip wideText 600)))
    (assert (= (gc/priorSpend wideText) (ok (* 2 est))) "a resumed run counts the abandoned estimate as prior spend")
    (assert (and (= rsTight.stopped "budget") (= rsTight.spent est)) (str "a cap just above one estimate stops the run before the next call: " rsTight.stopped " " (stringFromInt64 rsTight.spent)))
    (assert (and (stringContains? tightText "(:stopped :reason \"budget\"") (= (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:callFailed")) (stringLines tightText))) 1)) "the stop is recorded after the one failed trial")
    (assert (= (pairFirst ranTight) 1) (str "under the tight cap the request allows one send: " (stringFromInt64 (pairFirst ranTight))))
    (assert (> (pairFirst ranWide) 1) (str "under the wide cap the request allows retries: " (stringFromInt64 (pairFirst ranWide))))
    (assert (match opened
              ((err _) false)
              ((ok l) (reconsiderLink l)))
            "after one abandoned call the next call goes out on the same link, no reopen counted, and its late reply is matched by its own id, never read by the next call")
    (assert cleaned "the work directory is removed")
    true)
