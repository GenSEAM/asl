(module asl-tools/fleet/mergeUnit
  :x [capNeighbours clipWhy directGates! mergeBatch! claimDir! exportHeader baseText! Cfg defaultCfg mvDir! releaseLock! takeOver! ownerOf! gateKey gateOrder lockDirOf withLock! waitPid! emit! gateRun! gateVerdict! mergeUnit! mergeUnitWith! mainBuild! parseArgs main]
  :i [(asl-tools/fleet/run :a fr) (asl-tools/fleet/brief :a br) (asl-tools/vcs/git :a vg) (asl-gates/suiteTimes :a st)])

; (:m :ref BASH-EXIT-MERGE :do "bin/asl run asl/tools/fleet/mergeUnit.asl [--main DIR] [--worktrees DIR] [--brief-dir DIR] [--after PID] [--audit CMD|none] [--gate-secs N] [--audit-secs N] [--lock DIR] [--log FILE] UNIT...: per unit, in order: rebase the worktree asex-UNIT onto main (REBASE-CONFLICT stops the unit), build its host when asl/host/build.sh exists, run every :gates entry of the brief UNIT-leon.asn as a bounded sh -c child under env -u ASL_ROOT -u ASL_PRELUDE; a red gate is rerun in the main repo: red there too is BASE-RED and does not block, green there is NEW-RED and blocks (GATE-FAIL); then the audit command, then a fast-forward merge into main with up to 3 rebase retries when main moved, then the main host rebuild under a mkdir lock; one (:merge :unit U :event E ...) line per event; every child starts through fleet/run.asl, waiting is on a pid or a lock, never on a process name")
; (:m :ref MERGE-TRAIN-SLOW :do "--branch B names the branch every unit is rebased onto and fast-forwarded into (default main), never the unit's own branch (that is refused as BRANCH-IS-TARGET); the gate set is the brief's :gates plus the direct tests of the change (changed suites, and suites that import a changed module), within the budget; graph neighbours join only with --neighbours or a brief :neighbours true; a brief :budgetS N replaces --neighbour-budget-secs for that unit; live suites (cfg.liveSuites plus the tools/remote/ rows of .asl/mem/skipAllowed.asn) are selected only when the change touches tools/remote/; --batch U1,U2 cherry-picks the units onto one integration branch, runs the union of their gates once and fast-forwards main once")

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
  (:f lockMaxAgeS Int64 :default 3600)
  (:f mergeLock String :default "")
  (:f lockWaitS Int64 :default 10800)
  (:f gateSlots Int64 :default 2)
  (:f graphSelect Bool :default true)
  (:f graphDir String :default "")
  (:f checkCmd String :default "./bin/asl check")
  (:f aslBin String :default "./bin/asl")
  (:f invariantCapS Int64 :default 120)
  (:f neighbourBudgetS Int64 :default 1200)
  (:f neighbours Bool :default false)
  (:f liveRoot String :default "tools/remote/")
  (:f liveSuites (List String) :default (list "tools/remote/tests/vpsE2eTest.asl"))
  (:f symbolSelect Bool :default true)
  (:f affectedTool String :default "")
  (:f affectedSecs Int64 :default 300)
  (:f invariantCosts (List String) :default (list
    "./bin/asl test tools/tests/noSelfHostTest.asl=30"
    "./scripts/install.sh --check-rules=30"
    "git rev-parse --is-inside-work-tree >/dev/null 2>&1 && test $(git remote 2>/dev/null | wc -l) -eq 0=1"
    "./bin/asl audit consistency=30"
    "./bin/asl audit gates --full --sync=1200")))

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

; (:m :ref MERGE-NEIGHBOURS-PAR :do "the neighbour suites from the main checkout's tools/fleet/graph.asl run as a bounded subprocess (aslBin run GRAPH select BASE WT --cache DIR --check CMD, in the worktree), one suite path per line; none when the file is absent, the subprocess fails or times out, and the import scan runs instead. asl/ never imports tools/")
fn ! graphGates! cfg: Cfg wt: String -> (Option (List String))
  (let [(graph (str cfg.main "/tools/fleet/graph.asl"))]
    (if (not (fileExists? graph)) (none)
      (let [(d (fr/runOneLimited (fr/job (listAppend (list cfg.aslBin "run" graph "select" cfg.branch wt "--check" cfg.checkCmd) (if (stringEmpty? cfg.graphDir) (list) (list "--cache" cfg.graphDir))) wt (fr/childEnv (list))) (fr/limits 600 64)))]
        (if (and (= d.verdict "exit") (= d.exit 0))
          (some (map (fn [(t String)] -> String (str cfg.testCmd " " t))
                     (filter (fn [(t String)] -> Bool (and (stringEndsWith? t ".asl") (and (fileExists? (str wt "/" t)) (not (stringContains? t "/fixtures/")))))
                             (map stringTrim (stringLines d.out)))))
          (none)))))

; (:m :ref MERGE-NEIGHBOURS-PAR :do "the graph selector's answer is used when it names at least one suite, or when the branch changed no file; an empty answer for a branch that changed files falls back to the import scan with why graphEmpty, and a missing or failing graph with why graphUnavailable; the result pairs the direct suites (kept first under the budget) with the whole selection")
fn ! neighbourSets! cfg: Cfg unit: String wt: String -> (Pair (List String) (List String))
  (match (if cfg.graphSelect (graphGates! cfg wt) (none))
    ((some gs)
      (if (and (listEmpty? gs) (not (stringEmpty? (stringTrim (gitOut! wt (list "diff" "--name-only" (str cfg.branch "...HEAD"))).out))))
        (do (emit! cfg unit "NEIGHBOUR-SELECTOR" ":by \"scan\" :why \"graphEmpty\"") (let [(sc (scanGates! cfg wt))] (pair sc sc)))
        (do (emit! cfg unit "NEIGHBOUR-SELECTOR" (str ":by \"graph\" :n " (stringFromInt64 (listLength gs))))
            (pair (listAppend (scanGates! cfg wt) (importersOf! cfg wt gs)) gs))))
    ((none) (do (emit! cfg unit "NEIGHBOUR-SELECTOR" (str ":by \"scan\" :why " (if cfg.graphSelect "\"graphUnavailable\"" "\"off\""))) (let [(sc (scanGates! cfg wt))] (pair sc sc)))))

; (:m :ref MERGE-TRAIN-SLOW :do "a suite: an .asl file under a tests directory (top-level tests/ or any */tests/), not a fixture, whose text holds runTests")
fn ! suite? wt: String p: String -> Bool
  (and (stringEndsWith? p ".asl")
       (and (or (stringStartsWith? p "tests/") (stringContains? p "/tests/"))
            (and (not (stringContains? p "/fixtures/"))
                 (stringContains? (resultOr (fileReadString (str wt "/" p)) "") "runTests"))))

