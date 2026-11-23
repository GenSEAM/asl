(module asl-tools/remote/nodeStat
  :x [Proc statScript maskLine killClass maskCmd unitOf procOf parseProcs strays statReceipt statErr]
  :i [(asl-tools/remote/form :a fm)])

; (:m :ref TELEMETRY-BASE :do "stat: one constant sh script prints tagged lines (host at uptime me cores load mem disk P:processes U:worktrees J:jobs S:services R:relay) and parseStat turns them into one :nodeStat receipt; it reads /proc, ps, git, systemctl and the job records only, never an environment or a file under ~/.asl, and kills nothing")
fn statScript -> String
  "wb=$2; jd=$3; export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}; echo \"host $(hostname)\"; echo \"at $(date +%s)\"; echo \"uptime $(cut -d. -f1 /proc/uptime)\"; echo \"me $(id -un)\"; echo \"load $(cut -d' ' -f1-3 /proc/loadavg)\"; awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} /^SwapTotal/{st=$2} /^SwapFree/{sf=$2} END{print \"mem\", int(t/1024), int(a/1024), int((st-sf)/1024)}' /proc/meminfo; df -Pk 2>/dev/null | awk 'NR>1 && $1 ~ /^\\/dev\\// && $1 !~ /loop/ {print \"disk\", $6, int($2/1048576), int($4/1048576)}'; ps -eo pid=,ppid=,pcpu=,rss=,etimes=,user:24=,args= 2>/dev/null | while read pid ppid cpu rss et user args; do cwd=$(readlink /proc/$pid/cwd 2>/dev/null | tr ' ' '_'); echo \"P $pid $ppid $cpu $rss $et $user ${cwd:--} $args\"; done; for d in \"$HOME/$wb\"/*/; do [ -e \"${d}.git\" ] || continue; u=${d%/}; u=${u##*/}; b=$(git -C \"$d\" symbolic-ref --short -q HEAD || echo -); h=$(git -C \"$d\" rev-parse --short HEAD 2>/dev/null || echo -); n=$(git -C \"$d\" status --porcelain --untracked-files=no 2>/dev/null | head -1 | wc -l); echo \"U $u $b $h $n\"; done; sh -c \"$4\" x \"$jd\" \"$5\" 2>/dev/null; for s in $(systemctl --user list-unit-files 'asl-*.service' --no-legend --plain 2>/dev/null | awk '{print $1}'); do echo \"S ${s%.service} $(systemctl --user is-active \"$s\" 2>/dev/null | head -1) $(systemctl --user show -p MainPID --value \"$s\" 2>/dev/null | head -1)\"; done; sv=$(id -u svc 2>/dev/null); if [ -n \"$sv\" ] && [ -d \"/run/user/$sv\" ]; then for s in $(XDG_RUNTIME_DIR=/run/user/$sv systemctl --user list-unit-files 'asl-*.service' --no-legend --plain 2>/dev/null | awk '{print $1}'); do echo \"S svc:${s%.service} $(XDG_RUNTIME_DIR=/run/user/$sv systemctl --user is-active \"$s\" 2>/dev/null | head -1) 0\"; done; fi; if ss -ltn \"sport = :$1\" 2>/dev/null | grep -q LISTEN; then echo \"R $1 true\"; else echo \"R $1 false\"; fi"

schema Proc
  (:f pid Int64)
  (:f ppid Int64)
  (:f cpu String)
  (:f tenths Int64)
  (:f rssMb Int64)
  (:f et Int64)
  (:f user String)
  (:f cwd String)
  (:f cmd String)
  (:f unit String)

fn fields line: String -> (List String)
  (filter (fn [(t String)] -> Bool (not (stringEmpty? t))) (stringSplit (stringTrim line) " "))

fn at xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")

fn num s: String -> Int64
  (optionOr (stringToInt64 s) 0)

fn byteOf c: String -> Int64
  (bytesGet (stringToBytes c) 0)

fn digit? c: String -> Bool
  (let [(n (byteOf c))] (and (>= n 48) (<= n 57)))

fn letter? c: String -> Bool
  (let [(n (byteOf c))] (or (and (>= n 65) (<= n 90)) (and (>= n 97) (<= n 122))))

