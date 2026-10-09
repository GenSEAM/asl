(module aslGateway/tests/breakerTest
  :x [runTests]
  :i [(breaker :a brk)])

fn testFixtureLoaded! -> Bool
  (let [(fixtureRes (fileReadString "asl/packages/asl-gateway/tests/breakerFixture.asn"))]
    (assert (ok? fixtureRes) "breakerFixture.asn must be readable from disk")
    (mt fixtureRes
      ((err _) false)
      ((ok text)
       (do
         (assert (stringContains? text ":caseCount 26") "fixture must declare 26 test sequences")
         (assert (stringContains? text "seq01_quota_429_simple") "fixture must include seq01")
         (assert (stringContains? text "seq08_503_three_trips_breaker") "fixture must include seq08")
         (assert (stringContains? text "seq14_timeout_three_trips_breaker") "fixture must include seq14")
         (assert (stringContains? text "seq17_clear_resets_tripped_breaker") "fixture must include seq17")
         (assert (stringContains? text "seq21_cooldown_expiry_exact") "fixture must include seq21")
         (assert (stringContains? text "seq26_edge_case_empty_provider_and_dynamic") "fixture must include seq26")
         true))))

fn testQuotaDetectionParity -> Bool
  (do
    (assert (brk/breakerIsQuotaError "HTTP 429 Too Many Requests") "429 upper detected as quota")
    (assert (brk/breakerIsQuotaError "RESOURCE_EXHAUSTED: quota exceeded") "RESOURCE_EXHAUSTED detected as quota")
    (assert (brk/breakerIsQuotaError "error: resource_exhausted rate limit") "lowercase resource_exhausted detected as quota")
    (assert (brk/breakerIsQuotaError "rate limit: quota exceeded for current minute") "quota keyword detected as quota")
    (assert (brk/breakerIsQuotaError "QUOTA") "isolated QUOTA detected")
    (refute (brk/breakerIsQuotaError "500 Internal Server Error") "500 is not quota")
    (refute (brk/breakerIsQuotaError "503 Service Unavailable") "503 is not quota")
    (refute (brk/breakerIsQuotaError "Connection timed out") "timeout text is not quota")
    (refute (brk/breakerIsQuotaError "") "empty text is not quota")
    (let [(st0 (brk/defaultBreakerState))
          (s1 (brk/stepBreaker st0 (brk/evMarkDown "agy") 100))
          (st1 (pairFirst s1))
          (s2 (brk/stepBreaker st1 (brk/evCheckDown "agy") 100))
          (decDown (pairSecond s2))]
      (mt decDown
        ((decDownFor left)
         (do
           (assert (= left 600) "markdown on quota sets 600s cooldown")
           (refute (= left 0) "markdown on quota refutes zero cooldown")
           true))
        (_ false))))

