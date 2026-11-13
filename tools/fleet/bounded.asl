(module asl/tools/fleet/bounded
  :x [main parseArgs Parsed receiptLine minSecs]
  :i [(asl-tools/fleet/run :a fr)])

; (:m :ref WATCHDOG-GROUP-KILL :do "the one-line bounded runner for briefs and reruns: bin/asl run asl/tools/fleet/bounded.asl SECS [--max-desc N] [--receipt FILE] -- CMD ARGV...; the command runs as one fleet/run.asl child, and at SECS its whole process tree and groups are killed (a timeout verdict note is printed, exit 124); otherwise its output is printed whole and its exit code is returned; a perl alarm or a bare timeout kills only the direct child and leaves bin/asl descendants running")

(schema Parsed
  (:f secs Int64)
  (:f maxDesc Int64)
  (:f receipt String)
  (:f argv (List String))
  (:f error String))

fn usage -> String
  "usage: bin/asl run asl/tools/fleet/bounded.asl SECS [--max-desc N] [--receipt FILE] -- CMD ARGV..."

; (:m :do "SECS first (a positive integer), then the options --max-desc N (default 64) and --receipt FILE in any order, then -- and the command; a missing separator, a non-positive SECS, an option without its value or an empty command is an error text, never a run")
fn optionsOf rest: (List String) maxDesc: Int64 receipt: String bad: String -> Parsed
  (let [(flag (optionOr (listHead rest) ""))
        (value (optionOr (listGet rest 1) ""))
        (hasValue (and (>= (listLength rest) 2) (not (= value "--"))))]
    (cond
      ((and (= flag "--max-desc") hasValue) (optionsOf (listDrop rest 2) (optionOr (stringToInt64 value) 0) receipt bad))
      ((and (= flag "--receipt") hasValue) (optionsOf (listDrop rest 2) maxDesc value bad))
      ((or (= flag "--max-desc") (= flag "--receipt")) (Parsed :secs 0 :maxDesc maxDesc :receipt receipt :argv (list) :error (str flag " needs a value")))
      (else (let [(sepOk (= flag "--"))]
              (Parsed :secs 0 :maxDesc maxDesc :receipt receipt :argv (if sepOk (optionOr (listTail rest) (list)) (list))
                      :error (if sepOk bad "the command must follow --"))))))

fn parseArgs args: (List String) -> Parsed
  (let [(secs (optionOr (stringToInt64 (optionOr (listHead args) "")) 0))
        (o (optionsOf (optionOr (listTail args) (list)) 64 "" ""))]
    (Parsed :secs secs :maxDesc o.maxDesc :receipt o.receipt :argv o.argv
            :error (cond ((<= secs 0) "SECS must be a positive integer")
                         ((not (stringEmpty? o.error)) o.error)
                         ((<= o.maxDesc 0) "--max-desc must be a positive integer")
                         ((listEmpty? o.argv) "the command is empty")
                         (else ""))))

fn quoted s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

; (:m :ref BOUNDED-MIN-SECS-DOC :do "the smallest SECS that leaves the command time under load: since BOUNDED-WALL-INCLUDES-BUILD the launch (exec, a ps for its age, the sentinel fork with its lease reap) counts toward SECS, measured 1.1 to 2.2 s warm at load 96 and past 3 s under heavier load (BOUNDED-PIDS-FLAKE, 2026-11-13); a smaller SECS still runs, with a warning on stderr and :warn :secsUnderMin in the receipt; adopted")
fn minSecs -> Int64
  10

; (:m :ref LEON-TIMEOUT-NO-RECEIPT :do "the one ASN line --receipt FILE gains on every stop of the command, an exit, a timeout or a runaway kill: the verdict, exit code, SECS, run time and the command's first word, never its arguments or environment, so a run the bound killed before it wrote its own receipt still leaves one")
fn receiptLine verdict: String exit: Int64 secs: Int64 ms: Int64 argv: (List String) -> String
  (str "(:bounded :verdict :" verdict " :exit " (stringFromInt64 exit) " :secs " (stringFromInt64 secs) " :ms " (stringFromInt64 ms)
       (if (< secs (minSecs)) " :warn :secsUnderMin" "") " :cmd " (quoted (optionOr (listHead argv) "")) ")\n")