fn opaqueChar? c: String -> Bool
  (or (digit? c) (or (letter? c) (or (= c "_") (or (= c "-") (or (= c "+") (= c "="))))))

; (:m :ref TELEMETRY-BASE :do "masking: an argument is replaced by *** when its key (name before =, flag before the next word, header name before :) holds token secret passw pwd key auth cred bearer cookie, when it has a known key prefix (sk- ghp_ gho_ ghu_ ghs_ github_pat_ xox AKIA AIza eyJ), when it is a 32+ char opaque word with a digit and a letter, or when it is a URL with user:password@; unknown shapes err toward masking")
fn secretKey? k: String -> Bool
  (let [(l (stringLower k))]
    (listAny? (fn [(w String)] -> Bool (stringContains? l w)) (list "token" "secret" "passw" "pwd" "key" "auth" "cred" "bearer" "cookie")))

fn secretShape? v: String -> Bool
  (or (listAny? (fn [(p String)] -> Bool (stringStartsWith? v p)) (list "sk-" "ghp_" "gho_" "ghu_" "ghs_" "github_pat_" "xox" "AKIA" "AIza" "eyJ"))
      (let [(cs (stringChars v))]
        (and (>= (stringLength v) 32)
             (and (listAll? opaqueChar? cs)
                  (and (listAny? digit? cs) (listAny? letter? cs))))))

fn maskUrl t: String -> String
  (match (stringIndexOf t "://")
    ((none) t)
    ((some i)
      (let [(rest (optionOr (stringSlice t (+ i 3) (stringLength t)) ""))
            (slash (optionOr (stringIndexOf rest "/") (stringLength rest)))
            (auth (optionOr (stringSlice rest 0 slash) ""))]
        (if (stringContains? auth "@")
          (str (optionOr (stringSlice t 0 (+ i 3)) "") "***@" (optionOr (listLast (stringSplit auth "@")) "") (optionOr (stringSlice rest slash (stringLength rest)) ""))
          t))))

fn maskOne t: String -> String
  (match (stringIndexOf t "=")
    ((some i)
      (let [(k (optionOr (stringSlice t 0 i) ""))
            (v (optionOr (stringSlice t (+ i 1) (stringLength t)) ""))]
        (if (or (secretKey? k) (or (secretShape? v) (stringContains? v "://")))
          (if (or (secretKey? k) (secretShape? v)) (str k "=***") (str k "=" (maskUrl v)))
          t)))
    ((none)
      (cond
        ((secretShape? t) "***")
        ((stringContains? t "://") (maskUrl t))
        (else t))))

fn flagKey? t: String -> Bool
  (and (not (stringContains? t "="))
       (or (and (stringStartsWith? t "-") (secretKey? t))
           (and (stringEndsWith? t ":") (secretKey? t))))

fn maskWords words: (List String) limit: Int64 -> String
  (let [(step (fn [(acc (Pair Bool (List String))) (t String)] -> (Pair Bool (List String))
                (let [(armed (pairFirst acc))
                      (out (pairSecond acc))
                      (word (stringLower t))]
                  (cond
                    ((and armed (not (stringStartsWith? t "-")))
                      (pair (or (= word "bearer") (= word "basic")) (listAppend out (list "***"))))
                    (else (pair (flagKey? t) (listAppend out (list (maskOne t)))))))))
        (done (pairSecond (fold step (pair false (list)) words)))
        (text (stringJoin done " "))]
    (if (> (stringLength text) limit) (optionOr (stringSlice text 0 limit) "") text))

fn maskCmd cmd: String limit: Int64 -> String
  (maskWords (fields cmd) limit)

; (:m :ref RELAYVERBS :do "maskLine keeps the spacing of a log line (split on single spaces) so tail output stays readable while secrets are still replaced")
fn maskLine line: String limit: Int64 -> String
  (maskWords (stringSplit line " ") limit)

