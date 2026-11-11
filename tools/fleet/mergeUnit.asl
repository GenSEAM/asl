(module asl-tools/fleet/mergeUnit
  :x [Cfg defaultCfg waitPid! emit! gateRun! gateVerdict! mergeUnit! mergeUnitWith! mainBuild! parseArgs main]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/brief :a br) (asl-tools/vcs/git :a vg)])

; (:m :ref BASH-EXIT-MERGE :do "bin/asl run asl/tools/fleet/mergeUnit.asl [--main DIR] [--worktrees DIR] [--brief-dir DIR] [--after PID] [--audit CMD|none] [--gate-secs N] [--audit-secs N] [--lock DIR] [--log FILE] UNIT...: per unit, in order: rebase the worktree asex-UNIT onto main (REBASE-CONFLICT stops the unit), build its host when asl/host/build.sh exists, run every :gates entry of the brief UNIT-leon.asn as a bounded sh -c child under env -u ASL_ROOT -u ASL_PRELUDE; a red gate is rerun in the main repo: red there too is BASE-RED and does not block, green there is NEW-RED and blocks (GATE-FAIL); then the audit command, then a fast-forward merge into main with up to 3 rebase retries when main moved, then the main host rebuild under a mkdir lock; one (:merge :unit U :event E ...) line per event; every child starts through fleet/run.asl, waiting is on a pid or a lock, never on a process name")

(schema Cfg
  (:f main String)
  (:f worktrees String)
  (:f briefDir String)
  (:f branch String :default "main")
  (:f gateSecs Int64 :default 1500)
  (:f auditSecs Int64 :default 600)
  (:f audit String :default "./bin/asl audit consistency")
  (:f lock String)
  (:f log String :default "")
  (:f retries Int64 :default 3)
  (:f testCmd String :default "./bin/asl test")
  (:f lockMaxAgeS Int64 :default 3600))

fn ! homeDir -> String
  (optionOr (envGet "HOME") "/tmp")

fn ! defaultCfg -> Cfg
  (let [(main (str (homeDir) "/projects/asex"))]
    (Cfg :main main :worktrees (str (homeDir) "/projects/worktrees") :briefDir (str main "/.asl/mem/work/brief")
         :lock (str (homeDir) "/.asl/run/mainbuild.lock")))

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

; (:m :do "one event line, printed whole and appended to the cfg log when it names one")
fn ! emit! cfg: Cfg unit: String event: String rest: String -> Bool
  (let [(line (str "(:merge :unit " (q unit) " :event :" event (if (stringEmpty? rest) "" (str " " rest)) ")"))
        (_ (println line))]
    (if (stringEmpty? cfg.log) true (ok? (fileAppend cfg.log (str line "\n")))))

; (:m :do "wait until pid is gone, polling every 500 ms for at most maxS seconds; true when it is gone (pid <= 1 counts as gone). A pid, never a process name")
fn ! waitPid! pid: Int64 maxS: Int64 -> Bool
  (if (<= pid 1) true
    (let [(deadline (+ (monotonicNs) (* maxS 1000000000)))]
      (waitLoop! pid deadline)))

fn ! waitLoop! pid: Int64 deadline: Int64 -> Bool
  (cond
    ((not (resultOr (procAlive? pid) true)) true)
    ((>= (monotonicNs) deadline) false)
    (else (do (sleepMs 500) (waitLoop! pid deadline))))

fn ! sh! dir: String cmd: String secs: Int64 -> fr/Done
  (fr/runOneLimited (fr/job (list "env" "-u" "ASL_ROOT" "-u" "ASL_PRELUDE" "nice" "-n" "10" "sh" "-c" cmd) dir (fr/childEnv (list))) (fr/limits secs 64))

fn green? d: fr/Done -> Bool
  (and (= d.verdict "exit") (= d.exit 0))

