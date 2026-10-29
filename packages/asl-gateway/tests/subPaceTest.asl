(module aslGateway/tests/subPaceTest
  :x [runTests]
  :i [(subPace :a sp) (localTime :a lt)])

; (:m :ref SUBPACE :do "fixture subscriptions plus a fixture ledger give a deterministic ranking and caps, evaluated at 2026-10-28 12:00 UTC: the monthly window of 2026-11-13 is 48.33 percent elapsed, so a sub 20 percent used is under pace, 58 is 10 points over (weight falls), 80 is 32 over (drops out), a passed reset recovers, a figure from 2026-10-20 is stale, and a ledger-estimated sub is over pace from its call count")

fn subsFixture -> String
  (str "(:subscriptions :v 1 :updated \"2026-10-28\" :src \"fixture\"\n"
       "  (:sub :id okSub :renews \"2026-11-13\" :src principal :windows ((:monthly :resets \"2026-11-13\" :usedPercent 20 :src opencodeApi :at \"2026-10-28 11:50\")))\n"
       "  (:sub :id midSub :renews \"2026-11-13\" :windows ((:monthly :resets \"2026-11-13\" :usedPercent 58 :src opencodeApi :at \"2026-10-28 11:50\")))\n"
       "  (:sub :id overSub :renews \"2026-11-13\" :windows ((:rolling 5h :usedPercent 1 :src opencodeApi :at \"2026-10-28 11:50\") (:monthly :resets \"2026-11-13\" :usedPercent 80 :src opencodeApi :at \"2026-10-28 11:50\")))\n"
       "  (:sub :id resetSub :renews \"2026-11-13\" :windows ((:weekly :resets \"2026-10-20\" :usedPercent 90 :src opencodeApi :at \"2026-10-28 11:50\")))\n"
       "  (:sub :id staleSub :renews \"2026-11-13\" :windows ((:monthly :resets \"2026-11-13\" :usedPercent 10 :src opencodeApi :at \"2026-10-20 09:00\")))\n"
       "  (:sub :id ledgerSub :renews \"2026-11-16\" :capacity 100 :src principal :windows ())\n"
       "  (:sub :id noCapSub :renews \"2026-11-16\" :src principal :windows ())\n"
       "  (:sub :id freeSub :renews none :pace exhaust :note \"x\")\n"
       "  (:sub :id handSub :renews \"2026-11-13\" :src \"principal 2026-10-28: by hand\" :windows ((:monthly :resets \"2026-11-13\" :usedPercent 40))))\n")

; (:m :do "60 calls of ledgerSub after its window start 2026-10-17, 5 before it, 7 of another provider")
fn ledgerFixture -> String
  (let [(mk (fn [(prov String) (at Int64)] -> String
              (str "(:call :at " (stringFromInt64 at) " :profile \"\" :intent \"any\" :alias \"a\" :provider \"" prov "\" :model \"m\" :in 10 :cached 0 :out 5 :reasoning 0 :outcome \"ok\" :charge 0)")))
        (inside (+ (sp/parseTimeMs "2026-10-20 00:00") 0))
        (before (sp/parseTimeMs "2026-10-10 00:00"))]
    (stringJoin (listAppend (listAppend (map (fn [(i Int64)] -> String (mk "ledgerSub" (+ inside (* i 1000)))) (range 0 60))
                                        (map (fn [(i Int64)] -> String (mk "ledgerSub" (+ before (* i 1000)))) (range 0 5)))
                            (listAppend (map (fn [(i Int64)] -> String (mk "okSub" (+ inside (* i 1000)))) (range 0 7))
                                    (map (fn [(i Int64)] -> String (mk "noCapSub" (+ inside (* i 1000)))) (range 0 3))))
                "\n"))

fn localFixture -> String
  (str "(:subscriptions :v 1 :updated \"2026-10-28\"\n"
       "  (:sub :id localSub :renews \"2026-11-13\" :windows ((:weekly :resets \"2026-10-28 14:00\" :usedPercent 90 :src opencodeApi :at \"2026-10-28 13:00\")))\n")

fn byId paces: (List sp/SubPace) id: String -> sp/SubPace
  (optionOr (listHead (filter (fn [(p sp/SubPace)] -> Bool (= p.id id)) paces))
            (sp/SubPace :id "missing" :window "" :used 0.0 :known false :allowance 0.0 :pace 0.0 :factor -1.0 :src "" :atMs 0 :stale false :expired false :over false :hard false :calls 0 :tokens 0))

