(module asl-tools/remote/vpsCore
  :x [VpsCfg Exec textOr parseVpsCfg homeRelative? loadVpsCfg! withRelay! receiptErr q remoteLine remoteSh localSh boundScript boundArgv cdScript inDir cleanEnvArgv wtPath sshFailed? sshLineTo sshTo! execTo! b64Script relayTo! dialable! relayReady! tunnelArgv healTunnel! waitDial! exec! capText lastLines unreachable at inWt! noDir? fileOk? perFile! relayPool! relayGroups! check! test! shell! keyed locateAt!]
  :i [(asl-tools/remote/bridge :a br) (asl-tools/remote/form :a fm) (asl-tools/fleet/run :a fr) (asl-tools/remote/relay :a rl) (asl-tools/remote/sync :a sy) (asl-tools/remote/transport :a tr) (asl-tools/remote/vpsNode :a vn)])

; (:m :ref ASL-IMPORTS-TOOLS-FINAL :do "the VPS client core: the config, the ssh and relay exec, the worktree check, test and shell ops that asl/packages/asl-agent remoteOps needs; it lives under asl/ so asl/ imports no tools/ module, and tools/remote/vps.asl keeps every other verb and the CLI entry")
; (:m :ref REMOTE-PARITY :do "the Mac drives the VPS as if it were local: every command is one ssh round trip whose remote line is a shell-quoted argv (a constant sh or perl script plus positional operands, so no operand is ever reparsed), the remote side runs under a perl bound that kills its whole group at the timeout or when the ssh session goes away, and each answer is one ASN receipt; paths on the VPS are relative to the account home (repo ~/asex, worktrees ~/wt/UNIT, jobs ~/.asl/run/rjobs)")
(schema VpsCfg
  (:f ssh tr/Config)
  (:f repo String)
  (:f wtBase String)
  (:f jobsDir String)
  (:f e2eUnit String)
  (:f via String)
  (:f link rl/Link)
  (:f relayPort Int64)
  (:f relayUnit String)
  (:f tokenPath String)
  (:f key String)
  (:f node String)
  (:f slots Int64)
  (:f refNs String))

(schema Exec (:f exit Int64) (:f out String) (:f err String))

fn textOr node: fm/Node key: String fallback: String -> String
  (match (fm/formGet node key) ((some n) (optionOr (fm/formText n) fallback)) ((none) fallback))

; (:m :ref REMOTE-PARITY :do "the VPS settings extend ~/.asl/remote.asn: :repo (default asex), :wtBase (default wt) and :jobs (default .asl/run/rjobs) are home-relative paths of safe tokens, and :e2eUnit names the VPS worktree the remote suite runs its bridge from; a path that is absolute or climbs out of home is refused")
fn parseVpsCfg text: String -> (Result VpsCfg String)
  (match (tr/parseConfig text)
    ((err e) (err e))
    ((ok c)
      (match (fm/parseForm text)
        ((err e) (err e))
        ((ok node)
          (let [(repo (textOr node ":repo" "asex"))
                (wt (textOr node ":wtBase" "wt"))
                (jobs (textOr node ":jobs" ".asl/run/rjobs"))
                (e2e (textOr node ":e2eUnit" ""))
                (via (textOr node ":via" "ssh"))
                (relayUnit (textOr node ":relayUnit" ""))
                (port (match (fm/formGet node ":relayPort") ((some n) (optionOr (fm/formInt n) 47011)) ((none) 47011)))
                (sock (textOr node ":relaySock" ""))]
            (cond
              ((not (fm/safePath? repo)) (err "ERR_REMOTE_CONFIG :repo must be a home-relative path"))
              ((not (fm/safePath? wt)) (err "ERR_REMOTE_CONFIG :wtBase must be a home-relative path"))
              ((not (homeRelative? jobs)) (err "ERR_REMOTE_CONFIG :jobs must be a home-relative path"))
              ((and (not (stringEmpty? e2e)) (not (fm/safeUnit? e2e))) (err "ERR_REMOTE_CONFIG :e2eUnit must match [A-Za-z0-9-]+"))
              ((not (listContains? (list "ssh" "relay") via)) (err "ERR_REMOTE_CONFIG :via must be ssh or relay"))
              ((and (not (stringEmpty? relayUnit)) (not (fm/safeUnit? relayUnit))) (err "ERR_REMOTE_CONFIG :relayUnit must match [A-Za-z0-9-]+"))
              ((or (< port 1) (> port 65535)) (err "ERR_REMOTE_CONFIG :relayPort must be 1-65535"))
              (else (ok (VpsCfg :ssh c :repo repo :wtBase wt :jobsDir jobs :e2eUnit e2e :via via :link (rl/linkOf sock 0 "" "") :relayPort port
                                :relayUnit relayUnit :tokenPath (textOr node ":relayToken" "")
                                :key (textOr node ":key" "") :node "" :slots 0 :refNs "vps")))))))))

