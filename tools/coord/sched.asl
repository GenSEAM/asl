(module asl-tools/coord/sched
  :x [schedTick! schedTickDisk! slotsDue? slotsRead! baseRead! levelRead! Disk diskLevel diskSlots diskWorst parseDf probeDisk! unknownDisk Cfg Win Stats defaultCfg parseCfg cfgIssues quoted rowAt winOf nextSlots nextFlat okPerMin rateShare nonOkShare healthRows memFreeMB loadOne okShareOf clampF]
  :i [(aslGateway/subPace :a sp) (asl-tools/fleet/run :a fr)])

; (:m :ref SCHED :do "the light pool (Leon write slots, network bound) is bounded by machine resources and grows on goodput, the successful calls per minute of the last ledger window against the one before; a 429 share above softShare never halves the pool, it only holds growth or, when goodput is flat too, steps down by one; the strong reaction to 429 is per provider through the health multiplier of the rotation")
(schema Cfg
  (:f min Int64) (:f max Int64) (:f step Int64) (:f start Int64) (:f gainShare Float64) (:f flatWindows Int64) (:f softShare Float64) (:f minFreeMB Int64) (:f windowSec Int64) (:f diskLowPct Int64) (:f diskStopPct Int64) (:f diskMinFreeMb Int64))

(schema Win
  (:f ok Int64) (:f total Int64) (:f rate Int64) (:f okOut Int64))

; (:m :ref SCHED :do "cur and flat are the persisted state; goodput and prev are ok calls per minute of this and the previous window; freeMB and load are -1.0 when unknown, which blocks growth but is no pressure")
(schema Stats
  (:f goodput Float64) (:f prev Float64) (:f rateShare Float64) (:f freeMB Int64) (:f load Float64) (:f cores Int64) (:f flat Int64))

fn defaultCfg -> Cfg
  (Cfg :min 4 :max 64 :step 2 :start 16 :gainShare 0.05 :flatWindows 3 :softShare 0.30 :minFreeMB 3000 :windowSec 600 :diskLowPct 85 :diskStopPct 93 :diskMinFreeMb 3000)

fn numOr text: String key: String d: Int64 -> Int64
  (optionOr (stringToInt64 (stringTrim (sp/tokAfter text key))) d)

fn floatOr text: String key: String d: Float64 -> Float64
  (optionOr (stringToFloat64 (stringTrim (sp/tokAfter text key))) d)

; (:m :ref SCHED :do "a missing or unreadable file is no config: the caller then keeps today's behaviour, so parseCfg is only called on a present (:sched ...) row")
fn parseCfg text: String -> Cfg
  (let [(d (defaultCfg))
        (raw (rawCfg text))
        (pctOk (and (and (>= raw.diskLowPct 1) (<= raw.diskLowPct 100)) (and (and (>= raw.diskStopPct 1) (<= raw.diskStopPct 100)) (< raw.diskLowPct raw.diskStopPct))))]
    (with (with (with raw :diskLowPct (if pctOk raw.diskLowPct d.diskLowPct))
                :diskStopPct (if pctOk raw.diskStopPct d.diskStopPct))
          :diskMinFreeMb (if (>= raw.diskMinFreeMb 0) raw.diskMinFreeMb d.diskMinFreeMb)))

; (:m :ref RES-GUARD :do "what parseCfg replaced by defaults: the two disk percentages must each be 1..100 with low under stop, else both fall back; a negative diskMinFreeMb falls back; empty when the row is valid")
fn cfgIssues text: String -> (List String)
  (let [(raw (rawCfg text))
        (pctOk (and (and (>= raw.diskLowPct 1) (<= raw.diskLowPct 100)) (and (and (>= raw.diskStopPct 1) (<= raw.diskStopPct 100)) (< raw.diskLowPct raw.diskStopPct))))]
    (listAppend (if pctOk (list) (list ":diskLowPct/:diskStopPct need 1..100 with low under stop, defaults used"))
                (if (>= raw.diskMinFreeMb 0) (list) (list ":diskMinFreeMb must be 0 or more, default used"))))

