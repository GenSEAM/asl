(module asl-tools/remote/vpsNode
  :x [restartedReadScript restartedMarkScript restartedOf rangeBase restartDone? poolRestartScript poolRestartReceipt daemons jobWaitScript jobWaitReceipt tailScript tailReceipt getScript getMeta getReceipt putScript putReceipt putRelOk? refsScript refsReceipt killScript killReceipt pruneScript pruneReceipt devPromoteScript devPromoteReceipt hubRestartScript hubRestartReceipt warmTouched? warmScript warmReceipt groupText warmArgs warmBudgetS gwScript gwReceipt errLoc errFile locateScript locateReceipt eventsScript eventsReceipt]
  :i [(asl-tools/remote/form :a fm) (asl-tools/remote/nodeStat :a ns)])

; (:m :ref RELAYVERBS :do "node verbs: each is a constant sh script with positional operands (so no operand is reparsed) plus a pure receipt function over the exit code and stdout; vps.asl only runs them, so this module needs no ssh and the fixture tests feed it text")
fn fields line: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringTrim line) " "))

fn at xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

fn num s: String -> Int64
  (optionOr (stringToInt64 s) 0)

fn errRec code: String msg: String -> String
  (str "(:err :code " code " :msg " (fm/quoteText msg) ")")

fn lastLine text: String -> String
  (optionOr (listLast (stringLines (stringTrim text))) "")

; (:m :ref RELAYVERBS :do "job wait: blocks on the node (one bounded round trip) until the job log holds the fixed-string pattern, the job has an exit record, or the seconds run out; answers matched, exited N, lost (pid gone without an exit record), timeout or none")
fn jobWaitScript -> String
  "jd=$1; n=$2; pat=$3; secs=$4; lf=$jd/$n.log; xf=$jd/$n.exit; i=0; while :; do if [ -n \"$pat\" ] && [ -f \"$lf\" ] && grep -qF -- \"$pat\" \"$lf\"; then echo matched; exit 0; fi; if [ -f \"$xf\" ]; then echo \"exited $(cat \"$xf\")\"; exit 0; fi; pf=$jd/$n.pid; [ -f \"$pf\" ] || { echo none; exit 0; }; pid=$(sed -n 1p \"$pf\"); rec=$(sed -n 2p \"$pf\"); now=$(ps -o lstart= -p \"$pid\" 2>/dev/null | sed 's/^ *//'); if [ \"$now\" != \"$rec\" ]; then echo \"lost $pid\"; exit 0; fi; if [ \"$i\" -ge \"$secs\" ]; then echo timeout; exit 0; fi; sleep 1; i=$((i+1)); done"

fn jobWaitReceipt name: String exit: Int64 out: String -> String
  (let [(f (fields (lastLine out)))
        (r (at f 0))]
    (cond
      ((= r "matched") (str "(:jobWait :name " (fm/quoteText name) " :result matched)"))
      ((= r "exited") (str "(:jobWait :name " (fm/quoteText name) " :result exited :exit " (num (at f 1)) ")"))
      ((= r "timeout") (str "(:jobWait :name " (fm/quoteText name) " :result timeout)"))
      ((= r "none") (str "(:jobWait :name " (fm/quoteText name) " :result none)"))
      ((= r "lost") (str "(:jobWait :name " (fm/quoteText name) " :result lost)"))
      (else (errRec "waitFailed" (str "exit " exit ": " (lastLine out))))))

; (:m :ref RELAYVERBS :do "tail: read-only, bounded to files under the account home or /tmp, refused for ssh gnupg env key pem token secret and id_ files and anything that resolves outside; every line goes through the argument masker; 1000 lines at most")
fn tailScript -> String
  "p=$1; n=$2; case \"$p\" in /tmp/*|/var/tmp/*) full=$p;; /*) exit 3;; *) full=$HOME/$p;; esac; while [ \"${full%/}\" != \"$full\" ] && [ -n \"${full%/}\" ]; do full=${full%/}; done; if [ -e \"$full\" ]; then real=$(realpath -- \"$full\" 2>/dev/null) || exit 3; else rd=$(realpath -- \"$(dirname -- \"$full\")\" 2>/dev/null) || exit 3; real=$rd/$(basename -- \"$full\"); fi; rh=$(realpath -- \"$HOME\" 2>/dev/null) || rh=$HOME; case \"$real\" in \"$HOME\"/*|\"$rh\"/*|/tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*) ;; *) exit 3;; esac; lc=$(printf %s \"$real\" | tr A-Z a-z); case \"$lc\" in */.ssh/*|*/.gnupg/*|*keys.env*|*.env|*.key|*.pem|*id_rsa*|*id_ed25519*|*secret*|*token*|*gateway.asn*) exit 3;; esac; [ -f \"$real\" ] || exit 4; tail -n \"$n\" -- \"$real\""

