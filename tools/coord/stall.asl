(module asl-tools/coord/stall
  :x [Cfg Probe Signal Act Hooks stRowOf cfgOf cfgErrors replyRows sameTrail emptyTrail servedCount opText signalFrom verdictOf stallCount actOf stallRow statMs newestWrite! signalOf! sweep! stallsPath atPath]
  :i [])

; (:m :ref COND-STALL-AUTO :do "automatic stall handling for writing units: per unit a Signal (newest journal mtime, newest file write outside .asl, trailing identical-reply streak, trailing empty-reply streak, pid alive), a verdict ok|stalled|looping|dead from the (:stall ...) row of <store>/ladder.asn, and an Act (kill the run record's tree, requeue with an ASN note, escalate to the strong lane after :escalateAfter stalls); no valid row means no sweep, today's behaviour. The conductor owns the hooks, this module owns the decision and the rows")

(schema Cfg
  (:f on Bool) (:f stalledMin Int64) (:f sameOp Int64) (:f emptyReplies Int64) (:f escalateAfter Int64) (:f everyS Int64))

(schema Probe
  (:f id String) (:f lane String) (:f wt String) (:f alive Bool) (:f sinceMs Int64))

(schema Signal
  (:f served Int64) (:f sameOp Int64) (:f emptyRun Int64) (:f lastOp String) (:f turnAgeMs Int64) (:f writeAgeMs Int64) (:f alive Bool))

(schema Act
  (:f class String) (:f lane String) (:f note String))

(schema Hooks
  (:f kill (fn ! [String] -> Unit))
  (:f requeue (fn ! [String String String] -> Unit)))

fn stallsPath dir: String -> String
  (str dir "/stalls.asn")

fn atPath dir: String -> String
  (str dir "/stallAt.asn")

fn ! readOr path: String -> String
  (match (fileReadString path) ((ok t) t) ((err _) ""))

fn stRowOf text: String -> String
  (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "(:stall ")) (stringLines text)) "")

fn intAfter row: String key: String dflt: Int64 -> Int64
  (match (listGet (stringSplit row (str key " ")) 1)
    ((none) dflt)
    ((some rest) (optionOr (stringToInt64 (stringReplace (optionOr (listHead (stringSplit (stringTrim rest) " ")) "") ")" "")) dflt)))

; (:m :ref COND-STALL-AUTO :do "ranges, all adopted defaults: stalledMin 20 (1..1440; a served turn took 48 s at p50, 396 s at p99, 534 s max over 662 node2 sessions), sameOp 10 (3..1000; 34 of 708 journals repeated one reply 10 or more times in a row, most legitimate repeats of gate and read stop at 5), emptyReplies 4 (1..100), escalateAfter 2 (1..20), everyS 60 (5..3600)")
fn cfgErrors row: String -> (List String)
  (let [(keys (filter (fn [(t String)] -> Bool (stringStartsWith? t ":")) (stringSplit row " ")))
        (bad (filter (fn [(k String)] -> Bool (not (listContains? (list ":stalledMin" ":sameOp" ":emptyReplies" ":escalateAfter" ":everyS") k))) keys))
        (ranged (fn [(key String) (dflt Int64) (lo Int64) (hi Int64)] -> (List String)
                  (let [(v (intAfter row key dflt))]
                    (if (or (< v lo) (> v hi)) (list (str key " " (stringFromInt64 v) " outside " (stringFromInt64 lo) ".." (stringFromInt64 hi))) (list)))))]
    (flatten (list (map (fn [(k String)] -> String (str "unknown key " k)) bad)
                      (ranged ":stalledMin" 20 1 1440) (ranged ":sameOp" 10 3 1000) (ranged ":emptyReplies" 4 1 100)
                      (ranged ":escalateAfter" 2 1 20) (ranged ":everyS" 60 5 3600))))

fn flatten xss: (List (List String)) -> (List String)
  (fold (fn [(acc (List String)) (xs (List String))] -> (List String) (listAppend acc xs)) (list) xss)

fn cfgOf row: String -> Cfg
  (if (or (stringEmpty? row) (not (listEmpty? (cfgErrors row))))
    (Cfg :on false :stalledMin 20 :sameOp 10 :emptyReplies 4 :escalateAfter 2 :everyS 60)
    (Cfg :on true :stalledMin (intAfter row ":stalledMin" 20) :sameOp (intAfter row ":sameOp" 10) :emptyReplies (intAfter row ":emptyReplies" 4)
         :escalateAfter (intAfter row ":escalateAfter" 2) :everyS (intAfter row ":everyS" 60)))