; (:m :do "one gate command bounded in dir: exit 0 with the exit verdict is green, anything else (a nonzero exit, a timeout, a runaway) is red")
fn ! gateRun! dir: String cmd: String secs: Int64 -> Bool
  (green? (sh! dir cmd secs))

; (:m :do "the verdict of a gate that ran red in the worktree: newRed when the same command is green in the main repo, baseRed when it is red there too")
fn ! gateVerdict! cfg: Cfg cmd: String -> String
  (if (gateRun! cfg.main cmd cfg.gateSecs) "NEW-RED" "BASE-RED")

fn ! gitOut! dir: String args: (List String) -> vg/Out
  (vg/gitRun! dir args 120)

fn ! gatesOf! unit: String cfg: Cfg -> (List String)
  (let [(path (str cfg.briefDir "/" unit "-leon.asn"))]
    (match (fileReadString path)
      ((ok text) (let [(b (br/parseBrief text))] b.gates))
      ((err _) (list))))

; (:m :do "the gates of one unit in order: true when none blocks; each red gate is judged against the main repo")
; (:m :ref BASH-EXIT-MERGE :do "the neighbour tests of a change, as merge4 found them: for each file changed on the branch since main under */src/*.asl, the module named on its line 1, then every pkg/tests/*.asl that mentions (MODULE  and contains runTests; each becomes the gate cfg.testCmd + path")
fn ! moduleOf! path: String -> String
  (match (fileReadString path)
    ((ok text) (let [(l (optionOr (listHead (stringLines text)) ""))]
                 (if (stringStartsWith? l "(module ") (optionOr (listHead (stringSplit (stringReplace (stringReplace l "(module " "") ")" "") " ")) "") "")))
    ((err _) ""))

fn ! testsFor! wt: String file: String -> (List String)
  (let [(pkg (optionOr (listHead (stringSplit file "/src/")) ""))
        (mod (moduleOf! (str wt "/" file)))
        (dir (str wt "/" pkg "/tests"))
        (names (resultOr (dirList dir) (list)))]
    (if (or (stringEmpty? mod) (stringEmpty? pkg)) (list)
      (map (fn [n] (str pkg "/tests/" n))
        (filter (fn [n] (and (stringEndsWith? n ".asl")
                             (let [(t (resultOr (fileReadString (str dir "/" n)) ""))]
                               (and (stringContains? t (str "(" mod " ")) (stringContains? t "runTests")))))
          names))))

fn ! neighbourGates! cfg: Cfg wt: String -> (List String)
  (let [(d (gitOut! wt (list "diff" "--name-only" (str cfg.branch "...HEAD"))))
        (files (filter (fn [f] (and (stringContains? f "/src/") (stringEndsWith? f ".asl"))) (stringLines d.out)))
        (tests (fold (fn [acc f] (listAppend acc (testsFor! wt f))) (list) files))]
    (map (fn [t] (str cfg.testCmd " " t)) tests))

; (:m :ref MERGE-DOCLEDGER-GATE :do "the text of a module header's :x export list, whitespace normalised; empty when the file has none")
fn exportHeader text: String -> String
  (match (stringIndexOf text ":x [")
    ((none) "")
    ((some at)
      (let [(rest (optionOr (stringSlice text (+ at 4) (stringLength text)) ""))
            (end (optionOr (stringIndexOf rest "]") (stringLength rest)))]
        (stringJoin (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace (optionOr (stringSlice rest 0 end) "") "\n" " ") " ")) " "))))

fn docFile? path: String -> Bool
  (and (stringEndsWith? path ".asn")
       (or (= path "doc.asn") (or (stringEndsWith? path "/doc.asn") (stringStartsWith? path "asl/doc/"))))

; (:m :ref MERGE-DOCLEDGER-GATE :do "a change line of git diff --name-status: the status letter and the new path (a rename names the new path last)")
fn changeOf line: String -> (Pair String String)
  (let [(parts (stringSplit line "\t"))]
    (pair (optionOr (stringSlice (optionOr (listHead parts) "") 0 1) "") (optionOr (listLast parts) "")))