fn rawCfg text: String -> Cfg
  (let [(d (defaultCfg))]
    (Cfg :min (numOr text ":min" d.min) :max (numOr text ":max" d.max) :step (numOr text ":step" d.step) :start (numOr text ":start" d.start)
         :gainShare (floatOr text ":gainShare" d.gainShare) :flatWindows (numOr text ":flatWindows" d.flatWindows)
         :softShare (floatOr text ":softShare" d.softShare) :minFreeMB (numOr text ":minFreeMB" d.minFreeMB) :windowSec (numOr text ":windowSec" d.windowSec)
         :diskLowPct (numOr text ":diskLowPct" d.diskLowPct) :diskStopPct (numOr text ":diskStopPct" d.diskStopPct) :diskMinFreeMb (numOr text ":diskMinFreeMb" d.diskMinFreeMb)))

fn clampF x: Float64 lo: Float64 hi: Float64 -> Float64
  (if (< x lo) lo (if (> x hi) hi x))

; (:m :ref SCHED :do "the text of a quoted field: the ledger writes outcome values with spaces such as \"breaker 589s\"")
fn quoted line: String key: String -> String
  (match (stringIndexOf line (str key " \""))
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice line (+ i (stringLength key) 2) (stringLength line)) ""))]
        (optionOr (listHead (stringSplit rest "\"")) "")))) 

fn rowAt line: String -> Int64
  (optionOr (stringToInt64 (sp/tokAfter line ":at")) -1)

fn rateOutcome? o: String -> Bool
  (or (= o "429") (= o "throttled"))

; (:m :ref SCHED-BREAKER-COUNT :do "a ledger row the gateway answered itself without a request (open breaker, skipped member, daily cap or pace) is not a call: counting it made a provider out for the day read nonOkShare 1.0 and drag the pool to its floor")
fn notSent? o: String -> Bool
  (or (stringStartsWith? o "breaker") (or (stringStartsWith? o "skipped") (stringStartsWith? o "daily")))

fn callRow? l: String -> Bool
  (and (stringStartsWith? l "(:call ") (not (notSent? (quoted l ":outcome"))))

; (:m :ref SCHED-BREAKER-COUNT :do "a provider whose newest ledger row in the window is an open breaker is out until it closes")
fn breakerOpen? rows: (List String) -> Bool
  (match (listHead (listReverse rows))
    ((none) false)
    ((some l) (stringStartsWith? (quoted l ":outcome") "breaker")))

; (:m :ref SCHED :do "counts the calls with fromMs <= at < toMs: ok, all, rate-limited (429 or the local throttle) and the output tokens of the ok ones")
fn winOf lines: (List String) fromMs: Int64 toMs: Int64 -> Win
  (fold (fn [(w Win) (l String)] -> Win
          (let [(at (rowAt l))]
            (if (and (>= at fromMs) (< at toMs))
              (let [(o (quoted l ":outcome"))
                    (isOk (= o "ok"))]
                (Win :ok (+ w.ok (if isOk 1 0)) :total (+ w.total 1) :rate (+ w.rate (if (rateOutcome? o) 1 0))
                     :okOut (+ w.okOut (if isOk (optionOr (stringToInt64 (sp/tokAfter l ":out")) 0) 0))))
              w)))
        (Win :ok 0 :total 0 :rate 0 :okOut 0) (filter callRow? lines))

fn okPerMin w: Win windowSec: Int64 -> Float64
  (/ (int64ToFloat64 w.ok) (/ (int64ToFloat64 (max 1 windowSec)) 60.0))

fn rateShare w: Win -> Float64
  (if (<= w.total 0) 0.0 (/ (int64ToFloat64 w.rate) (int64ToFloat64 w.total)))

fn nonOkShare w: Win -> Float64
  (if (<= w.total 0) 0.0 (/ (int64ToFloat64 (- w.total w.ok)) (int64ToFloat64 w.total)))

fn rose? s: Stats cfg: Cfg -> Bool
  (if (<= s.prev 0.0) (> s.goodput 0.0) (> s.goodput (* s.prev (+ 1.0 cfg.gainShare))))

fn pressure? s: Stats cfg: Cfg -> Bool
  (or (and (>= s.freeMB 0) (< s.freeMB cfg.minFreeMB)) (and (>= s.load 0.0) (> s.load (* 1.5 (int64ToFloat64 s.cores)))))