fn near a: Float64 b: Float64 -> Bool
  (< (if (> a b) (- a b) (- b a)) 0.01)

; (:m :ref COND5 :do "KIMI-MONTH-CAP: a monthly window with :capacity \"18 full 5 h windows\" makes the rolling window's allowance the monthly remainder over the rolling windows left: day 1 of the month, 18 windows, 0 used is at most 15 percent of a 5 h window (12.3 adopted arithmetic), half the month used halves it, a sub without a capacity keeps the burst allowance of 80")
fn kimiLine used: String rolling: String -> String
  (str "(:subscriptions :v 1 :updated \"2026-10-29\"\n  (:sub :id kimiSub :renews \"2026-11-29\" :windows ((:rolling 5h :usedPercent " rolling " :src kimiApi :at \"2026-10-29 11:50\") (:monthly :capacity \"18 full 5 h windows\" :usedPercent " used " :resets \"2026-11-29\" :src kimiApi :at \"2026-10-29 11:50\")))\n"
       "  (:sub :id plainSub :renews \"2026-11-29\" :windows ((:rolling 5h :usedPercent 10 :src kimiApi :at \"2026-10-29 11:50\")))\n")

fn ! testMonthlyCap -> Bool
  (let [(now (sp/parseTimeMs "2026-10-29 12:00"))
        (fresh (sp/paceSubs (lt/utcZone) (kimiLine "0" "12") "" now))
        (half (sp/paceSubs (lt/utcZone) (kimiLine "50" "12") "" now))
        (spent (sp/paceSubs (lt/utcZone) (kimiLine "0" "40") "" now))
        (a (byId fresh "kimiSub")) (b (byId half "kimiSub")) (c (byId spent "kimiSub")) (plain (byId fresh "plainSub"))]
    (do (assert (and (= a.window "rolling") (< a.allowance 15.0) (> a.allowance 5.0)) (str "month 0 percent used: per-window allowance at most 15: " (sp/fixed1 a.allowance)))
        (assert (and (< b.allowance (* 0.6 a.allowance)) (> b.allowance 1.0)) (str "half the month used roughly halves it: " (sp/fixed1 b.allowance) " vs " (sp/fixed1 a.allowance)))
        (assert (and c.over (< c.factor 0.5)) (str "a window 40 percent used against a 12 percent allowance is over and weighed down: " (sp/fixed1 c.factor)))
        (assert (near plain.allowance 80.0) (str "no capacity keeps the burst allowance: " (sp/fixed1 plain.allowance)))
        true))

