(module asl-tools/coord/docRowsGate
  :x [main runGate runGateEnv envLimit memoKey]
  :i [(asl-tools/coord/conductor :a cd) (asl-tools/coord/docDup :a dd) (aslAgent/gateLimit :a gl)])

; (:m :ref COND-WORK-PRESENT :do "docRowsGate.asl WT BASE: the fix-round writer's gate for a docRows failure; it runs docRowsCheckAt! on the worktree against the base, prints the red message and exits 1 when the unit's new exported symbols lack their contract rows, else prints one assert line and exits 0")
; (:m :ref REVIEW-CRITERIA-DOCDUP :do "a second assert: a symbol whose doc row the unit added has one row in its file (docDup); a duplicate is exit 1 with the symbol and both lines, printed with the missing-row message so one turn fixes both, and it is red even when the missing-row check could not run")
; (:m :ref WALL-SLOW-GATES :do "node2 72 h: docRowsGate --writer was killed 140 times because its inner know run had the whole 300 s Leon gate limit; the inner budget is now gl/innerBudgetSec of one limit (--limit N, default gl/gateLimitSec) less the time already spent, and a check that runs out of it ends with a (:partial ...) line and the findings so far, inside the limit")

fn n i: Int64 -> String
  (stringFromInt64 i)

fn nowSec -> Int64
  (/ (monotonicNs) 1000000000)

fn optionInt args: (List String) flag: String dflt: Int64 -> Int64
  (match (listIndexOf args flag)
    ((some i) (match (listGet args (+ i 1)) ((some v) (optionOr (stringToInt64 v) dflt)) ((none) dflt)))
    ((none) dflt))

fn ! out dir: String args: (List String) -> String
  (stringTrim (cd/gitOut dir args).out)

; (:m :ref WALL-SLOW-GATES :do "the memo key of one check: merge-base, base ref, the diff of the worktree against the merge-base (committed and not) and the content of every untracked file; the check reads nothing else that changes between two runs in one write session, so equal keys mean an equal answer")
fn ! memoKey wt: String base: String -> String
  (let [(mb (out wt (list "merge-base" "HEAD" base)))
        (diff (cd/gitOut wt (list "diff" "--no-renames" mb)))
        (untracked (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines (out wt (list "ls-files" "--others" "--exclude-standard")))))
        (body (stringJoin (map (fn [(p String)] -> String (str p "\n" (resultOr (fileReadString (str wt "/" p)) ""))) untracked) "\n"))
        (text (str mb "\n" base "\n" diff.out "\n" body))]
    (str (n (fnv1a64 text)) ":" (n (stringLength text))))

fn ! memoPath wt: String -> String
  (str (out wt (list "rev-parse" "--absolute-git-dir")) "/docRowsGate.memo")

; (:m :ref WALL-SLOW-GATES :do "the memo file lives in the worktree's own git dir (never tracked, never under ~/.asl) as four lines: key, kind (done, partial1 or partial2: a know timeout is retried once on the same tree, the budget skip is never stored), message, note; a different key or a missing file is a miss")
fn ! memoRead! wt: String key: String -> (Option (Pair String (Pair String String)))
  (let [(ls (stringLines (resultOr (fileReadString (memoPath wt)) "")))]
    (if (and (>= (listLength ls) 4) (= (optionOr (listGet ls 0) "") key))
      (some (pair (optionOr (listGet ls 1) "") (pair (optionOr (listGet ls 2) "") (optionOr (listGet ls 3) ""))))
      (none)))

fn ! memoWrite! wt: String key: String kind: String r: (Pair String String) -> Bool
  (match (fileWrite (memoPath wt) (str key "\n" kind "\n" (stringReplace (pairFirst r) "\n" " ") "\n" (stringReplace (pairSecond r) "\n" " ") "\n"))
    ((ok _) true)
    ((err _) false))

