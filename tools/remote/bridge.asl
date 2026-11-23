(module asl-tools/remote/bridge
  :x [main BridgeCfg Frame Conn BridgeJob Server Reply jobArgv serverEntries
      kinds defaultCfg parseCfg loadCfg! cfgPath tokenPath socketPath expandArgv capArgv capScript
      parseFrame frameKind frameId errFrame outFrame doneFrame frameText helloFrame
      listenTcp! listenUnix! serverClose! step! serve! pollFds jobCount connCount connOf
      loadToken! makeToken! pruneStore!
      clientTcp! clientUnix! clientSend! clientHello! clientPoll! terminal? replyOf call! main]
  :i [(asl-tools/fleet/run :a fr) (asl-net/socket :a sock) (asl-net/unix :a unx) (asl-tools/remote/form :a fm)])

; (:m :ref VPS-BRIDGE :do "one ASN form per line each way: a connection opens with (:hello :id I :v 1), then each request names its kind and an :id and gets zero or more (:out ...) frames and exactly one terminal (:done ...) or (:err ...); the default listener is a 0600 unix socket, tcp is opt-in on 127.0.0.1 and then the hello must carry the token from a 0600 file")
(schema BridgeCfg
  (:f root String)
  (:f asl String)
  (:f templates (List (Pair String (List String))))
  (:f defaultTimeoutS Int64)
  (:f maxTimeoutS Int64)
  (:f maxDesc Int64)
  (:f maxJobs Int64)
  (:f maxLine Int64)
  (:f readMaxLines Int64)
  (:f chunk Int64)
  (:f nice Int64)
  (:f cpuS Int64)
  (:f memKb Int64)
  (:f maxOutBuf Int64)
  (:f maxConns Int64)
  (:f idleS Int64)
  (:f wtBase String)
  (:f exec Bool)
  (:f stateDir String)
  (:f keepS Int64))

(schema Frame (:f kind String) (:f id String) (:f node fm/Node))

(schema Conn (:f id Int64) (:f fd Int64) (:f inBuf String) (:f outBuf String) (:f open Bool) (:f discard Bool)
  (:f ready Bool) (:f closing Bool) (:f lastNs Int64) (:f session String))

(schema BridgeJob (:f conn Int64) (:f id String) (:f kind String) (:f guard fr/Guarded) (:f startNs Int64) (:f timeoutMs Int64)
  (:f key String) (:f keep Bool) (:f outAcc String) (:f errAcc String) (:f inFile String)
  (:f seq Int64) (:f rbuf (List (Pair Int64 String))))

(schema Server
  (:f listenFd Int64)
  (:f port Int64)
  (:f unixPath String)
  (:f token String)
  (:f cfg BridgeCfg)
  (:f conns (List Conn))
  (:f jobs (List BridgeJob))
  (:f nextConn Int64))

(schema Reply (:f frames (List String)) (:f buf String) (:f closed Bool))

fn kinds -> (List String)
  (list "hello" "ping" "read" "check" "test" "run" "agent" "session" "forms" "exec" "cancel" "stage")

fn sessionOps -> (List String)
  (list "start" "send" "list" "show" "stop" "fork")

fn defaultTemplates -> (List (Pair String (List String)))
  (list (pair "check" (list "{asl}" "check" "{file}"))
        (pair "test" (list "{asl}" "test" "{file}"))
        (pair "run" (list "{asl}" "run" "{file}" "{args}"))
        (pair "agent" (list "{asl}" "run" "{root}/asl/packages/asl-agent/src/main.asl" "{form}"))
        (pair "session" (list "{root}/bin/asl-gateway" "session" "{op}" "{props}"))
        (pair "forms" (list "{asl}" "{form}")))

fn defaultCfg root: String -> BridgeCfg
  (BridgeCfg :root root :asl (str root "/bin/asl") :templates (defaultTemplates)
             :defaultTimeoutS 600 :maxTimeoutS 3600 :maxDesc 64 :maxJobs 4 :maxLine 1048576
             :readMaxLines 2000 :chunk 16384 :nice 15 :cpuS 0 :memKb 0
             :maxOutBuf 4194304 :maxConns 16 :idleS 600 :wtBase "" :exec false :stateDir "" :keepS 604800)

fn ! homeAsl -> String
  (str (resultOr (getHomeDir) "/tmp") "/.asl")

fn ! cfgPath -> String
  (str (homeAsl) "/bridge.asn")

fn ! tokenPath -> String
  (str (homeAsl) "/bridge.token")

fn ! socketPath -> String
  (str (homeAsl) "/run/bridge.sock")

fn intOf node: fm/Node key: String fallback: Int64 -> Int64
  (match (fm/formGet node key) ((some n) (optionOr (fm/formInt n) fallback)) ((none) fallback))

fn textOf node: fm/Node key: String fallback: String -> String
  (match (fm/formGet node key) ((some n) (optionOr (fm/formText n) fallback)) ((none) fallback))

fn listOf node: fm/Node key: String -> (List String)
  (match (fm/formGet node key) ((some n) (fm/formStrings n)) ((none) (list)))

fn templateOf node: fm/Node kind: String fallback: (List String) -> (List String)
  (let [(xs (listOf node (str ":" kind)))] (if (listEmpty? xs) fallback xs))

; (:m :ref VPS-BRIDGE :do "settings live in ~/.asl/bridge.asn as (:bridge :timeout S :maxTimeout S :maxJobs N :nice N :cpu S :mem KB :maxOutBuf B :maxConns N :idle S :check (ARGV) ...); a kind's template is an argv list, never a shell string, and a missing file is the defaults")
fn parseCfg text: String root: String -> (Result BridgeCfg String)
  (match (fm/parseForm text)
    ((err e) (err (str "ERR_BRIDGE_CONFIG parse: " e)))
    ((ok node)
      (let [(d (defaultCfg root))
            (r (textOf node ":root" root))
            (d2 (defaultCfg r))]
        (ok (BridgeCfg :root r :asl (textOf node ":asl" d2.asl)
                       :templates (map (fn [(p (Pair String (List String)))] -> (Pair String (List String))
                                         (pair (pairFirst p) (templateOf node (pairFirst p) (pairSecond p))))
                                       (defaultTemplates))
                       :defaultTimeoutS (intOf node ":timeout" d.defaultTimeoutS)
                       :maxTimeoutS (intOf node ":maxTimeout" d.maxTimeoutS)
                       :maxDesc (intOf node ":maxDesc" d.maxDesc)
                       :maxJobs (intOf node ":maxJobs" d.maxJobs)
                       :maxLine (intOf node ":maxLine" d.maxLine)
                       :readMaxLines (intOf node ":readMaxLines" d.readMaxLines)
                       :chunk (intOf node ":chunk" d.chunk)
                       :nice (intOf node ":nice" d.nice)
                       :cpuS (intOf node ":cpu" d.cpuS)
                       :memKb (intOf node ":mem" d.memKb)
                       :maxOutBuf (intOf node ":maxOutBuf" d.maxOutBuf)
                       :maxConns (intOf node ":maxConns" d.maxConns)
                       :idleS (intOf node ":idle" d.idleS)
                       :wtBase (textOf node ":wtBase" "")
                       :exec (= (textOf node ":exec" "false") "true")
                       :stateDir (textOf node ":stateDir" "")
                       :keepS (intOf node ":keep" d.keepS))))))

fn ! withWtBase! c: BridgeCfg -> BridgeCfg
  (let [(home (resultOr (getHomeDir) "/tmp"))
        (c1 (if (stringEmpty? c.wtBase) (with c :wtBase (str home "/wt")) c))]
    (if (stringEmpty? c1.stateDir) (with c1 :stateDir (str home "/.asl/run/relay")) c1))

fn ! loadCfg! path: String root: String -> (Result BridgeCfg String)
  (if (not (fileExists? path))
    (ok (withWtBase! (defaultCfg root)))
    (match (fileReadString path)
      ((err e) (err (str "ERR_BRIDGE_CONFIG read: " e)))
      ((ok text) (resultMap (parseCfg text root) withWtBase!))))