; (:m :ref SCHED :do "one step per window, never more than one down: RAM or load pressure steps down by one; a rate share above softShare holds when goodput rose and steps down by one when it is flat; healthy growth adds step only with known free RAM above the floor and load under the cores; otherwise hold")
fn nextSlots cur: Int64 s: Stats cfg: Cfg -> Int64
  (let [(up (rose? s cfg))
        (down1 (max cfg.min (- cur 1)))
        (n (cond
             ((pressure? s cfg) down1)
             ((> s.rateShare cfg.softShare) (if up cur down1))
             ((and up (and (> s.freeMB cfg.minFreeMB) (and (>= s.load 0.0) (< s.load (int64ToFloat64 s.cores))))) (min cfg.max (+ cur cfg.step)))
             (else cur)))]
    (max cfg.min (min cfg.max n)))

; (:m :ref SCHED :do "consecutive windows without a goodput rise; flatWindows of them is the stable plateau the journal shows")
fn nextFlat s: Stats cfg: Cfg -> Int64
  (if (rose? s cfg) 0 (+ s.flat 1))

; (:m :ref SCHED :do "MemAvailable of /proc/meminfo in MB, -1 when the file is absent (macOS): unknown blocks growth")
fn memFreeMB text: String -> Int64
  (match (stringIndexOf text "MemAvailable:")
    ((none) -1)
    ((some i)
      (let [(rest (stringTrim (optionOr (stringSlice text (+ i 13) (stringLength text)) "")))
            (kb (optionOr (stringToInt64 (optionOr (listHead (stringSplit rest " ")) "")) -1))]
        (if (< kb 0) -1 (/ kb 1024)))))

fn loadOne text: String -> Float64
  (optionOr (stringToFloat64 (optionOr (listHead (stringSplit (stringTrim text) " ")) "")) -1.0)

; (:m :ref SCHED :do "per provider and per alias over one window: ok/min, 429/min (429 or local throttle), non-ok share, and where the provider limits: account when every alias seen at the provider was rate limited, model when only some were, none when none")
fn healthRows lines: (List String) fromMs: Int64 toMs: Int64 windowSec: Int64 -> (List String)
  (let [(inWin (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:call ") (and (>= (rowAt l) fromMs) (< (rowAt l) toMs)))) lines))
        (calls (filter callRow? inWin))
        (provs (uniq (map (fn [(l String)] -> String (quoted l ":provider")) inWin)))
        (mins (/ (int64ToFloat64 (max 1 windowSec)) 60.0))
        (f (fn [(x Float64)] -> String (stringFromFloat64 (/ (int64ToFloat64 (optionOr (float64ToInt64 (* x 100.0)) 0)) 100.0))))
        (row (fn [(kind String) (name String) (ls (List String))] -> String
               (let [(w (winOf ls fromMs toMs))]
                 (str "(:" kind " " name " :okPerMin " (f (/ (int64ToFloat64 w.ok) mins)) " :r429PerMin " (f (/ (int64ToFloat64 w.rate) mins)) " :nonOkShare " (f (nonOkShare w)) " :calls " (stringFromInt64 w.total)))))]
    (concatAll (fn [(p String)] -> (List String)
               (let [(mine (filter (fn [(l String)] -> Bool (= (quoted l ":provider") p)) calls))
                     (aliases (uniq (map (fn [(l String)] -> String (quoted l ":alias")) mine)))
                     (limited (filter (fn [(a String)] -> Bool (listAny? (fn [(l String)] -> Bool (and (= (quoted l ":alias") a) (rateOutcome? (quoted l ":outcome")))) mine)) aliases))
                     (scope (cond ((= (listLength limited) 0) "none") ((and (> (listLength aliases) 1) (= (listLength limited) (listLength aliases))) "account") ((= (listLength aliases) 1) "unknown") (else "model")))]
                 (cons (str (row "prov" p mine) " :aliases " (stringFromInt64 (listLength aliases)) " :limit " scope (if (breakerOpen? (filter (fn [(l String)] -> Bool (= (quoted l ":provider") p)) inWin)) " :open true" "") ")")
                       (map (fn [(a String)] -> String (str (row "alias" a (filter (fn [(l String)] -> Bool (= (quoted l ":alias") a)) mine)) ")")) aliases))))
             provs))

; (:m :ref SCHED :do "the health multiplier input: ok share of a provider in its health row, 1.0 when the row is absent, so a provider without data keeps its full weight")
fn okShareOf health: String prov: String -> Float64
  (match (listFind (fn [(l String)] -> Bool (stringStartsWith? l (str "(:prov " prov " "))) (stringLines health))
    ((none) 1.0)
    ((some l) (if (stringContains? l ":open true") 0.0 (clampF (- 1.0 (floatOr l ":nonOkShare" 0.0)) 0.2 1.0))))

fn uniq xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn concatAll f: (fn [String] -> (List String)) xs: (List String) -> (List String)
  (fold (fn [(acc (List String)) (x String)] -> (List String) (listAppend acc (f x))) (list) xs)

; (:m :ref RES-GUARD :do "a disk reading: used percent and free MB of one filesystem, both -1 when unknown; unknown is no pressure, like unknown RAM")
(schema Disk
  (:f usedPct Int64) (:f freeMb Int64))

fn unknownDisk -> Disk
  (Disk :usedPct -1 :freeMb -1)

; (:m :ref RES-GUARD :do "df -Pk text to a Disk: the last non-empty line, fields Filesystem 1024-blocks Used Available Capacity Mounted, located from the right: the last field ending in a percent sign is Capacity and the one before it Available, so a filesystem name or mount point with spaces parses; free is Available in MB, used is the Capacity percent; anything unparseable is unknown")
fn parseDf text: String -> Disk
  (let [(lines (filter (fn [(l String)] -> Bool (not (stringEmpty? (stringTrim l)))) (stringLines text)))
        (f (match (listLast lines)
             ((none) (list))
             ((some l) (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringTrim l) " ")))))
        (pi (fold (fn [(acc Int64) (i Int64)] -> Int64 (if (stringEndsWith? (optionOr (listGet f i) "") "%") i acc)) -1 (range 0 (listLength f))))
        (kb (if (< pi 1) -1 (optionOr (stringToInt64 (optionOr (listGet f (- pi 1)) "")) -1)))
        (pct (if (< pi 1) -1 (optionOr (stringToInt64 (stringReplace (optionOr (listGet f pi) "") "%" "")) -1)))]
    (if (or (< pi 3) (or (< kb 0) (or (< pct 0) (> pct 100))))
      (unknownDisk)
      (Disk :usedPct pct :freeMb (/ kb 1024))))