fn homeRelative? s: String -> Bool
  (and (fm/safeToken? s)
       (and (not (stringStartsWith? s "/"))
            (listAll? (fn [(seg String)] -> Bool (and (not (stringEmpty? seg)) (and (!= seg "..") (!= seg ".")))) (stringSplit s "/"))))

fn ! loadVpsCfg! path: String -> (Result VpsCfg String)
  (match (fileReadString path)
    ((err _) (err (str "ERR_REMOTE_NO_CONFIG " path)))
    ((ok text) (resultMap (parseVpsCfg text) withRelay!)))

; (:m :ref RELAY-LINK :do "the relay end on this machine: the local socket (default ~/.asl/run/relay.sock) is the near end of the tunnel and the token (default ~/.asl/run/relay.token, 0600, fetched once from the VPS by relay up) authenticates the hello; each process is one session, so its retries are recognised by the bridge")
fn ! withRelay! cfg: VpsCfg -> VpsCfg
  (let [(home (resultOr (getHomeDir) "/tmp"))
        (sock (if (stringEmpty? cfg.link.path) (str home "/.asl/run/relay.sock") cfg.link.path))
        (tp (if (stringEmpty? cfg.tokenPath) (str home "/.asl/run/relay.token") cfg.tokenPath))]
    (with cfg :tokenPath tp :link (rl/linkOf sock 0 (resultOr (br/loadToken! tp) "") (rl/newSession))))

fn receiptErr code: String msg: String -> String
  (sy/receiptErr code msg)

fn q s: String -> String
  (fm/quoteText s)

fn remoteLine argv: (List String) -> String
  (stringJoin (map tr/shQuote argv) " ")

; (:m :ref REMOTE-BOUND :do "the remote half of every timeout: the command runs as the leader of its own group, and the waiter kills that whole group at the deadline (exit 124) or when it is orphaned because sshd went away (exit 129), so a dropped link or a hung build never leaves work running on the VPS")
; (:m :ref REMOTE-FOREIGN-CONSOLIDATE :do "the one remote shell site: every command run on the VPS is sh -c over a constant script with positional operands ($0 names the step), so no operand is ever parsed by a shell; the line still goes through boundArgv and ssh or the relay")
fn remoteSh script: String args: (List String) -> (List String)
  (cons "sh" (cons "-c" (cons script args)))

; (:m :ref REMOTE-FOREIGN-CONSOLIDATE :do "the one local shell site: tr/run! (fleet/run, timeout and descendant limit) of /bin/sh -c over a constant script, used only to redirect a file into ssh or to background the tunnel, which runGuarded cannot do itself")
fn localSh script: String args: (List String) -> (List String)
  (cons "/bin/sh" (cons "-c" (cons script args)))

fn boundScript -> String
  "my $t = shift; my $pp = getppid(); my $p = fork(); exit 127 unless defined $p; if (!$p) { POSIX::setsid(); exec { $ARGV[0] } @ARGV; exit 127; } my $end = time + $t; my $code = 0; while (1) { my $w = waitpid($p, POSIX::WNOHANG()); if ($w == $p) { my $s = $?; $code = ($s & 127) ? 128 + ($s & 127) : ($s >> 8); last; } if (time >= $end) { kill 'KILL', -$p; waitpid($p, 0); $code = 124; last; } if (getppid() != $pp) { kill 'KILL', -$p; waitpid($p, 0); $code = 129; last; } select(undef, undef, undef, 0.2); } exit $code"

fn boundArgv timeoutS: Int64 argv: (List String) -> (List String)
  (listAppend (list "perl" "-MPOSIX" "-e" (boundScript) (str (max 1 timeoutS))) argv)

fn cdScript -> String
  "cd \"$1\" || { echo \"(:err :code noDir :msg \\\"no such directory on the VPS\\\")\"; exit 3; }; shift; exec \"$@\""

fn inDir dir: String argv: (List String) -> (List String)
  (listAppend (remoteSh (cdScript) (list "inDir" dir)) argv)

fn cleanEnvArgv argv: (List String) -> (List String)
  (listAppend (list "env" "-u" "ASL_ROOT" "-u" "ASL_PRELUDE") argv)