fn hexDigit n: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" n (+ n 1)) "0")

fn ! randomHex! n: Int64 -> (Result String String)
  (match (fileReadRange "/dev/urandom" 0 n)
    ((err e) (err e))
    ((ok bs) (if (< (bytesLength bs) n) (err "short read from /dev/urandom")
               (ok (stringJoin (map (fn [(i Int64)] -> String (let [(b (bytesGet bs i))] (str (hexDigit (/ b 16)) (hexDigit (mod b 16)))))
                                    (range 0 n)) "")))))

fn modeBits st: LinkStat -> Int64
  (mod st.mode 512)

fn symlinkMode? mode: Int64 -> Bool
  (= (mod (/ mode 4096) 16) 10)

; (:m :ref VPS-BRIDGE :do "the tcp token is a file the owner alone can read: a symlink, a group or other bit, or a short value is refused, so a token another user could plant or read never authenticates")
fn ! loadToken! path: String -> (Result String String)
  (match (fileLstat path)
    ((err _) (err (str "ERR_BRIDGE_TOKEN no token file " path)))
    ((ok st)
      (cond
        ((symlinkMode? st.mode) (err "ERR_BRIDGE_TOKEN the token file is a symlink"))
        ((!= (mod (modeBits st) 64) 0) (err "ERR_BRIDGE_TOKEN the token file must be mode 0600"))
        (else (match (fileReadString path)
                ((err e) (err (str "ERR_BRIDGE_TOKEN " e)))
                ((ok t) (let [(tok (stringTrim t))]
                          (if (< (stringLength tok) 32) (err "ERR_BRIDGE_TOKEN the token is shorter than 32 chars") (ok tok)))))))))

fn ! makeToken! path: String -> (Result String String)
  (if (fileExists? path) (loadToken! path)
    (match (randomHex! 32)
      ((err e) (err (str "ERR_BRIDGE_TOKEN " e)))
      ((ok tok) (match (fileCreateExclusive path (str tok "\n"))
                  ((err e) (err (str "ERR_BRIDGE_TOKEN " e)))
                  ((ok _) (match (fileChmod path 384) ((err e) (err (str "ERR_BRIDGE_TOKEN " e))) ((ok _) (ok tok))))))))

fn frameText id: String kind: String rest: String -> String
  (str "(:" kind " :id " (fm/quoteText id) rest ")")

fn errFrame id: String code: String msg: String -> String
  (frameText id "err" (str " :code " code " :msg " (fm/quoteText msg)))

fn outFrame id: String stream: String text: String -> String
  (frameText id "out" (str " :stream " stream " :text " (fm/quoteText text)))

fn doneFrame id: String exit: Int64 verdict: String -> String
  (frameText id "done" (str " :exit " exit " :verdict " verdict))

fn headKind items: (List fm/Node) -> String
  (match (listHead items)
    ((none) "")
    ((some n) (let [(t (optionOr (fm/formText n) ""))]
                (if (stringStartsWith? t ":") (optionOr (stringSlice t 1 (stringLength t)) "") ""))))

fn frameKind node: fm/Node -> String
  (match node
    ((fm/seq items) (headKind items))
    (_ ""))

fn frameId node: fm/Node -> String
  (textOf node ":id" "")

fn idOk? id: String -> Bool
  (and (fm/safeToken? id) (<= (stringLength id) 64))

; (:m :ref VPS-BRIDGE :do "a frame that does not parse, names no known kind or carries no safe :id is refused here with a reason; the caller answers (:err ...) under id ? and closes the connection")
fn parseFrame line: String -> (Result Frame String)
  (match (fm/parseForm line)
    ((err e) (err (str "unparseable: " e)))
    ((ok node)
      (let [(kind (frameKind node)) (id (frameId node))]
        (cond
          ((not (listContains? (kinds) kind)) (err (str "unknown kind " (fm/quoteText kind))))
          ((not (idOk? id)) (err "missing or unsafe :id"))
          (else (ok (Frame :kind kind :id id :node node)))))))


fn slot name: String -> String
  (str "{" name "}")

; (:m :ref VPS-BRIDGE :do "a frame value only ever fills a whole argv element ({file} {form} {op} {props}) or splices as elements ({args}); only {root} and {asl}, which come from the server's own config, are replaced inside an element, so no frame byte is reparsed")
fn expandArgv cfg: BridgeCfg tmpl: (List String) vals: (List (Pair String String)) args: (List String) -> (List String)
  (fold (fn [(acc (List String)) (el String)] -> (List String)
          (if (= el "{args}")
            (listAppend acc args)
            (match (listHead (filter (fn [(p (Pair String String))] -> Bool (= (slot (pairFirst p)) el)) vals))
              ((some p) (listAppend acc (list (pairSecond p))))
              ((none) (listAppend acc (list (stringReplace (stringReplace el "{root}" cfg.root) "{asl}" cfg.asl)))))))
        (list) tmpl)

fn capScript -> String
  "[ \"$1\" -gt 0 ] && ulimit -t \"$1\"; [ \"$2\" -gt 0 ] && ulimit -v \"$2\"; shift 2; exec \"$@\""

; (:m :ref VPS-BRIDGE :do "a shared box keeps headroom: every child runs under nice and, when :cpu or :mem is set, under ulimit -t/-v through one constant sh script whose operands are positional, so the child's own argv never meets a shell")
fn capArgv cfg: BridgeCfg argv: (List String) -> (List String)
  (listAppend (if (> cfg.nice 0) (list "nice" "-n" (str cfg.nice)) (list))
    (listAppend (if (or (> cfg.cpuS 0) (> cfg.memKb 0)) (list "/bin/sh" "-c" (capScript) "bridgeCap" (str cfg.cpuS) (str cfg.memKb)) (list))
                argv))

; (:m :ref REMOTE-PARITY :do "a frame with :wt UNIT works in that worktree under :wtBase (default ~/wt): read, check, test, run and forms resolve against it and use its own bin/asl; the unit is a safe token and the real path must lie under the real base, so a symlinked or missing worktree is refused, and a server with no base refuses every :wt")
fn ! cfgFor! cfg: BridgeCfg node: fm/Node -> (Result BridgeCfg String)
  (let [(unit (textOf node ":wt" ""))]
    (cond
      ((none? (fm/formGet node ":wt")) (ok cfg))
      ((not (fm/safeUnit? unit)) (err ":wt must match [A-Za-z0-9-]+"))
      ((stringEmpty? cfg.wtBase) (err "this bridge has no worktree base"))
      (else
        (match (realPath cfg.wtBase)
          ((err _) (err "the worktree base is missing"))
          ((ok base)
            (match (realPath (str base "/" unit))
              ((err _) (err (str "no worktree " unit)))
              ((ok dir) (if (stringStartsWith? dir (str base "/"))
                          (ok (with cfg :root dir :asl (str dir "/bin/asl")))
                          (err (str "worktree " unit " lies outside the base"))))))))))

fn templateFor cfg: BridgeCfg kind: String -> (List String)
  (match (listHead (filter (fn [(p (Pair String (List String)))] -> Bool (= (pairFirst p) kind)) cfg.templates))
    ((some p) (pairSecond p))
    ((none) (list)))

fn propText node: fm/Node key: String -> String
  (match (fm/formGet node (str ":" key))
    ((none) "")
    ((some n) (match n
                ((fm/seq _) (str " :" key " " (fm/quoteAll (fm/formStrings n))))
                (_ (str " :" key " " (fm/quoteText (optionOr (fm/formText n) "")))))))

fn sessionProps node: fm/Node -> String
  (str "(" (stringTrim (str (propText node "name") (propText node "key") (propText node "vendor") (propText node "cwd")
                            (propText node "text") (propText node "to") (propText node "args"))) ")")

; (:m :ref spawnSafety :do "the entry points that serve or keep a server; a job naming one is refused before anything runs, so no frame can start another bridge, tunnel keeper or gateway")
fn serverEntries -> (List String)
  (list "tools/remote/bridge.asl" "tools/remote/tunnel.asl" "tools/remote/dispatch.asl" "asl/packages/asl-gateway/src/server.asl" "bin/asl-gateway" "bin/asl")