fn ! runTests -> Bool
  (let [(now (sp/parseTimeMs "2026-10-28 12:00"))
        (paces (sp/paceSubs (lt/utcZone) (subsFixture) (ledgerFixture) now))
        (ok (byId paces "okSub")) (mid (byId paces "midSub")) (over (byId paces "overSub")) (reset (byId paces "resetSub"))
        (stale (byId paces "staleSub")) (led (byId paces "ledgerSub")) (free (byId paces "freeSub")) (hand (byId paces "handSub"))
        (cet (resultOr (lt/zoneFromPosix "CET-2") (lt/utcZone)))
        (localPaces (sp/paceSubs cet (localFixture) "" (sp/parseTimeMs "2026-10-28 12:01")))
        (beforePaces (sp/paceSubs cet (localFixture) "" (sp/parseTimeMs "2026-10-28 11:59")))
        (nocap (byId paces "noCapSub"))
        (factors (sp/factorsFromPaces paces now))
        (pools (list (pair "aOk" "okSub:aOk") (pair "aMid" "midSub:aMid") (pair "aOver" "overSub:aOver") (pair "aFree" "nim:aFree") (pair "aLed" "ledgerSub:aLed")))
        (spread (list (pair "aOk" 10) (pair "aMid" 10) (pair "aOver" 10) (pair "aFree" 10) (pair "aLed" 10)))
        (adjusted (sp/adjustSpread factors pools spread))
        (weightOf (fn [(a String)] -> Int64 (optionOr (mapGet (mapFromPairs adjusted) a) -1)))]
    (do
      (assert (= (listLength paces) 9) (str "one pace row per sub line: " (listLength paces)))
      (assert (near ok.allowance 48.33) (str "even pace: 14.5 of 30 days elapsed is 48.33 percent, got " (sp/fixed1 ok.allowance)))
      (assert (and (near ok.used 20.0) (not ok.over) (> ok.factor 1.0)) "a sub well under pace is boosted")
      (assert (and mid.over (not mid.hard) (near mid.factor 0.751)) (str "10 points over: soft zone, weight falls to 0.751 not 0: " (sp/fixed1 mid.factor)))
      (assert (and over.hard (= over.factor 0.0) (= over.window "monthly")) (str "32 points over drops out; the binding window is the monthly one, not the 1 percent rolling one: " over.window))
      (assert (and reset.expired (near reset.used 0.0) (> reset.factor 1.0) (not reset.hard)) "a window whose reset has passed recovers: used 0, boosted, flagged expired")
      (assert (and stale.stale (not ok.stale)) "a 2026-10-20 figure is stale at 12:00 on the 28th, a 10-minute-old one is not")
      (assert (and (not hand.stale) (near hand.used 40.0)) "a hand-entered window inherits the file's :updated date and the sub's :src word")
      (assert (and (= led.src "ledger") (near led.used 60.0) (= led.calls 60) (= led.tokens 900)) (str "ledger estimate counts only rows of its provider since the window start: " (sp/fixed1 led.used) " calls " (stringFromInt64 led.calls)))
      (assert (and led.hard (not led.stale)) "60 percent of the capacity in 38 percent of the month is over the hard limit; a ledger estimate is never stale")
      (assert (and (= free.factor 1.0) (= free.window "exhaust")) "pace exhaust is never limited")
      (assert (= (listLength adjusted) 3) (str "two over-hard subs leave the spread: " (listLength adjusted)))
      (assert (= (weightOf "aOver") -1) "the over-pace sub is behind: not in the spread")
      (assert (= (weightOf "aLed") -1) "the ledger-over sub is behind too")
      (assert (> (weightOf "aOk") (weightOf "aFree")) "under pace beats a sub-less free model")
      (assert (> (weightOf "aFree") (weightOf "aMid")) "a sub in the soft zone ranks behind the free model")
      (assert (= (weightOf "aFree") 100) "a model with no subscription keeps weight x10 with factor 1")
      (assert (= (sp/adjustSpread (sp/factorsFromPaces (list) now) pools spread) spread) "no subscription data leaves the spread untouched")
      (assert (> (sp/parseTimeMs "2026-11-13T19:46:51.000Z") (sp/parseTimeMs "2026-11-13")) "iso timestamps parse")
      (assert (and (not nocap.known) (= nocap.factor 1.0) (not nocap.hard) (> nocap.calls 0) (near nocap.allowance 38.33)) (str "no capacity: used unknown, never a percent, on the even time pace, never limited: " (sp/statusLine nocap 1.0 0.0 now)))
      (assert (and (stringContains? (sp/statusLine nocap 1.0 0.0 now) ":used unknown") (stringContains? (sp/statusLine nocap 1.0 0.0 now) ":capacity unknown") (stringContains? (sp/statusLine nocap 1.0 0.0 now) ":pace unknown")) "status says capacity unknown")
      (assert (and (stringContains? (sp/statusLine led 1.0 0.0 now) ":used 60.0") (not (stringContains? (sp/statusLine led 1.0 0.0 now) "capacity unknown"))) "a declared capacity shows its percent")
      (assert (and (not (byId localPaces "localSub").hard) (byId localPaces "localSub").expired (not (byId beforePaces "localSub").expired)) "a local reset of 14:00 at UTC+2 is 12:00Z: expired at 12:01Z, not at 11:59Z")
      (assert (and (= (sp/parseStampMs (lt/utcZone) "2026-10-28T14:00:00+02:00") (sp/parseTimeMs "2026-10-28 12:00")) (= (sp/parseStampMs cet "2026-10-28 14:00") (sp/parseTimeMs "2026-10-28 12:00"))) "an explicit offset wins, a bare stamp takes the zone")
      (assert (testMonthlyCap) "monthly capacity paces the rolling window")
      (assert (= (sp/parseTimeMs "never") 0) "a non-date is 0")
      (assert (and (sp/paceCacheFresh? factors (+ now 59000)) (not (sp/paceCacheFresh? factors (+ now 60000))) (not (sp/paceCacheFresh? (mapEmpty) now))) "the factor cache lives for a minute and an empty cache is never fresh")
      true))
