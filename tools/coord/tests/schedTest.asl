(module asl-tools/coord/tests/schedTest
  :x [runTests]
  :i [(asl-tools/coord/sched :a sc) (asl-tools/fleet/run :a fr)])

; (:m :ref SCHED :do "AIMD table on goodput, the ledger window parse on a fixture, the per-provider health rows, and one persisted tick in a scratch store")
fn ! scratch name: String -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/schedTest-" (stringFromInt64 (procSelf)) "-" name)

fn ! cleanup dir: String -> Unit
  (let [(_ (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)))] ())

fn st goodput: Float64 prev: Float64 rate: Float64 freeMB: Int64 load: Float64 -> sc/Stats
  (sc/Stats :goodput goodput :prev prev :rateShare rate :freeMB freeMB :load load :cores 8 :flat 0)

fn call at: Int64 prov: String alias: String outcome: String out: Int64 -> String
  (str "(:call :at " (stringFromInt64 at) " :profile \"freeWriter\" :intent \"auto\" :alias \"" alias "\" :provider \"" prov "\" :model \"\" :in 10 :cached 0 :out " (stringFromInt64 out) " :reasoning 0 :ttftMs absent :ms 5 :outcome \"" outcome "\" :charge 0)")

fn fixture -> (List String)
  (list (call 100000 "nim" "a" "ok" 50) (call 200000 "nim" "a" "429" 0) (call 300000 "nim" "b" "ok" 70)
        (call 400000 "openrouter" "c" "throttled" 0) (call 450000 "openrouter" "c" "breaker 589s" 0) (call 500000 "openrouter" "d" "ok" 5)
        (call 900000 "nim" "a" "ok" 10) (call 5000 "nim" "a" "ok" 1000))

fn ! testTable -> Bool
  (let [(cfg (sc/defaultCfg))
        (grow (sc/nextSlots 10 (st 12.0 10.0 0.05 8000 2.0) cfg))
        (flat (sc/nextSlots 10 (st 10.0 10.0 0.05 8000 2.0) cfg))
        (hot (sc/nextSlots 10 (st 12.0 10.0 0.40 8000 2.0) cfg))
        (hotFlat (sc/nextSlots 10 (st 10.0 10.0 0.40 8000 2.0) cfg))
        (ram (sc/nextSlots 10 (st 12.0 10.0 0.0 1000 2.0) cfg))
        (load (sc/nextSlots 10 (st 12.0 10.0 0.0 8000 13.0) cfg))
        (unknownRam (sc/nextSlots 10 (st 12.0 10.0 0.0 -1 2.0) cfg))
        (busy (sc/nextSlots 10 (st 12.0 10.0 0.0 8000 9.0) cfg))
        (top (sc/nextSlots 63 (st 12.0 10.0 0.0 8000 2.0) cfg))
        (atMax (sc/nextSlots 64 (st 12.0 10.0 0.0 8000 2.0) cfg))
        (atMin (sc/nextSlots 4 (st 10.0 10.0 0.5 1000 2.0) cfg))
        (fromZero (sc/nextSlots 10 (st 3.0 0.0 0.0 8000 2.0) cfg))
        (f1 (sc/nextFlat (st 10.0 10.0 0.0 8000 2.0) cfg))
        (f0 (sc/nextFlat (st 12.0 10.0 0.0 8000 2.0) cfg))]
    (do (assert (= grow 12) (str "goodput rose, RAM and load fine: plus step: " (stringFromInt64 grow)))
        (assert (= flat 10) "goodput flat: hold")
        (assert (= hot 10) "429 share above soft but goodput rising: hold, no growth")
        (assert (= hotFlat 9) "429 share above soft and goodput flat: minus one, never halving")
        (assert (= ram 9) "RAM short: minus one")
        (assert (= load 9) "load above 1.5 cores: minus one")
        (assert (= unknownRam 10) "unknown RAM blocks growth and is no pressure")
        (assert (= busy 10) "load between cores and 1.5 cores: hold")
        (assert (and (= top 64) (= atMax 64)) "growth clamps to max")
        (assert (= atMin 4) "decrease clamps to min")
        (assert (= fromZero 12) "a first window with goodput and no previous one counts as a rise")
        (assert (and (= f1 1) (= f0 0)) "flat counter increments on flat and resets on a rise")
        true))