; (:m :ref VPS-BRIDGE :do "the argv a job frame asks for, or the reason it is refused: files are root-relative safe paths, a session op is one of the gateway's own and its name a safe token; the session row on the box binds the Leon session name to the vendor session id (GWSESS) and :args pass through to the vendor CLI")
fn jobArgv cfg: BridgeCfg f: Frame -> (Result (List String) String)
  (let [(node f.node)
        (file (textOf node ":file" ""))
        (tmpl (templateFor cfg f.kind))
        (needsFile (or (= f.kind "check") (or (= f.kind "test") (= f.kind "run"))))]
    (cond
      ((listEmpty? tmpl) (err (str "no template for " f.kind)))
      ((and needsFile (not (fm/safePath? file))) (err ":file must be a root-relative path without dot or dash segments"))
      ((and (= f.kind "run") (listContains? (serverEntries) file)) (err (str "recursive: " file " is a server entry; no job may start a bridge, tunnel or gateway server")))
      ((= f.kind "agent")
        (let [(task (textOf node ":task" ""))]
          (if (stringEmpty? task) (err ":task is empty")
            (ok (expandArgv cfg tmpl (list (pair "form" task)) (list))))))
      ((= f.kind "forms")
        (let [(text (stringTrim (textOf node ":text" "")))]
          (if (not (stringStartsWith? text "(:")) (err ":text must hold asl forms starting with (:")
            (ok (expandArgv cfg tmpl (list (pair "form" text)) (list))))))
      ((= f.kind "session")
        (let [(op (textOf node ":op" ""))
              (name (textOf node ":name" ""))]
          (cond
            ((not (listContains? (sessionOps) op)) (err ":op must be start, send, list, show, stop or fork"))
            ((and (not (stringEmpty? name)) (not (fm/safeToken? name))) (err ":name holds a character outside the allowlist"))
            (else (ok (expandArgv cfg tmpl (list (pair "op" op) (pair "props" (sessionProps node))) (list)))))))
      (else (ok (expandArgv cfg tmpl (list (pair "file" file)) (listOf node ":args"))))))

fn timeoutOf cfg: BridgeCfg node: fm/Node -> Int64
  (let [(t (intOf node ":timeout" cfg.defaultTimeoutS))]
    (cond ((< t 1) 1) ((> t cfg.maxTimeoutS) cfg.maxTimeoutS) (else t)))


fn dropLines lines: (List String) n: Int64 -> (List String)
  (if (or (<= n 0) (listEmpty? lines)) lines (dropLines (optionOr (listTail lines) (list)) (- n 1)))

fn takeLines lines: (List String) n: Int64 acc: (List String) -> (List String)
  (if (<= n 0) (listReverse acc)
    (match (listHead lines)
      ((none) (listReverse acc))
      ((some l) (takeLines (optionOr (listTail lines) (list)) (- n 1) (cons l acc)))))

; (:m :ref VPS-BRIDGE :do "read answers in process with a bounded slice of a root-relative file: :from is 1-based, :lines is capped by :readMaxLines, so a read never blocks the loop on a child; the real path must stay under the real root, so a symlink out of the root is refused")
fn ! readSlice! cfg: BridgeCfg node: fm/Node -> (Result String String)
  (let [(file (textOf node ":file" ""))
        (from (intOf node ":from" 1))
        (want (intOf node ":lines" cfg.readMaxLines))
        (n (if (or (< want 1) (> want cfg.readMaxLines)) cfg.readMaxLines want))]
    (if (not (fm/safePath? file))
      (err ":file must be a root-relative path without dot or dash segments")
      (let [(base (resultOr (realPath cfg.root) cfg.root))
            (full (resultOr (realPath (str cfg.root "/" file)) ""))]
        (if (not (stringStartsWith? full (str base "/")))
          (err (str "cannot read " file ": missing or outside the root"))
          (match (fileReadString full)
            ((err e) (err (str "cannot read " file)))
            ((ok text) (ok (stringJoin (takeLines (dropLines (stringLines text) (- from 1)) n (list)) "\n"))))))))


fn connWith s: Server cid: Int64 f: (fn [Conn] -> Conn) -> Server
  (with s :conns (map (fn [(c Conn)] -> Conn (if (= c.id cid) (f c) c)) s.conns))

fn connOf s: Server cid: Int64 -> (Option Conn)
  (listHead (filter (fn [(c Conn)] -> Bool (= c.id cid)) s.conns))

fn emit s: Server cid: Int64 text: String -> Server
  (connWith s cid (fn [(c Conn)] -> Conn (with c :outBuf (str c.outBuf text "\n"))))

; (:m :ref VPS-BRIDGE :do "a connection that sent anything but a well-formed frame is answered once and closed: the HTTP request line of a cross-protocol POST closes it before its body line is read, so a browser or a stray local process can never reach a job")
fn closeWith s: Server cid: Int64 frame: String -> Server
  (connWith (emit s cid frame) cid (fn [(c Conn)] -> Conn (with c :closing true :inBuf "")))

fn chunks text: String size: Int64 acc: (List String) -> (List String)
  (if (<= (stringLength text) size)
    (listReverse (if (stringEmpty? text) acc (cons text acc)))
    (chunks (optionOr (stringSlice text size (stringLength text)) "") size (cons (optionOr (stringSlice text 0 size) "") acc)))

; (:m :ref NET-SEQ-RESUME :do "every out frame of a job carries :seq N, counting from 1 across out and err; a keyed job keeps its sent frames in rbuf, bounded by :maxOutBuf bytes (oldest dropped), so a client that reattaches with :from N is sent exactly the frames with seq >= N; a :from older than the oldest kept frame is answered replayGap, never silently shortened")
fn seqText n: Int64 text: String -> String
  (let [(body (optionOr (stringSlice text 0 (- (stringLength text) 1)) text))]
    (str body " :seq " n ")"))

fn jobOf p: (Pair BridgeJob (List String)) -> BridgeJob
  (pairFirst p)

fn jobOutParts j: BridgeJob cfg: BridgeCfg stream: String text: String -> (Pair BridgeJob (List String))
  (fold (fn [(acc (Pair BridgeJob (List String))) (part String)] -> (Pair BridgeJob (List String))
          (let [(jj (jobOf acc))
                (n (+ jj.seq 1))
                (frm (seqText n (outFrame jj.id stream part)))]
            (pair (with jj :seq n :rbuf (if jj.keep (trimRbuf (listAppend jj.rbuf (list (pair n frm))) cfg.maxOutBuf) (list))) (listAppend (pairSecond acc) (list frm)))))
        (pair j (list)) (chunks text (if (> cfg.chunk 0) cfg.chunk 16384) (list)))

fn rbufBytes r: (List (Pair Int64 String)) -> Int64
  (fold (fn [(a Int64) (p (Pair Int64 String))] -> Int64 (+ a (stringLength (pairSecond p)))) 0 r)

fn trimRbuf r: (List (Pair Int64 String)) cap: Int64 -> (List (Pair Int64 String))
  (if (and (> (listLength r) 1) (> (rbufBytes r) cap)) (trimRbuf (optionOr (listTail r) (list)) cap) r)

fn emitOut s: Server cid: Int64 id: String stream: String text: String -> Server
  (fold (fn [(acc Server) (part String)] -> Server (emit acc cid (outFrame id stream part)))
        s (chunks text (if (> s.cfg.chunk 0) s.cfg.chunk 16384) (list)))

fn jobCount s: Server -> Int64
  (listLength s.jobs)

fn connCount s: Server -> Int64
  (listLength s.conns)

fn jobKey? j: BridgeJob cid: Int64 id: String -> Bool
  (and (= j.conn cid) (= j.id id))

fn newServer fd: Int64 port: Int64 path: String token: String cfg: BridgeCfg -> Server
  (Server :listenFd fd :port port :unixPath path :token token :cfg cfg :conns (list) :jobs (list) :nextConn 1)