fn wtPath cfg: VpsCfg unit: String -> String
  (str cfg.wtBase "/" unit)

fn sshFailed? e: Exec -> Bool
  (or (and (= e.exit 255) (stringEmpty? (stringTrim e.out))) (or (= e.exit -2) (= e.exit -3)))

fn sshLineTo argv: (List String) inPath: String outPath: String -> String
  (str "exec " (stringJoin (map tr/shQuote argv) " ") " < " (tr/shQuote inPath)
       (if (stringEmpty? outPath) "" (str " > " (tr/shQuote outPath))))

; (:m :ref REMOTE-PARITY :do "the only local child is the ssh client, started through runGuarded with a timeout of the remote bound plus slack and a descendant limit (spawnSafety); stdin comes from a file (or /dev/null) and a binary stdout goes to a file, so no payload byte reaches a local shell either")
fn ! sshTo! cfg: VpsCfg argv: (List String) timeoutS: Int64 inPath: String outPath: String -> Exec
  (let [(line (remoteLine (boundArgv timeoutS argv)))
        (ssh (keyed cfg (tr/sshArgv cfg.ssh line)))
        (d (tr/run! (localSh (sshLineTo ssh (if (stringEmpty? inPath) "/dev/null" inPath) outPath) (list)) (+ timeoutS 30)))]
    (Exec :exit d.exitCode :out d.stdout :err d.stderr))

; (:m :ref RELAY-PRIMARY :do "with :via relay every op travels as an exec frame over the relay and ssh carries only the bootstrap: a relay that cannot be dialled even after one tunnel heal falls back to ssh, which is safe because nothing was sent; once a frame is sent the client retries the same id until its deadline and never falls back, so an op is never run twice")
fn ! execTo! cfg: VpsCfg argv: (List String) timeoutS: Int64 inPath: String outPath: String -> Exec
  (if (and (= cfg.via "relay") (relayReady! cfg))
    (relayTo! cfg argv timeoutS inPath outPath)
    (sshTo! cfg argv timeoutS inPath outPath))

fn b64Script -> String
  "open(my $h, '-|', @ARGV) or exit 127; binmode $h; local $/; my $d = <$h>; close $h; print MIME::Base64::encode_base64(defined $d ? $d : '', ''); exit($? >> 8)"

fn ! relayTo! cfg: VpsCfg argv: (List String) timeoutS: Int64 inPath: String outPath: String -> Exec
  (let [(stdin (if (stringEmpty? inPath) "" (resultOr (resultMap (fileReadBytes inPath) bytesToBase64) "")))
        (argv2 (if (stringEmpty? outPath) argv (listAppend (list "perl" "-MMIME::Base64" "-e" (b64Script)) argv)))
        (r (rl/execVia! cfg.link (rl/newId) "" argv2 timeoutS stdin (* (+ timeoutS 120) 1000) (fn [] -> Bool (healTunnel! cfg))))]
    (cond
      ((= r.code "noAnswer") (Exec :exit -2 :out "" :err (str "relay: " r.err)))
      ((not (stringEmpty? r.code)) (Exec :exit -3 :out "" :err (str "relay " r.code ": " r.err)))
      ((stringEmpty? outPath) (Exec :exit r.exit :out r.out :err r.err))
      (else
        (match (bytesFromBase64 (stringTrim r.out))
          ((err e) (Exec :exit -3 :out "" :err (str "relay: bad base64 stdout: " e)))
          ((ok bytes) (do (fileWrite outPath bytes) (Exec :exit r.exit :out "" :err r.err)))))))

fn ! dialable! cfg: VpsCfg -> Bool
  (match (rl/connect! cfg.link) ((ok fd) (do (fdClose fd) true)) ((err _) false))

fn ! relayReady! cfg: VpsCfg -> Bool
  (and (not (stringEmpty? cfg.link.token)) (or (dialable! cfg) (healTunnel! cfg)))

fn tunnelArgv cfg: VpsCfg -> (List String)
  (keyed cfg (list cfg.ssh.ssh "-f" "-N" "-T" "-o" "BatchMode=yes" "-o" "ExitOnForwardFailure=yes" "-o" "ServerAliveInterval=5" "-o" "ServerAliveCountMax=3"
        "-o" (str "ConnectTimeout=" cfg.ssh.connectTimeout) "-o" "ControlMaster=no" "-o" "ControlPath=none" "-o" "StreamLocalBindUnlink=yes"
        "-L" (str cfg.link.path ":127.0.0.1:" cfg.relayPort) "--" cfg.ssh.host))