; (:m :ref COND-STALL-AUTO :do "a reply row is one line (:turn N :reply \"...\"); the reply text is everything after :reply, so an op with its arguments is one signature")
fn replyRows journal: String -> (List String)
  (map (fn [(l String)] -> String (unwrap (optionOr (listGet (stringSplit l " :reply ") 1) "")))
       (filter (fn [(l String)] -> Bool (and (stringStartsWith? l "(:turn ") (stringContains? l " :reply "))) (stringLines journal)))

fn unwrap r: String -> String
  (let [(a (if (stringStartsWith? r "\"") (optionOr (stringSlice r 1 (stringLength r)) r) r))]
    (if (stringEndsWith? a "\")") (optionOr (stringSlice a 0 (- (stringLength a) 2)) a) a))

fn trailWhile xs: (List String) ok: (fn [String] -> Bool) -> Int64
  (match (listLast xs)
    ((none) 0)
    ((some _) (let [(rev (listReverse xs))
                    (k (fold (fn [(acc (Pair Bool Int64)) (x String)] -> (Pair Bool Int64)
                               (if (and (pairFirst acc) (ok x)) (pair true (+ (pairSecond acc) 1)) (pair false (pairSecond acc))))
                             (pair true 0) rev))]
                (pairSecond k))))

fn sameTrail replies: (List String) -> Int64
  (match (listLast replies)
    ((none) 0)
    ((some last) (if (stringEmpty? (emptyKey last)) 0 (trailWhile replies (fn [(x String)] -> Bool (= x last))))))

fn emptyKey r: String -> String
  (stringTrim r)

fn emptyTrail replies: (List String) -> Int64
  (trailWhile replies (fn [(x String)] -> Bool (stringEmpty? (emptyKey x))))

fn servedCount journal: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:served :turn ")) (stringLines journal)))

; (:m :ref COND-STALL-AUTO :do "the op text for the note: the reply cut to 100 bytes with quotes, backslashes and parens replaced so it stays inside one quoted ASN string")
fn opText reply: String -> String
  (let [(clean (stringReplace (stringReplace (stringReplace (stringReplace reply "\\" "") "\"" "'") "(" "<") ")" ">"))]
    (optionOr (stringSlice clean 0 (min 100 (stringLength clean))) ""))

fn signalFrom journal: String turnAgeMs: Int64 writeAgeMs: Int64 alive: Bool -> Signal
  (let [(rs (replyRows journal))]
    (Signal :served (servedCount journal) :sameOp (sameTrail rs) :emptyRun (emptyTrail rs) :lastOp (opText (optionOr (listLast rs) ""))
            :turnAgeMs turnAgeMs :writeAgeMs writeAgeMs :alive alive))

; (:m :ref COND-STALL-AUTO :do "dead beats looping beats stalled: a gone pid ends the unit at once, a loop is judged on the reply trail whatever the clock says, and a unit is stalled only when both the newest turn and the newest file write are older than stalledMin")
fn verdictOf cfg: Cfg s: Signal -> String
  (cond
    ((not s.alive) "dead")
    ((>= s.sameOp cfg.sameOp) "looping")
    ((>= s.emptyRun cfg.emptyReplies) "looping")
    ((and (> s.turnAgeMs (* cfg.stalledMin 60000)) (> s.writeAgeMs (* cfg.stalledMin 60000))) "stalled")
    (else "ok"))

fn stallCount rows: String id: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "(:stall :unit \"" id "\" "))) (stringLines rows)))

fn actOf cfg: Cfg prior: Int64 class: String op: String -> Act
  (Act :class class
       :lane (if (>= (+ prior 1) cfg.escalateAfter) "strong" "")
       :note (str "(:stall :class " class " :n " (stringFromInt64 (+ prior 1)) " :op \"" op "\") the previous attempt on this unit was cut for this; change the approach instead of repeating that op"))

fn stallRow id: String class: String op: String lane: String now: Int64 -> String
  (str "(:stall :unit \"" id "\" :class " class " :op \"" op "\" :escalate \"" lane "\" :at " (stringFromInt64 now) ")")

fn ! statMs path: String -> Int64
  (match (fileStat path) ((ok st) (/ st.mtimeNs 1000000)) ((err _) 0))