; (:m :ref TELEMETRY-BASE :do "unit attribution: the first /WTBASE/UNIT path in the process cwd, else in its argument text; empty when neither names a worktree")
fn unitAfter text: String marker: String -> String
  (match (stringIndexOf text marker)
    ((none) "")
    ((some i)
      (let [(rest (optionOr (stringSlice text (+ i (stringLength marker)) (stringLength text)) ""))]
        (optionOr (listHead (stringSplit (optionOr (listHead (stringSplit rest "/")) "") " ")) ""))))

fn unitOf wtBase: String cwd: String cmd: String -> String
  (let [(marker (str "/" wtBase "/"))
        (fromCwd (unitAfter (str cwd "/") marker))]
    (if (stringEmpty? fromCwd) (unitAfter cmd marker) fromCwd))

fn tenths s: String -> Int64
  (let [(parts (stringSplit s "."))
        (frac (at parts 1))]
    (+ (* 10 (num (at parts 0))) (num (optionOr (stringSlice frac 0 1) "0"))))

fn procOf wtBase: String line: String -> (Option Proc)
  (let [(f (fields line))]
    (if (or (< (listLength f) 8) (not (= (at f 0) "P")))
      (none)
      (let [(cwd (at f 7))
            (args (stringJoin (listDrop f 8) " "))
            (cwdReal (if (= cwd "-") "" cwd))]
        (if (stringStartsWith? args "[")
          (none)
          (some (Proc :pid (num (at f 1)) :ppid (num (at f 2)) :cpu (at f 3) :tenths (tenths (at f 3)) :rssMb (/ (num (at f 4)) 1024) :et (num (at f 5))
                      :user (at f 6) :cwd cwdReal :cmd (maskCmd args 100) :unit (unitOf wtBase cwdReal args)))))))

fn parseProcs wtBase: String text: String -> (List Proc)
  (fold (fn [(acc (List Proc)) (l String)] -> (List Proc)
          (match (procOf wtBase l) ((some p) (listAppend acc (list p))) ((none) acc)))
        (list) (stringLines text))

; (:m :ref TELEMETRY-BASE :do "stray: a process of the dev user older than sixHours with at least one percent cpu (lifetime average) that has no worktree unit and no ancestor that is a recorded job pid or a service MainPID; listed only, never killed")
fn ancestorIn? ps: (List Proc) roots: (List Int64) pid: Int64 depth: Int64 -> Bool
  (cond
    ((or (<= pid 1) (> depth 40)) false)
    ((listContains? roots pid) true)
    (else (match (listFind (fn [(p Proc)] -> Bool (= p.pid pid)) ps)
            ((some p) (ancestorIn? ps roots p.ppid (+ depth 1)))
            ((none) false))))

fn strays ps: (List Proc) me: String roots: (List Int64) -> (List Proc)
  (filter (fn [(p Proc)] -> Bool
            (and (= p.user me)
                 (and (> p.et 21600)
                      (and (>= p.tenths 10)
                           (and (stringEmpty? p.unit) (not (ancestorIn? ps roots p.pid 0)))))))
          ps)

fn tagLines text: String tag: String -> (List (List String))
  (map fields (filter (fn [(l String)] -> Bool (stringStartsWith? l (str tag " "))) (stringLines text)))

fn tagVal text: String tag: String -> String
  (match (listHead (tagLines text tag))
    ((some f) (stringJoin (listDrop f 1) " "))
    ((none) ""))

fn unitRow f: (List String) -> String
  (str "(:unit " (fm/quoteText (at f 1)) " :wt " (fm/quoteText (str "~/wt/" (at f 1))) " :branch " (fm/quoteText (at f 2)) " :head " (fm/quoteText (at f 3)) " :dirty " (if (= (at f 4) "0") "false" "true") ")")

fn jobRow f: (List String) -> String
  (str "(:job :name " (fm/quoteText (at f 1)) " :st " (at f 2) " :pid " (num (at f 3)) ")")

fn serviceRow f: (List String) -> String
  (str "(:service :name " (fm/quoteText (at f 1)) " :active " (if (= (at f 2) "active") "true" "false") ")")

fn procRow p: Proc -> String
  (str "(:proc :pid " p.pid " :cpu " p.cpu " :rssMb " p.rssMb " :etimeS " p.et " :user " (fm/quoteText p.user) " :unit " (fm/quoteText p.unit) " :cmd " (fm/quoteText p.cmd) ")")