; (:m :ref VPS-BRIDGE :do "tcp is opt-in and never anonymous: any local user can reach 127.0.0.1, so a tcp listener demands a token of at least 32 chars in every hello")
fn ! listenTcp! cfg: BridgeCfg port: Int64 token: String -> (Result Server String)
  (if (< (stringLength token) 32)
    (err "ERR_BRIDGE_TOKEN a tcp listener needs a token of at least 32 chars")
    (match (sock/openServerSocket (sock/makeSocketConfig "127.0.0.1" port true))
      ((err e) (err e))
      ((ok srv) (ok (newServer srv.fd srv.port "" token cfg)))))

fn socketMode? mode: Int64 -> Bool
  (= (mod (/ mode 4096) 16) 12)

; (:m :ref VPS-BRIDGE :do "a unix listener is chmod 0600 by asl-net before the first accept; a path that is a symlink is refused, and a socket some live server still answers on is addrInUse rather than unlinked from under it; only a dead socket is replaced")
fn ! listenUnix! cfg: BridgeCfg path: String -> (Result Server String)
  (let [(pre (match (fileLstat path)
               ((err _) (ok true))
               ((ok st) (cond
                          ((symlinkMode? st.mode) (err (str "ERR_BRIDGE_SYMLINK " path " is a symlink")))
                          ((and (socketMode? st.mode) (match (unx/connectUnixSocket path) ((ok fd) (do (fdClose fd) true)) ((err _) false)))
                            (err (str "ERR_BRIDGE_ADDR_IN_USE addrInUse: a live server answers on " path)))
                          (else (ok true))))))]
    (match pre
      ((err e) (err e))
      ((ok _)
        (match (unx/openUnixServerSocket (unx/makeUnixSocketConfig path true 384))
          ((err e) (err e))
          ((ok srv) (match (fdNonBlocking srv.fd true)
                      ((err e) (do (unx/closeUnixSocket srv) (err (str "ERR_BRIDGE_NONBLOCK: " e))))
                      ((ok _) (ok (newServer srv.fd 0 path "" cfg)))))))))

fn ! settle! g: fr/Guarded tries: Int64 -> Bool
  (let [(st (fr/guardAdvance! g))]
    (match st.out
      ((some _) true)
      ((none) (if (<= tries 0) false
                (do (fdPoll (fr/guardFds st.guard) 20) (settle! st.guard (- tries 1)))))))

; (:m :ref VPS-BRIDGE :do "a cancel, a paused job past its deadline or a dropped connection takes the job's whole tree with fr/stopGuard! (its recorded groups and pins, so a setsid escapee goes too), then steps the guard until its pipes close so the child is reaped and its lease removed")
fn ! stopJob! j: BridgeJob -> Bool
  (let [(_ (fr/stopGuard! j.guard))]
    (settle! j.guard 100))

fn ! spawnJob! s: Server cid: Int64 f: Frame jc: BridgeCfg argv: (List String) key: String keep: Bool inFile: String -> Server
  (let [(tS (timeoutOf s.cfg f.node))]
    (match (fr/guardStart! (capArgv jc argv) jc.root (fr/childEnv (list)) (fr/limits tS s.cfg.maxDesc))
      ((err po) (let [(_ (forget! s.cfg key inFile))] (emit s cid (errFrame f.id "spawnFailed" (stringTrim po.stderr)))))
      ((ok g) (with s :jobs (listAppend s.jobs (list (BridgeJob :conn cid :id f.id :kind f.kind :guard g :startNs (monotonicNs) :timeoutMs (* tS 1000)
                                                                :key key :keep keep :outAcc "" :errAcc "" :inFile inFile :seq 0 :rbuf (list))))))))

fn ! startJob! s: Server cid: Int64 f: Frame -> Server
  (cond
    ((listAny? (fn [(j BridgeJob)] -> Bool (jobKey? j cid f.id)) s.jobs) (emit s cid (errFrame f.id "dupId" "a job with this id is still running on this connection")))
    ((>= (listLength s.jobs) s.cfg.maxJobs) (emit s cid (errFrame f.id "busy" (str "the box runs " s.cfg.maxJobs " jobs at most"))))
    (else
      (match (match (cfgFor! s.cfg f.node) ((err e) (err e)) ((ok c) (resultMap (jobArgv c f) (fn [(a (List String))] -> (Pair BridgeCfg (List String)) (pair c a)))))
        ((err e) (emit s cid (errFrame f.id "badRequest" e)))
        ((ok ca) (spawnJob! s cid f (pairFirst ca) (pairSecond ca) "" false "")))))

fn sessionOf node: fm/Node -> String
  (let [(v (textOf node ":session" ""))] (if (and (fm/safeUnit? v) (<= (stringLength v) 64)) v ""))

; (:m :ref RELAY-IDEMPOTENT :do "an exec request is keyed by the session its hello named and its :id; the key's result is kept on disk under :stateDir/req, so the same key sent again (a retry after a dropped link, or after a bridge restart) replays the stored result instead of running twice, joins the run while it is still going, or, when an earlier bridge died mid-run, answers interrupted; a request on a connection with no session is not kept")
fn reqKey s: Server cid: Int64 id: String -> String
  (match (connOf s cid)
    ((some c) (if (stringEmpty? c.session) "" (str c.session "." id)))
    ((none) ""))

fn reqDir cfg: BridgeCfg -> String
  (str cfg.stateDir "/req")

fn resPath cfg: BridgeCfg key: String -> String
  (str (reqDir cfg) "/" key ".res")

fn runPath cfg: BridgeCfg key: String -> String
  (str (reqDir cfg) "/" key ".run")

fn ! ensureState! cfg: BridgeCfg -> Bool
  (do (dirCreate cfg.stateDir) (fileChmod cfg.stateDir 448) (dirCreate (reqDir cfg)) (fileChmod (reqDir cfg) 448) true)

fn ! forget! cfg: BridgeCfg key: String inFile: String -> Bool
  (do (if (stringEmpty? key) true (ok? (pathRemove (runPath cfg key))))
      (if (stringEmpty? inFile) true (ok? (pathRemove inFile))))

; (:m :ref RELAY-STORE-PRUNE :do "the result store is pruned by age: a .res, .run or in- stdin file under stateDir/req whose mtime is older than :keep seconds (default 7 days, 0 keeps all) is removed, except the files of a job this bridge still runs (its key or its stdin file), so a live run is never forgotten under it; serve prunes at start and then hourly")
fn storeKind? name: String -> Bool
  (or (stringEndsWith? name ".res") (stringEndsWith? name ".run") (or (stringStartsWith? name "in-") (stringStartsWith? name "stg-")))

fn protected? jobs: (List BridgeJob) dir: String name: String -> Bool
  (listAny? (fn [(j BridgeJob)] -> Bool
              (or (= (str dir "/" name) j.inFile)
                  (and (not (stringEmpty? j.key)) (or (= name (str j.key ".res")) (= name (str j.key ".run"))))))
            jobs)

fn ! pruneStore! cfg: BridgeCfg jobs: (List BridgeJob) nowNs: Int64 -> Int64
  (if (or (stringEmpty? cfg.stateDir) (<= cfg.keepS 0)) 0
    (let [(dir (reqDir cfg))
          (cut (- nowNs (* cfg.keepS 1000000000)))]
      (fold (fn [(n Int64) (name String)] -> Int64
              (if (or (not (storeKind? name)) (protected? jobs dir name)) n
                (match (fileStat (str dir "/" name))
                  ((err _) n)
                  ((ok st) (if (and (< st.mtimeNs cut) (ok? (pathRemove (str dir "/" name)))) (+ n 1) n)))))
            0 (resultOr (dirList dir) (list)))))

fn ! writeStdin! cfg: BridgeCfg b64: String -> String
  (match (bytesFromBase64 (stringTrim b64))
    ((err _) "!")
    ((ok bytes)
      (let [(_ (ensureState! cfg))
            (path (str (reqDir cfg) "/in-" (procSelf) "-" (nowNs)))]
        (if (ok? (fileWrite path bytes)) (do (fileChmod path 384) path) "!"))))