fn ! baseText! cfg: Cfg wt: String path: String -> String
  (let [(o (gitOut! wt (list "show" (str cfg.branch ":" path))))]
    (if (= o.exit 0) o.out ""))

; (:m :ref MERGE-DOCLEDGER-GATE :do "does one changed path of the branch need the doc ledger test: a doc.asn or asl/doc/*.asn touched; an .asl file deleted whose main header had a non-empty :x list; an .asl file added with a non-empty :x export list (tests with runTests included); an .asl file changed whose :x list differs from main's; a body-only change does not")
fn ! needsLedger? cfg: Cfg wt: String c: (Pair String String) -> Bool
  (let [(status (pairFirst c))
        (path (pairSecond c))]
    (cond
      ((docFile? path) true)
      ((not (stringEndsWith? path ".asl")) false)
      ((= status "D") (not (stringEmpty? (exportHeader (baseText! cfg wt path)))))
      (else
        (let [(now (exportHeader (resultOr (fileReadString (str wt "/" path)) "")))
              (was (if (= status "A") "" (exportHeader (baseText! cfg wt path))))]
          (!= now was)))))

fn ! ledgerGates! cfg: Cfg wt: String -> (List String)
  (let [(d (gitOut! wt (list "diff" "--name-status" (str cfg.branch "...HEAD"))))
        (changes (map changeOf (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines d.out))))]
    (if (listAny? (fn [(c (Pair String String))] -> Bool (needsLedger? cfg wt c)) changes)
      (list (str cfg.testCmd " asl/packages/asl-gates/tests/docLedgerTest.asl"))
      (list)))

fn uniq xs: (List String) -> (List String)
  (fold (fn [acc x] (if (listContains? acc x) acc (listAppend acc (list x)))) (list) xs)

fn ! gatesPass! cfg: Cfg unit: String wt: String gates: (List String) -> Bool
  (fold (fn [(ok0 Bool) (g String)] -> Bool
          (if (gateRun! wt g cfg.gateSecs)
            (do (emit! cfg unit "GATE" (str ":cmd " (q g) " :exit 0")) ok0)
            (let [(v (gateVerdict! cfg g))]
              (do (emit! cfg unit v (str ":cmd " (q g)))
                  (and ok0 (= v "BASE-RED"))))))
        true gates)

fn ! auditPass! cfg: Cfg wt: String -> Bool
  (if (or (stringEmpty? cfg.audit) (= cfg.audit "none")) true
    (let [(d (sh! wt cfg.audit cfg.auditSecs))]
      (and (= d.verdict "exit") (stringContains? d.out "audit consistency: passed"))))

; (:m :do "the rebase of the worktree onto the main branch; a conflict is aborted and reported false")
; (:m :ref BASH-EXIT-MERGE :do "a build leaves the tracked .asl.config.asn modified, and a dirty tree makes the rebase fail as a false conflict: that one path is restored from HEAD through the vcs layer first (an untracked or absent file is a no-op)")
fn ! rebaseOnto! cfg: Cfg wt: String -> Bool
  (let [(_ (if (stringEmpty? (stringTrim (vg/changes! wt (list ".asl.config.asn")).out)) 0 (do (vg/restoreTree! wt "HEAD" (list ".asl.config.asn")) 0)))
        (r (gitOut! wt (list "rebase" "-q" cfg.branch)))]
    (if (= r.exit 0) true
      (do (gitOut! wt (list "rebase" "--abort")) false)))

fn ! hostBuild! dir: String -> Bool
  (if (fileExists? (str dir "/asl/host/build.sh"))
    (green? (sh! dir "nice sh asl/host/build.sh" 1800))
    true)

; (:m :ref BASH-EXIT-MERGE :do "a lock directory older than lockMaxAgeS (default 3600 s, by its mtime) is stale: a merge that died holding it must not skip rebuilds forever")
fn ! lockStale? cfg: Cfg -> Bool
  (match (fileStat cfg.lock)
    ((ok st) (> (- (/ (nowNs) 1000000000) st.mtime) cfg.lockMaxAgeS))
    ((err _) false))