fn test503CountersAndTrip -> Bool
  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "agy") 100))
        (st1 (pairFirst s1))
        (d1 (pairSecond s1))]
    (assert (= (brk/breaker503Count st1 "agy") 1) "seq06: 503 count is 1 after first failure")
    (mt d1 ((decTripped tr) (refute tr "seq06: single 503 does not trip")) (_ (assert false "unexpected branch")))
    (let [(sCheck (brk/stepBreaker st1 (brk/evCheckDown "agy") 100))]
      (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 0) "seq06: down_for is 0")) (_ (assert false "unexpected branch")))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "agy") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "agy") 105))
        (st2 (pairFirst s2))
        (d2 (pairSecond s2))]
    (assert (= (brk/breaker503Count st2 "agy") 2) "seq07: 503 count is 2 after second failure")
    (mt d2 ((decTripped tr) (refute tr "seq07: two 503s do not trip")) (_ (assert false "unexpected branch")))
    (let [(sCheck (brk/stepBreaker st2 (brk/evCheckDown "agy") 105))]
      (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 0) "seq07: down_for is 0")) (_ (assert false "unexpected branch")))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "agy") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "agy") 105))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evNote503 "agy") 110))
        (st3 (pairFirst s3))
        (d3 (pairSecond s3))]
    (assert (= (brk/breaker503Count st3 "agy") 0) "seq08: 503 count resets to 0 on trip")
    (mt d3 ((decTripped tr) (assert tr "seq08: 3rd 503 trips breaker")) (_ (assert false "unexpected branch")))
    (let [(sCheck (brk/stepBreaker st3 (brk/evCheckDown "agy") 110))]
      (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 600) "seq08: down_for is 600 on trip")) (_ (assert false "unexpected branch")))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "agy") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "codex") 101))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evNote503 "agy") 102))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNote503 "codex") 103))
        (s5 (brk/stepBreaker (pairFirst s4) (brk/evNote503 "agy") 104))
        (stFinal (pairFirst s5))
        (dAgy (pairSecond s5))]
    (mt dAgy ((decTripped tr) (assert tr "seq09: agy trips on 3rd failure")) (_ (assert false "unexpected branch")))
    (assert (= (brk/breaker503Count stFinal "codex") 2) "seq09: codex count remains 2")
    (let [(cAgy (brk/stepBreaker stFinal (brk/evCheckDown "agy") 104))
          (cCodex (brk/stepBreaker (pairFirst cAgy) (brk/evCheckDown "codex") 104))]
      (mt (pairSecond cAgy) ((decDownFor sec) (assert (= sec 600) "seq09: agy is down 600s")) (_ (assert false "unexpected branch")))
      (mt (pairSecond cCodex) ((decDownFor sec) (assert (= sec 0) "seq09: codex is not down")) (_ (assert false "unexpected branch")))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "agy") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "agy") 105))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evReset503 "agy") 110))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNote503 "agy") 115))
        (stFinal (pairFirst s4))
        (dFinal (pairSecond s4))]
    (assert (= (brk/breaker503Count stFinal "agy") 1) "seq10: 503 count is 1 after reset and 1 new failure")
    (mt dFinal ((decTripped tr) (refute tr "seq10: reset prevented trip")) (_ (assert false "unexpected branch"))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "codex") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "codex") 101))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evNote503 "codex") 102))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNote503 "codex") 103))
        (stFinal (pairFirst s4))
        (d4 (pairSecond s4))]
    (assert (= (brk/breaker503Count stFinal "codex") 1) "seq11: 4th failure starts count at 1")
    (mt d4 ((decTripped tr) (refute tr "seq11: 4th failure does not report tripped")) (_ (assert false "unexpected branch")))
    (let [(sCheck (brk/stepBreaker stFinal (brk/evCheckDown "codex") 103))]
      (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 599) "seq11: 599s left")) (_ (assert false "unexpected branch")))))
  true

fn testTimeoutCountersAndTrip -> Bool
  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNoteTimeout "claude") 200))
        (st1 (pairFirst s1))
        (d1 (pairSecond s1))]
    (assert (= (brk/breakerTimeoutCount st1 "claude") 1) "seq12: timeout count is 1")
    (mt d1 ((decTripped tr) (refute tr "seq12: single timeout does not trip")) (_ (assert false "unexpected branch"))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNoteTimeout "claude") 200))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNoteTimeout "claude") 205))
        (st2 (pairFirst s2))
        (d2 (pairSecond s2))]
    (assert (= (brk/breakerTimeoutCount st2 "claude") 2) "seq13: timeout count is 2")
    (mt d2 ((decTripped tr) (refute tr "seq13: two timeouts do not trip")) (_ (assert false "unexpected branch"))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNoteTimeout "claude") 200))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNoteTimeout "claude") 205))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evNoteTimeout "claude") 210))
        (st3 (pairFirst s3))
        (d3 (pairSecond s3))]
    (assert (= (brk/breakerTimeoutCount st3 "claude") 0) "seq14: timeout count resets on trip")
    (mt d3 ((decTripped tr) (assert tr "seq14: 3rd timeout trips breaker")) (_ (assert false "unexpected branch")))
    (let [(sCheck (brk/stepBreaker st3 (brk/evCheckDown "claude") 210))]
      (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 600) "seq14: down_for is 600")) (_ (assert false "unexpected branch")))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNoteTimeout "claude") 200))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNoteTimeout "claude") 205))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evResetTimeout "claude") 210))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNoteTimeout "claude") 215))
        (stFinal (pairFirst s4))
        (dFinal (pairSecond s4))]
    (assert (= (brk/breakerTimeoutCount stFinal "claude") 1) "seq15: timeout count is 1 after reset and new failure")
    (mt dFinal ((decTripped tr) (refute tr "seq15: reset prevented trip")) (_ (assert false "unexpected branch"))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNoteTimeout "agy") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "agy") 101))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evNoteTimeout "agy") 102))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNote503 "agy") 103))
        (stFinal (pairFirst s4))]
    (assert (= (brk/breakerTimeoutCount stFinal "agy") 2) "seq16: timeout count is 2")
    (assert (= (brk/breaker503Count stFinal "agy") 2) "seq16: 503 count is 2")
    (let [(sCheck (brk/stepBreaker stFinal (brk/evCheckDown "agy") 103))]
      (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 0) "seq16: interleaved failures do not trip")) (_ (assert false "unexpected branch")))))
  true

