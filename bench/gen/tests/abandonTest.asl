(module aslBench/gen/tests/abandonTest
  :x [runTests]
  :i [(aslBench/gen/core :a gc)])

; (:m :ref GENRUN-CROSSWIRE :do "a request abandoned at its limit is still billed by the provider: its estimate (prompt tokens sent plus max tokens out, the reserve of one call) is added to the spend, written in the row as (:abandoned (:n N :estUsd X)), counted again on resume, and a cap just above it stops the run before the next call; the request tells the caller how many sends the cap still covers")

fn abandoning tokIn: Int64 tokOut: Int64 -> (fn [Int64 gc/Req] -> (Pair Int64 gc/Reply))
  (fn [(seen Int64) (r gc/Req)] -> (Pair Int64 gc/Reply)
    (pair r.sendsLeft (gc/Reply :text "" :tokIn 0 :tokOut 0 :served "" :error "link: in-process gateway request timed out"
                                :abandoned 2 :abandonedIn tokIn :abandonedOut tokOut)))

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
    (assert cleaned "the work directory is removed")
    true)