; (:m :ref RELAY-HEAL :do "the client heals its own transport: when the local relay socket does not answer it starts one backgrounded ssh -L (ServerAlive 5s x3, so a dead path is noticed within ~15s) and waits up to 5s for the socket; after a VPN toggle the next op or retry redials through a fresh tunnel without any keeper process")
fn ! healTunnel! cfg: VpsCfg -> Bool
  (cond
    ((dialable! cfg) true)
    ((not (stringStartsWith? cfg.link.path "/")) false)
    (else
      (let [(_ (tr/run! (localSh (str "exec " (stringJoin (map tr/shQuote (tunnelArgv cfg)) " ") " </dev/null >/dev/null 2>&1") (list)) (+ cfg.ssh.connectTimeout 15)))]
        (waitDial! cfg 50))))

fn ! waitDial! cfg: VpsCfg tries: Int64 -> Bool
  (cond
    ((dialable! cfg) true)
    ((<= tries 0) false)
    (else (do (sleepMs 100) (waitDial! cfg (- tries 1)))))

fn ! exec! cfg: VpsCfg argv: (List String) timeoutS: Int64 -> Exec
  (execTo! cfg argv timeoutS "" "")

fn capText s: String cap: Int64 -> String
  (let [(len (stringLength s))]
    (if (> len cap) (optionOr (stringSlice s (- len cap) len) s) s))

fn lastLines text: String n: Int64 -> String
  (let [(lines (stringLines (stringTrim text)))
        (k (listLength lines))]
    (stringJoin (if (> k n) (listDrop lines (- k n)) lines) "\n"))

fn unreachable e: Exec -> String
  (cond
    ((= e.exit -2) (receiptErr "noAnswer" (lastLines e.err 3)))
    ((= e.exit -3) (receiptErr "relayRefused" (lastLines e.err 3)))
    (else (receiptErr "unreachable" (str "ssh exit 255: " (lastLines e.err 3)))))

fn at xs: (List String) i: Int64 -> String
  (optionOr (listGet xs i) "")


fn ! inWt! cfg: VpsCfg unit: String argv: (List String) timeoutS: Int64 -> Exec
  (exec! cfg (inDir (wtPath cfg unit) argv) timeoutS)

fn noDir? e: Exec -> Bool
  (stringStartsWith? (stringTrim e.out) "(:err :code noDir")

fn fileOk? f: String -> Bool
  (fm/safePath? f)

; (:m :ref REMOTE-SUITES :do "check and test take worktree-relative files; at most :jobs files (default 2, capped at 4) run at once, each as its own ssh round trip under its own bound, and each file gets a row with its exit, executed assertion count and first error lines")
fn ! perFile! cfg: VpsCfg unit: String files: (List String) jobs: Int64 timeoutS: Int64 verb: String -> String
  (cond
    ((not (fm/safeUnit? unit)) (receiptErr "badUnit" "unit must match [A-Za-z0-9-]+"))
    ((listEmpty? files) (receiptErr "noFiles" (str verb " needs at least one file")))
    ((not (listAll? fileOk? files)) (receiptErr "badPath" "files must be worktree-relative paths without dot or dash segments"))
    (else
      (let [(slots (max 1 (min jobs 4)))
            (argvFor (fn [(f String)] -> (List String)
                       (let [(line (remoteLine (boundArgv timeoutS (inDir (wtPath cfg unit) (cleanEnvArgv (list "nice" "-n" "10" "./bin/asl" verb f))))))]
                         (localSh (sshLineTo (tr/sshArgv cfg.ssh line) "/dev/null" "") (list)))))
            (pool (map (fn [(f String)] -> fr/Job (fr/job (argvFor f) "." (fr/childEnv (list)))) files))
            (done (if (and (= cfg.via "relay") (relayReady! cfg))
                    (relayPool! cfg (map (fn [(f String)] -> (List String) (inDir (wtPath cfg unit) (cleanEnvArgv (list "nice" "-n" "10" "./bin/asl" verb f)))) files) slots timeoutS)
                    (fr/runPoolLimited pool slots (fr/limits (+ timeoutS 30) 32))))
            (rowOf (fn [(d fr/Done)] -> String
                     (let [(f (at files d.idx))]
                       (str "(:file " (q f) " :exit " d.exit
                            (if (= verb "test") (str " :executed " (optionOr (fr/executedOf d.out) 0)) "")
                            " :errors " (fm/quoteAll (listTake (fr/errorLinesOf d.out) 5))
                            (if (= d.exit 0) "" (str " :tail " (q (lastLines d.out 8)) (locateAt! cfg unit f d.out))) ")"))))
            (sorted (listSortBy (fn [(d fr/Done)] -> Int64 d.idx) done))
            (bad (listLength (filter (fn [(d fr/Done)] -> Bool (!= d.exit 0)) done)))
            (lost (listAny? (fn [(d fr/Done)] -> Bool (and (= d.exit 255) (not (stringContains? d.out "(:")))) done))]
        (if lost
          (receiptErr "unreachable" "ssh exit 255 for at least one file")
          (str "(:" verb " :unit " unit " :jobs " slots " :failed " bad " :files (" (stringJoin (map rowOf sorted) " ") "))")))))