fn tailReceipt path: String exit: Int64 out: String -> String
  (cond
    ((= exit 3) (errRec "denied" "path is outside home and /tmp, or names a key, token or secret file"))
    ((= exit 4) (errRec "notFound" "no such file"))
    ((!= exit 0) (errRec "tailFailed" (str "exit " exit)))
    (else
      (let [(body (if (stringEndsWith? out "\n") (optionOr (stringSlice out 0 (- (stringLength out) 1)) out) out))
            (ls (stringLines body))
            (masked (map (fn [(l String)] -> String (ns/maskLine l 2000)) ls))]
        (str "(:tail :path " (fm/quoteText path) " :lines " (listLength ls) " :out " (fm/quoteText (stringJoin masked "\n")) ")"))))

; (:m :ref RELAYVERBS :do "put: the file bytes travel as the stdin of one exec (the relay stages anything over 48 KiB), so no argument-size limit; the destination is a relative path inside the unit worktree with no .. segment and no .git, written to a temp name then renamed")
fn putRelOk? rel: String -> Bool
  (and (not (stringEmpty? rel))
       (and (not (stringStartsWith? rel "/"))
            (and (not (stringContains? rel " "))
                 (listAll? (fn [(seg String)] -> Bool (and (not (stringEmpty? seg)) (and (not (= seg "..")) (not (= seg ".git"))))) (stringSplit rel "/")))))

; (:m :ref RELAY-SH-64K-TAIL :do "get PATH: the same path rule as tail (home, /tmp or /var/tmp, no key, token or secret names); stdout is the gzip of the whole file and stderr one line `sha HEX BYTES` taken before it, so the client checks what it unpacked; exit 3 denied, 4 no file, 5 no sha tool")
fn getScript -> String
  "p=$1; case \"$p\" in /tmp/*|/var/tmp/*) full=$p;; /*) exit 3;; *) full=$HOME/$p;; esac; while [ \"${full%/}\" != \"$full\" ] && [ -n \"${full%/}\" ]; do full=${full%/}; done; if [ -e \"$full\" ]; then real=$(realpath -- \"$full\" 2>/dev/null) || exit 3; else rd=$(realpath -- \"$(dirname -- \"$full\")\" 2>/dev/null) || exit 3; real=$rd/$(basename -- \"$full\"); fi; rh=$(realpath -- \"$HOME\" 2>/dev/null) || rh=$HOME; case \"$real\" in \"$HOME\"/*|\"$rh\"/*|/tmp/*|/var/tmp/*|/private/tmp/*|/private/var/tmp/*) ;; *) exit 3;; esac; lc=$(printf %s \"$real\" | tr A-Z a-z); case \"$lc\" in */.ssh/*|*/.gnupg/*|*keys.env*|*.env|*.key|*.pem|*id_rsa*|*id_ed25519*|*secret*|*token*|*gateway.asn*) exit 3;; esac; [ -f \"$real\" ] || exit 4; s=$( (sha256sum -- \"$real\" || shasum -a 256 -- \"$real\") 2>/dev/null) || exit 5; n=$(wc -c < \"$real\"); echo \"sha ${s%% *} $n\" >&2; gzip -c < \"$real\""

; (:m :do "the sha line of a get's stderr: (sha bytes), empty sha when absent")
fn getMeta err: String -> (Pair String Int64)
  (match (listFind (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "sha ")) (stringLines err))
    ((some l) (let [(f (fields l))] (pair (at f 1) (num (at f 2)))))
    ((none) (pair "" -1)))

fn getReceipt exit: Int64 -> String
  (cond
    ((= exit 3) (errRec "denied" "path is outside home and /tmp, or names a key, token or secret file"))
    ((= exit 4) (errRec "notFound" "no such file"))
    ((= exit 5) (errRec "noSha" "the node has neither sha256sum nor shasum"))
    (else (errRec "getFailed" (str "exit " exit))))

; (:m :ref VPS-PUT-MODE :do "the fourth operand is the source file mode in octal (default 644); the file gets it before the rename, so an executable lands executable")
fn putScript -> String
  "base=$HOME/$1/$2; rel=$3; mode=${4:-644}; case $mode in [0-7][0-7][0-7]) ;; *) exit 4;; esac; [ -d \"$base\" ] || exit 3; dst=$base/$rel; mkdir -p \"$(dirname \"$dst\")\" && cat > \"$dst.putTmp\" && chmod \"$mode\" \"$dst.putTmp\" && mv \"$dst.putTmp\" \"$dst\" && echo \"ok $(wc -c < \"$dst\") $mode\""

fn putReceipt rel: String exit: Int64 out: String -> String
  (let [(f (fields (lastLine out)))]
    (cond
      ((= exit 3) (errRec "noWorktree" "no such unit worktree"))
      ((= exit 4) (errRec "badMode" "put mode must be three octal digits"))
      ((and (= exit 0) (= (at f 0) "ok")) (str "(:put :path " (fm/quoteText rel) " :bytes " (num (at f 1)) " :mode " (if (= (at f 2) "") "644" (at f 2)) ")"))
      (else (errRec "putFailed" (str "exit " exit)))))