; (:m :ref BOUNDED-WALL-INCLUDES-BUILD :do "ms since this process was forked, from its own ps etime (1 s steps, rounded down; 0 when unknown): bin/asl and its native CLI exec into the run binary, so the pid that sh forked for bin/asl run bounded.asl is this one and its age holds the cold build of bounded.asl and of anything it imports, measured as 3124 s wall under a 900 s bound at load 190-220, 2026-11-13")
fn ! launchMs! -> Int64
  (let [(self (procSelf))
        (row (listHead (filter (fn [(p fr/Proc)] -> Bool (= p.pid self)) (fr/procSnapshot))))]
    (match row
      ((some p) (if (> p.age 0) (* p.age 1000) 0))
      ((none) 0)))

; (:m :ref BOUNDED-LAUNCHER-GROUP :do "the command's group leader: the oldest direct child of the launcher that leads its own group (fleet/run.asl spawns the command so), never the sentinel; the launcher's own short ps children lead their groups too (seen: the sentinel held a ps pid and the command survived), and they are younger than the command at every sample after it starts; 0 when none shows")
fn childOf snap: (List fr/Proc) launcher: Int64 sentinel: Int64 -> Int64
  (pairFirst (fold (fn [(best (Pair Int64 Int64)) (p fr/Proc)] -> (Pair Int64 Int64) (if (> p.age (pairSecond best)) (pair p.pid p.age) best))
               (pair 0 -2) (filter (fn [(p fr/Proc)] -> Bool (and (= p.ppid launcher) (and (= p.pgid p.pid) (not (= p.pid sentinel))))) snap)))

; (:m :ref BOUNDED-LAUNCHER-GROUP :do "the launcher is gone when its pid answers no signal, or when a snapshot shows the sentinel no longer its child (a killed launcher left as a zombie still answers kill 0, its orphans are reparented at once); an empty snapshot (ps failed) proves nothing")
fn launcherGone? alive: Bool snap: (List fr/Proc) launcher: Int64 sentinel: Int64 -> Bool
  (or (not alive)
      (and (not (listEmpty? snap))
           (not (listAny? (fn [(p fr/Proc)] -> Bool (and (= p.pid sentinel) (= p.ppid launcher))) snap))))

; (:m :ref BOUNDED-STALE-PID :do "the start second (wall clock less ps age) of pid in snap, -1 when it is not there or not its own group leader any more")
fn bornOf snap: (List fr/Proc) pid: Int64 wallSec: Int64 -> Int64
  (optionOr (optionMap (fn [(p fr/Proc)] -> Int64 (- wallSec p.age)) (listHead (filter (fn [(p fr/Proc)] -> Bool (and (= p.pid pid) (and (= p.pgid pid) (>= p.age 0)))) snap))) -1)

; (:m :ref BOUNDED-STALE-PID :do "the remembered command is killed only if the last snapshot still shows that pid leading its own group with the start second it had when first seen (2 s ps slack plus the longer of the two ps runs: the wall is read before each ps, so ps ages place a start at most one ps run early, and a slow ps at kill time no longer refuses the real command (BOUNDED-SENTINEL-PS-LATENCY)): a command that ended before its launcher died leaves a pid the kernel may have handed to anything")
fn sameCommand? snap: (List fr/Proc) pid: Int64 born: Int64 wallSec: Int64 slack: Int64 -> Bool
  (let [(now (bornOf snap pid wallSec))
        (d (- now born))]
    (and (> pid 0) (and (>= born 0) (and (>= now 0) (<= (if (< d 0) (- 0 d) d) (+ 2 slack))))))