fn ! testWindow -> Bool
  (let [(lines (fixture))
        (w (sc/winOf lines 50000 600000))
        (w0 (sc/winOf lines 600000 1200000))
        (cfg (sc/parseCfg "(:sched :min 2 :max 9 :start 5 :softShare 0.5)"))
        (dflt (sc/defaultCfg))]
    (do (assert (and (= w.total 6) (= w.ok 3) (= w.rate 3) (= w.okOut 125)) (str "window 50-600s: " (stringFromInt64 w.total) " " (stringFromInt64 w.ok) " " (stringFromInt64 w.rate) " " (stringFromInt64 w.okOut)))
        (assert (and (= w0.total 1) (= w0.ok 1)) "the next window holds only its own call")
        (assert (= (sc/quoted (optionOr (listGet lines 4) "") ":outcome") "breaker 589s") "a quoted value keeps its spaces")
        (assert (= (sc/okPerMin w 600) 0.3) "ok per minute over a 600 s window")
        (assert (and (= cfg.min 2) (= cfg.max 9) (= cfg.start 5) (= cfg.softShare 0.5) (= cfg.step dflt.step)) "parseCfg reads given keys and defaults the rest")
        (assert (= dflt.softShare 0.30) "default soft share")
        (assert (= (sc/memFreeMB "MemTotal: 1 kB\nMemAvailable:   12626992 kB\n") 12330) "MemAvailable in MB")
        (assert (= (sc/memFreeMB "nothing") -1) "no meminfo is unknown")
        (assert (= (sc/loadOne "3.22 3.80 3.18 5/358 3103727") 3.22) "one-minute load")
        true))

fn ! testHealth -> Bool
  (let [(rows (sc/healthRows (fixture) 50000 600000 600))
        (txt (stringJoin rows "\n"))]
    (do (assert (stringContains? txt "(:prov nim :okPerMin 0.2 :r429PerMin 0.1") (str "nim row: " txt))
        (assert (stringContains? txt ":aliases 2 :limit model") (str "nim limits only alias a: model scope: " txt))
        (assert (stringContains? txt "(:prov openrouter") "openrouter row")
        (assert (< (sc/okShareOf txt "nim") 1.0) "a provider with failures has a share under 1")
        (assert (= (sc/okShareOf txt "ghost") 1.0) "a provider without data keeps full weight")
        (assert (>= (sc/okShareOf txt "openrouter") 0.2) "the multiplier never goes under 0.2")
        true))

fn ! testTick -> Bool
  (let [(dir (scratch "tick"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (cfg (sc/defaultCfg))
        (now 1200000)
        (lines (list (call 700000 "nim" "a" "ok" 1) (call 800000 "nim" "a" "ok" 1) (call 900000 "nim" "a" "ok" 1) (call 1000000 "nim" "a" "ok" 1) (call 300000 "nim" "a" "ok" 1)))
        (n1 (sc/schedTick! dir cfg now lines 8000 2.0 8))
        (slots (resultOr (fileReadString (str dir "/slots.asn")) ""))
        (j (resultOr (fileReadString (str dir "/journal.asn")) ""))
        (health (resultOr (fileReadString (str dir "/providerHealth.asn")) ""))
        (due0 (sc/slotsDue? dir (+ now 10000) 60000))
        (due1 (sc/slotsDue? dir (+ now 70000) 60000))
        (_ (cleanup dir))]
    (do (assert (= n1 18) (str "start 16, goodput 0.4 against 0.1 per minute: plus step 2: " (stringFromInt64 n1)))
        (assert (stringContains? slots ":n 18") (str "the slots file keeps the value: " slots))
        (assert (and (stringContains? j "(:slots :n 18") (stringContains? j ":goodput") (stringContains? j ":freeMB 8000")) (str "the change is journalled: " j))
        (assert (stringContains? health "(:prov nim") "the health file is written")
        (assert (and (not due0) due1) "sampling is due after the period only")
        true))

fn ! runTests -> Bool
  (do (assert (testTable) "AIMD table")
      (assert (testWindow) "ledger window and config parse")
      (assert (testHealth) "per provider health")
      (assert (testTick) "a persisted tick")
      true)