fn stdinArgv path: String argv: (List String) -> (List String)
  (listAppend (list "/bin/sh" "-c" "f=$1; shift; exec \"$@\" < \"$f\"" "relayIn" path) argv)

; (:m :ref RELAY-EXEC :do "an exec may not start a bridge, tunnel or gateway server (that would nest relays and outlive its job), but it may name their files: argv elements and the words inside a sh -c line are read in order, and a server entry is refused only in command position, first or after a launcher, a flag, a number or a shell separator; an edit form or a cat that mentions tools/remote/bridge.asl runs. This is an accident guard, not a sandbox: exec is already a shell")
fn bareWord w: String -> String
  (fold (fn [(acc String) (ch String)] -> String (stringReplace acc ch "")) w (list "\"" "'" "(" ")" "{" "}" "`"))

fn execWords argv: (List String) -> (List String)
  (filter (fn [(w String)] -> Bool (not (stringEmpty? w)))
          (map bareWord
               (fold (fn [(acc (List String)) (a String)] -> (List String)
                       (listAppend acc (stringSplit (stringReplace (stringReplace a "\n" " ") "\t" " ") " ")))
                     (list) argv)))

fn serverWord? w: String -> Bool
  (listAny? (fn [(e String)] -> Bool (and (!= e "bin/asl") (or (= w e) (stringEndsWith? w (str "/" e))))) (serverEntries))

fn launcherWords -> (List String)
  (stringSplit "run exec nohup setsid nice env sh bash dash perl timeout then do else ; && || | &" " ")

fn launcher? w: String -> Bool
  (or (stringEmpty? w)
      (listContains? (launcherWords) w)
      (stringStartsWith? w "-")
      (stringEndsWith? w ";") (stringEndsWith? w "&") (stringEndsWith? w "|")
      (some? (stringToInt64 w)))

fn recursive? argv: (List String) -> Bool
  (pairSecond (fold (fn [(acc (Pair String Bool)) (w String)] -> (Pair String Bool)
                      (pair w (or (pairSecond acc) (and (serverWord? w) (launcher? (pairFirst acc))))))
                    (pair "" false) (execWords argv)))

fn ! replay! s: Server cid: Int64 id: String key: String -> Server
  (match (fm/parseForm (resultOr (fileReadString (resPath s.cfg key)) ""))
    ((err _) (emit s cid (errFrame id "badState" "the stored result does not parse")))
    ((ok node)
      (let [(s0 (emit s cid (frameText id "out" " :stream out :text \"\" :reset true")))
            (s1 (emitOut s0 cid id "out" (textOf node ":out" "")))
            (s2 (emitOut s1 cid id "err" (textOf node ":err" "")))]
        (emit s2 cid (frameText id "done" (str " :exit " (intOf node ":exit" -1) " :verdict " (textOf node ":verdict" "exit") " :replayed true"))))))

fn ! reattach! s: Server cid: Int64 id: String key: String from: Int64 -> Server
  (match (listHead (filter (fn [(j BridgeJob)] -> Bool (= j.key key)) s.jobs))
    ((none) s)
    ((some j)
      (let [(s1 (with s :jobs (map (fn [(x BridgeJob)] -> BridgeJob (if (= x.key key) (with x :conn cid :id id) x)) s.jobs)))
            (oldest (match (listHead j.rbuf) ((some p) (pairFirst p)) ((none) (+ j.seq 1))))]
        (if (and (<= from j.seq) (> oldest from))
          (emit s1 cid (errFrame id "replayGap" (str "frames " from ".." (- oldest 1) " are no longer kept; the replay buffer starts at " oldest)))
          (fold (fn [(acc Server) (p (Pair Int64 String))] -> Server (if (>= (pairFirst p) from) (emit acc cid (pairSecond p)) acc))
                s1 j.rbuf)))))

; (:m :ref RELAY-LARGE-FRAME :do "a (:stage :id C :for ID :n N :data B64) frame stores one bounded piece of a request's stdin under stateDir/req as stg-SESSION.ID.N and is answered with its own done frame, so the sender can see every piece land; storing the same piece again overwrites it; the exec frame that follows names :stdinParts and the pieces are joined into the one stdin file when the job starts; pieces need a hello session, because a piece without an owner could be joined into someone else's request")
fn stgPath cfg: BridgeCfg session: String for: String n: Int64 -> String
  (str (reqDir cfg) "/stg-" session "." for "." n)

fn ! stageReq! s: Server cid: Int64 f: Frame data: String -> Server
  (let [(session (match (connOf s cid) ((some c) c.session) ((none) "")))
        (for (textOf f.node ":for" ""))
        (n (intOf f.node ":n" -1))]
    (cond
      ((not s.cfg.exec) (emit s cid (errFrame f.id "execOff" "this bridge runs no exec frames; its config needs :exec true")))
      ((stringEmpty? session) (emit s cid (errFrame f.id "noSession" "a stage frame needs the session named in hello")))
      ((not (idOk? for)) (emit s cid (errFrame f.id "badRequest" ":for is missing or unsafe")))
      ((or (< n 0) (> n 9999)) (emit s cid (errFrame f.id "badRequest" ":n must be within 0..9999")))
      (else
        (match (bytesFromBase64 (stringTrim data))
          ((err _) (emit s cid (errFrame f.id "badRequest" ":data is not base64")))
          ((ok bytes)
            (let [(_ (ensureState! s.cfg))
                  (path (stgPath s.cfg session for n))]
              (if (ok? (fileWrite path bytes))
                (do (fileChmod path 384) (emit s cid (doneFrame f.id 0 "staged")))
                (emit s cid (errFrame f.id "stageFailed" "the piece could not be written")))))))))

fn indexes i: Int64 n: Int64 -> (List Int64)
  (if (>= i n) (list) (cons i (indexes (+ i 1) n)))

; (:m :ref RELAY-LARGE-FRAME :do "joins the pieces 0..N-1 of a request into one stdin file and removes them; a missing piece gives !, which the exec answers as an incomplete stdin, never a run on partial input")
fn ! joinParts! s: Server cid: Int64 id: String parts: Int64 -> String
  (let [(session (match (connOf s cid) ((some c) c.session) ((none) "")))
        (paths (map (fn [(i Int64)] -> String (stgPath s.cfg session id i)) (indexes 0 parts)))
        (out (str (reqDir s.cfg) "/in-" (procSelf) "-" (nowNs)))]
    (cond
      ((stringEmpty? session) "!")
      ((not (listAll? fileExists? paths)) "!")
      (else
        (let [(_ (ok? (fileWrite out (bytesAlloc 0))))
              (done (fold (fn [(acc Bool) (p String)] -> Bool
                            (and acc (match (fileReadBytes p) ((err _) false) ((ok b) (ok? (fileAppend out b))))))
                          true paths))
              (_ (map pathRemove paths))]
          (if done (do (fileChmod out 384) out) "!")))))

fn ! execReq! s: Server cid: Int64 f: Frame -> Server
  (let [(key (reqKey s cid f.id))
        (keyed (not (stringEmpty? key)))
        (argv (listOf f.node ":argv"))]
    (cond
      ((not s.cfg.exec) (emit s cid (errFrame f.id "execOff" "this bridge runs no exec frames; its config needs :exec true")))
      ((and keyed (fileExists? (resPath s.cfg key))) (replay! s cid f.id key))
      ((and keyed (listAny? (fn [(j BridgeJob)] -> Bool (= j.key key)) s.jobs)) (reattach! s cid f.id key (intOf f.node ":from" 1)))
      ((and keyed (fileExists? (runPath s.cfg key))) (emit s cid (errFrame f.id "interrupted" "an earlier bridge started this request and stopped before it finished; whether it completed is unknown")))
      ((listAny? (fn [(j BridgeJob)] -> Bool (jobKey? j cid f.id)) s.jobs) (emit s cid (errFrame f.id "dupId" "a job with this id is still running on this connection")))
      ((>= (listLength s.jobs) s.cfg.maxJobs) (emit s cid (errFrame f.id "busy" (str "the box runs " s.cfg.maxJobs " jobs at most"))))
      ((listEmpty? argv) (emit s cid (errFrame f.id "badRequest" ":argv is empty")))
      ((recursive? argv) (emit s cid (errFrame f.id "badRequest" "recursive: no exec may start a bridge, tunnel or gateway server")))
      (else
        (match (cfgFor! s.cfg f.node)
          ((err e) (emit s cid (errFrame f.id "badRequest" e)))
          ((ok jc)
            (let [(stdin (textOf f.node ":stdin" ""))
                  (parts (intOf f.node ":stdinParts" 0))
                  (inFile (cond ((> parts 0) (joinParts! s cid f.id parts)) ((stringEmpty? stdin) "") (else (writeStdin! s.cfg stdin))))]
              (if (= inFile "!")
                (emit s cid (errFrame f.id "badRequest" ":stdin is not base64, or a :stdinParts piece is missing"))
                (let [(_ (if keyed (do (ensureState! s.cfg) (ok? (fileWrite (runPath s.cfg key) (str "(:run :pid " (procSelf) " :startNs " (nowNs) ")\n")))) false))]
                  (spawnJob! s cid f jc (if (stringEmpty? inFile) argv (stdinArgv inFile argv)) key true inFile)))))))))