; (:m :do "the main host rebuild under a mkdir lock: mkdir fails when another merge holds it, so the rebuild is skipped, never doubled; a missing build script is a no-op")
fn ! mainBuild! cfg: Cfg unit: String -> Bool
  (let [(parent (stringJoin (listTake (stringSplit cfg.lock "/") (- (listLength (stringSplit cfg.lock "/")) 1)) "/"))
        (_ (dirCreate parent))
        (_x (if (lockStale? cfg) (do (pathRemove cfg.lock) (emit! cfg unit "MAIN-BUILD-LOCK-EXPIRED" (str ":maxAgeS " cfg.lockMaxAgeS))) true))
        (got (fr/runOneLimited (fr/job (list "mkdir" cfg.lock) "." (fr/childEnv (list))) (fr/limits 20 8)))]
    (cond
      ((!= got.exit 0) (do (emit! cfg unit "MAIN-BUILD-SKIPPED" ":why \"another merge builds\"") true))
      (else
        (let [(built (hostBuild! cfg.main))
              (_ (pathRemove cfg.lock))]
          (do (if built true (emit! cfg unit "MAIN-HOST-BUILD-FAIL" ""))
              built)))))

; (:m :do "fast-forward the unit's branch into main, rebasing onto the moved main between attempts; true when merged")
fn ! ffLoop! cfg: Cfg unit: String wt: String branch: String try: Int64 -> Bool
  (let [(m (vg/mergeFf! cfg.main branch))]
    (cond
      ((= m.exit 0) true)
      ((>= try cfg.retries) (do (emit! cfg unit "FF-FAIL" (str ":tries " try)) false))
      ((not (rebaseOnto! cfg wt)) (do (emit! cfg unit "REBASE-CONFLICT-AT-MERGE" "") false))
      (else
        (do (emit! cfg unit "REBASED-ONTO-MOVED-MAIN" ":note \"disjoint; the gates ran on the earlier base\"")
            (ffLoop! cfg unit wt branch (+ try 1))))))

; (:m :do "one unit end to end; hook runs after the gates and the audit, just before the first merge attempt (the test moves main there). true when merged")
fn ! mergeUnitWith! cfg: Cfg unit: String hook: (fn [] -> Bool) -> Bool
  (let [(wt (str cfg.worktrees "/asex-" unit))]
    (cond
      ((not (fileExists? wt)) (do (emit! cfg unit "NO-WORKTREE" (str ":path " (q wt))) false))
      ((not (rebaseOnto! cfg wt)) (do (emit! cfg unit "REBASE-CONFLICT" "") false))
      ((not (hostBuild! wt)) (do (emit! cfg unit "BUILD-FAIL" "") false))
      (else
        (let [(gates (uniq (listAppend (gatesOf! unit cfg) (if (listEmpty? (gatesOf! unit cfg)) (list) (listAppend (neighbourGates! cfg wt) (ledgerGates! cfg wt))))))]
          (cond
            ((listEmpty? gates) (do (emit! cfg unit "NO-GATES" (str ":brief " (q (str cfg.briefDir "/" unit "-leon.asn")))) false))
            ((not (gatesPass! cfg unit wt gates)) (do (emit! cfg unit "GATE-FAIL" "") false))
            ((not (auditPass! cfg wt)) (do (emit! cfg unit "AUDIT-FAIL" "") false))
            (else
              (let [(branchOut (gitOut! wt (list "branch" "--show-current")))
                    (branch (stringTrim branchOut.out))
                    (_ (hook))]
                (if (or (!= branchOut.exit 0) (stringEmpty? branch))
                  (do (emit! cfg unit "FF-FAIL" ":why \"worktree has no branch\"") false)
                  (if (ffLoop! cfg unit wt branch 1)
                    (let [(h (vg/head! cfg.main))]
                      (do (emit! cfg unit "MERGED" (str ":sha " (q (stringTrim h.out))))
                          (mainBuild! cfg unit)
                          true))
                    false)))))))))