; (:m :ref MERGE-TRAIN-SLOW :do "the suites anywhere in the worktree (tracked or untracked, not ignored) whose text names any of names in an import, (NAME ...), found by one git grep over the whole tree (the vcs layer passes --literal-pathspecs, so no glob narrows it; suite? filters); a suite that reaches the module only through another module's re-export is not followed")
fn ! importersIn! wt: String names: (List String) -> (List String)
  (let [(o (gitOut! wt (listAppend (list "grep" "-l" "-F" "--untracked") (fold (fn [(acc (List String)) (m String)] -> (List String) (listAppend acc (list "-e" (str "(" m " ")))) (list) names))))]
    (filter (fn [(p String)] -> Bool (suite? wt p)) (map stringTrim (stringLines o.out))))

; (:m :ref MERGESLIM-FIX :do "the names a suite may import a changed file by: its module name and its path without .asl (39 suites import by path, e.g. (asl/packages/asl-cli/src/verify :a v))")
fn importNames mod: String path: String -> (List String)
  (let [(byPath (optionOr (stringSlice path 0 (- (stringLength path) 4)) ""))]
    (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (if (= mod byPath) (list mod) (list mod byPath))))

; (:m :ref AFFSYM-WIRE :do "a reason chain in an event is cut to 400 characters with a trailing ...; the selector repeats a chain that loops (seen 2026-11-12: runCoreTests <- runTests <- runCoreTests ...)")
fn clipWhy s: String -> String
  (if (> (stringLength s) 400) (str (optionOr (stringSlice s 0 400) s) "...") s)

; (:m :ref AFFSYM-WIRE :do "the (suite reason) pairs of an asl/tools/affectedSuites.asl receipt line (:affected ... :suites ((\"path\" \"reason\") ...)); paths and reasons hold no quote: affectedSuites.asl prints them unescaped and they are file paths and module#symbol chains, so a quote or \")\" inside one would cut the pair here")
fn affectedPairs out: String -> (List (Pair String String))
  (let [(line (optionOr (listFind (fn [(l String)] -> Bool (stringStartsWith? l "(:affected ")) (stringLines out)) ""))
        (after (match (stringIndexOf line ":suites (") ((some at) (optionOr (stringSlice line (+ at 9) (stringLength line)) "")) ((none) "")))]
    (map (fn [(piece String)] -> (Pair String String)
           (let [(parts (stringSplit piece "\" \""))]
             (pair (optionOr (listHead parts) "") (optionOr (listHead (stringSplit (optionOr (listGet parts 1) "") "\")")) ""))))
         (listDrop (stringSplit after "(\"") 1)))

; (:m :ref AFFSYM-WIRE :do "the symbol-level selector: cfg.affectedTool (default the main checkout's asl/tools/affectedSuites.asl) runs as a bounded child in the worktree with --base set to the merge base of cfg.branch, and answers the suites that reach a changed item through a chain of mentions, each with its reason chain; err names why it could not answer (no tool, no merge base, a failed or timed-out run, no receipt line)")
fn ! symbolSuites! cfg: Cfg wt: String -> (Result (List (Pair String String)) String)
  (let [(tool (if (stringEmpty? cfg.affectedTool) (str cfg.main "/asl/tools/affectedSuites.asl") cfg.affectedTool))
        (mb (gitOut! wt (list "merge-base" cfg.branch "HEAD")))]
    (cond
      ((not (fileExists? tool)) (err "noTool"))
      ((!= mb.exit 0) (err "noMergeBase"))
      (else
        (let [(d (fr/runOneLimited (fr/job (list cfg.aslBin "run" tool (str "--base=" (stringTrim mb.out))) wt (fr/childEnv (list))) (fr/limits cfg.affectedSecs 64)))]
          (cond
            ((not (and (= d.verdict "exit") (= d.exit 0))) (err (str "run " d.verdict " " (stringFromInt64 d.exit))))
            ((not (stringContains? d.out "(:affected ")) (err "noReceipt"))
            (else (ok (affectedPairs d.out))))))))

; (:m :ref AFFWIRE-FIX :do "true when the change adds, edits or deletes an .asl file: an empty symbol answer for such a change falls back to the importer scan (emptySelection), so a code change never merges on the brief's gates alone")
fn changesAsl? changes: (List (Pair String String)) -> Bool
  (listAny? (fn [(c (Pair String String))] -> Bool (stringEndsWith? (pairSecond c) ".asl")) changes)

; (:m :ref AFFSYM-WIRE :do "the direct suites of a change: by default the symbol-level selector's answer (only suites reaching a changed item, each logged as SELECTED with its reason chain); when it cannot answer, answers no suite for a change to an .asl file, or with cfg.symbolSelect off, the import scan below runs instead and NEIGHBOUR-SELECTOR names why")
fn ! directGates! cfg: Cfg unit: String wt: String changes: (List (Pair String String)) -> (List String)
  (match (if cfg.symbolSelect (symbolSuites! cfg wt) (err "off"))
    ((ok picked)
      (let [(kept (filter (fn [(p (Pair String String))] -> Bool (suite? wt (pairFirst p))) picked))]
        (if (and (listEmpty? kept) (changesAsl? changes))
          (importerGates! cfg unit wt changes "emptySelection")
          (let [(_ (emit! cfg unit "NEIGHBOUR-SELECTOR" (str ":by \"symbol\" :n " (stringFromInt64 (listLength kept)))))
                (_ (map (fn [(p (Pair String String))] -> Bool (emit! cfg unit "SELECTED" (str ":suite " (q (pairFirst p)) " :why " (q (clipWhy (pairSecond p)))))) kept))]
            (map (fn [(t String)] -> String (str cfg.testCmd " " t)) (uniq (map pairFirst kept)))))))
    ((err why) (importerGates! cfg unit wt changes why)))

; (:m :ref MERGE-TRAIN-SLOW :do "2026-11-12 principal: merge mostly with affected tests; the import-scan suites of a change are the suites it adds or changes and the suites that import a module it adds or changes, wherever they live; no transitive graph walk; the fallback of the symbol selector")
; (:m :ref AFFWIRE-LOWS :do "a deleted .asl file counts too: its module name is read from the main checkout, where it still exists, so the suites importing the removed module run")
fn ! importerGates! cfg: Cfg unit: String wt: String changes: (List (Pair String String)) why: String -> (List String)
  (let [(paths (map pairSecond (filter (fn [(c (Pair String String))] -> Bool (and (!= (pairFirst c) "D") (stringEndsWith? (pairSecond c) ".asl"))) changes)))
        (tests (filter (fn [(p String)] -> Bool (suite? wt p)) paths))
        (gone (map pairSecond (filter (fn [(c (Pair String String))] -> Bool (and (= (pairFirst c) "D") (stringEndsWith? (pairSecond c) ".asl"))) changes)))
        (names (listAppend (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (importNames (moduleOf! (str wt "/" p)) p))) (list) paths)
                           (fold (fn [(acc (List String)) (p String)] -> (List String) (listAppend acc (importNames (moduleOf! (str cfg.main "/" p)) p))) (list) gone)))
        (imps (if (listEmpty? names) (list) (importersIn! wt (uniq names))))
        (all (uniq (listAppend tests imps)))
        (_ (emit! cfg unit "NEIGHBOUR-SELECTOR" (str ":by \"direct\" :why " (q why) " :n " (stringFromInt64 (listLength all)))))
        (_ (map (fn [(t String)] -> Bool (emit! cfg unit "SELECTED" (str ":suite " (q t) " :why " (if (listContains? tests t) "\"changed\"" "\"importer\"")))) all))]
    (map (fn [(t String)] -> String (str cfg.testCmd " " t)) all))