; (:m :ref RES-GUARD :do "of two readings the tighter one: the higher used percent and the lower free MB, an unknown field yielding to a known one; the store home and TMPDIR may be two filesystems and the worse one governs")
fn diskWorst a: Disk b: Disk -> Disk
  (Disk :usedPct (max a.usedPct b.usedPct)
        :freeMb (cond ((< a.freeMb 0) b.freeMb) ((< b.freeMb 0) a.freeMb) (else (min a.freeMb b.freeMb))))

; (:m :ref RES-GUARD :do "ok, low or stop: stop at or above diskStopPct or with free under diskMinFreeMb, low at or above diskLowPct; unknown readings never raise a level")
fn diskLevel d: Disk cfg: Cfg -> String
  (cond
    ((or (>= d.usedPct cfg.diskStopPct) (and (>= d.freeMb 0) (< d.freeMb cfg.diskMinFreeMb))) "stop")
    ((>= d.usedPct cfg.diskLowPct) "low")
    (else "ok"))

; (:m :ref RES-GUARD :do "the slots a level allows over the AIMD base: ok keeps it, low halves it (at least 1), stop is 0 so no new claim (ready to writing) starts while in-flight work continues; gating and review launches are not gated by the slots today")
fn diskSlots base: Int64 level: String -> Int64
  (cond
    ((= level "stop") 0)
    ((= level "low") (max 1 (/ base 2)))
    (else base))

; (:m :ref RES-GUARD :do "df -Pk of one path through fr/runOneLimited, no shell; a failing df is unknown")
fn ! dfOf! path: String -> Disk
  (let [(d (fr/runOneLimited (fr/job (list "/bin/df" "-Pk" path) "." (fr/childEnv (list))) (fr/limits 20 8)))]
    (if (= d.exit 0) (parseDf d.out) (unknownDisk)))

; (:m :ref RES-GUARD :do "the filesystems that fill: the one holding the store dir and the one holding TMPDIR (/tmp when unset); the worse reading governs")
fn ! probeDisk! dir: String -> Disk
  (diskWorst (dfOf! (if (stringEmpty? dir) "." dir)) (dfOf! (optionOr (envGet "TMPDIR") "/tmp")))

fn slotsPath dir: String -> String
  (str dir "/slots.asn")

; (:m :ref SCHED :do "the persisted light-pool state: n slots, flat windows, at ms of the last sample; n is -1 when the store has none yet")
fn ! slotsRead! dir: String -> (Pair Int64 (Pair Int64 Int64))
  (let [(t (resultOr (fileReadString (slotsPath dir)) ""))]
    (if (stringEmpty? t)
      (pair -1 (pair 0 0))
      (pair (numOr t ":n" -1) (pair (numOr t ":flat" 0) (numOr t ":at" 0)))))