fn testSuccessResetsAndClear -> Bool
  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evMarkDown "agy") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evClear "agy") 150))
        (sCheck (brk/stepBreaker (pairFirst s2) (brk/evCheckDown "agy") 150))]
    (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 0) "seq17: clear makes down_for 0 immediately")) (_ (assert false "unexpected branch"))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "codex") 200))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "codex") 201))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evNoteTimeout "codex") 202))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNoteTimeout "codex") 203))
        (s5 (brk/stepBreaker (pairFirst s4) (brk/evClear "codex") 205))
        (stFinal (pairFirst s5))]
    (assert (= (brk/breaker503Count stFinal "codex") 0) "seq18: clear resets 503 count")
    (assert (= (brk/breakerTimeoutCount stFinal "codex") 0) "seq18: clear resets timeout count"))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNote503 "claude") 300))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNote503 "claude") 301))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evNoteTimeout "claude") 302))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNoteTimeout "claude") 303))
        (s5 (brk/stepBreaker (pairFirst s4) (brk/evMarkDown "claude") 305))
        (stFinal (pairFirst s5))]
    (assert (= (brk/breaker503Count stFinal "claude") 0) "seq19: mark_down resets 503 count")
    (assert (= (brk/breakerTimeoutCount stFinal "claude") 0) "seq19: mark_down resets timeout count")
    (let [(sCheck (brk/stepBreaker stFinal (brk/evCheckDown "claude") 305))]
      (mt (pairSecond sCheck) ((decDownFor sec) (assert (= sec 600) "seq19: mark_down sets 600s")) (_ (assert false "unexpected branch")))))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evNoteTimeout "agy") 100))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evNoteTimeout "agy") 105))
        (s3 (brk/stepBreaker (pairFirst s2) (brk/evClear "agy") 110))
        (s4 (brk/stepBreaker (pairFirst s3) (brk/evNoteTimeout "agy") 115))
        (s5 (brk/stepBreaker (pairFirst s4) (brk/evNoteTimeout "agy") 120))
        (stFinal (pairFirst s5))
        (dFinal (pairSecond s5))]
    (assert (= (brk/breakerTimeoutCount stFinal "agy") 2) "seq20: count is 2, not 4")
    (mt dFinal ((decTripped tr) (refute tr "seq20: clear between prevented trip")) (_ (assert false "unexpected branch"))))
  true