fn ! mergeUnit! cfg: Cfg unit: String -> Bool
  (mergeUnitWith! cfg unit (fn [] true))

(schema Parsed
  (:f cfg Cfg)
  (:f after Int64)
  (:f units (List String))
  (:f error String))

fn intOpt s: String -> Int64
  (optionOr (stringToInt64 s) -1)

; (:m :do "options, then unit names; an unknown option or a missing value is an error text, never a run")
fn parseLoop args: (List String) p: Parsed -> Parsed
  (match (listHead args)
    ((none) p)
    ((some a)
      (let [(rest (optionOr (listTail args) (list)))
            (v (optionOr (listHead rest) ""))
            (c p.cfg)
            (more (optionOr (listTail rest) (list)))]
        (cond
          ((not (stringStartsWith? a "--")) (parseLoop rest (with p :units (listAppend p.units (list a)))))
          ((stringEmpty? v) (with p :error (str a " needs a value")))
          ((= a "--main") (parseLoop more (with p :cfg (with c :main v))))
          ((= a "--worktrees") (parseLoop more (with p :cfg (with c :worktrees v))))
          ((= a "--brief-dir") (parseLoop more (with p :cfg (with c :briefDir v))))
          ((= a "--audit") (parseLoop more (with p :cfg (with c :audit v))))
          ((= a "--lock") (parseLoop more (with p :cfg (with c :lock v))))
          ((= a "--log") (parseLoop more (with p :cfg (with c :log v))))
          ((= a "--branch") (parseLoop more (with p :cfg (with c :branch v))))
          ((= a "--gate-secs") (parseLoop more (with p :cfg (with c :gateSecs (intOpt v)))))
          ((= a "--audit-secs") (parseLoop more (with p :cfg (with c :auditSecs (intOpt v)))))
          ((= a "--after") (parseLoop more (with p :after (intOpt v))))
          (else (with p :error (str "unknown option " a)))))))

fn ! parseArgs args: (List String) -> Parsed
  (let [(d (defaultCfg))
        (p (parseLoop args (Parsed :cfg d :after 0 :units (list) :error "")))
        (c p.cfg)
        (c2 c)]
    (cond
      ((not (stringEmpty? p.error)) p)
      ((or (<= c.gateSecs 0) (<= c.auditSecs 0)) (with p :error "--gate-secs and --audit-secs must be positive integers"))
      ((< p.after 0) (with p :error "--after needs a pid"))
      ((listEmpty? p.units) (with p :error "no unit named"))
      (else p)))

fn usage -> String
  "usage: bin/asl run asl/tools/fleet/mergeUnit.asl [--main DIR] [--worktrees DIR] [--brief-dir DIR] [--after PID] [--audit CMD|none] [--gate-secs N] [--audit-secs N] [--lock DIR] [--log FILE] [--branch B] UNIT..."

fn ! main args: (List String) -> (Result Int64 String)
  (let [(p (parseArgs args))]
    (if (not (stringEmpty? p.error))
      (do (eprintln (str "mergeUnit: " p.error)) (eprintln (usage)) (ok 2))
      (let [(waited (waitPid! p.after 10800))
            (c p.cfg)]
        (if (not waited)
          (do (emit! c "" "AFTER-TIMEOUT" (str ":pid " p.after)) (ok 3))
          (let [(merged (map (fn [u] (mergeUnit! c u)) p.units))
                (_ (if (or (stringEmpty? c.audit) (= c.audit "none")) true
                     (let [(d (sh! c.main c.audit c.auditSecs))]
                       (emit! c "" "MAIN-AUDIT" (str ":passed " (if (and (= d.verdict "exit") (stringContains? d.out "audit consistency: passed")) "true" "false"))))))]
            (ok (if (listAll? (fn [m] m) merged) 0 1)))))))