fn strayRow p: Proc -> String
  (str "(:stray :pid " p.pid " :why " (fm/quoteText (str "etime " (/ p.et 3600) "h cpu " p.cpu "% no unit no job: " (maskCmd p.cmd 40))) ")")

fn rows xs: (List String) -> String
  (str "(" (stringJoin xs " ") ")")

; (:m :ref RELAYVERBS :do "kill gate: a pid may be signalled only when it is a running job pid or a descendant of one (class job, whole group), or a stray as stat lists it (class stray, that pid only); everything else answers empty")
fn killClass text: String wtBase: String pid: Int64 -> String
  (let [(ps (parseProcs wtBase text))
        (me (tagVal text "me"))
        (jobPids (map (fn [(f (List String))] -> Int64 (num (at f 3))) (filter (fn [(f (List String))] -> Bool (= (at f 2) "running")) (tagLines text "job"))))
        (svcPids (filter (fn [(n Int64)] -> Bool (> n 1)) (map (fn [(f (List String))] -> Int64 (num (at f 3))) (tagLines text "S"))))
        (roots (listAppend jobPids svcPids))]
    (cond
      ((<= pid 1) "")
      ((listContains? jobPids pid) "job")
      ((and (ancestorIn? ps jobPids pid 0) (listAny? (fn [(p Proc)] -> Bool (and (= p.pid pid) (= p.user me))) ps)) "job")
      ((listAny? (fn [(p Proc)] -> Bool (= p.pid pid)) (strays ps me (filter (fn [(n Int64)] -> Bool (> n 1)) roots))) "stray")
      (else "")))

; (:m :ref TELEMETRY-BASE :do "receipt: top is the N busiest by cpu then rss, while every process feeds unit attribution and stray detection")
fn statReceipt text: String wtBase: String top: Int64 -> String
  (let [(ps (parseProcs wtBase text))
        (me (tagVal text "me"))
        (jobs (tagLines text "job"))
        (svcs (tagLines text "S"))
        (roots (map (fn [(f (List String))] -> Int64 (num (at f 3))) (filter (fn [(f (List String))] -> Bool (or (= (at f 0) "S") (= (at f 2) "running"))) (listAppend jobs svcs))))
        (sorted (listSortBy (fn [(p Proc)] -> Int64 (- 0 (+ (* p.tenths 1000000) p.rssMb))) ps))
        (load (fields (tagVal text "load")))
        (mem (fields (tagVal text "mem")))
        (relay (fields (tagVal text "R")))]
    (str "(:nodeStat :host " (fm/quoteText (tagVal text "host")) " :at " (num (tagVal text "at")) " :uptimeS " (num (tagVal text "uptime")) " :cpus " (num (tagVal text "cores"))
         " :load (" (stringJoin load " ") ")"
         " :mem (:totalMb " (num (at mem 0)) " :availMb " (num (at mem 1)) " :swapUsedMb " (num (at mem 2)) ")"
         " :disk " (rows (map (fn [(f (List String))] -> String (str "(:mount " (fm/quoteText (at f 1)) " :sizeGb " (num (at f 2)) " :freeGb " (num (at f 3)) ")")) (filter (fn [(f (List String))] -> Bool (>= (listLength f) 4)) (tagLines text "disk"))))
         " :top " (rows (map procRow (listTake sorted top)))
         " :units " (rows (map unitRow (tagLines text "U")))
         " :jobs " (rows (map jobRow (filter (fn [(f (List String))] -> Bool (not (stringEmpty? (at f 1)))) (tagLines text "job"))))
         " :services " (rows (map serviceRow svcs))
         " :relay (:active " (if (= (at relay 1) "true") "true" "false") " :port " (num (at relay 0)) ")"
         " :stray " (rows (map strayRow (strays ps me (filter (fn [(n Int64)] -> Bool (> n 1)) roots)))) ")"))

fn statErr node: String code: String msg: String -> String
  (str "(:nodeStat :node " (fm/quoteText node) " :err (:code " code " :msg " (fm/quoteText msg) "))")