; (:m :ref MERGE-TRAIN-SLOW :do "the live suites: cfg.liveSuites and every :suite of the main checkout's .asl/mem/skipAllowed.asn under cfg.liveRoot (suites that need a reachable VPS)")
fn ! liveSuites! cfg: Cfg -> (List String)
  (let [(text (resultOr (fileReadString (str cfg.main "/.asl/mem/skipAllowed.asn")) ""))
        (listed (map (fn [(piece String)] -> String (optionOr (listHead (stringSplit piece "\"")) "")) (listDrop (stringSplit text ":suite \"") 1)))]
    (uniq (listAppend cfg.liveSuites (filter (fn [(s String)] -> Bool (stringStartsWith? s cfg.liveRoot)) listed))))

; (:m :ref MERGE-TRAIN-SLOW :do "the selected suites of a unit: the direct suites, or with cfg.neighbours the graph selection; a live suite is dropped with SKIPPED-LIVE unless the change touches cfg.liveRoot; the rest is capped to the budget by cost")
fn ! selectedGates! cfg: Cfg unit: String wt: String -> (List String)
  (let [(d (gitOut! wt (list "diff" "--name-status" (str cfg.branch "...HEAD"))))
        (changes (map changeOf (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines d.out))))
        (remote (listAny? (fn [(c (Pair String String))] -> Bool (stringStartsWith? (pairSecond c) cfg.liveRoot)) changes))
        (live (liveSuites! cfg))
        (sel (if cfg.neighbours (neighbourSets! cfg unit wt) (let [(ds (directGates! cfg unit wt changes))] (pair ds ds))))
        (keep? (fn [(g String)] -> Bool (or remote (not (listContains? live (gateKey cfg g))))))
        (_ (map (fn [(g String)] -> Bool (emit! cfg unit "SKIPPED-LIVE" (str ":cmd " (q g) " :why \"the change touches nothing under " cfg.liveRoot "\"")))
                (filter (fn [(g String)] -> Bool (not (keep? g))) (pairSecond sel))))]
    (capNeighbours cfg unit (timesNow!) (filter keep? (pairFirst sel)) (filter keep? (pairSecond sel))))

; (:m :ref MERGE-NEIGHBOUR-FANOUT :do "the suites among gs whose source names a module changed by the branch in an import, (<module> ...), wherever that module lives: the import scan only covers /src/ files, so a change to tools/fleet/run.asl or mergeUnit.asl would otherwise have no direct importer")
fn ! importersOf! cfg: Cfg wt: String gs: (List String) -> (List String)
  (let [(d (gitOut! wt (list "diff" "--name-only" (str cfg.branch "...HEAD"))))
        (mods (filter (fn [(m String)] -> Bool (not (stringEmpty? m)))
                (map (fn [(f String)] -> String (moduleOf! (str wt "/" f))) (filter (fn [(f String)] -> Bool (stringEndsWith? f ".asl")) (stringLines d.out)))))]
    (if (listEmpty? mods)
      (list)
      (filter (fn [(g String)] -> Bool
                (let [(t (resultOr (fileReadString (str wt "/" (gateKey cfg g))) ""))]
                  (listAny? (fn [(m String)] -> Bool (stringContains? t (str "(" m " "))) mods)))
              gs)))

; (:m :ref MERGE-NEIGHBOUR-FANOUT :do "a file many suites depend on (the test runner, prelude, fleet/run) selects hundreds of neighbour suites and held the merge queue for hours; the selected suites cost their gateTimes median (60 s when unrecorded), and when they would need more than cfg.neighbourBudgetS of wall time on cfg.gateSlots slots, the suites that import the changed module directly (the import scan) are kept and the rest are sampled in a fixed order (sha256 of the suite path, so the same selection always gives the same sample) up to the budget; the event NEIGHBOUR-CAP names :n selected, :picked, :direct, :budgetS and :costS; a set within budget is returned unchanged and logs nothing; the default budget 1200 s is adopted, not measured: from ~/.asl/run/gateTimes.asn on 2026-11-11 (1504 suites, total 26429 s, median 1.9 s, p90 18 s, max 1949 s) 1200 s on 2 slots is 2400 slot-seconds, about 9% of all suite time, and the 60 s cost of an unrecorded suite is about 30 times the median")
fn costSecs cfg: Cfg times: (Map String Int64) g: String -> Int64
  (/ (+ (optionOr (mapGet times (gateKey cfg g)) 60000) 999) 1000)

fn sumSecs cfg: Cfg times: (Map String Int64) gs: (List String) -> Int64
  (fold (fn [(acc Int64) (g String)] -> Int64 (+ acc (costSecs cfg times g))) 0 gs)

fn pickWithin cfg: Cfg times: (Map String Int64) left: Int64 gs: (List String) acc: (List String) -> (List String)
  (match (listHead gs)
    ((none) (listReverse acc))
    ((some g)
      (let [(c (costSecs cfg times g))]
        (if (<= c left)
          (pickWithin cfg times (- left c) (optionOr (listTail gs) (list)) (cons g acc))
          (pickWithin cfg times left (optionOr (listTail gs) (list)) acc)))))

fn hashKey g: String -> String
  (bytesSha256 (stringToBytes g))

; (:m :ref MERGE-TRAIN-SLOW :do "the budget is never exceeded: the picked cost stays within cfg.neighbourBudgetS times the slots; direct suites are picked first in their order, each only while it fits, the rest sampled after them; :directDropped counts the direct suites that did not fit")
fn capNeighbours cfg: Cfg unit: String times: (Map String Int64) direct: (List String) gs: (List String) -> (List String)
  (let [(slots (max 1 cfg.gateSlots))
        (room (* cfg.neighbourBudgetS slots))
        (total (sumSecs cfg times gs))]
    (if (<= total room)
      gs
      (let [(directs (filter (fn [(g String)] -> Bool (listContains? direct g)) gs))
            (keep (pickWithin cfg times room directs (list)))
            (rest (listSortBy hashKey (filter (fn [(g String)] -> Bool (not (listContains? direct g))) gs)))
            (sample (pickWithin cfg times (max 0 (- room (sumSecs cfg times keep))) rest (list)))
            (picked (listAppend keep sample))]
        (do (emit! cfg unit "NEIGHBOUR-CAP" (str ":n " (stringFromInt64 (listLength gs)) " :picked " (stringFromInt64 (listLength picked)) " :direct " (stringFromInt64 (listLength keep)) " :budgetS " (stringFromInt64 cfg.neighbourBudgetS) " :costS " (stringFromInt64 (sumSecs cfg times picked)) " :directDropped " (stringFromInt64 (- (listLength directs) (listLength keep)))))
            picked))))