fn ! cancel! s: Server cid: Int64 f: Frame -> Server
  (let [(target (textOf f.node ":target" ""))]
    (match (listHead (filter (fn [(j BridgeJob)] -> Bool (jobKey? j cid target)) s.jobs))
      ((none) (emit s cid (errFrame f.id "noSuchJob" (str "no running job " (fm/quoteText target) " on this connection"))))
      ((some j)
        (let [(_ (stopJob! j))
              (s1 (with s :jobs (filter (fn [(x BridgeJob)] -> Bool (not (jobKey? x cid target))) s.jobs)))]
          (emit (emit s1 cid (doneFrame target 130 "cancelled")) cid (doneFrame f.id 0 "exit"))))))

fn sliceFrom text: String n: Int64 -> String
  (optionOr (stringSlice text n (stringLength text)) "")

fn outBufOf s: Server cid: Int64 -> Int64
  (match (connOf s cid) ((some c) (stringLength c.outBuf)) ((none) 0))

fn paused? s: Server j: BridgeJob -> Bool
  (> (outBufOf s j.conn) s.cfg.maxOutBuf)

fn withoutJob s: Server j: BridgeJob -> Server
  (with s :jobs (filter (fn [(x BridgeJob)] -> Bool (not (jobKey? x j.conn j.id))) s.jobs))

fn drain g: fr/Guarded -> fr/Guarded
  (let [(r g.run)]
    (fr/Guarded :run (fr/RunningSep :pid r.pid :outFd r.outFd :errFd r.errFd :outText "" :errText "" :outOpen r.outOpen :errOpen r.errOpen
                                      :startNs r.startNs :killed r.killed :groups r.groups :known r.known)
                 :lim g.lim :lastCheck g.lastCheck))

; (:m :ref VPS-BRIDGE :do "memory stays bounded and streaming linear: each step forwards only what the guard pumped since the last step and then empties the guard's text, and a job whose reader lets its connection buffer pass :maxOutBuf is not pumped at all, so its pipe fills and the child blocks; its deadline still holds while paused")
fn ! advanceJob! s: Server j: BridgeJob -> Server
  (if (paused? s j)
    (if (> (/ (- (monotonicNs) j.startNs) 1000000) j.timeoutMs)
      (let [(_ (stopJob! j))] (emit (withoutJob s j) j.conn (doneFrame j.id 124 "timeout")))
      s)
    (let [(st (fr/guardAdvance! j.guard))
          (r st.guard.run)
          (jo (jobOutParts j s.cfg "out" r.outText))
          (je (jobOutParts (jobOf jo) s.cfg "err" r.errText))
          (jn (jobOf je))
          (s2 (fold (fn [(acc Server) (frm String)] -> Server (emit acc j.conn frm)) s (listAppend (pairSecond jo) (pairSecond je))))
          (others (withoutJob s2 j))
          (drained (drain st.guard))
          (j2 (if j.keep (with jn :outAcc (capAcc (str j.outAcc r.outText) s.cfg.maxOutBuf) :errAcc (capAcc (str j.errAcc r.errText) s.cfg.maxOutBuf)) jn))]
      (match st.out
        ((some o) (let [(verdict (if (stringEmpty? r.killed) "exit" r.killed))
                        (_ (store! s.cfg j2 o.exitCode verdict))]
                    (emit others j.conn (doneFrame j.id o.exitCode verdict))))
        ((none) (with others :jobs (listAppend others.jobs (list (with j2 :guard drained))))))))

fn capAcc text: String cap: Int64 -> String
  (if (> (stringLength text) cap) (optionOr (stringSlice text 0 cap) text) text)

fn ! store! cfg: BridgeCfg j: BridgeJob exit: Int64 verdict: String -> Bool
  (do (if (stringEmpty? j.key) true
        (ok? (fileWrite (resPath cfg j.key) (str "(:res :exit " exit " :verdict " verdict " :out " (fm/quoteText j.outAcc) " :err " (fm/quoteText j.errAcc) ")\n"))))
      (forget! cfg j.key j.inFile))

fn ! advanceJobs! s: Server -> Server
  (fold advanceJob! s s.jobs)

fn helloFrame id: String token: String -> String
  (if (stringEmpty? token)
    (str "(:hello :id " (fm/quoteText id) " :v 1)")
    (str "(:hello :id " (fm/quoteText id) " :v 1 :token " (fm/quoteText token) ")"))

; (:m :ref VPS-BRIDGE :do "until a connection says (:hello :v 1), with the server token when it listens on tcp, every other frame closes it; a second hello is an err")
fn ! greet! s: Server cid: Int64 f: Frame -> Server
  (cond
    ((!= f.kind "hello") (closeWith s cid (errFrame f.id "needHello" "the first frame must be (:hello :id I :v 1)")))
    ((!= (intOf f.node ":v" 0) 1) (closeWith s cid (errFrame f.id "badVersion" "this bridge speaks :v 1")))
    ((and (not (stringEmpty? s.token)) (!= (textOf f.node ":token" "") s.token)) (closeWith s cid (errFrame f.id "badToken" "the token does not match")))
    (else (emit (connWith s cid (fn [(c Conn)] -> Conn (with c :ready true :session (sessionOf f.node)))) cid (frameText f.id "ready" " :v 1"))))

fn ! dispatch! s: Server cid: Int64 f: Frame -> Server
  (cond
    ((= f.kind "hello") (emit s cid (errFrame f.id "dupHello" "this connection already said hello")))
    ((= f.kind "ping") (emit s cid (frameText f.id "pong" "")))
    ((= f.kind "read")
      (match (match (cfgFor! s.cfg f.node) ((err e) (err e)) ((ok c) (readSlice! c f.node)))
        ((err e) (emit s cid (errFrame f.id "badRequest" e)))
        ((ok text) (emit (emitOut s cid f.id "out" text) cid (doneFrame f.id 0 "exit")))))
    ((= f.kind "cancel") (cancel! s cid f))
    ((= f.kind "exec") (execReq! s cid f))
    ((= f.kind "stage") (stageReq! s cid f ""))
    (else (startJob! s cid f)))

; (:m :ref RELAY-LARGE-FRAME :do "a stage line is (:stage :id C :for ID :n N) then one space then the raw base64: only the short header goes through the form parser, which is super-linear in line length (a 48 KiB piece cost 0.7 s to parse, the data decode 13 ms), the data is never quoted or parsed; the header holds only safe ids, so its first close paren ends it")
fn ! stageLine! s: Server cid: Int64 t: String -> Server
  (match (stringIndexOf t ")")
    ((none) (closeWith s cid (errFrame "?" "badFrame" "a stage header must close")))
    ((some i)
      (match (parseFrame (optionOr (stringSlice t 0 (+ i 1)) ""))
        ((err e) (closeWith s cid (errFrame "?" "badFrame" e)))
        ((ok f) (match (connOf s cid)
                  ((none) s)
                  ((some c) (if c.ready (stageReq! s cid f (optionOr (stringSlice t (+ i 1) (stringLength t)) "")) (greet! s cid f))))))))

