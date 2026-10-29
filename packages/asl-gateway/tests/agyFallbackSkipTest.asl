(module aslGateway/tests/agyFallbackSkipTest
  :x [runTests]
  :i [(chat :a ch)
      (upstream :a u)])

; (:m :ref ROTATE :do "agyFallback asks the pool agy:bin first; a nonzero answer (no agy binary on PATH or configured) skips the CLI without any effCli and notes skipped-noBinary; a zero answer leaves the call unchanged")
(schema Seen
  (:f notes String)
  (:f cli Int64)
  (:f bin Int64))

fn ! drive! step: ch/ChatStep binMissing: Bool seen: Seen fuel: Int64 -> Seen
  (if (<= fuel 0)
    (with seen :notes (str seen.notes "|outOfFuel"))
    (match step
      ((ch/stepDone _) seen)
      ((ch/stepRaised kind msg) (with seen :notes (str seen.notes "|raised " kind " " msg)))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (drive! (k (ch/outPath "/tmp")) binMissing seen (- fuel 1)))
         ((ch/effIsDir _) (drive! (k (ch/outBool true)) binMissing seen (- fuel 1)))
         ((ch/effClock) (drive! (k (ch/outFloat 1.0)) binMissing seen (- fuel 1)))
         ((ch/effBreakerDown pool)
          (if (= pool "agy:bin")
            (drive! (k (ch/outFloat (if binMissing 1.0 0.0))) binMissing (with seen :bin (+ seen.bin 1)) (- fuel 1))
            (drive! (k (ch/outFloat 0.0)) binMissing seen (- fuel 1))))
         ((ch/effBreakerDownAll _) (drive! (k (ch/outFloats (list 0.0))) binMissing seen (- fuel 1)))
         ((ch/effBucket _ _ _) (drive! (k (ch/outBool false)) binMissing seen (- fuel 1)))
         ((ch/effUsageNote _ _ o _) (drive! (k ch/outDone) binMissing (with seen :notes (str seen.notes "|" o)) (- fuel 1)))
         ((ch/effCli _ _) (drive! (k (ch/outCli none)) binMissing (with seen :cli (+ seen.cli 1)) (- fuel 1)))
         ((ch/effHttp _ _ _ _ _ _ _ _) (with seen :notes (str seen.notes "|http")))
         ((ch/effPoolHttp _ _ _ _ _ _) (with seen :notes (str seen.notes "|http")))
         (_ (drive! (k ch/outDone) binMissing seen (- fuel 1)))))))

fn ! post! binMissing: Bool -> Seen
  (match (u/upstreamSettings (mapEmpty))
    ((err _) (Seen :notes "no settings" :cli 0 :bin 0))
    ((ok st)
      (drive! (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers (list) :body "{\"model\":\"gemini-2.5-flash\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")
                (ch/ChatWorld :env (mapFromPairs (list (pair "GEMINI_API_KEY" "k-AAAA1111"))) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table (err "builtin")))
              binMissing (Seen :notes "" :cli 0 :bin 0) 120)))

fn ! runTests -> Bool
  (let [(absent (post! true))
        (present (post! false))]
    (do (assert (> absent.bin 0) (str "the binary probe ran: " absent.notes))
        (assert (and (= absent.cli 0) (stringContains? absent.notes "skipped-noBinary")) (str "no agy binary: no cli effect, noted: " absent.cli absent.notes))
        (assert (and (> present.cli 0) (not (stringContains? present.notes "skipped-noBinary"))) (str "agy present: cli effect runs: " present.cli present.notes))
        true))