; (:m :ref RELAYVERBS :do "refs: branches of the node repo matching a glob (default every head, capped at 400) with the worktree that has each checked out")
fn refsScript -> String
  "r=$HOME/$1; p=$2; case \"$p\" in refs/*) pat=$p;; *\\**) pat=refs/heads/$p;; *) pat=\"refs/heads/$p*\";; esac; git -C \"$r\" for-each-ref --count=400 --format='ref %(refname:short) %(objectname:short)' \"$pat\" 2>&1; git -C \"$r\" worktree list --porcelain 2>/dev/null | awk '/^worktree /{w=$2} /^branch /{b=$2; sub(\"refs/heads/\",\"\",b); print \"wt\", b, w}'"

fn refsReceipt out: String -> String
  (let [(ls (map fields (stringLines out)))
        (wts (filter (fn [(f (List String))] -> Bool (= (at f 0) "wt")) ls))
        (wtOf (fn [(b String)] -> String (match (listFind (fn [(f (List String))] -> Bool (= (at f 1) b)) wts) ((some f) (at f 2)) ((none) ""))))
        (items (map (fn [(f (List String))] -> String (str "(:ref " (fm/quoteText (at f 1)) " :sha " (fm/quoteText (at f 2)) " :wt " (fm/quoteText (wtOf (at f 1))) ")"))
                    (filter (fn [(f (List String))] -> Bool (= (at f 0) "ref")) ls)))]
    (str "(:refs :count " (listLength items) " :items (" (stringJoin items " ") "))"))

; (:m :ref RELAYVERBS :do "kill: TERM then KILL after 3 s on one pid, or on the whole group for a job; the caller has already checked the pid against stat (job pid or stray), the script never decides that")
fn killScript -> String
  "pid=$1; mode=$2; sig() { if [ \"$mode\" = group ]; then perl -e 'kill $ARGV[0], -$ARGV[1]' \"$1\" \"$pid\" 2>/dev/null; else kill -\"$1\" \"$pid\" 2>/dev/null; fi; }; sig TERM; i=0; while [ $i -lt 30 ] && kill -0 \"$pid\" 2>/dev/null; do sleep 0.1; i=$((i+1)); done; if kill -0 \"$pid\" 2>/dev/null; then sig KILL; sleep 0.3; fi; if kill -0 \"$pid\" 2>/dev/null; then echo alive; else echo gone; fi"

fn killReceipt pid: Int64 cls: String out: String -> String
  (str "(:kill :pid " pid " :class " cls " :result " (if (= (lastLine out) "gone") "gone" "alive") ")")

; (:m :ref RELAYVERBS :do "wt prune: git worktree prune on the node repo, a dry run unless apply is given; entries are listed, nothing else is removed")
fn pruneScript -> String
  "r=$HOME/$1; if [ \"$2\" = apply ]; then git -C \"$r\" worktree prune -v 2>&1; else git -C \"$r\" worktree prune --dry-run -v 2>&1; fi; echo \"exit $?\""

fn pruneReceipt apply: Bool out: String -> String
  (let [(ls (filter (fn [(l String)] -> Bool (and (not (stringEmpty? l)) (not (stringStartsWith? l "exit ")))) (stringLines out)))]
    (str "(:wtPrune :apply " (if apply "true" "false") " :count " (listLength ls) " :lines " (fm/quoteAll (listTake ls 100)) ")"))

; (:m :ref DEV-PROMOTE-ON-DEPLOY :do "after a deploy the node's dev branch (checked out in the conductor's dev clone) follows the deployed main when dev is an ancestor of it: a clean checked-out dev is merged --ff-only, an unchecked-out one is moved by a compare-and-swap update-ref; a diverged dev is left untouched and reported with its ahead and behind counts; operands are the dev clone, the source repo (both relative to HOME unless absolute) and the branch")
fn devPromoteScript -> String
  "abs() { case $1 in /*) echo \"$1\";; *) echo \"$HOME/$1\";; esac; }; d=$(abs \"$1\"); s=$(abs \"$2\"); b=$3; [ -d \"$d\" ] || { echo \"result absent\"; exit 0; }; git -C \"$d\" fetch -q \"$s\" \"+refs/heads/main:refs/heads/srcMain\" 2>/dev/null || { echo \"result fetchFailed\"; exit 0; }; dev=$(git -C \"$d\" rev-parse -q --verify \"refs/heads/$b\") || { echo \"result absent\"; exit 0; }; main=$(git -C \"$d\" rev-parse srcMain); echo \"dev $dev\"; echo \"main $main\"; if [ \"$dev\" = \"$main\" ]; then echo \"result same\"; exit 0; fi; if git -C \"$d\" merge-base --is-ancestor \"$dev\" \"$main\"; then if [ \"$(git -C \"$d\" rev-parse --abbrev-ref HEAD)\" = \"$b\" ]; then [ -z \"$(git -C \"$d\" status --porcelain --untracked-files=no)\" ] || { echo \"result busy\"; exit 0; }; git -C \"$d\" merge -q --ff-only srcMain >/dev/null 2>&1 || { echo \"result ffFailed\"; exit 0; }; else git -C \"$d\" update-ref \"refs/heads/$b\" \"$main\" \"$dev\" || { echo \"result ffFailed\"; exit 0; }; fi; echo \"result promoted\"; exit 0; fi; echo \"ahead $(git -C \"$d\" rev-list --count \"srcMain..$dev\")\"; echo \"behind $(git -C \"$d\" rev-list --count \"$dev..srcMain\")\"; echo \"result diverged\""