; (:m :ref WALL-SLOW-GATES :do "the check itself under a budget: the time left after the duplicate check and the memo lookup goes to docRowsCheckAt! as its limit; a check that cannot start for lack of time, or whose know run hits the limit, answers a :partial note naming what did finish (the duplicate check and the doc ledger findings, which docRowsCheckAt! settles before the know run) and not a kill")
fn ! boundedCheck! wt: String base: String t0: Int64 inner: Int64 limit: Int64 -> (Pair String String)
  (let [(left (- inner (- (nowSec) t0)))]
    (if (< left 2)
      (pair "" (str ":docRows :ran false :partial true :why budget :done (dup) :skipped (ledger know) :limitSec " (n limit) " :budgetSec " (n inner)))
      (let [(r (cd/docRowsCheckAt! wt base left))]
        (if (stringContains? (pairSecond r) ":detail timeout")
          (pair "" (str ":docRows :ran false :partial true :why budget :done (dup ledger) :skipped (know) :limitSec " (n limit) " :budgetSec " (n inner) " :spentSec " (n (- (nowSec) t0))))
          r))))

; (:m :ref WALL-SLOW-GATES :do "runGate ARGS: the gate as (exit, output lines) so a test can read the text; ARGS are WT BASE [--writer] [--limit N]; the duplicate check runs live, the doc check is memoised by memoKey for complete answers and for :partial ones, so a repeat run in one write session costs the key only")
fn ! runGate args: (List String) -> (Pair Int64 (List String))
  (runGateEnv args (optionOr (envGet "ASL_GATE_LIMIT_SEC") ""))

; (:m :ref WALL-SLOW-GATES :do "the limit a gate was given through ASL_GATE_LIMIT_SEC: a whole number of at least 1, anything else (empty, 0, negative, not a number) is dropped for the default")
fn envLimit raw: String dflt: Int64 -> Int64
  (match (stringToInt64 (stringTrim raw))
    ((some k) (if (>= k 1) k dflt))
    ((none) dflt))

; (:m :ref WALL-SLOW-GATES :do "runGate with the value of ASL_GATE_LIMIT_SEC passed in, so a test sets it without a child process; --limit N wins over it")
fn ! runGateEnv args: (List String) envRaw: String -> (Pair Int64 (List String))
  (let [(t0 (nowSec))
        (wt (optionOr (listGet args 0) "."))
        (base (optionOr (listGet args 1) "main"))
        (limit (optionInt args "--limit" (envLimit envRaw (gl/gateLimitSec))))
        (inner (gl/innerBudgetSec limit))
        (dup (dd/dupCheckAt! wt base))
        (dupRed (if (stringEmpty? dup) 0 1))
        (key (memoKey wt base))
        (hit (memoRead! wt key))
        (fresh? (match hit ((some h) (= (pairFirst h) "partial1")) ((none) true)))
        (r (if fresh? (boundedCheck! wt base t0 inner limit) (match hit ((some h) (pairSecond h)) ((none) (pair "" "")))))
        (note (pairSecond r))
        (partial (stringContains? note ":partial true"))
        (_ (if (and fresh? (not (and (stringContains? note ":why infra") (not partial))) (not (stringContains? note ":skipped (ledger know)"))) (memoWrite! wt key (if partial (match hit ((some _) "partial2") ((none) "partial1")) "done") r) true))
        (msg (pairFirst r))
        (writer (listContains? args "--writer"))
        (infra (stringContains? note ":why infra"))
        (failed (+ dupRed (if (stringEmpty? msg) (if (or writer (not (or partial infra))) 0 1) 1)))
        (head (str "(:gate :asserts 2 :failed " (n failed) ")"))
        (dupLine (if (= dupRed 1) (str "FAIL docRows: " dup) "assert docRows: no symbol the unit added has two doc rows"))]
    (cond
      (partial (pair (if writer dupRed (if (= dupRed 1) 1 2)) (list head dupLine (str "(:partial " note ")") (str "assert docRows: partial, the know run did not finish inside the budget, left to the conductor " note))))
      (infra
        ; (:m :ref COND-OWNS-DOC :do "--writer: the gate inside the writer's own run; a check that could not run is infrastructure and no fault of the model, so it is green there with the note, and the conductor's gate stage still judges the unit")
        (if writer
          (pair dupRed (list head dupLine (str "assert docRows: could not run, left to the conductor " note)))
          (pair (if (= dupRed 1) 1 2) (list head dupLine (str "gateInfra: docRows could not run " note)))))
      ((stringEmpty? msg) (pair dupRed (list head dupLine "assert docRows: no new exported symbol lacks its contract row")))
      (else (pair 1 (list head dupLine (str "FAIL docRows: " msg))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(r (runGate args))
        (_ (map (fn [(l String)] -> Bool (let [(_ (println l))] true)) (pairSecond r)))]
    (ok (pairFirst r)))