fn ! scanGates! cfg: Cfg wt: String -> (List String)
  (let [(d (gitOut! wt (list "diff" "--name-only" (str cfg.branch "...HEAD"))))
        (files (filter (fn [f] (and (stringContains? f "/src/") (stringEndsWith? f ".asl"))) (stringLines d.out)))
        (tests (fold (fn [acc f] (listAppend acc (testsFor! wt f))) (list) files))]
    (map (fn [t] (str cfg.testCmd " " t)) tests))

fn skipBlank text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (listContains? (list " " "\t" "\n" "\r") (optionOr (stringSlice text i (+ i 1)) "")))
    (skipBlank text (+ i 1))
    i)

; (:m :ref MERGEDOC-LOWS :do "the byte offset of the :x key that opens the export list: :x followed by any run of blanks or newlines (or none) and then [, so :x  [ and a list on the next line count and a longer key such as :xy does not; -1 when absent")
fn exportKeyAt text: String from: Int64 -> Int64
  (match (stringIndexOf (optionOr (stringSlice text from (stringLength text)) "") ":x")
    ((none) -1)
    ((some rel)
      (let [(at (+ from rel))
            (bracket (skipBlank text (+ at 2)))]
        (if (and (< bracket (stringLength text)) (= (optionOr (stringSlice text bracket (+ bracket 1)) "") "["))
          bracket
          (exportKeyAt text (+ at 2))))))

; (:m :ref MERGE-DOCLEDGER-GATE :do "the text of a module header's :x export list, whitespace normalised; empty when the file has none")
fn exportHeader text: String -> String
  (let [(bracketAt (exportKeyAt text 0))]
    (if (< bracketAt 0)
      ""
      (let [(rest (optionOr (stringSlice text (+ bracketAt 1) (stringLength text)) ""))
            (end (optionOr (stringIndexOf rest "]") (stringLength rest)))
            (flat (stringReplace (stringReplace (optionOr (stringSlice rest 0 end) "") "\n" " ") "\t" " "))]
        (stringJoin (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit flat " ")) " "))))

fn docFile? path: String -> Bool
  (and (stringEndsWith? path ".asn")
       (or (= path "doc.asn") (or (stringEndsWith? path "/doc.asn") (stringStartsWith? path "asl/doc/"))))

; (:m :ref MERGE-DOCLEDGER-GATE :do "a change line of git diff --name-status: the status letter and the new path (a rename names the new path last)")
fn changeOf line: String -> (Pair String String)
  (let [(parts (stringSplit line "\t"))]
    (pair (optionOr (stringSlice (optionOr (listHead parts) "") 0 1) "") (optionOr (listLast parts) "")))

; (:m :ref MERGEDOC-LOWS :do "the file as it was where the branch left main (git merge-base), not at main's tip: a main that moved on, or that already deleted or rewrote the file, must not hide what the branch deleted or changed")
fn ! baseText! cfg: Cfg wt: String path: String -> String
  (let [(mb (gitOut! wt (list "merge-base" cfg.branch "HEAD")))
        (rev (if (= mb.exit 0) (stringTrim mb.out) cfg.branch))
        (o (gitOut! wt (list "show" (str rev ":" path))))]
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

; (:m :ref MERGE-INVARIANT-GATES :do "gates compare by their text with runs of blanks collapsed, the first spelling wins, so an invariant the brief already names is run once, as the brief wrote it")
fn norm s: String -> String
  (stringJoin (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit s " ")) " ")

fn uniq xs: (List String) -> (List String)
  (fold (fn [acc x] (if (listAny? (fn [(y String)] -> Bool (= (norm y) (norm x))) acc) acc (listAppend acc (list x)))) (list) xs)

; (:m :ref MERGE-INVARIANT-GATES :do "the :enforcedBy command of every rule in the rules files (asl/grammar/rules.asn and the workspace .asl/rules.asn of the main repo), :none skipped")
fn ! rulesCmds! cfg: Cfg -> (List String)
  (fold (fn [acc path] (listAppend acc (enforcedIn (resultOr (fileReadString path) ""))))
        (list)
        (list (str cfg.main "/asl/grammar/rules.asn") (str cfg.main "/.asl/rules.asn")))

; (:m :ref MERGE-INVARIANT-GATES :do "the text of a quoted string up to its closing quote, with \\\" and \\\\ unescaped; a command may hold quotes, and a piece with no closing quote is read to its end")
fn quotedText chars: (List String) acc: (List String) -> String
  (match (listHead chars)
    ((none) (stringJoin (listReverse acc) ""))
    ((some c)
      (let [(rest (optionOr (listTail chars) (list)))]
        (cond
          ((= c "\"") (stringJoin (listReverse acc) ""))
          ((and (= c "\\") (some? (listHead rest)))
            (let [(n (optionOr (listHead rest) ""))]
              (if (or (= n "\"") (= n "\\"))
                (quotedText (optionOr (listTail rest) (list)) (cons n acc))
                (quotedText rest (cons c acc)))))
          (else (quotedText rest (cons c acc)))))))

fn enforcedIn text: String -> (List String)
  (map (fn [(piece String)] -> String (quotedText (stringChars piece) (list)))
       (listDrop (stringSplit text ":enforcedBy \"") 1))

; (:m :ref MERGE-INVARIANT-GATES :do "the recorded cost in seconds of a command from cfg.invariantCosts rows cmd=secs (the number after the last =); none when no row names it, which the caller treats as too costly to run unasked")
fn costOf cfg: Cfg cmd: String -> (Option Int64)
  (fold (fn [(best (Option Int64)) (row String)] -> (Option Int64)
          (let [(parts (stringSplit row "="))
                (n (listLength parts))]
            (if (and (> n 1) (= (norm (stringJoin (listTake parts (- n 1)) "=")) (norm cmd)))
              (stringToInt64 (optionOr (listLast parts) ""))
              best)))
        (none) cfg.invariantCosts)

; (:m :ref MERGE-INVARIANT-GATES :do "the invariant gates every unit with gates runs: the rules files' :enforcedBy commands, except the audit command (auditPass! runs that one in the worktree); a command whose recorded cost exceeds cfg.invariantCapS is skipped with a SKIPPED-OVERCAP event, and one no cost row names is skipped with SKIPPED-UNCOSTED, so a new slow invariant never joins silently")
fn ! invariantGates! cfg: Cfg unit: String -> (List String)
  (let [(cmds (filter (fn [(c String)] -> Bool (and (not (stringEmpty? c)) (!= (norm c) (norm cfg.audit)))) (uniq (rulesCmds! cfg))))]
    (filter (fn [(c String)] -> Bool
              (match (costOf cfg c)
                ((none) (do (emit! cfg unit "SKIPPED-UNCOSTED" (str ":cmd " (q c))) false))
                ((some secs) (if (<= secs cfg.invariantCapS) true
                               (do (emit! cfg unit "SKIPPED-OVERCAP" (str ":cmd " (q c) " :costS " secs " :capS " cfg.invariantCapS)) false)))))
            cmds))