fn ! handle! s: Server cid: Int64 line: String -> Server
  (let [(t (stringTrim line))]
    (cond
      ((stringEmpty? t) s)
      ((not (stringStartsWith? t "(:")) (closeWith s cid (errFrame "?" "badFrame" "a frame starts with (:")))
      ((stringStartsWith? t "(:stage ") (stageLine! s cid t))
      (else
        (match (parseFrame t)
          ((err e) (closeWith s cid (errFrame "?" "badFrame" e)))
          ((ok f) (match (connOf s cid)
                    ((none) s)
                    ((some c) (if c.ready (dispatch! s cid f) (greet! s cid f)))))))))

fn splitLine buf: String -> (Option (Pair String String))
  (match (stringIndexOf buf "\n")
    ((none) (none))
    ((some i) (some (pair (optionOr (stringSlice buf 0 i) "") (sliceFrom buf (+ i 1))))))

fn oversize cfg: BridgeCfg -> String
  (errFrame "?" "badFrame" (str "line exceeds " cfg.maxLine " bytes"))

fn ! drainLines! s: Server cid: Int64 -> Server
  (match (connOf s cid)
    ((none) s)
    ((some c)
      (if c.closing s
        (match (splitLine c.inBuf)
          ((some p)
            (let [(s1 (connWith s cid (fn [(x Conn)] -> Conn (with x :inBuf (pairSecond p) :discard false))))]
              (drainLines! (cond (c.discard s1)
                                 ((> (stringLength (pairFirst p)) s.cfg.maxLine) (closeWith s1 cid (oversize s.cfg)))
                                 (else (handle! s1 cid (pairFirst p))))
                           cid)))
          ((none)
            (if (and (> (stringLength c.inBuf) s.cfg.maxLine) (not c.discard))
              (closeWith s cid (oversize s.cfg))
              s))))))

fn busyFrame -> String
  (str (errFrame "?" "busy" "too many connections") "\n")

; (:m :ref VPS-BRIDGE :do "at most :maxConns connections at once: one more is told busy and closed at accept, so a flood of idle sockets cannot exhaust descriptors")
fn ! acceptAll! s: Server n: Int64 -> Server
  (if (<= n 0) s
    (match (sock/acceptSocketConnection s.listenFd)
      ((err _) s)
      ((ok fd)
        (if (>= (listLength s.conns) s.cfg.maxConns)
          (let [(_ (fdWrite fd (busyFrame))) (_ (fdClose fd))] (acceptAll! s (- n 1)))
          (let [(_ (fdNonBlocking fd true))]
            (acceptAll! (with s :conns (listAppend s.conns (list (Conn :id s.nextConn :fd fd :inBuf "" :outBuf "" :open true :discard false
                                                                       :ready false :closing false :lastNs (monotonicNs) :session "")))
                                :nextConn (+ s.nextConn 1))
                        (- n 1)))))))

fn ! readConn! s: Server c: Conn -> Server
  (if (or (not c.open) c.closing) s
    (match (fdRead c.fd 65536)
      ((err _) s)
      ((ok chunk)
        (if (stringEmpty? chunk)
          (connWith s c.id (fn [(x Conn)] -> Conn (with x :open false)))
          (drainLines! (connWith s c.id (fn [(x Conn)] -> Conn (with x :inBuf (str x.inBuf chunk) :lastNs (monotonicNs)))) c.id)))))

fn ! readAll! s: Server -> Server
  (fold readConn! s s.conns)

fn ! flushConn! c: Conn -> Conn
  (if (or (stringEmpty? c.outBuf) (not c.open)) c
    (match (fdWrite c.fd c.outBuf)
      ((err _) c)
      ((ok n) (with c :outBuf (sliceFrom c.outBuf n)))))

fn ! idle? s: Server now: Int64 c: Conn -> Bool
  (and (> s.cfg.idleS 0)
       (and (not (listAny? (fn [(j BridgeJob)] -> Bool (= j.conn c.id)) s.jobs))
            (> (- now c.lastNs) (* s.cfg.idleS 1000000000))))

fn ! connGone? s: Server now: Int64 c: Conn -> Bool
  (or (not c.open) (or c.closing (idle? s now c)))

; (:m :ref VPS-BRIDGE :do "dropped here: a connection the peer closed, one marked closing after its last frame was flushed, and one idle past :idle seconds with no job; their jobs are killed through stopJob!; SIGPIPE is ignored by the runtime, so a write to a gone peer is an error value, never a crash")
fn ! reap! s: Server -> Server
  (let [(now (monotonicNs))
        (goneIds (map (fn [(c Conn)] -> Int64 c.id) (filter (fn [(c Conn)] -> Bool (connGone? s now c)) s.conns)))
        (dead (filter (fn [(j BridgeJob)] -> Bool (and (listContains? goneIds j.conn) (not j.keep))) s.jobs))
        (_ (map stopJob! dead))
        (_ (map (fn [(c Conn)] -> Bool (ok? (fdClose c.fd))) (filter (fn [(c Conn)] -> Bool (listContains? goneIds c.id)) s.conns)))]
    (with s :conns (filter (fn [(c Conn)] -> Bool (not (listContains? goneIds c.id))) s.conns)
            :jobs (map (fn [(j BridgeJob)] -> BridgeJob (if (listContains? goneIds j.conn) (with j :conn -1) j))
                       (filter (fn [(j BridgeJob)] -> Bool (or j.keep (not (listContains? goneIds j.conn)))) s.jobs))))

fn connPoll c: Conn -> (Pair Int64 Int64)
  (pair c.fd (if (stringEmpty? c.outBuf) 1 3))

; (:m :ref VPS-BRIDGE :do "what one step waits on: the listener, each open connection for input (and for output while it has bytes queued) and the pipes of jobs that are not paused, so a paused job or a slow reader never turns the loop into a spin")
fn pollFds s: Server -> (List (Pair Int64 Int64))
  (listAppend (cons (pair s.listenFd 1) (map connPoll (filter (fn [(c Conn)] -> Bool c.open) s.conns)))
              (fold (fn [(acc (List (Pair Int64 Int64))) (j BridgeJob)] -> (List (Pair Int64 Int64))
                      (if (paused? s j) acc (listAppend acc (fr/guardFds j.guard))))
                    (list) s.jobs))

; (:m :ref VPS-BRIDGE :do "one non-blocking turn of the loop: wait at most waitMs, accept, read and answer whole lines, step every job (streaming new output), flush, then drop closed connections; a single thread serves every client because no step blocks on a child")
fn ! step! s: Server waitMs: Int64 -> Server
  (let [(_ (fdPoll (pollFds s) waitMs))
        (s1 (acceptAll! s 16))
        (s2 (readAll! s1))
        (s3 (advanceJobs! s2))
        (s4 (with s3 :conns (map flushConn! s3.conns)))]
    (reap! s4))

fn ! serverClose! s: Server -> Bool
  (let [(_ (map stopJob! s.jobs))
        (_ (map (fn [(c Conn)] -> Bool (ok? (fdClose c.fd))) s.conns))
        (_ (fdClose s.listenFd))]
    (if (stringEmpty? s.unixPath) true (ok? (pathRemove s.unixPath))))

fn ! serveLoop! s: Server untilNs: Int64 pruneAt: Int64 -> Server
  (cond
    ((and (> untilNs 0) (> (monotonicNs) untilNs)) s)
    ((>= (monotonicNs) pruneAt) (do (pruneStore! s.cfg s.jobs (nowNs)) (serveLoop! (step! s 100) untilNs (+ (monotonicNs) 3600000000000))))
    (else (serveLoop! (step! s 100) untilNs pruneAt)))

fn ! serve! s: Server untilNs: Int64 -> Server
  (serveLoop! s untilNs 0)

fn ! clientTcp! port: Int64 -> (Result Int64 String)
  (match (sock/connectSocket port)
    ((err e) (err e))
    ((ok fd) (match (fdNonBlocking fd true) ((err e) (do (fdClose fd) (err e))) ((ok _) (ok fd)))))