fn devPromoteReceipt out: String -> String
  (let [(ls (map fields (stringLines out)))
        (val (fn [(k String)] -> String (match (listFind (fn [(f (List String))] -> Bool (= (at f 0) k)) ls) ((some f) (at f 1)) ((none) ""))))
        (short (fn [(s String)] -> String (optionOr (stringSlice s 0 (min 9 (stringLength s))) s)))
        (r (val "result"))]
    (cond
      ((= r "promoted") (str "(:devPromoted :from " (fm/quoteText (short (val "dev"))) " :to " (fm/quoteText (short (val "main"))) ")"))
      ((= r "diverged") (str "(:devDiverged :dev " (fm/quoteText (short (val "dev"))) " :main " (fm/quoteText (short (val "main"))) " :ahead " (num (val "ahead")) " :behind " (num (val "behind")) ")"))
      ((stringEmpty? r) (errRec "devPromoteFailed" "no result from the node"))
      (else (str "(:devPromote :result " r (if (stringEmpty? (val "main")) "" (str " :main " (fm/quoteText (short (val "main"))))) ")"))))

; (:m :ref DEPLOY-RESTARTS-HUB :do "restart the hub unit only after the conductor drain: with no conductor restart file pending it restarts now; otherwise the waiter runs as the transient user unit asl-hub-restart (systemd-run --user --collect, RuntimeMaxSec grace+100), outside the relay cgroup: it polls until the restart file is gone or grace seconds pass, restarts and appends (:hub :restarted :after drained|graceOut :waitedS) to the log; a waiter already active is reused; operands: restart file, grace, ctl, unit, log, mark file (paths under HOME unless absolute), runner, sha")
; (:m :ref DEPLOY-HUB-SCHEDULED-MARK :do "a scheduled restart is not done when the deploy answers: the deploy writes its sha to MARK.pending, and the waiter reads that file before it restarts and, only when the restart exits 0, writes the sha it read to the mark file (temp and rename) and logs it as :sha; so a reused waiter marks the newest deploy it saw, a failed or graced-out-and-failed restart marks nothing, and a deploy landing after the read stays unmarked for the next deploy")
fn hubRestartScript -> String
  "abs() { case $1 in /*) echo \"$1\";; *) echo \"$HOME/$1\";; esac; }; rf=$(abs \"$1\"); g=$2; ctl=$3; u=$4; lf=$(abs \"$5\"); mf=$(abs \"$6\"); run=$7; sha=$8; wu=asl-hub-restart; if [ ! -f \"$rf\" ]; then if \"$ctl\" --user restart \"$u\" >/dev/null 2>&1; then echo \"result restarted\"; else echo \"result failed\"; fi; exit 0; fi; mkdir -p \"$(dirname \"$mf\")\" && printf '%s\\n' \"$sha\" > \"$mf.pending\"; if \"$ctl\" --user is-active --quiet \"$wu\"; then echo \"result waiting\"; exit 0; fi; if \"$run\" --user --collect --unit \"$wu\" -p RuntimeMaxSec=$((g+100)) /bin/sh -c 'rf=$1; g=$2; ctl=$3; u=$4; lf=$5; mf=$6; i=0; while [ -f \"$rf\" ] && [ $i -lt $g ]; do sleep 1; i=$((i+1)); done; if [ -f \"$rf\" ]; then w=graceOut; else w=drained; fi; p=$(head -n 1 \"$mf.pending\" 2>/dev/null | tr -cd 0-9a-f); if \"$ctl\" --user restart \"$u\" >/dev/null 2>&1; then r=true; if [ -n \"$p\" ]; then printf \"%s\\n\" \"$p\" > \"$mf.w.tmp\" && mv \"$mf.w.tmp\" \"$mf\"; fi; else r=false; fi; echo \"(:hub :restarted $r :after $w :waitedS $i :sha ${p:--})\" >> \"$lf\"' sh \"$rf\" \"$g\" \"$ctl\" \"$u\" \"$lf\" \"$mf\" >/dev/null 2>&1; then echo \"result scheduled\"; else echo \"result failed\"; fi"