; (:m :ref RELAY-PRIMARY :do "over the relay the files go in groups of :jobs exec frames on one connection, each with its own id, so a reconnect resends only the ones still open")
fn ! relayPool! cfg: VpsCfg argvs: (List (List String)) slots: Int64 timeoutS: Int64 -> (List fr/Done)
  (relayGroups! cfg (range 0 (listLength argvs)) argvs slots timeoutS (list))

fn ! relayGroups! cfg: VpsCfg idxs: (List Int64) argvs: (List (List String)) slots: Int64 timeoutS: Int64 acc: (List fr/Done) -> (List fr/Done)
  (if (listEmpty? idxs) acc
    (let [(group (listTake idxs slots))
          (pends (map (fn [(i Int64)] -> rl/Pend (let [(id (str (rl/newId) "-" i))] (rl/pendText id (rl/execFrame id "" (optionOr (listGet argvs i) (list)) timeoutS "")))) group))
          (c (rl/request! cfg.link pends (* (+ timeoutS 120) 1000) (fn [] -> Bool (healTunnel! cfg))))
          (rows (map (fn [(i Int64)] -> fr/Done
                       (let [(p (optionOr (listGet c.pend (- i (optionOr (listHead group) 0))) (rl/pendText "" "")))
                             (r (rl/replyOf c p))
                             (code (if (stringEmpty? r.code) r.exit (if (= r.code "noAnswer") 255 1)))]
                         (fr/Done :idx i :exit code :out (str r.out "\n" r.err) :ms 0 :verdict r.verdict)))
                     group))]
      (relayGroups! cfg (listDrop idxs slots) argvs slots timeoutS (listAppend acc rows))))

fn ! check! cfg: VpsCfg unit: String files: (List String) jobs: Int64 timeoutS: Int64 -> String
  (perFile! cfg unit files jobs timeoutS "check")

fn ! test! cfg: VpsCfg unit: String files: (List String) jobs: Int64 timeoutS: Int64 -> String
  (perFile! cfg unit files jobs timeoutS "test")

; (:m :ref REMOTE-SHELL :do "a bounded shell command in a worktree: the text is one argv element of sh -c under the group-killing bound, so it can be any pipeline but cannot outlive its timeout or the ssh session; output is capped at 64KB each")
fn ! shell! cfg: VpsCfg unit: String cmd: String timeoutS: Int64 -> String
  (cond
    ((not (fm/safeUnit? unit)) (receiptErr "badUnit" "unit must match [A-Za-z0-9-]+"))
    ((stringEmpty? (stringTrim cmd)) (receiptErr "noCommand" "sh needs a command"))
    (else
      (let [(e (inWt! cfg unit (remoteSh cmd (list)) timeoutS))]
        (cond
          ((sshFailed? e) (unreachable e))
          ((noDir? e) (receiptErr "noWorktree" (str "no worktree " unit)))
          (else (str "(:sh :unit " unit " :exit " e.exit (if (= e.exit 124) " :verdict timeout" "") " :out " (q (capText e.out 65536)) " :err " (q (capText e.err 65536)) ")"))))))


fn keyed cfg: VpsCfg argv: (List String) -> (List String)
  (if (stringEmpty? cfg.key) argv
    (cons (at argv 0) (cons "-i" (cons cfg.key (cons "-o" (cons "IdentitiesOnly=yes" (optionOr (listTail argv) (list))))))))

fn ! locateAt! cfg: VpsCfg unit: String file: String out: String -> String
  (let [(l (vn/errLoc out file))
        (ln (pairFirst l))]
    (if (= ln 0)
      ""
      (let [(e (exec! cfg (remoteSh (vn/locateScript) (list "locate" cfg.wtBase (str unit "/" (vn/errFile out unit file)) (str ln))) 30))]
        (str " :at " (vn/locateReceipt ln (pairSecond l) (if (sshFailed? e) "" e.out))))))