; (:m :ref MERGE-NEIGHBOURS-PAR :do "a gate's key in the gate times file is its suite path: the test command prefix is dropped, any other command keeps its whole text")
fn gateKey cfg: Cfg g: String -> String
  (let [(pre (str cfg.testCmd " "))]
    (if (stringStartsWith? g pre) (stringTrim (optionOr (stringSlice g (stringLength pre) (stringLength g)) "")) g))

; (:m :ref MERGE-NEIGHBOURS-PAR :do "start order of the gates, longest first by the gateTimes median, a gate with no recorded time first (treated as heavy); the result lists gate indexes")
fn gateOrder cfg: Cfg gates: (List String) times: (Map String Int64) -> (List Int64)
  (st/startOrder (map (fn [(g String)] -> String (gateKey cfg g)) gates) times)

fn ! timesNow! -> (Map String Int64)
  (match (st/timesPath!)
    ((ok p) (resultOr (st/readTimes! p) (mapEmpty)))
    ((err _) (mapEmpty)))

fn ! gateJob wt: String cmd: String -> fr/Job
  (fr/job (list "env" "-u" "ASL_ROOT" "-u" "ASL_PRELUDE" "nice" "-n" "10" "sh" "-c" cmd) wt (fr/childEnv (list)))

fn posOf order: (List Int64) gi: Int64 -> Int64
  (fold (fn [(acc Int64) (p (Pair Int64 Int64))] -> Int64 (if (= (pairSecond p) gi) (pairFirst p) acc)) -1 (enumerate order))

; (:m :ref MERGE-NEIGHBOURS-PAR :do "every gate runs in the worktree through the fleet pool, cfg.gateSlots at a time, longest first; the result is one green flag per gate in the gates' own order, so verdicts do not depend on the run order")
fn ! greensOf! cfg: Cfg wt: String gates: (List String) -> (List Bool)
  (let [(order (gateOrder cfg gates (timesNow!)))
        (jobs (map (fn [(i Int64)] -> fr/Job (gateJob wt (optionOr (listGet gates i) ""))) order))
        (dones (fr/runPoolLimited jobs cfg.gateSlots (fr/limits cfg.gateSecs 64)))]
    (map (fn [(gi Int64)] -> Bool
           (let [(pos (posOf order gi))]
             (listAny? (fn [(d fr/Done)] -> Bool (and (= d.idx pos) (green? d))) dones)))
         (range 0 (listLength gates))))

fn ! gatesPass! cfg: Cfg unit: String wt: String gates: (List String) -> Bool
  (let [(greens (greensOf! cfg wt gates))]
    (fold (fn [(ok0 Bool) (i Int64)] -> Bool
            (let [(g (optionOr (listGet gates i) ""))]
              (if (optionOr (listGet greens i) false)
                (do (emit! cfg unit "GATE" (str ":cmd " (q g) " :exit 0")) ok0)
                (let [(v (gateVerdict! cfg g))]
                  (do (emit! cfg unit v (str ":cmd " (q g)))
                      (and ok0 (= v "BASE-RED")))))))
          true (range 0 (listLength gates))))

fn ! auditPass! cfg: Cfg wt: String -> Bool
  (if (or (stringEmpty? cfg.audit) (= cfg.audit "none")) true
    (let [(d (sh! wt cfg.audit cfg.auditSecs))]
      (and (= d.verdict "exit") (stringContains? d.out "audit consistency: passed"))))

; (:m :do "the rebase of the worktree onto the main branch; a conflict is aborted and reported false")
; (:m :ref BASH-EXIT-MERGE :do "a build leaves the tracked .asl.config.asn modified, and a dirty tree makes the rebase fail as a false conflict: that one path is restored from HEAD through the vcs layer first (an untracked or absent file is a no-op)")
; (:m :ref MERGEUNIT-FF-NOREBASE :do "2026-11-12 LRED-sessionPool: --branch named the unit's own branch, so the rebase onto it was a no-op that exited 0, REBASED-ONTO-MOVED-MAIN was emitted twice and FF-FAIL followed; the main checkout HEAD sha is read once, the worktree rebases onto that sha and the result is empty only when HEAD then contains it; else conflict: (aborted), failed: (refused, nothing to abort) or notOnMain: with the git output")
fn ! rebaseOnto! cfg: Cfg wt: String -> String
  (let [(_ (if (stringEmpty? (stringTrim (vg/changes! wt (list ".asl.config.asn")).out)) 0 (do (vg/restoreTree! wt "HEAD" (list ".asl.config.asn")) 0)))
        (h (vg/head! cfg.main))
        (mainHead (stringTrim h.out))]
    (if (or (!= h.exit 0) (stringEmpty? mainHead))
      (str "notOnMain: the main checkout has no HEAD: " (stringTrim h.out))
      (let [(r (gitOut! wt (list "rebase" "-q" mainHead)))]
        (if (!= r.exit 0)
          (if (rebasing! wt)
            (do (gitOut! wt (list "rebase" "--abort")) (str "conflict: " (stringTrim r.out)))
            (str "failed: " (stringTrim r.out)))
          (let [(has (gitOut! wt (list "merge-base" "--is-ancestor" mainHead "HEAD")))]
            (if (= has.exit 0) ""
              (str "notOnMain: HEAD does not contain main " mainHead " after git rebase" (if (stringEmpty? (stringTrim has.out)) "" (str ": " (stringTrim has.out))))))))))

; (:m :ref MERGEUNIT-FF-NOREBASE :do "a rebase stopped mid-way leaves rebase-merge or rebase-apply in the worktree's git dir: that is a conflict to abort; a rebase refused up front (dirty tree) leaves neither and needs no abort")
fn ! rebasing! wt: String -> Bool
  (let [(m (gitOut! wt (list "rev-parse" "--git-path" "rebase-merge")))
        (a (gitOut! wt (list "rev-parse" "--git-path" "rebase-apply")))
        (abs (fn [(p String)] -> String (if (stringStartsWith? p "/") p (str wt "/" p))))]
    (or (and (= m.exit 0) (fileExists? (abs (stringTrim m.out)))) (and (= a.exit 0) (fileExists? (abs (stringTrim a.out))))))

; (:m :ref MERGEUNIT-FF-NOREBASE :do "true when the rebase landed on main; a conflict emits conflictEvent, a refused rebase or one that left HEAD off main emits REBASE-FAILED, both with the git output")
fn ! rebased! cfg: Cfg unit: String wt: String conflictEvent: String -> Bool
  (let [(why (rebaseOnto! cfg wt))]
    (cond
      ((stringEmpty? why) true)
      ((stringStartsWith? why "conflict: ") (do (emit! cfg unit conflictEvent (str ":git " (q why))) false))
      (else (do (emit! cfg unit "REBASE-FAILED" (str ":git " (q why))) false))))

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
      ((not (rebased! cfg unit wt "REBASE-CONFLICT-AT-MERGE")) false)
      (else
        (do (emit! cfg unit "REBASED-ONTO-MOVED-MAIN" ":note \"disjoint; the gates ran on the earlier base\"")
            (ffLoop! cfg unit wt branch (+ try 1))))))

; (:m :ref MERGE-QUEUE-LOCK :do "the main-merge lock directory: cfg.mergeLock, or cfg.lock with .merge appended; it holds a pid file naming the owner")
fn lockDirOf cfg: Cfg -> String
  (if (stringEmpty? cfg.mergeLock) (str cfg.lock ".merge") cfg.mergeLock)