fn hubRestartReceipt out: String -> String
  (let [(r (at (fields (lastLine out)) 1))]
    (cond
      ((= r "restarted") "(:hub :restarted true :why gateway)")
      ((= r "scheduled") "(:hub :restarted scheduled :why drain)")
      ((= r "waiting") "(:hub :restarted scheduled :why waiterActive)")
      ((= r "failed") "(:hub :restarted false :why ctlFailed)")
      (else (errRec "hubRestartFailed" "no result from the node"))))

; (:m :ref DEPLOY-RESTARTS-POOL :do "the pool restart is the drain-aware hub script with the waiter name of the pool unit and log row (asl-leon-pool-restart, (:pool :restarted ...)): with no conductor restart file pending it restarts now, else a waiter restarts it after the conductor drained; the code has no in-flight probe of the pool itself, so a pending drain is the only wait")
fn poolRestartScript -> String
  (stringReplace (stringReplace (hubRestartScript) "asl-hub-restart" "asl-leon-pool-restart") "(:hub :restarted" "(:pool :restarted")

fn poolRestartReceipt out: String -> String
  (let [(r (at (fields (lastLine out)) 1))]
    (cond
      ((= r "restarted") "(:pool :restarted true :when now)")
      ((= r "scheduled") "(:pool :restarted scheduled :when drain)")
      ((= r "waiting") "(:pool :restarted scheduled :when waiterActive)")
      ((= r "failed") "(:pool :restarted false :why ctlFailed)")
      (else (errRec "poolRestartFailed" "no result from the node"))))

; (:m :ref LEONSERVE-COLD-START :do "a deployed range that changes anything under asl/ leaves the daemons' compile store cold: the first start of leonServe, hub main or the conductor then compiles every changed module (7 minutes measured live)")
fn warmTouched? names: String -> Bool
  (listAny? (fn [(l String)] -> Bool (stringStartsWith? (stringTrim l) "asl/")) (stringLines names))

; (:m :ref LEONSERVE-COLD-START :do "warm: before any daemon restart, each entry is compiled and its binary kept by nativeTest prepare in the deployed worktree (operands: worktree under HOME, seconds per entry, entries); a failed or timed-out entry only counts, the deploy goes on and that daemon compiles on its own start; the answer counts entries, compiled modules (NATIVE-MODULE-PHASES lines) and failures")
fn warmScript -> String
  "wt=$1; t=$2; nc=$3; shift 3; cd \"$HOME/$wt\" || { echo \"result noWorktree\"; exit 0; }; n=0; c=0; f=0; for e in \"$@\"; do n=$((n+1)); o=$(ASL_NATIVE_TRACE=1 perl -e 'alarm shift; exec @ARGV' \"$t\" nice -n \"$nc\" env -u ASL_ROOT -u ASL_PRELUDE ./bin/asl run asl/tools/nativeTest.asl prepare \"$e\" 2>&1); rc=$?; k=$(printf '%s\\n' \"$o\" | grep -c NATIVE-MODULE-PHASES); c=$((c+k)); [ $rc -eq 0 ] || f=$((f+1)); done; echo \"result warmed\"; echo \"entries $n\"; echo \"compiled $c\"; echo \"failed $f\""

fn warmReceipt out: String -> String
  (let [(ls (map fields (stringLines out)))
        (val (fn [(k String)] -> String (match (listFind (fn [(f (List String))] -> Bool (= (at f 0) k)) ls) ((some f) (at f 1)) ((none) ""))))
        (r (val "result"))]
    (cond
      ((= r "warmed") (str "(:warm :entries " (num (val "entries")) " :compiled " (num (val "compiled")) " :failed " (num (val "failed")) ")"))
      ((= r "noWorktree") "(:warm :skipped noWorktree)")
      (else (errRec "warmFailed" "no result from the node"))))

; (:m :ref LEONSERVE-COLD-START :do "the warm operands come from the deploy group of .asl.config.asn (warmS wall seconds per entry, warmNice, warmEntries), read from the tree the deploy ships; an absent or non-numeric row keeps the default, the schema (asl/grammar/workspaceConfig.asn) bounds the values")
fn cfgToken text: String key: String -> String
  (match (stringIndexOf text (str ":" key " "))
    ((none) "")
    ((some i) (let [(rest (stringTrim (optionOr (stringSlice text (+ i (+ (stringLength key) 2)) (stringLength text)) "")))]
                (stringReplace (optionOr (listHead (stringSplit (optionOr (listHead (stringLines rest)) "") " ")) "") ")" ""))))

fn cfgInt text: String key: String fallback: Int64 -> Int64
  (optionOr (stringToInt64 (cfgToken text key)) fallback)

fn cfgStrings text: String key: String -> (List String)
  (match (stringIndexOf text (str ":" key " ["))
    ((none) (list))
    ((some i) (let [(rest (optionOr (stringSlice text (+ i (+ (stringLength key) 3)) (stringLength text)) ""))
                    (body (optionOr (stringSlice rest 0 (optionOr (stringIndexOf rest "]") (stringLength rest))) ""))]
                (filter (fn [(p String)] -> Bool (not (stringEmpty? (stringTrim p)))) (stringSplit body "\"")))))