; (:m :ref RES-GUARD :do "slots.asn keeps :n, the effective count the conductor reads, and :base, the AIMD value the disk level scales; a file without :base (older) has base = n")
fn ! baseRead! dir: String -> Int64
  (let [(t (resultOr (fileReadString (slotsPath dir)) ""))]
    (numOr t ":base" (numOr t ":n" -1)))

fn ! levelRead! dir: String -> String
  (let [(l (sp/tokAfter (resultOr (fileReadString (slotsPath dir)) "") ":level"))]
    (if (stringEmpty? l) "ok" l))

fn ! slotsDue? dir: String now: Int64 periodMs: Int64 -> Bool
  (let [(s (slotsRead! dir))]
    (or (< (pairFirst s) 0) (>= (- now (pairSecond (pairSecond s))) periodMs)))

; (:m :ref SCHED :do "one sample: the ledger lines of the last two windows give goodput and the 429 share, nextSlots moves the persisted value, a change is journalled as (:slots :n :goodput :prev :freeMB :load), and the per provider health file is rewritten at most once per window; returns the new slot count")
fn ! schedTick! dir: String cfg: Cfg now: Int64 lines: (List String) freeMB: Int64 load: Float64 cores: Int64 -> Int64
  (schedTickDisk! dir cfg now lines freeMB load cores (probeDisk! dir))

; (:m :ref RES-GUARD :do "the tick with the disk reading passed in: the AIMD base moves as before; the level of the disk scales it into the effective :n (ok full, low half, stop 0) and recovery is the next sample under the thresholds; only a level change is journalled, as (:resource :level :disk :free :at), so a steady level writes nothing; returns the effective count")
fn ! schedTickDisk! dir: String cfg: Cfg now: Int64 lines: (List String) freeMB: Int64 load: Float64 cores: Int64 disk: Disk -> Int64
  (let [(prior (slotsRead! dir))
        (prevBase (baseRead! dir))
        (prevLevel (levelRead! dir))
        (cur (if (< prevBase 0) cfg.start prevBase))
        (w (* cfg.windowSec 1000))
        (w1 (winOf lines (- now w) now))
        (w0 (winOf lines (- now (* 2 w)) (- now w)))
        (s (Stats :goodput (okPerMin w1 cfg.windowSec) :prev (okPerMin w0 cfg.windowSec) :rateShare (rateShare w1) :freeMB freeMB :load load :cores cores :flat (pairFirst (pairSecond prior))))
        (base (nextSlots cur s cfg))
        (level (diskLevel disk cfg))
        (n (diskSlots base level))
        (flat (nextFlat s cfg))
        (_ (fileWrite (slotsPath dir) (str "(:slots :n " (stringFromInt64 n) " :base " (stringFromInt64 base) " :level " level " :flat " (stringFromInt64 flat) " :at " (stringFromInt64 now) ")\n")))
        (_ (if (!= level prevLevel)
             (fileAppend (str dir "/journal.asn")
               (str "(:resource :level " level " :disk " (stringFromInt64 disk.usedPct) " :free " (stringFromInt64 disk.freeMb) " :at " (stringFromInt64 now) ")\n"))
             (ok ())))
        (_ (if (or (!= base cur) (< prevBase 0))
             (fileAppend (str dir "/journal.asn")
               (str "(:slots :n " (stringFromInt64 n) " :goodput " (stringFromFloat64 s.goodput) " :prev " (stringFromFloat64 s.prev) " :nonOk " (stringFromFloat64 s.rateShare) " :freeMB " (stringFromInt64 freeMB) " :load " (stringFromFloat64 load) " :at " (stringFromInt64 now) ")\n"))
             (ok ())))
        (hpath (str dir "/providerHealth.asn"))
        (hold (resultOr (fileReadString hpath) ""))
        (hat (numOr (optionOr (listHead (stringLines hold)) "") ":at" 0))
        (_ (if (>= (- now hat) w)
             (fileWrite hpath (str "(:health :at " (stringFromInt64 now) " :windowSec " (stringFromInt64 cfg.windowSec) ")\n" (stringJoin (healthRows lines (- now w) now cfg.windowSec) "\n") "\n"))
             (ok ())))]
    n)