fn ! ownerOf! dir: String -> Int64
  (optionOr (stringToInt64 (stringTrim (resultOr (fileReadString (str dir "/pid")) ""))) -1)

fn ! parentDir! path: String -> String
  (stringJoin (listTake (stringSplit path "/") (- (listLength (stringSplit path "/")) 1)) "/")

; (:m :ref MERGE-LOCK-RESIDUAL :do "a claim is a private directory that already holds the pid file, renamed to the lock path in one step: rename(2) onto an existing non-empty directory fails, so exactly one claimant wins, and the lock is never visible without its pid (no mkdir-to-pid-write window); an existing path is refused first so a half-made legacy empty directory is never replaced")
fn ! claimDir! dir: String -> Bool
  (let [(_ (dirCreate (parentDir! dir)))
        (priv (str dir ".new." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
    (if (ok? (fileStat dir))
      false
      (if (and (ok? (dirCreate priv)) (ok? (fileWrite (str priv "/pid") (stringFromInt64 (procSelf)))) (ok? (pathRename priv dir)))
        true
        (do (pathRemove priv) false))))

fn ! tryLock! dir: String -> Bool
  (claimDir! dir)

; (:m :ref MERGE-QUEUE-LOCK :do "a lock is stale when its owner pid is dead, or when it has no pid file and is older than 30 s (a holder that died between mkdir and the pid write); it is taken over by an atomic rename to a private name, so two takers cannot both win, and a lock that turns out to be live again is not kept")
fn ! staleOwner! dir: String -> (Option Int64)
  (let [(o (ownerOf! dir))]
    (cond
      ((> o 1) (if (resultOr (procAlive? o) true) (none) (some o)))
      (else (match (fileStat dir)
              ((ok st) (if (> (- (/ (nowNs) 1000000000) st.mtime) 30) (some o) (none)))
              ((err _) (none))))))

fn ! mvDir! from: String to: String -> Bool
  (= (fr/runOneLimited (fr/job (list "mv" from to) "." (fr/childEnv (list))) (fr/limits 20 8)).exit 0)

; (:m :ref MERGE-LOCK-RESIDUAL :do "a takeover is serialised by its own claim, dir.takeover, taken like the lock itself: while it is held no other taker can touch the lock, and a lock directory with a pid cannot be replaced, so the dead owner re-read under the claim is still the one removed and the removal never needs an undo; a live lock, or a dead owner other than the one this taker saw, leaves the lock alone; a takeover claim whose owner died is removed once it is older than 30 s")
fn ! takeOver! cfg: Cfg unit: String dir: String owner: Int64 -> Bool
  (let [(claim (str dir ".takeover"))]
    (if (not (claimDir! claim))
      (do (match (staleOwner! claim) ((some _) (pathRemove claim)) ((none) (ok ()))) false)
      (let [(again (staleOwner! dir))
            (mine (str dir ".stale." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))
            (took (match again
                    ((some o) (and (= o owner) (mvDir! dir mine)))
                    ((none) false)))
            (_ (if took (pathRemove mine) (ok ())))
            (_ (if took (emit! cfg unit "LOCK-TAKEOVER" (str ":deadPid " owner)) true))
            (_ (releaseLock! claim))]
        took)))

; (:m :ref MERGE-QUEUE-LOCK :do "release removes the lock only when its pid file still names this process: the directory is renamed away, the pid verified, then removed; a lock that names someone else is put back")
fn ! releaseLock! dir: String -> Bool
  (let [(mine (str dir ".rel." (stringFromInt64 (procSelf)) "." (stringFromInt64 (nowNs))))]
    (if (not (mvDir! dir mine)) false
      (if (= (ownerOf! mine) (procSelf))
        (do (pathRemove mine) true)
        (do (or (mvDir! mine dir) (do (pathRemove mine) false))
            false))))

fn ! lockLoop! cfg: Cfg unit: String dir: String deadline: Int64 waited: Bool -> Bool
  (cond
    ((tryLock! dir) true)
    ((>= (monotonicNs) deadline) (do (emit! cfg unit "LOCK-TIMEOUT" (str ":holder " (stringFromInt64 (ownerOf! dir)))) false))
    (else
      (match (staleOwner! dir)
        ((some o) (do (takeOver! cfg unit dir o) (lockLoop! cfg unit dir deadline waited)))
        ((none) (do (if waited true (emit! cfg unit "LOCK-WAIT" (str ":holder " (stringFromInt64 (ownerOf! dir)))))
                    (sleepMs 500)
                    (lockLoop! cfg unit dir deadline true))))))

; (:m :ref MERGE-QUEUE-LOCK :do "the LOCK-RELEASED event is written just before the lock is released, so a waiter that takes the lock at once can never log LOCK-ACQUIRED ahead of it; body runs while this process holds the main-merge lock; concurrent callers queue on it for at most cfg.lockWaitS and then fail with LOCK-TIMEOUT")
fn ! withLock! cfg: Cfg unit: String body: (fn [] -> Bool) -> Bool
  (let [(dir (lockDirOf cfg))]
    (if (not (lockLoop! cfg unit dir (+ (monotonicNs) (* cfg.lockWaitS 1000000000)) false)) false
      (do (emit! cfg unit "LOCK-ACQUIRED" (str ":pid " (stringFromInt64 (procSelf))))
          (let [(r (body))]
            (do (emit! cfg unit "LOCK-RELEASED" "")
                (releaseLock! dir)
                r)))))

; (:m :do "one unit end to end; hook runs after the gates and the audit, just before the first merge attempt (the test moves main there). true when merged")
fn ! mergeUnitWith! cfg: Cfg unit: String hook: (fn [] -> Bool) -> Bool
  (withLock! cfg unit (fn [] -> Bool (mergeLocked! cfg unit hook)))

; (:m :ref MERGEUNIT-FF-NOREBASE :do "--branch equal to the worktree's checked-out branch is the 2026-11-12 misuse: refused before the rebase and any gate")
fn ! branchIsTarget! cfg: Cfg wt: String -> Bool
  (let [(b (gitOut! wt (list "branch" "--show-current")))]
    (and (= b.exit 0) (= (stringTrim b.out) cfg.branch)))

fn ! mergeLocked! cfg: Cfg unit: String hook: (fn [] -> Bool) -> Bool
  (let [(wt (str cfg.worktrees "/asex-" unit))]
    (cond
      ((not (fileExists? wt)) (do (emit! cfg unit "NO-WORKTREE" (str ":path " (q wt))) false))
      ((branchIsTarget! cfg wt) (do (emit! cfg unit "BRANCH-IS-TARGET" (str ":branch " (q cfg.branch) " :why \"--branch names the branch to rebase onto and merge into (default main); it is the worktree's own checked-out branch, so the rebase would be a no-op\"")) false))
      ((not (rebased! cfg unit wt "REBASE-CONFLICT")) false)
      ((not (hostBuild! wt)) (do (emit! cfg unit "BUILD-FAIL" "") false))
      (else
        (let [(own (unitGates! cfg unit wt))
              (gates (uniq (listAppend own (if (listEmpty? own) (list) (invariantGates! cfg unit)))))]
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

fn leadDigits chars: (List String) acc: String -> String
  (match (listHead chars)
    ((none) acc)
    ((some c) (if (stringContains? "0123456789" c) (leadDigits (optionOr (listTail chars) (list)) (str acc c)) acc)))

; (:m :ref MERGE-TRAIN-SLOW :do "the brief's own selection keys: :neighbours true turns the graph neighbours on for the unit, :budgetS N (N > 0) replaces the neighbour budget")
fn briefCfg cfg: Cfg text: String -> Cfg
  (let [(c1 (if (stringContains? text ":neighbours true") (with cfg :neighbours true) cfg))]
    (match (stringIndexOf text ":budgetS ")
      ((none) c1)
      ((some at)
        (let [(n (optionOr (stringToInt64 (leadDigits (stringChars (stringTrim (optionOr (stringSlice text (+ at 9) (stringLength text)) ""))) "")) 0))]
          (if (> n 0) (with c1 :neighbourBudgetS n) c1)))))

; (:m :ref MERGE-TRAIN-SLOW :do "a unit's own gates in order: the brief's :gates, then (when the brief names any) its selected suites and the doc ledger gate; empty when the brief names none")
fn ! unitGates! cfg: Cfg unit: String wt: String -> (List String)
  (let [(brief (gatesOf! unit cfg))
        (c (briefCfg cfg (resultOr (fileReadString (str cfg.briefDir "/" unit "-leon.asn")) "")))]
    (if (listEmpty? brief) (list)
      (uniq (listAppend brief (listAppend (selectedGates! c unit wt) (ledgerGates! c wt))))))

; (:m :ref MERGE-TRAIN-SLOW :do "one unit of a batch: its commits not on main are cherry-picked onto the integration worktree; some gates when they landed, none (with an event naming the unit) for no worktree, --branch as its own branch, no brief gates, nothing to merge, a branch holding merge commits (BATCH-HAS-MERGES: a cherry-pick would drop the resolution) or a conflict (aborted)")
fn ! batchUnit! cfg: Cfg iwt: String mainHead: String unit: String -> (Option (List String))
  (let [(wt (str cfg.worktrees "/asex-" unit))]
    (cond
      ((not (fileExists? wt)) (do (emit! cfg unit "NO-WORKTREE" (str ":path " (q wt))) (none)))
      ((branchIsTarget! cfg wt) (do (emit! cfg unit "BRANCH-IS-TARGET" (str ":branch " (q cfg.branch))) (none)))
      (else
        (let [(gates (unitGates! cfg unit wt))
              (h (gitOut! wt (list "rev-parse" "HEAD")))
              (revs (gitOut! cfg.main (list "rev-list" "--reverse" (str mainHead ".." (stringTrim h.out)))))
              (merges (gitOut! cfg.main (list "rev-list" "--merges" (str mainHead ".." (stringTrim h.out)))))
              (shas (filter (fn [(s String)] -> Bool (not (stringEmpty? s))) (map stringTrim (stringLines revs.out))))]
          (cond
            ((listEmpty? gates) (do (emit! cfg unit "NO-GATES" (str ":brief " (q (str cfg.briefDir "/" unit "-leon.asn")))) (none)))
            ((or (!= h.exit 0) (!= revs.exit 0)) (do (emit! cfg unit "BATCH-PICK-FAIL" (str ":git " (q (stringTrim (str h.out " " revs.out))))) (none)))
            ((not (stringEmpty? (stringTrim merges.out))) (do (emit! cfg unit "BATCH-HAS-MERGES" ":why \"a cherry-pick cannot carry a merge resolution; merge this unit alone or rebase it flat\"") (none)))
            ((listEmpty? shas) (do (emit! cfg unit "NOTHING-TO-MERGE" "") (none)))
            (else
              (let [(cp (gitOut! iwt (listAppend (list "cherry-pick") shas)))]
                (if (= cp.exit 0)
                  (do (emit! cfg unit "BATCH-PICKED" (str ":commits " (stringFromInt64 (listLength shas)))) (some gates))
                  (do (gitOut! iwt (list "cherry-pick" "--abort"))
                      (emit! cfg unit "BATCH-CONFLICT" (str ":git " (q (stringTrim cp.out))))
                      (none))))))))))

; (:m :ref MERGE-TRAIN-SLOW :do "the units whose gate set holds g (by normalised text); every unit when none does (an invariant gate)")
fn ownersOf picked: (List (Pair String (List String))) g: String -> (List String)
  (let [(own (map pairFirst (filter (fn [(p (Pair String (List String)))] -> Bool (listAny? (fn [(x String)] -> Bool (= (norm x) (norm g))) (pairSecond p))) picked)))]
    (if (listEmpty? own) (map pairFirst picked) own))

; (:m :ref MERGE-TRAIN-SLOW :do "the union of the picked units' gates runs once in the integration worktree; a red gate is judged against main and its verdict is logged under every unit that selected it; the blocking units are returned")
fn ! batchBlockers! cfg: Cfg name: String iwt: String picked: (List (Pair String (List String))) gates: (List String) -> (List String)
  (let [(greens (greensOf! cfg iwt gates))]
    (fold (fn [(acc (List String)) (i Int64)] -> (List String)
            (let [(g (optionOr (listGet gates i) ""))
                  (own (ownersOf picked g))]
              (if (optionOr (listGet greens i) false)
                (do (emit! cfg name "GATE" (str ":cmd " (q g) " :exit 0")) acc)
                (let [(v (gateVerdict! cfg g))
                      (_ (map (fn [(u String)] -> Bool (emit! cfg u v (str ":cmd " (q g) " :batch " (q name)))) own))]
                  (if (= v "BASE-RED") acc (uniq (listAppend acc own)))))))
          (list) (range 0 (listLength gates))))

fn ! batchGated! cfg: Cfg name: String iwt: String picked: (List (Pair String (List String))) hook: (fn [] -> Bool) -> Bool
  (let [(units (map pairFirst picked))]
    (cond
      ((listEmpty? picked) (do (emit! cfg name "BATCH-EMPTY" "") false))
      ((not (hostBuild! iwt)) (do (emit! cfg name "BUILD-FAIL" "") false))
      (else
        (let [(gates (uniq (listAppend (fold (fn [(acc (List String)) (p (Pair String (List String)))] -> (List String) (listAppend acc (pairSecond p))) (list) picked) (invariantGates! cfg name))))
              (_ (emit! cfg name "BATCH-GATES" (str ":units (" (stringJoin (map q units) " ") ") :n " (stringFromInt64 (listLength gates)))))
              (blockers (batchBlockers! cfg name iwt picked gates))]
          (cond
            ((not (listEmpty? blockers))
              (do (map (fn [(u String)] -> Bool (emit! cfg u "GATE-FAIL" (str ":batch " (q name)))) blockers)
                  (emit! cfg name "BATCH-FAIL" (str ":red (" (stringJoin (map q blockers) " ") ")"))
                  false))
            ((not (auditPass! cfg iwt)) (do (emit! cfg name "AUDIT-FAIL" "") false))
            (else
              (let [(_ (hook))]
                (if (ffLoop! cfg name iwt name 1)
                  (let [(h (vg/head! cfg.main))
                        (sha (q (stringTrim h.out)))]
                    (do (map (fn [(u String)] -> Bool (emit! cfg u "MERGED" (str ":sha " sha " :batch " (q name)))) units)
                        (emit! cfg name "BATCH-MERGED" (str ":sha " sha " :units " (stringFromInt64 (listLength units))))
                        (mainBuild! cfg name)
                        true))
                  false))))))))

fn ! batchClean! cfg: Cfg name: String iwt: String -> Bool
  (let [(r (vg/worktreeRemove! cfg.main iwt))
        (b (gitOut! cfg.main (list "branch" "-D" name)))]
    (and (= r.exit 0) (= b.exit 0)))

fn ! batchLocked! cfg: Cfg name: String units: (List String) hook: (fn [] -> Bool) -> Bool
  (let [(h (vg/head! cfg.main))
        (mainHead (stringTrim h.out))
        (iwt (str cfg.worktrees "/asex-" name))
        (add (vg/worktreeAdd! cfg.main iwt mainHead))
        (sw (if (= add.exit 0) (vg/switch! iwt name mainHead) add))]
    (if (or (!= h.exit 0) (!= sw.exit 0))
      (do (emit! cfg name "BATCH-FAIL" (str ":why " (q (str "integration worktree: " (stringTrim sw.out)))))
          (if (= add.exit 0) (batchClean! cfg name iwt) true)
          false)
      (let [(picked (fold (fn [(acc (List (Pair String (List String)))) (u String)] -> (List (Pair String (List String)))
                            (match (batchUnit! cfg iwt mainHead u)
                              ((some gs) (listAppend acc (list (pair u gs))))
                              ((none) acc)))
                          (list) units))
            (merged (batchGated! cfg name iwt picked hook))
            (cleaned (batchClean! cfg name iwt))]
        (do (if cleaned true (emit! cfg name "BATCH-CLEAN-FAIL" (str ":path " (q iwt))))
            (and merged (= (listLength picked) (listLength units)))))))

; (:m :ref MERGE-TRAIN-SLOW :do "several units merged as one batch under the main-merge lock: an integration branch batch-NS from main's HEAD in its own worktree, each unit's commits cherry-picked onto it in order, the union of their gates run once there, one fast-forward of main, then the integration worktree and branch removed; a unit that cannot be picked is left out and named, a blocking red names the units that selected the gate and nothing merges; true when every unit merged. hook runs just before the fast-forward")
fn ! mergeBatchWith! cfg: Cfg units: (List String) hook: (fn [] -> Bool) -> Bool
  (let [(name (str "batch-" (stringFromInt64 (nowNs))))]
    (withLock! cfg name (fn [] -> Bool (batchLocked! cfg name units hook))))

fn ! mergeBatch! cfg: Cfg units: (List String) -> Bool
  (mergeBatchWith! cfg units (fn [] true))

(schema Parsed
  (:f cfg Cfg)
  (:f after Int64)
  (:f units (List String))
  (:f batch Bool :default false)
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
          ((= a "--neighbours") (parseLoop rest (with p :cfg (with c :neighbours true))))
          ((stringEmpty? v) (with p :error (str a " needs a value")))
          ((= a "--batch") (parseLoop more (with p :batch true :units (listAppend p.units (filter (fn [(u String)] -> Bool (not (stringEmpty? u))) (stringSplit v ","))))))
          ((= a "--main") (parseLoop more (with p :cfg (with c :main v))))
          ((= a "--worktrees") (parseLoop more (with p :cfg (with c :worktrees v))))
          ((= a "--brief-dir") (parseLoop more (with p :cfg (with c :briefDir v))))
          ((= a "--audit") (parseLoop more (with p :cfg (with c :audit v))))
          ((= a "--lock") (parseLoop more (with p :cfg (with c :lock v))))
          ((= a "--log") (parseLoop more (with p :cfg (with c :log v))))
          ((= a "--branch") (parseLoop more (with p :cfg (with c :branch v))))
          ((= a "--gate-secs") (parseLoop more (with p :cfg (with c :gateSecs (intOpt v)))))
          ((= a "--audit-secs") (parseLoop more (with p :cfg (with c :auditSecs (intOpt v)))))
          ((= a "--merge-lock") (parseLoop more (with p :cfg (with c :mergeLock v))))
          ((= a "--graph-dir") (parseLoop more (with p :cfg (with c :graphDir v))))
          ((= a "--neighbour-budget-secs") (parseLoop more (with p :cfg (with c :neighbourBudgetS (intOpt v)))))
          ((= a "--lock-wait") (parseLoop more (with p :cfg (with c :lockWaitS (intOpt v)))))
          ((= a "--asl-bin") (parseLoop more (with p :cfg (with c :aslBin v))))
          ((= a "--gate-slots") (parseLoop more (with p :cfg (with c :gateSlots (intOpt v)))))
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
      ((<= c.neighbourBudgetS 0) (with p :error "--neighbour-budget-secs must be a positive integer"))
      ((< p.after 0) (with p :error "--after needs a pid"))
      ((listEmpty? p.units) (with p :error "no unit named"))
      (else p)))

fn usage -> String
  "usage: bin/asl run asl/tools/fleet/mergeUnit.asl [--main DIR] [--worktrees DIR] [--brief-dir DIR] [--after PID] [--audit CMD|none] [--gate-secs N] [--audit-secs N] [--lock DIR] [--log FILE] [--branch B] [--neighbour-budget-secs N] [--neighbours] [--batch U1,U2,...] UNIT...\n  --branch B: the branch every unit is rebased onto and fast-forwarded into (default main); never the unit's own branch\n  --neighbours: add the graph neighbour suites to the direct ones (a brief :neighbours true does it per unit)\n  --batch U1,U2: cherry-pick the units onto one integration branch, run the union of their gates once, fast-forward main once"

fn ! main args: (List String) -> (Result Int64 String)
  (let [(p (parseArgs args))]
    (if (not (stringEmpty? p.error))
      (do (eprintln (str "mergeUnit: " p.error)) (eprintln (usage)) (ok 2))
      (let [(waited (waitPid! p.after 10800))
            (c p.cfg)]
        (if (not waited)
          (do (emit! c "" "AFTER-TIMEOUT" (str ":pid " p.after)) (ok 3))
          (let [(merged (if p.batch (list (mergeBatch! c p.units)) (map (fn [u] (mergeUnit! c u)) p.units)))
                (_ (if (or (stringEmpty? c.audit) (= c.audit "none")) true
                     (let [(d (sh! c.main c.audit c.auditSecs))]
                       (emit! c "" "MAIN-AUDIT" (str ":passed " (if (and (= d.verdict "exit") (stringContains? d.out "audit consistency: passed")) "true" "false"))))))]
            (ok (if (listAll? (fn [m] m) merged) 0 1)))))))