fn warmEntryList text: String -> (List String)
  (let [(row (cfgStrings text "warmEntries"))]
    (if (listEmpty? row) (list "asl/packages/asl-agent/src/leonServe.asl" "asl/tools/hub/main.asl" "asl/tools/coord/conductor.asl") row))

; (:m :ref LEONSERVE-COLD-START-LOWS :do "the scan of a group: from the opening paren at i to the index after its closing one, parens inside a quoted string do not count")
fn groupEnd text: String i: Int64 depth: Int64 quoted: Bool -> Int64
  (if (>= i (stringLength text)) i
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (cond
        (quoted (groupEnd text (+ i 1) depth (not (= c "\""))))
        ((= c "\"") (groupEnd text (+ i 1) depth true))
        ((= c "(") (groupEnd text (+ i 1) (+ depth 1) false))
        ((= c ")") (if (<= depth 1) (+ i 1) (groupEnd text (+ i 1) (- depth 1) false)))
        (else (groupEnd text (+ i 1) depth false)))))

; (:m :ref LEONSERVE-COLD-START-LOWS :do "the text of the first group named group, parens included, empty when absent: a key of another group with the same name is not seen through it")
fn groupText text: String group: String -> String
  (match (stringIndexOf text (str ":" group " ("))
    ((none) "")
    ((some i) (let [(start (+ i (+ (stringLength group) 2)))]
                (optionOr (stringSlice text start (groupEnd text start 0 false)) ""))))

; (:m :ref LEONSERVE-COLD-START-LOWS :do "a numeric key outside lo..hi, or present and not a number, warns on stderr and takes the default, so a bad shipped value never reaches nice or the wall of an entry; an absent key takes the default silently")
fn ! warmWarn! key: String raw: String lo: Int64 hi: Int64 fallback: Int64 -> Int64
  (do (eprintln (str "(:warn :deploy :key " key " :value \"" raw "\" :range " (stringFromInt64 lo) ".." (stringFromInt64 hi) " :use " (stringFromInt64 fallback) ")")) fallback)

fn ! warmClamped! group: String key: String lo: Int64 hi: Int64 fallback: Int64 -> Int64
  (let [(raw (cfgToken group key))]
    (if (stringEmpty? raw) fallback
      (match (stringToInt64 raw)
        ((some n) (if (and (>= n lo) (<= n hi)) n (warmWarn! key raw lo hi fallback)))
        ((none) (warmWarn! key raw lo hi fallback)))))

; (:m :ref LEONSERVE-COLD-START-LOWS :do "worst case of a deploy: the warm block lasts 120 s + entries x warmS (warmS at most 86400), so the exec budget warmBudgetS is derived from the same operands; a deploy with 3 entries at the default 900 s holds the relay for 2820 s")
fn ! warmArgs text: String -> (List String)
  (let [(g (groupText text "deploy"))]
    (listAppend (list "warm" "wt/main" (stringFromInt64 (warmClamped! g "warmS" 1 86400 900)) (stringFromInt64 (warmClamped! g "warmNice" 0 19 10))) (warmEntryList g)))

; (:m :ref RELAYVERBS :do "gw: the gateway config on the node is never edited in place: the patch (unified diff, or the ASN (:patch ...) shape of ~/.asl/run/gwsync converted by tools/remote/gwPatch.asl in the --wt worktree, on stdin) is applied to a copy, the copy is configChecked by the node's own asl, and only apply, after a green check, backs the file up (gateway.asn.bak-STAMP) and renames the copy over it; the answer carries counts and masked messages, never a config line")
fn gwScript -> String
  "mode=$1; wt=$2; cw=$3; g=$HOME/.asl/gateway.asn; [ -f \"$g\" ] || { echo \"result noGateway\"; exit 0; }; t=$(mktemp \"$HOME/.asl/gateway.asn.new.XXXXXX\") || exit 3; pf=$t.patch; cat > \"$pf\"; cp -p \"$g\" \"$t\"; if ! { if head -c 8 \"$pf\" | grep -q '^(:patch'; then (cd \"$HOME/$cw\" && env -u ASL_ROOT -u ASL_PRELUDE ./bin/asl run tools/remote/gwPatch.asl \"$t\" \"$pf\" \"$t.out\") 2>&1 | grep -v '^asl: native' > \"$t.log\"; [ -s \"$t.out\" ] && mv \"$t.out\" \"$t\"; else patch -s \"$t\" < \"$pf\" > \"$t.log\" 2>&1; fi; }; then echo \"result rejected\"; echo \"msg $(head -c 200 \"$t.log\" | tr '\\n' ' ')\"; rm -f \"$t\" \"$pf\" \"$t.log\" \"$t.orig\" \"$t.rej\"; exit 0; fi; rm -f \"$t.orig\" \"$t.rej\"; chk=$(cd \"$HOME/$wt\" && env -u ASL_ROOT -u ASL_PRELUDE ./bin/asl gateway configCheck \"$t\" 2>&1); rc=$?; changed=$(diff \"$g\" \"$t\" | grep -c '^[<>]'); if [ $rc -ne 0 ]; then echo \"result checkFailed\"; echo \"msg $(printf %s \"$chk\" | head -c 300 | tr '\\n' ' ')\"; rm -f \"$t\" \"$pf\" \"$t.log\"; exit 0; fi; if [ \"$mode\" = apply ]; then b=gateway.asn.bak-$(date +%Y%m%d%H%M%S); cp -p \"$g\" \"$HOME/.asl/$b\" && mv \"$t\" \"$g\" && { echo \"result applied\"; echo \"backup $b\"; } || echo \"result applyFailed\"; else echo \"result checked\"; rm -f \"$t\"; fi; echo \"changed $changed\"; rm -f \"$pf\" \"$t.log\" \"$t\""