fn skipDir? name: String -> Bool
  (listContains? (list ".git" ".asl" "node_modules" "out") name)

; (:m :ref COND-STALL-AUTO :do "newest file mtime under wt, skipping .git .asl node_modules out; the walk returns (newest . entries left) and stops at 40000 entries, so a huge tree costs a bounded walk")
fn ! newestWrite! wt: String -> Int64
  (pairFirst (walkNewest! wt 0 40000))

fn ! walkNewest! path: String depth: Int64 budget: Int64 -> (Pair Int64 Int64)
  (if (or (> depth 14) (<= budget 0)) (pair 0 budget)
    (match (fileStat path)
      ((err _) (pair 0 (- budget 1)))
      ((ok st)
        (if (not st.isDir) (pair (/ st.mtimeNs 1000000) (- budget 1))
          (match (dirList path)
            ((err _) (pair 0 (- budget 1)))
            ((ok names)
              (fold (fn [(acc (Pair Int64 Int64)) (nm String)] -> (Pair Int64 Int64)
                      (if (skipDir? nm) acc
                        (let [(r (walkNewest! (str path "/" nm) (+ depth 1) (pairSecond acc)))]
                          (pair (max (pairFirst acc) (pairFirst r)) (pairSecond r)))))
                    (pair 0 (- budget 1)) names)))))))

; (:m :ref COND-STALL-AUTO :do "only journals written since the current admit (mtime >= sinceMs) count: a requeued unit reuses its worktree, and the previous session's looping journal re-tripped the probe at once (AUDIT-META-ROUTE, 3 times at 60 s)")
fn ! newestJournal! wt: String since: Int64 -> (Pair Int64 String)
  (let [(jd (str wt "/.asl/run/agentLoop"))
        (names (filter (fn [(f String)] -> Bool (stringEndsWith? f ".journal")) (resultOr (dirList jd) (list))))
        (best (fold (fn [(acc (Pair Int64 String)) (f String)] -> (Pair Int64 String)
                      (let [(m (statMs (str jd "/" f)))] (if (and (>= m since) (> m (pairFirst acc))) (pair m f) acc)))
                    (pair 0 "") names))]
    (if (stringEmpty? (pairSecond best)) (pair 0 "") (pair (pairFirst best) (readOr (str jd "/" (pairSecond best))))))

fn ! signalOf! cfg: Cfg p: Probe now: Int64 -> Signal
  (let [(j (newestJournal! p.wt p.sinceMs))
        (turnAt (max (pairFirst j) p.sinceMs))
        (turnAge (- now turnAt))
        (writeAge (if (> turnAge (* cfg.stalledMin 60000)) (- now (max (newestWrite! p.wt) p.sinceMs)) 0))]
    (signalFrom (pairSecond j) turnAge writeAge p.alive))

; (:m :ref COND-STALL-AUTO :do "one pass over the writing units: at most once per :everyS, each non-ok unit gets one (:stall :unit :class :op :escalate :at) row in <store>/stalls.asn, its tree killed through the hook (the conductor kills only from the run record) and the unit requeued with the note; the Nth stall of one unit (:escalateAfter) sends it to the strong lane")
fn ! sweep! dir: String now: Int64 probes: (List Probe) hooks: Hooks -> (List String)
  (let [(cfg (cfgOf (stRowOf (readOr (str dir "/ladder.asn")))))
        (last (optionOr (stringToInt64 (stringTrim (readOr (atPath dir)))) 0))]
    (if (or (not cfg.on) (listEmpty? probes) (< (- now last) (* cfg.everyS 1000))) (list)
      (let [(_ (fileWrite (atPath dir) (str (stringFromInt64 now) "\n")))]
        (fold (fn [(acc (List String)) (p Probe)] -> (List String)
                (let [(s (signalOf! cfg p now))
                      (v (verdictOf cfg s))]
                  (if (= v "ok") acc
                    (let [(a (actOf cfg (stallCount (readOr (stallsPath dir)) p.id) v s.lastOp))
                          (row (stallRow p.id v s.lastOp a.lane now))
                          (_ (fileAppend (stallsPath dir) (str row "\n")))
                          (k hooks.kill)
                          (_ (k p.id))
                          (rq hooks.requeue)
                          (_ (rq p.id (if (stringEmpty? a.lane) p.lane a.lane) a.note))]
                      (listAppend acc (list row))))))
              (list) probes))))