fn ! clientUnix! path: String -> (Result Int64 String)
  (match (unx/connectUnixSocket path)
    ((err e) (err e))
    ((ok fd) (match (fdNonBlocking fd true) ((err e) (do (fdClose fd) (err e))) ((ok _) (ok fd)))))

fn ! writeAll! fd: Int64 text: String tries: Int64 -> (Result Int64 String)
  (if (stringEmpty? text) (ok 0)
    (match (fdWrite fd text)
      ((ok n) (writeAll! fd (sliceFrom text n) tries))
      ((err e) (if (<= tries 0) (err e) (do (fdPoll (list (pair fd 2)) 50) (writeAll! fd text (- tries 1)))))))

fn ! clientSend! fd: Int64 frame: String -> (Result Int64 String)
  (writeAll! fd (str frame "\n") 200)

fn ! clientHello! fd: Int64 token: String -> (Result Int64 String)
  (clientSend! fd (helloFrame "hello" token))

fn splitAll buf: String acc: (List String) -> Reply
  (match (splitLine buf)
    ((none) (Reply :frames (listReverse acc) :buf buf :closed false))
    ((some p) (splitAll (pairSecond p) (if (stringEmpty? (stringTrim (pairFirst p))) acc (cons (pairFirst p) acc)))))

; (:m :ref VPS-BRIDGE :do "a non-blocking client read: whatever whole frames arrived since the last call, the partial tail kept for the next one; closed is true at end of stream")
fn ! clientPoll! fd: Int64 buf: String -> Reply
  (match (fdRead fd 65536)
    ((err _) (splitAll buf (list)))
    ((ok chunk) (if (stringEmpty? chunk)
                  (with (splitAll buf (list)) :closed true)
                  (splitAll (str buf chunk) (list)))))

fn terminal? frame: String id: String -> Bool
  (match (fm/parseForm frame)
    ((err _) false)
    ((ok node) (let [(k (frameKind node))]
                 (and (or (= k "done") (or (= k "err") (or (= k "pong") (= k "ready")))) (= (frameId node) id)))))

fn replyOf frame: String key: String -> String
  (match (fm/parseForm frame)
    ((err _) "")
    ((ok node) (textOf node key "")))

fn ! callLoop! fd: Int64 id: String buf: String untilNs: Int64 seen: (List String) -> (Result (List String) String)
  (if (> (monotonicNs) untilNs) (err (str "ERR_BRIDGE_TIMEOUT no terminal frame for " id))
    (let [(_ (fdPoll (list (pair fd 1)) 100))
          (r (clientPoll! fd buf))
          (_ (map (fn [(f String)] -> Bool (do (println f) true)) r.frames))
          (all (listAppend seen r.frames))]
      (cond
        ((listAny? (fn [(f String)] -> Bool (or (terminal? f id) (terminal? f "?"))) r.frames) (ok all))
        (r.closed (err "ERR_BRIDGE_CLOSED the server closed the connection"))
        (else (callLoop! fd id r.buf untilNs all)))))

; (:m :ref VPS-BRIDGE :do "the local half: say hello, send one frame, print every reply frame as it streams in, stop at the terminal frame for its id or at the deadline")
fn ! call! fd: Int64 token: String frame: String timeoutS: Int64 -> (Result (List String) String)
  (match (fm/parseForm frame)
    ((err e) (err (str "ERR_BRIDGE_FRAME " e)))
    ((ok node)
      (match (clientSend! fd (str (helloFrame "hello" token) "\n" frame))
        ((err e) (err (str "ERR_BRIDGE_SEND " e)))
        ((ok _) (callLoop! fd (frameId node) "" (+ (monotonicNs) (* timeoutS 1000000000)) (list))))))

fn flagValue args: (List String) flag: String -> (Option String)
  (match (listHead args)
    ((none) (none))
    ((some a)
      (let [(rest (optionOr (listTail args) (list)))]
        (if (= a flag) (listHead rest) (flagValue rest flag)))))

fn tcp? args: (List String) -> Bool
  (listContains? args "--tcp")

fn ! connectFrom! args: (List String) -> (Result (Pair Int64 String) String)
  (if (tcp? args)
    (match (stringToInt64 (optionOr (flagValue args "--port") ""))
      ((none) (err "ERR_BRIDGE_USAGE --tcp needs --port N"))
      ((some port) (match (loadToken! (optionOr (flagValue args "--token") (tokenPath)))
                     ((err e) (err e))
                     ((ok tok) (match (clientTcp! port) ((err e) (err e)) ((ok fd) (ok (pair fd tok))))))))
    (match (clientUnix! (optionOr (flagValue args "--unix") (socketPath)))
      ((err e) (err e))
      ((ok fd) (ok (pair fd "")))))

fn ! ensureRunDir! path: String -> Bool
  (let [(parts (stringSplit path "/"))
        (dir (stringJoin (listTake parts (- (listLength parts) 1)) "/"))]
    (if (or (stringEmpty? dir) (fileExists? dir)) true
      (and (ok? (dirCreate dir)) (ok? (fileChmod dir 448)))))

fn ! listenFrom! cfg: BridgeCfg args: (List String) -> (Result Server String)
  (if (tcp? args)
    (match (makeToken! (optionOr (flagValue args "--token") (tokenPath)))
      ((err e) (err e))
      ((ok tok) (listenTcp! cfg (optionOr (stringToInt64 (optionOr (flagValue args "--port") "0")) 0) tok)))
    (let [(path (optionOr (flagValue args "--unix") (socketPath)))
          (_ (ensureRunDir! path))]
      (listenUnix! cfg path)))

fn usage -> String
  "(:err :code usage :msg \"bridge serve [--unix PATH | --tcp --port N [--token F]] [--config F] [--root R] [--for S] | bridge call [--unix PATH | --tcp --port N [--token F]] [--timeout S] FRAME\")"

; (:m :ref VPS-BRIDGE :do "serve listens on ~/.asl/run/bridge.sock unless told otherwise, prints one (:bridge :listening ...) line, then loops; --tcp makes or reads the 0600 token file and binds 127.0.0.1; --for S bounds the run (0 is until killed); call exits 0 only on (:done ... :exit 0) or (:pong ...)")
fn ! main args: (List String) -> (Result Int64 String)
  (let [(cmd (optionOr (listHead args) ""))
        (rest (optionOr (listTail args) (list)))
        (root (optionOr (flagValue rest "--root") (resultOr (realPath ".") ".")))]
    (cond
      ((= cmd "serve")
        (match (loadCfg! (optionOr (flagValue rest "--config") (cfgPath)) root)
          ((err e) (do (println (errFrame "serve" "badConfig" e)) (ok 1)))
          ((ok cfg)
            (match (listenFrom! cfg rest)
              ((err e) (do (println (errFrame "serve" "listen" e)) (ok 1)))
              ((ok s)
                (let [(forS (optionOr (stringToInt64 (optionOr (flagValue rest "--for") "0")) 0))
                      (_ (println (str "(:bridge :listening :port " s.port " :unix " (fm/quoteText s.unixPath) ")")))
                      (end (serve! s (if (> forS 0) (+ (monotonicNs) (* forS 1000000000)) 0)))]
                  (do (serverClose! end) (ok 0))))))))
      ((= cmd "call")
        (match (connectFrom! rest)
          ((err e) (do (println (errFrame "call" "connect" e)) (ok 1)))
          ((ok conn)
            (let [(fd (pairFirst conn))
                  (frame (optionOr (listLast rest) ""))
                  (res (call! fd (pairSecond conn) frame (optionOr (stringToInt64 (optionOr (flagValue rest "--timeout") "600")) 600)))
                  (_ (fdClose fd))]
              (match res
                ((err e) (do (println (errFrame "call" "failed" e)) (ok 1)))
                ((ok frames)
                  (let [(last (optionOr (listLast frames) ""))]
                    (ok (if (or (stringStartsWith? last "(:pong") (and (stringStartsWith? last "(:done") (= (replyOf last ":exit") "0"))) 0 1)))))))))
      (else (do (println (usage)) (ok 2)))))