fn testCooldownExpiryAndSnapshot -> Bool
  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evMarkDown "agy") 1000))
        (st1 (pairFirst s1))
        (sBefore (brk/stepBreaker st1 (brk/evCheckDown "agy") 1599))
        (stBefore (pairFirst sBefore))
        (dBefore (pairSecond sBefore))
        (sExact (brk/stepBreaker stBefore (brk/evCheckDown "agy") 1600))
        (stExact (pairFirst sExact))
        (dExact (pairSecond sExact))]
    (mt dBefore ((decDownFor sec) (assert (= sec 1) "seq21: 1s remaining at t=1599")) (_ (assert false "unexpected branch")))
    (mt dExact ((decDownFor sec) (assert (= sec 0) "seq21: 0s remaining at t=1600 (expired)")) (_ (assert false "unexpected branch")))
    (refute (mapHas? stExact.breakers "agy") "seq21: expired breaker pruned from map"))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evMarkDown "codex") 1000))
        (sCheck (brk/stepBreaker (pairFirst s1) (brk/evCheckDown "codex") 1700))
        (stCheck (pairFirst sCheck))
        (dCheck (pairSecond sCheck))]
    (mt dCheck ((decDownFor sec) (assert (= sec 0) "seq22: 0s past expiry")) (_ (assert false "unexpected branch")))
    (refute (mapHas? stCheck.breakers "codex") "seq22: pruned past expiry"))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evMarkDown "agy") 1000))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evMarkDown "codex") 1000))
        (sSnap (brk/stepBreaker (pairFirst s2) (brk/evSnapshot) 1200))
        (decSnap (pairSecond sSnap))]
    (mt decSnap
      ((decSnapshot snap)
       (do
         (assert (mapHas? snap "agy") "seq23: agy in snapshot")
         (assert (mapHas? snap "codex") "seq23: codex in snapshot")
         (assert (mapHas? snap "claude") "seq23: claude in snapshot")
         (let [(stAgy (optionOr (mapGet snap "agy") (brk/ProviderStatus :down false :secondsLeft 0)))
               (stCodex (optionOr (mapGet snap "codex") (brk/ProviderStatus :down false :secondsLeft 0)))
               (stClaude (optionOr (mapGet snap "claude") (brk/ProviderStatus :down false :secondsLeft 0)))]
           (assert stAgy.down "seq23: agy is down")
           (assert (= stAgy.secondsLeft 400) "seq23: agy 400s left")
           (assert stCodex.down "seq23: codex is down")
           (assert (= stCodex.secondsLeft 400) "seq23: codex 400s left")
           (refute stClaude.down "seq23: claude is not down")
           (assert (= stClaude.secondsLeft 0) "seq23: claude 0s left")
           true)))
      (_ false)))

  (let [(st0 (brk/defaultBreakerState))
        (s1 (brk/stepBreaker st0 (brk/evMarkDown "agy") 1000))
        (s2 (brk/stepBreaker (pairFirst s1) (brk/evMarkDown "codex") 1200))
        (sSnap (brk/stepBreaker (pairFirst s2) (brk/evSnapshot) 1650))
        (decSnap (pairSecond sSnap))]
    (mt decSnap
      ((decSnapshot snap)
       (let [(stAgy (optionOr (mapGet snap "agy") (brk/ProviderStatus :down false :secondsLeft 0)))
             (stCodex (optionOr (mapGet snap "codex") (brk/ProviderStatus :down false :secondsLeft 0)))]
         (refute stAgy.down "seq24: agy expired at t=1650")
         (assert (= stAgy.secondsLeft 0) "seq24: agy 0s left")
         (assert stCodex.down "seq24: codex still down at t=1650")
         (assert (= stCodex.secondsLeft 150) "seq24: codex 150s left")
         true))
      (_ false)))

  (let [(stCustom (brk/makeBreakerState 120))
        (s1 (brk/stepBreaker stCustom (brk/evMarkDown "agy") 50))
        (sCheck1 (brk/stepBreaker (pairFirst s1) (brk/evCheckDown "agy") 100))
        (sCheck2 (brk/stepBreaker (pairFirst sCheck1) (brk/evCheckDown "agy") 170))]
    (mt (pairSecond sCheck1) ((decDownFor sec) (assert (= sec 70) "seq25: 70s left at t=100")) (_ (assert false "unexpected branch")))
    (mt (pairSecond sCheck2) ((decDownFor sec) (assert (= sec 0) "seq25: expired at t=170")) (_ (assert false "unexpected branch"))))

  (let [(st0 (brk/defaultBreakerState))
        (sEmptyDown (brk/stepBreaker st0 (brk/evCheckDown "") 100))
        (sEmptyMark (brk/stepBreaker (pairFirst sEmptyDown) (brk/evMarkDown "") 100))
        (sEmpty503 (brk/stepBreaker (pairFirst sEmptyMark) (brk/evNote503 "") 100))
        (sEmptyTimeout (brk/stepBreaker (pairFirst sEmpty503) (brk/evNoteTimeout "") 100))
        (sDyn (brk/stepBreaker (pairFirst sEmptyTimeout) (brk/evNote503 "gemini") 100))
        (stDyn (pairFirst sDyn))
        (sSnap (brk/stepBreaker stDyn (brk/evSnapshot) 100))]
    (mt (pairSecond sEmptyDown) ((decDownFor sec) (assert (= sec 0) "seq26: empty down_for is 0")) (_ (assert false "unexpected branch")))
    (mt (pairSecond sEmpty503) ((decTripped tr) (refute tr "seq26: empty 503 is false")) (_ (assert false "unexpected branch")))
    (mt (pairSecond sEmptyTimeout) ((decTripped tr) (refute tr "seq26: empty timeout is false")) (_ (assert false "unexpected branch")))
    (assert (= (brk/breaker503Count stDyn "gemini") 1) "seq26: gemini count is 1")
    (mt (pairSecond sSnap)
      ((decSnapshot snap)
       (do
         (assert (mapHas? snap "gemini") "seq26: gemini dynamically included in snapshot")
         (assert (= (listLength (mapKeys snap)) 4) "seq26: snapshot has exactly 4 providers")
         true))
      (_ false)))
  true