fn gwReceipt mode: String out: String -> String
  (let [(ls (map fields (stringLines out)))
        (val (fn [(k String)] -> String (match (listFind (fn [(f (List String))] -> Bool (= (at f 0) k)) ls) ((some f) (stringJoin (listDrop f 1) " ")) ((none) ""))))
        (r (val "result"))]
    (if (stringEmpty? r)
      (errRec "gwFailed" "no result from the node")
      (str "(:gw :mode " mode " :result " r " :changed " (num (val "changed"))
           (if (stringEmpty? (val "backup")) "" (str " :backup " (fm/quoteText (val "backup"))))
           (if (stringEmpty? (val "msg")) "" (str " :msg " (fm/quoteText (ns/maskLine (val "msg") 300))))
           ")")))

; (:m :ref RELAYVERBS :do "test failure location: the first file:line:col ERR line of a failing run, and the node-side script that names the enclosing fn, schema or enum header of that line, so a failure shows what broke and not only the output tail")
fn locTok t: String -> Bool
  (and (stringContains? t ".asl:") (> (num (at (stringSplit t ":") 1)) 0))

fn locLine out: String -> Option String
  (listFind (fn [(l String)] -> Bool (listAny? locTok (fields l))) (stringLines out))

fn errLoc out: String file: String -> (Pair Int64 String)
  (match (locLine out)
    ((none) (pair 0 ""))
    ((some l)
      (let [(tok (optionOr (listFind locTok (fields l)) ""))
            (at0 (optionOr (stringIndexOf l tok) 0))]
        (pair (num (at (stringSplit tok ":") 1)) (stringTrim (optionOr (stringSlice l (+ at0 (stringLength tok)) (stringLength l)) ""))))))

fn errFile out: String unit: String fallback: String -> String
  (match (locLine out)
    ((none) fallback)
    ((some l)
      (let [(p (optionOr (listHead (stringSplit (optionOr (listFind locTok (fields l)) "") ":")) fallback))
            (marker (str "/" unit "/"))]
        (match (stringIndexOf p marker)
          ((some i) (optionOr (stringSlice p (+ i (stringLength marker)) (stringLength p)) fallback))
          ((none) (if (stringStartsWith? p "/") fallback p))))))

fn locateScript -> String
  "awk -v L=\"$3\" 'NR<=L && /^(fn|schema|enum) /{f=$0} END{print f}' \"$HOME/$1/$2\" 2>/dev/null | cut -c1-120"

fn locateReceipt line: Int64 msg: String hdr: String -> String
  (str "(:at :line " line " :fn " (fm/quoteText (stringTrim hdr)) " :msg " (fm/quoteText (optionOr (stringSlice msg 0 (min 160 (stringLength msg))) "")) ")")

; (:m :ref ESC-EVENTS :do "events: one exec runs tools/remote/eventsNode.asl (pure ASL, no perl) in the node main worktree; it reads the conductor store from byte offsets (-1 = the newest :lines rows, or all rows since a time), keeps only whole lines, filters by row class and :at, and prints E rows plus the next offset of each file; the client resumes from the offsets, so a follower neither repeats nor loses a row; the file is never written")
fn eventsScript -> String
  "cw=$1; shift; cd \"$HOME/$cw\" || exit 3; exec env -u ASL_ROOT -u ASL_PRELUDE ./bin/asl run tools/remote/eventsNode.asl \"$HOME/.asl/run/conductor\" \"$@\" 2>/dev/null"

