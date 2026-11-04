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
        (lowered (sc/nextSlots 41 (st 10.0 10.0 0.0 8000 2.0) (sc/parseCfg "(:sched :min 4 :max 8)")))
        (raised (sc/nextSlots 2 (st 10.0 10.0 0.0 8000 2.0) cfg))
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
        (assert (= lowered 8) (str "a persisted count above a lowered :max clamps at once: " (stringFromInt64 lowered)))
        (assert (= raised 4) (str "a persisted count below :min lifts at once: " (stringFromInt64 raised)))
        (assert (and (= f1 1) (= f0 0)) "flat counter increments on flat and resets on a rise")
        true))

fn ! testWindow -> Bool
  (let [(lines (fixture))
        (w (sc/winOf lines 50000 600000))
        (w0 (sc/winOf lines 600000 1200000))
        (cfg (sc/parseCfg "(:sched :min 2 :max 9 :start 5 :softShare 0.5)"))
        (dflt (sc/defaultCfg))]
    (do (assert (and (= w.total 5) (= w.ok 3) (= w.rate 2) (= w.okOut 125)) (str "window 50-600s, the breaker row is not a call: " (stringFromInt64 w.total) " " (stringFromInt64 w.ok) " " (stringFromInt64 w.rate) " " (stringFromInt64 w.okOut)))
        (assert (and (= w0.total 1) (= w0.ok 1)) "the next window holds only its own call")
        (assert (= (sc/quoted (optionOr (listGet lines 4) "") ":outcome") "breaker 589s") "a quoted value keeps its spaces")
        (assert (= (sc/okPerMin w 600) 0.3) "ok per minute over a 600 s window")
        (assert (and (= cfg.min 2) (= cfg.max 9) (= cfg.start 5) (= cfg.softShare 0.5) (= cfg.step dflt.step)) "parseCfg reads given keys and defaults the rest")
        (assert (= dflt.softShare 0.30) "default soft share")
        (assert (= (sc/memFreeMB "MemTotal: 1 kB\nMemAvailable:   12626992 kB\n") 12331) "MemAvailable in MB")
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

; (:m :ref SCHED-BREAKER-COUNT :do "breaker rows are not calls: a provider out for the day has no calls and no pool share; one whose newest row is a breaker weighs 0")
fn ! testBreaker -> Bool
  (let [(lines (listAppend (map (fn [(i Int64)] -> String (call (+ 100000 (* i 1000)) "openrouter" "c" "breaker 31822s" 0)) (range 0 30))
                           (map (fn [(i Int64)] -> String (call (+ 200000 (* i 1000)) "nim" "a" "ok" 5)) (range 0 10))))
        (w (sc/winOf lines 50000 600000))
        (txt (stringJoin (sc/healthRows lines 50000 600000 600) "\n"))
        (reopened (stringJoin (sc/healthRows (listAppend lines (list (call 400000 "openrouter" "c" "ok" 5))) 50000 600000 600) "\n"))]
    (do (assert (and (= w.total 10) (= w.ok 10)) (str "30 breaker rows add no calls: " (stringFromInt64 w.total)))
        (assert (= (sc/rateShare w) 0.0) "breaker rows add no rate share to the pool")
        (assert (stringContains? txt "(:prov openrouter :okPerMin 0.0 :r429PerMin 0.0 :nonOkShare 0.0 :calls 0") (str "openrouter has no calls: " txt))
        (assert (= (sc/okShareOf txt "openrouter") 0.0) (str "a provider whose newest row is a breaker weighs 0: " txt))
        (assert (= (sc/okShareOf txt "nim") 1.0) "a healthy provider keeps full weight")
        (assert (= (sc/okShareOf reopened "openrouter") 1.0) (str "an ok after the breaker reopens it: " reopened))
        true))

fn ! testTick -> Bool
  (let [(dir (scratch "tick"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (cfg (sc/defaultCfg))
        (now 1200000)
        (lines (list (call 700000 "nim" "a" "ok" 1) (call 800000 "nim" "a" "ok" 1) (call 900000 "nim" "a" "ok" 1) (call 1000000 "nim" "a" "ok" 1) (call 300000 "nim" "a" "ok" 1)))
        (n1 (sc/schedTickDisk! dir cfg now lines 8000 2.0 8 (sc/Disk :usedPct 50 :freeMb 90000)))
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

fn dsk pct: Int64 free: Int64 -> sc/Disk
  (sc/Disk :usedPct pct :freeMb free)

fn countOf text: String needle: String -> Int64
  (- (listLength (stringSplit text needle)) 1)

; (:m :ref RES-GUARD :do "df text parsing on fixed macOS and Linux output")
fn ! testDfParse -> Bool
  (let [(mac (sc/parseDf "Filesystem   1024-blocks      Used Available Capacity  Mounted on\n/dev/disk3s5   482797652 363599076  95907420    80%    /System/Volumes/Data\n"))
        (linux (sc/parseDf "Filesystem     1024-blocks      Used Available Capacity Mounted on\n/dev/sda1        103080888  98765432   454000      100% /\n"))
        (spaced (sc/parseDf "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 2048000 1024000 1024000 50% /Volumes/My Disk\n"))
        (junk (sc/parseDf "df: no such file\n"))
        (empty (sc/parseDf ""))
        (real (sc/probeDisk! "."))
        (worst (sc/diskWorst (dsk 50 90000) (dsk 91 2500)))
        (known (sc/diskWorst (sc/unknownDisk) (dsk 40 8000)))]
    (do (assert (and (= mac.usedPct 80) (= mac.freeMb 93659)) (str "macOS df line: " (stringFromInt64 mac.usedPct) " " (stringFromInt64 mac.freeMb)))
        (assert (and (= linux.usedPct 100) (= linux.freeMb 443)) (str "linux df line: " (stringFromInt64 linux.usedPct) " " (stringFromInt64 linux.freeMb)))
        (assert (and (= spaced.usedPct 50) (= spaced.freeMb 1000)) "a mount point with a space still parses the first five fields")
        (assert (and (= junk.usedPct -1) (= junk.freeMb -1) (= empty.usedPct -1)) "unparseable text is unknown")
        (assert (and (>= real.usedPct 0) (<= real.usedPct 100) (> real.freeMb 0)) (str "the real df of the store dir and TMPDIR parses: " (stringFromInt64 real.usedPct) " " (stringFromInt64 real.freeMb)))
        (assert (and (= worst.usedPct 91) (= worst.freeMb 2500)) "the tighter of two filesystems governs")
        (assert (and (= known.usedPct 40) (= known.freeMb 8000)) "an unknown reading yields to a known one")
        true))

; (:m :ref RES-GUARD :do "the level table: 50 percent full slots, 88 half, 95 or free under 2000 MB zero, the edges inclusive, unknown no pressure")
fn ! testDiskLevel -> Bool
  (let [(cfg (sc/defaultCfg))
        (lv (fn [(d sc/Disk)] -> String (sc/diskLevel d cfg)))
        (slots (fn [(d sc/Disk)] -> Int64 (sc/diskSlots 16 (sc/diskLevel d cfg))))
        (tuned (sc/parseCfg "(:sched :diskLowPct 70 :diskStopPct 80 :diskMinFreeMb 500)"))]
    (do (assert (= (slots (dsk 50 90000)) 16) "50 percent: full slots")
        (assert (= (slots (dsk 88 40000)) 8) "88 percent: half")
        (assert (= (slots (dsk 95 40000)) 0) "95 percent: zero")
        (assert (= (slots (dsk 50 2000)) 0) "free 2000 MB at 50 percent: zero")
        (assert (and (= (lv (dsk 84 9000)) "ok") (= (lv (dsk 85 9000)) "low")) "low starts at 85 inclusive")
        (assert (and (= (lv (dsk 92 9000)) "low") (= (lv (dsk 93 9000)) "stop")) "stop starts at 93 inclusive")
        (assert (and (= (lv (dsk 50 3000)) "ok") (= (lv (dsk 50 2999)) "stop")) "free 3000 MB is fine, 2999 stops")
        (assert (= (lv (sc/unknownDisk)) "ok") "an unknown disk is no pressure")
        (assert (= (sc/diskSlots 1 "low") 1) "halving never reaches zero")
        (assert (and (= tuned.diskStopPct 80) (= tuned.diskLowPct 70) (= tuned.diskMinFreeMb 500)) "thresholds come from sched.asn")
        (assert (= (sc/diskLevel (dsk 75 9000) (sc/parseCfg "(:sched :diskLowPct 70 :diskStopPct 80)")) "low") "a configured low threshold applies")
        true))

; (:m :ref RES-GUARD :do "ticks through ok, low, low, stop, stop by free, ok: the effective :n follows the level, the AIMD base is untouched, and the journal gets one (:resource) row per level change")
fn ! testDiskTicks -> Bool
  (let [(dir (scratch "disk"))
        (_ (cleanup dir))
        (_ (dirCreate dir))
        (cfg (sc/defaultCfg))
        (now 1200000)
        (lines (list (call 300000 "nim" "a" "ok" 1) (call 900000 "nim" "a" "ok" 1)))
        (nOk (sc/schedTickDisk! dir cfg now lines 8000 2.0 8 (dsk 50 90000)))
        (j0 (resultOr (fileReadString (str dir "/journal.asn")) ""))
        (nLow (sc/schedTickDisk! dir cfg now lines 8000 2.0 8 (dsk 88 40000)))
        (nLow2 (sc/schedTickDisk! dir cfg now lines 8000 2.0 8 (dsk 89 39000)))
        (j1 (resultOr (fileReadString (str dir "/journal.asn")) ""))
        (nStop (sc/schedTickDisk! dir cfg now lines 8000 2.0 8 (dsk 95 40000)))
        (readStop (pairFirst (sc/slotsRead! dir)))
        (baseStop (sc/baseRead! dir))
        (nStop2 (sc/schedTickDisk! dir cfg now lines 8000 2.0 8 (dsk 50 2000)))
        (j2 (resultOr (fileReadString (str dir "/journal.asn")) ""))
        (nBack (sc/schedTickDisk! dir cfg now lines 8000 2.0 8 (dsk 50 90000)))
        (j3 (resultOr (fileReadString (str dir "/journal.asn")) ""))
        (_ (cleanup dir))]
    (do (assert (= nOk 16) (str "50 percent: full slots: " (stringFromInt64 nOk)))
        (assert (= (countOf j0 "(:resource") 0) (str "a steady ok level journals no resource row: " j0))
        (assert (and (= nLow 8) (= nLow2 8)) (str "88 percent: half: " (stringFromInt64 nLow) " " (stringFromInt64 nLow2)))
        (assert (and (= (countOf j1 "(:resource") 1) (stringContains? j1 "(:resource :level low :disk 88 :free 40000 :at 1200000)")) (str "low is journalled once with its reading: " j1))
        (assert (and (= nStop 0) (= readStop 0)) "95 percent: zero, and the conductor's non-due read of :n sees zero")
        (assert (= baseStop 16) (str "the AIMD base survives a stop: " (stringFromInt64 baseStop)))
        (assert (= nStop2 0) "free 2000 MB: still zero")
        (assert (and (= (countOf j2 "(:resource") 2) (stringContains? j2 "(:resource :level stop :disk 95")) (str "stop journalled once, not again on the second stop reading: " j2))
        (assert (= nBack 16) (str "recovery returns the full slots: " (stringFromInt64 nBack)))
        (assert (and (= (countOf j3 "(:resource") 3) (stringContains? j3 "(:resource :level ok :disk 50 :free 90000")) (str "recovery is journalled: " j3))
        true))

fn ! runTests -> Bool
  (do (assert (testTable) "AIMD table")
      (assert (testWindow) "ledger window and config parse")
      (assert (testHealth) "per provider health")
      (assert (testBreaker) "breaker rows are not calls")
      (assert (testTick) "a persisted tick")
      (assert (testDfParse) "df text parsing")
      (assert (testDiskLevel) "disk level table")
      (assert (testDiskTicks) "disk level in persisted ticks")
      true)