fn testDirectApiEquivalence -> Bool
  (let [(st0 (brk/defaultBreakerState))]
    (let [(st1 (brk/breakerMarkDown st0 "agy" 500))
          (p1 (brk/breakerDownFor st1 "agy" 500))
          (st2 (pairFirst p1))
          (left1 (pairSecond p1))]
      (assert (= left1 600) "direct breakerDownFor returns 600s")
      (assert (= (brk/breaker503Count st2 "agy") 0) "direct 503 count is 0")
      (assert (= (brk/breakerTimeoutCount st2 "agy") 0) "direct timeout count is 0")
      (let [(st3 (brk/breakerClear st2 "agy"))
            (p2 (brk/breakerDownFor st3 "agy" 500))]
        (assert (= (pairSecond p2) 0) "direct breakerClear resets down_for to 0"))
      (let [(res1 (brk/breakerNote503 st0 "codex" 100))
            (res2 (brk/breakerNote503 (pairFirst res1) "codex" 105))
            (res3 (brk/breakerNote503 (pairFirst res2) "codex" 110))]
        (refute (pairSecond res1) "direct 1st 503 does not trip")
        (refute (pairSecond res2) "direct 2nd 503 does not trip")
        (assert (pairSecond res3) "direct 3rd 503 trips")
        (let [(pDown (brk/breakerDownFor (pairFirst res3) "codex" 110))]
          (assert (= (pairSecond pDown) 600) "direct down_for is 600 after 3rd 503"))
        (let [(stReset (brk/breakerReset503 (pairFirst res2) "codex"))]
          (assert (= (brk/breaker503Count stReset "codex") 0) "direct breakerReset503 zeroes count")))
      (let [(res1 (brk/breakerNoteTimeout st0 "claude" 200))
            (res2 (brk/breakerNoteTimeout (pairFirst res1) "claude" 205))
            (res3 (brk/breakerNoteTimeout (pairFirst res2) "claude" 210))]
        (refute (pairSecond res1) "direct 1st timeout does not trip")
        (refute (pairSecond res2) "direct 2nd timeout does not trip")
        (assert (pairSecond res3) "direct 3rd timeout trips")
        (let [(pDown (brk/breakerDownFor (pairFirst res3) "claude" 210))]
          (assert (= (pairSecond pDown) 600) "direct down_for is 600 after 3rd timeout"))
        (let [(stReset (brk/breakerResetTimeout (pairFirst res2) "claude"))]
          (assert (= (brk/breakerTimeoutCount stReset "claude") 0) "direct breakerResetTimeout zeroes count")))
      (let [(stDown (brk/breakerMarkDown st0 "agy" 100))
            (pSnap (brk/breakerSnapshot stDown 200))
            (snap (pairSecond pSnap))
            (asnStr (brk/formatBreakerSnapshotAsn snap))]
        (assert (stringStartsWith? asnStr "(:breaker (") "snapshot ASN starts with (:breaker (")
        (assert (stringContains? asnStr ":agy (:down true :secondsLeft 500)") "snapshot ASN formats agy as down with 500s left")
        (assert (stringContains? asnStr ":claude (:down false :secondsLeft 0)") "snapshot ASN formats claude as down false")
        (assert (= (brk/providerCooldownSec) 600) "providerCooldownSec is 600")
        (assert (= (brk/defaultCooldownSec) 600) "defaultCooldownSec is 600")
        true)))

fn ! runTests -> Bool
  (do
    (assert (testFixtureLoaded!) "testFixtureLoaded passed")
    (assert (testQuotaDetectionParity) "testQuotaDetectionParity passed")
    (assert (test503CountersAndTrip) "test503CountersAndTrip passed")
    (assert (testTimeoutCountersAndTrip) "testTimeoutCountersAndTrip passed")
    (assert (testSuccessResetsAndClear) "testSuccessResetsAndClear passed")
    (assert (testCooldownExpiryAndSnapshot) "testCooldownExpiryAndSnapshot passed")
    (assert (testDirectApiEquivalence) "testDirectApiEquivalence passed")
    true)