; (:m :ref BOUNDED-LAUNCHER-GROUP :do "the sentinel's loop: every 250 ms a kill-0 probe of the launcher, a snapshot every tick until the command shows and every 4th tick after, each naming the oldest candidate; once the launcher is gone the command's whole tree is killed and the sentinel ends; it ends on its own at deadlineNs, as nobody judges it when the launcher is dead")
fn ! watch! launcher: Int64 sentinel: Int64 child: Int64 born: Int64 bornDur: Int64 deadlineNs: Int64 tick: Int64 -> Int64
  (if (> (monotonicNs) deadlineNs) 0
    (let [(alive (resultOr (procAlive? launcher) false))
          (wall (/ (nowNs) 1000000000))
          (snap (if (or (not alive) (or (= child 0) (= (mod tick 4) 0))) (fr/procSnapshot) (list)))
          (dur (- (/ (nowNs) 1000000000) wall))
          (seen (childOf snap launcher sentinel))
          (c (if (> seen 0) seen child))
          (cBorn (if (> seen 0) (bornOf snap seen wall) born))
          (cDur (if (> seen 0) dur bornDur))]
      (if (launcherGone? alive snap launcher sentinel)
        (if (sameCommand? snap c cBorn wall (max dur cDur)) (do (fr/killTree! c) 1) 0)
        (do (sleepMs 250) (watch! launcher sentinel c cBorn cDur deadlineNs (+ tick 1))))))

; (:m :ref BOUNDED-LAUNCHER-GROUP :do "a forked sentinel in its own group watches this launcher: a kill of the launcher alone (SIGKILL included, which no handler sees) leaves the command's group, which fleet/run.asl puts outside the launcher's, running with ppid 1; the sentinel kills it within about a second; it lives at most SECS plus 60 s; forkLimited! leases it to the launcher, so any reaper on the machine would kill it the moment the launcher dies, before it acts (seen: the command survived); its lease is rewritten to name itself as owner (born now, it was just forked; no ps before the command starts), so only its deadline reaps it")
fn ! sentinel! launcher: Int64 secs: Int64 -> (Result fr/Forked String)
  (match (fr/forkLimited! "/dev/null" (fr/Limits :timeoutMs (* (+ secs 60) 1000) :maxDesc 16 :class "" :jsDir "")
           (fn [] -> Int64 (watch! launcher (procSelf) 0 -1 0 (+ (monotonicNs) (* (+ secs 60) 1000000000)) 0)))
    ((ok f) (let [(now (monotonicNs))
                  (_ (fr/writeLeaseAt! f.pid f.pid now (+ now (* (+ secs 60) 1000000000)) (nowNs) (/ (nowNs) 1000000000) (/ (nowNs) 1000000000)))]
              (ok f)))
    ((err e) (err e)))

; (:m :ref BOUNDED-WALL-INCLUDES-BUILD :do "SECS bounds the wall from launch: the command gets what the launch left, and a launch that used all of SECS starts nothing and stops with the timeout exit 124 and a (:bounded :verdict :timeout :phase :launch ...) note; the receipt's :ms is the wall, launch plus run")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(p (parseArgs args))]
    (if (not (stringEmpty? p.error))
      (do (eprintln (str "bounded: " p.error)) (eprintln (usage)) (ok 2))
      (let [(launched (launchMs!))
            (leftMs (- (* p.secs 1000) launched))
            (root (resultOr (realPath ".") "."))
            (guard (if (> leftMs 0) (sentinel! (procSelf) p.secs) (err "no run")))
            (d (if (> leftMs 0)
                 (fr/runOneLimited (fr/job p.argv root (fr/childEnv (list))) (fr/Limits :timeoutMs leftMs :maxDesc p.maxDesc :class "" :jsDir ""))
                 (fr/Done :idx 0 :exit 124 :out (str "(:bounded :verdict :timeout :phase :launch :launchMs " (stringFromInt64 launched) " :secs " (stringFromInt64 p.secs) ")\n") :ms 0 :verdict "timeout")))
            (stopped (match guard ((ok f) (do (fr/forkKill! f "done") true)) ((err _) false)))
            (wrote (or (stringEmpty? p.receipt) (ok? (fileAppend p.receipt (receiptLine d.verdict d.exit p.secs (+ launched d.ms) p.argv)))))]
        (do (if (< p.secs (minSecs)) (eprintln (str "bounded: SECS " (stringFromInt64 p.secs) " is under " (stringFromInt64 (minSecs)) "; the launch counts toward it and can use it all under load")) ())
            (print d.out)
            (if wrote () (eprintln (str "bounded: the receipt could not be written to " p.receipt)))
            (ok d.exit)))))