; (:m :ref ESC-EVENTS :do "each E row becomes (:ev :src S ROW) with secrets masked; the last line (:eventsNext :journal J :escalations E :count K) carries the offsets to resume from")
fn eventsReceipt exit: Int64 out: String -> String
  (cond
    ((= exit 4) (errRec "noStore" "no conductor store on the node"))
    ((= exit 5) (errRec "badSince" "--since takes an ISO time: 2026-10-30 or 2026-10-30T12:00:00Z"))
    ((!= exit 0) (errRec "eventsFailed" (str "exit " exit)))
    (else
      (let [(ls (stringLines (stringTrim out)))
            (rows (filter (fn [(l String)] -> Bool (stringStartsWith? l "E ")) ls))
            (off (fn [(src String)] -> String
                   (optionOr (listHead (map (fn [(l String)] -> String (at (fields l) 2)) (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "N " src " "))) ls))) "0")))
            (evs (map (fn [(l String)] -> String
                        (let [(f (fields l))
                              (src (at f 1))
                              (row (optionOr (stringSlice l (+ (stringLength src) 3) (stringLength l)) ""))]
                          (str "(:ev :src " src " " (ns/maskLine row 2000) ")")))
                      rows))]
        (str (stringJoin evs "\n") (if (listEmpty? evs) "" "\n")
             "(:eventsNext :journal " (off "journal") " :escalations " (off "escalations") " :count " (listLength evs) ")"))))

; (:m :ref LEONSERVE-COLD-START :do "the relay round trip of the warm step may last as long as its entries do: one wall per entry plus two minutes, from the same operands warmArgs built")
fn warmBudgetS args: (List String) -> Int64
  (+ 120 (* (max 0 (- (listLength args) 4)) (num (at args 2))))

; (:m :ref DEPLOY-INTERRUPTED-NO-RESTART :do "a deploy diffs each daemon's range from the sha that daemon was last restarted (or warmed) on, kept on the node in ~/.asl/run/deploy/<daemon>.sha, not from the worktree HEAD before the checkout: a deploy killed after the checkout moved and before the restarts left HEAD at the new sha, and the next deploy saw no change and skipped them")
fn daemons -> (List String)
  (list "warm" "conductor" "hub" "pool")

; (:m :ref DEPLOY-INTERRUPTED-NO-RESTART :do "read: one line (sha DAEMON VALUE) per daemon operand after the worktree operand (under HOME unless absolute), VALUE the recorded sha when it names a commit of that worktree, else -")
fn restartedReadScript -> String
  "case $1 in /*) wt=$1;; *) wt=$HOME/$1;; esac; shift; for d in \"$@\"; do f=\"$HOME/.asl/run/deploy/$d.sha\"; v=-; if [ -f \"$f\" ]; then s=$(head -n 1 \"$f\" | tr -cd '0-9a-f'); if [ -n \"$s\" ] && git -C \"$wt\" cat-file -e \"$s^{commit}\" 2>/dev/null; then v=$s; fi; fi; echo \"sha $d $v\"; done"

; (:m :ref DEPLOY-INTERRUPTED-NO-RESTART :do "mark: write SHA to each daemon operand's file by temp file and rename, one (marked DAEMON) line each")
fn restartedMarkScript -> String
  "sha=$1; shift; dir=\"$HOME/.asl/run/deploy\"; mkdir -p \"$dir\" || exit 1; for d in \"$@\"; do printf '%s\\n' \"$sha\" > \"$dir/$d.sha.tmp\" && mv \"$dir/$d.sha.tmp\" \"$dir/$d.sha\" && echo \"marked $d\"; done"

fn restartedOf out: String daemon: String -> String
  (match (listFind (fn [(f (List String))] -> Bool (and (= (at f 0) "sha") (= (at f 1) daemon))) (map fields (stringLines out)))
    ((some f) (if (= (at f 2) "-") "" (at f 2)))
    ((none) ""))

; (:m :ref DEPLOY-INTERRUPTED-NO-RESTART :do "a daemon's range starts at its recorded sha; with none (first deploy since this landed, or a sha the worktree no longer has) it starts at the HEAD before the checkout")
fn rangeBase recorded: String before: String -> String
  (if (stringEmpty? recorded) before recorded)

; (:m :ref DEPLOY-INTERRUPTED-NO-RESTART :do "a daemon is marked done on the new sha only when its step ran to an answer: warmed with no failed entry or untouched, a conductor restart that exited 0 and printed :requested true (state restarted) or none needed (state none), a hub restarted at once or untouched (a scheduled one is marked by its waiter, DEPLOY-HUB-SCHEDULED-MARK); unreachable, failed or unanswered steps leave the old sha so the next deploy retries them")
fn restartDone? daemon: String receipt: String -> Bool
  (cond
    ((= daemon "warm") (or (and (stringStartsWith? receipt "(:warm :entries ") (stringEndsWith? receipt ":failed 0)")) (= receipt "(:warm :skipped untouched)")))
    ((= daemon "conductor") (or (= receipt "none") (= receipt "restarted")))
    ((= daemon "hub") (or (stringStartsWith? receipt "(:hub :restarted true") (= receipt "(:hub :restarted false :why untouched)")))
    ((= daemon "pool") (or (stringStartsWith? receipt "(:pool :restarted true") (= receipt "(:pool :restarted false :why untouched)")))
    (else false))

