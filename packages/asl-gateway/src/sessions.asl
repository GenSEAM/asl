(module aslGateway/sessions
  :x [SessVendor
      SessCtx
      SessRow
      sessNameOk?
      sessCwdOk?
      sessCtxFromText
      sessCtxHome!
      sessCtxAt!
      sessKeyValues
      sessReplyOf
      sessSubst
      sessArgv
      sessVendorEnv
      sessRowPath
      sessRowFiles!
      sessStart!
      sessSend!
      sessList!
      sessShow!
      sessStop!
      sessionsCli!
      sessKeyName
      sessFork!
      SessTurn
      sessTurn!
      sessLock!
      sessUnlock!
      sessReadRow!
      sessWriteRow!
      sessWriteFile!
      sessVendorNamed
      sessQuote
      sessErr
      sessReplyPath
      sessRowText
      sessFirst
      sessPropStr
      sessPropList
      sessPropInt
      sessReceipt
      sessAlivePid?
      sessLockPath
      sessClip
      sessUsageText
      sessParseRows
      sessLockOwner!
      sessUserNameOk?
      sessLockTake!
      sessLockHeld?
      sessLeasePath
      sessLeaseWrite!
      sessStopChild!
      SessRun
      sessBegin!
      sessAdvance!
      sessRunFds
      sessWait!
      sessTurnOf]
  :i [(asl-tools/fleet/run :a fr)
      (config :a cfg)
      (asl-parser/ast :a ast)
      (asl-parser/lexer :a lx)
      (asl-parser/reader :a rd)
      (asl-cli/system :a sys)])

; (:m :ref GW-SESSIONS-2 :do "a gateway session is a named handle onto a vendor CLI's own conversation id: every turn runs the vendor headless through fleet/run runGuarded (timeout, descendant limit, allowlisted env) and continues the same context with the vendor's resume flag; no pty, no tmux; flags, id and reply keys come from the (:gateway :sessions ...) row of gateway.asn")
(schema SessVendor
  (:f name String) (:f bin String) (:f env (List String)) (:f first (List String)) (:f resume (List String))
  (:f idFrom String) (:f replyFrom String) (:f wrap String) (:f wrapResume String) (:f sep String) (:f modelArgs (List String)) (:f fork (List String)))
(schema SessTurn (:f id String) (:f reply String) (:f usage String) (:f inTok Int64) (:f outTok Int64))
(schema SessRun (:f g fr/Guarded) (:f idFrom String) (:f replyFrom String) (:f prevId String))
(schema SessCtx (:f dir String) (:f vendors (List SessVendor)) (:f env (List String)) (:f timeoutSec Int64) (:f ttlSec Int64) (:f ledger String))
(schema SessRow
  (:f name String) (:f vendor String) (:f cwd String) (:f args (List String)) (:f sessionId String)
  (:f startedAt Int64) (:f updatedAt Int64) (:f turns Int64)
  (:f key String) (:f model String) (:f digest String) (:f delivered Int64) (:f usageIn Int64) (:f usageOut Int64) (:f fork Bool)
  (:f kind String) (:f ctxDigest String))

fn sessQuote s: String -> String
  (str "\"" (stringReplace (stringReplace (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\n" "\\n") "\r" "\\r") "\"")

fn sessErr code: String msg: String -> String
  (str "(:err :code " code " :msg " (sessQuote msg) ")")

fn sessErrIs? receipt: String -> Bool
  (stringStartsWith? receipt "(:err ")

fn sessNameChar? c: String -> Bool
  (or (and (>= c "a") (<= c "z")) (or (and (>= c "A") (<= c "Z")) (or (and (>= c "0") (<= c "9")) (= c "-"))))

fn sessNameOk? n: String -> Bool
  (and (not (stringEmpty? n))
       (and (<= (stringLength n) 64)
            (fold (fn [(acc Bool) (c String)] -> Bool (and acc (sessNameChar? c))) true (stringChars n))))

; (:m :do "a named session never starts with b-: that prefix is the binding namespace, so a caller key can neither reach nor shadow a named session")
fn sessUserNameOk? n: String -> Bool
  (and (sessNameOk? n) (not (stringStartsWith? n "b-")))

fn sessCwdOk? cwd: String -> Bool
  (and (stringStartsWith? cwd "/") (not (stringContains? cwd "#")))

fn sessPropStr g: (Map String rd/SExpr) key: String -> String
  (match (mapGet g key)
    ((none) "")
    ((some v) (cfg/scalarToString (cfg/asn_scalar v))))

fn sessPropInt g: (Map String rd/SExpr) key: String -> Int64
  (match (mapGet g key)
    ((none) 0)
    ((some v) (match (cfg/asn_scalar v) ((cfg/scalarInt n) n) (_ 0))))

fn sessPropBool g: (Map String rd/SExpr) key: String default: Bool -> Bool
  (match (mapGet g key)
    ((none) default)
    ((some v) (match (cfg/asn_scalar v) ((cfg/scalarBool b) b) (_ default))))

fn sessPropList g: (Map String rd/SExpr) key: String -> (List String)
  (match (mapGet g key)
    ((none) (list))
    ((some v)
     (let [(items (match v ((rd/sexprList l) l) ((rd/sexprVect l) l) (_ (list))))]
       (map (fn [(it rd/SExpr)] -> String (cfg/scalarToString (cfg/asn_scalar it))) items))))

; (:m :do "a vendor row: (:vendor N :bin B :first (ARGS before the prompt on a first turn) :resume (ARGS on a later turn, {id} is the stored id) :idFrom KEY :replyFrom KEY :wrap TEMPLATE :wrapResume TEMPLATE :sep S :env (NAME ...)); the prompt is the last argument, or {prompt} inside a wrap template; nothing is defaulted in code")
fn sessVendorOf item: rd/SExpr -> (Option SessVendor)
  (match (cfg/asn_props item none)
    ((err _) none)
    ((ok g)
     (let [(name (sessPropStr g "vendor")) (bin (sessPropStr g "bin"))]
       (if (stringEmpty? name)
         none
         (some (SessVendor :name name :bin (if (stringEmpty? bin) name bin) :env (sessPropList g "env")
                           :first (sessPropList g "first") :resume (sessPropList g "resume")
                           :idFrom (sessPropStr g "idFrom") :replyFrom (sessPropStr g "replyFrom")
                           :wrap (sessPropStr g "wrap") :wrapResume (sessPropStr g "wrapResume") :sep (sessPropStr g "sep") :modelArgs (sessPropList g "model") :fork (sessPropList g "fork")))))))

fn sessVendorList g: (Map String rd/SExpr) -> (List SessVendor)
  (match (mapGet g "sessions")
    ((none) (list))
    ((some v)
     (let [(items (match v ((rd/sexprList l) l) ((rd/sexprVect l) l) (_ (list))))]
       (fold (fn [(acc (List SessVendor)) (it rd/SExpr)] -> (List SessVendor)
               (match (sessVendorOf it) ((some sv) (listAppend acc (list sv))) ((none) acc)))
             (list) items))))

fn sessEmptyCtx dir: String env: (List String) -> SessCtx
  (SessCtx :dir dir :vendors (list) :env env :timeoutSec 600 :ttlSec 0 :ledger "")

; (:m :do "absent or unparseable gateway.asn text yields an empty allowlist, so every start is refused rather than guessed")
fn sessCtxFromText text: String dir: String env: (List String) -> SessCtx
  (match (ast/readForms (lx/tokenize text))
    ((err _) (sessEmptyCtx dir env))
    ((ok forms)
     (if (!= (listLength forms) 1)
       (sessEmptyCtx dir env)
       (let [(top (optionOr (listHead forms) (ast/PosForm :expr (rd/makeAtom "") :line 0 :col 0)).expr)]
         (match (cfg/asn_props top (some ":gateway"))
           ((err _) (sessEmptyCtx dir env))
           ((ok g)
            (let [(t (sessPropInt g "sessionsTimeoutSec"))]
              (SessCtx :dir dir :vendors (sessVendorList g) :env env :timeoutSec (if (> t 0) t 600) :ttlSec (sessPropInt g "sessionsTtlSec") :ledger ""))))))))

fn sessCtxLedger c: SessCtx path: String -> SessCtx
  (with c :ledger path)

fn sessRowAfterTurn r: SessRow id: String now: Int64 inTok: Int64 outTok: Int64 -> SessRow
  (with r :sessionId id :updatedAt now :turns (+ r.turns 1) :usageIn (+ r.usageIn inTok) :usageOut (+ r.usageOut outTok) :fork false)

fn sessRowForked r: SessRow to: String now: Int64 -> SessRow
  (with r :name to :key to :fork true :turns 0 :startedAt now)

fn ! sessCtxAt! home: String env: (List String) -> SessCtx
  (let [(text (resultOr (fileReadString (str home "/.asl/gateway.asn")) ""))]
    (sessCtxLedger (sessCtxFromText text (str home "/.asl/run/sessions") env) (str home "/.asl/run/gatewayCalls.asn")))

fn ! sessCtxHome! -> SessCtx
  (sessCtxAt! (optionOr (envGet "HOME") "") (envList))

fn sessBaseNames -> (List String)
  (list "PATH" "HOME" "LANG" "LC_ALL" "LC_CTYPE" "TERM" "USER" "TMPDIR")

fn sessEnvName row: String -> String
  (optionOr (listHead (stringSplit row "=")) row)

; (:m :do "a vendor child sees the base names and the names its own :env row lists, nothing else")
fn sessVendorEnv ctx: SessCtx v: SessVendor -> (List String)
  (filter (fn [(row String)] -> Bool
            (let [(n (sessEnvName row))] (or (listContains? (sessBaseNames) n) (listContains? v.env n))))
          ctx.env)

fn sessSubst s: String id: String prompt: String -> String
  (stringReplace (stringReplace s "{id}" id) "{prompt}" (sessQuote prompt))

fn sessSubstId s: String id: String -> String
  (stringReplace s "{id}" id)

; (:m :do "argv is bin, the first or resume head, the caller's extra args, then the prompt (or the wrapped prompt); never a shell string; a prompt that starts with a dash follows -- when the row names no :sep, so it cannot be read as a flag")
fn sessArgv v: SessVendor id: String extra: (List String) prompt: String -> (List String)
  (let [(resuming (not (stringEmpty? id)))
        (head (map (fn [(a String)] -> String (sessSubstId a id)) (if resuming v.resume v.first)))
        (tmpl (if (and resuming (not (stringEmpty? v.wrapResume))) v.wrapResume v.wrap))
        (last (if (stringEmpty? tmpl)
                (cond ((not (stringEmpty? v.sep)) (list v.sep prompt)) ((stringStartsWith? prompt "-") (list "--" prompt)) (else (list prompt)))
                (list (sessSubst tmpl id prompt))))]
    (listAppend (listAppend (cons v.bin head) extra) last))

; (:m :do "values of a key in vendor output, in order: JSON \"key\": value (string or bare token) and ASN :key value; enough for one JSON object, JSON lines and an ASN receipt")
fn sessUnescape s: String -> String
  (stringReplace (stringReplace (stringReplace (stringReplace (stringReplace s "\\\\" "\u0001") "\\\"" "\"") "\\n" "\n") "\\t" "\t") "\u0001" "\\")

fn sessStringEnd text: String i: Int64 -> Int64
  (cond
    ((>= i (stringLength text)) i)
    ((= (optionOr (stringSlice text i (+ i 1)) "") "\\") (sessStringEnd text (+ i 2)))
    ((= (optionOr (stringSlice text i (+ i 1)) "") "\"") i)
    (else (sessStringEnd text (+ i 1))))

fn sessTokenEnd text: String i: Int64 -> Int64
  (if (>= i (stringLength text))
    i
    (let [(c (optionOr (stringSlice text i (+ i 1)) ""))]
      (if (or (= c ",") (or (= c "}") (or (= c "]") (or (= c ")") (or (= c " ") (or (= c "\n") (= c "\r")))))))
        i
        (sessTokenEnd text (+ i 1)))))

fn sessSkipSpace text: String i: Int64 -> Int64
  (if (and (< i (stringLength text)) (listContains? (list " " "\n" "\t" "\r") (optionOr (stringSlice text i (+ i 1)) "")))
    (sessSkipSpace text (+ i 1))
    i)

fn sessValueAt text: String i: Int64 -> (Pair String Int64)
  (let [(j (sessSkipSpace text i))
        (c (optionOr (stringSlice text j (+ j 1)) ""))]
    (if (= c "\"")
      (let [(e (sessStringEnd text (+ j 1)))]
        (pair (sessUnescape (optionOr (stringSlice text (+ j 1) e) "")) (+ e 1)))
      (let [(e (sessTokenEnd text j))]
        (pair (optionOr (stringSlice text j e) "") e))))

fn sessAfter text: String needle: String from: Int64 -> Int64
  (match (stringIndexOf (optionOr (stringSlice text from (stringLength text)) "") needle)
    ((some i) (+ from (+ i (stringLength needle))))
    ((none) -1))

fn sessKeyValuesFrom text: String key: String from: Int64 acc: (List String) -> (List String)
  (let [(jsonKey (str "\"" key "\""))
        (asnKey (str ":" key " "))
        (a (sessAfter text jsonKey from))
        (b (sessAfter text asnKey from))
        (useA (and (>= a 0) (or (< b 0) (< a b))))
        (at (if useA a b))]
    (cond
      ((< at 0) acc)
      (useA
       (let [(j (sessSkipSpace text at))]
         (if (= (optionOr (stringSlice text j (+ j 1)) "") ":")
           (let [(v (sessValueAt text (+ j 1)))]
             (sessKeyValuesFrom text key (pairSecond v) (listAppend acc (list (pairFirst v)))))
           (sessKeyValuesFrom text key at acc))))
      (else
       (let [(v (sessValueAt text at))]
         (sessKeyValuesFrom text key (pairSecond v) (listAppend acc (list (pairFirst v))))))))

fn sessKeyValues text: String key: String -> (List String)
  (if (stringEmpty? key) (list) (sessKeyValuesFrom text key 0 (list)))

fn sessRowOf form: rd/SExpr -> (Option SessRow)
  (match (cfg/asn_props form (some ":session"))
    ((err _) none)
    ((ok g)
     (let [(name (sessPropStr g "name"))]
       (if (stringEmpty? name)
         none
         (some (SessRow :name name :vendor (sessPropStr g "vendor") :cwd (sessPropStr g "cwd") :args (sessPropList g "args")
                        :sessionId (sessPropStr g "sessionId") :startedAt (sessPropInt g "startedAt")
                        :updatedAt (sessPropInt g "updatedAt") :turns (sessPropInt g "turns")
                        :key (sessPropStr g "key") :model (sessPropStr g "model") :digest (sessPropStr g "digest")
                        :delivered (sessPropInt g "delivered") :usageIn (sessPropInt g "usageIn") :usageOut (sessPropInt g "usageOut")
                        :fork (sessPropBool g "fork" false)
                        :kind (let [(k (sessPropStr g "kind"))] (if (stringEmpty? k) "named" k)) :ctxDigest (sessPropStr g "ctxDigest")))))))

fn sessParseRows text: String -> (List SessRow)
  (match (ast/readForms (lx/tokenize text))
    ((err _) (list))
    ((ok forms)
     (fold (fn [(acc (List SessRow)) (pf ast/PosForm)] -> (List SessRow)
             (match (sessRowOf pf.expr) ((some r) (listAppend acc (list r))) ((none) acc)))
           (list) forms)))

fn sessRowText r: SessRow -> String
  (str "(:session :name " (sessQuote r.name) " :vendor " (sessQuote r.vendor) " :cwd " (sessQuote r.cwd)
       " :args (" (stringJoin (map sessQuote r.args) " ") ") :sessionId " (sessQuote r.sessionId)
       " :startedAt " (stringFromInt64 r.startedAt) " :updatedAt " (stringFromInt64 r.updatedAt)
       " :turns " (stringFromInt64 r.turns)
       " :key " (sessQuote r.key) " :model " (sessQuote r.model) " :digest " (sessQuote r.digest)
       " :delivered " (stringFromInt64 r.delivered) " :usageIn " (stringFromInt64 r.usageIn) " :usageOut " (stringFromInt64 r.usageOut)
       " :fork " (if r.fork "true" "false") " :kind " (sessQuote r.kind) " :ctxDigest " (sessQuote r.ctxDigest) ")")

fn sessRowPath ctx: SessCtx name: String -> String
  (str ctx.dir "/" name ".asn")

fn sessReplyPath ctx: SessCtx name: String -> String
  (str ctx.dir "/" name ".reply")

fn sessLockPath ctx: SessCtx name: String -> String
  (str ctx.dir "/" name ".lock")

fn ! sessRowFiles! ctx: SessCtx -> (List String)
  (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asn"))
          (resultOr (dirList ctx.dir) (list)))

fn ! sessReadRow! ctx: SessCtx name: String -> (Option SessRow)
  (listHead (sessParseRows (resultOr (fileReadString (sessRowPath ctx name)) "")))

; (:m :do "a row is 0600 in a 0700 directory, written to a tmp file and renamed; the reply file is the same")
fn ! sessWriteFile! ctx: SessCtx path: String text: String -> (Result Unit String)
  (let [(tmp (str path ".tmp" (stringFromInt64 (procSelf))))]
    (match (dirCreate ctx.dir)
      ((err e) (err (str "registry dir: " e)))
      ((ok _)
       (let [(_m (fileChmod ctx.dir 448))]
         (match (fileWrite tmp text)
           ((err e) (err (str "registry write: " e)))
           ((ok _)
            (let [(_c (fileChmod tmp 384))]
              (match (pathRename tmp path)
                ((err e) (err (str "registry rename: " e)))
                ((ok _) (ok ()))))))))))

fn ! sessWriteRow! ctx: SessCtx r: SessRow -> (Result Unit String)
  (sessWriteFile! ctx (sessRowPath ctx r.name) (str (sessRowText r) "\n"))

fn ! sessAlivePid? pid: Int64 -> Bool
  (and (> pid 0) (listContains? (map (fn [(p fr/Proc)] -> Int64 p.pid) (fr/procSnapshot)) pid))

fn ! sessLockTarget! ctx: SessCtx name: String -> String
  (resultOr (fileReadlink (sessLockPath ctx name)) "")

fn sessLockPidOf target: String -> Int64
  (optionOr (stringToInt64 (sessFirst (stringSplit target ":"))) 0)

fn ! sessLockOwner! ctx: SessCtx name: String -> Int64
  (sessLockPidOf (sessLockTarget! ctx name))

fn ! sessLockHeld? ctx: SessCtx name: String token: String -> Bool
  (and (not (stringEmpty? token)) (= (sessLockTarget! ctx name) token))

fn sessLeasePath ctx: SessCtx name: String -> String
  (str ctx.dir "/" name ".lease")

; (:m :do "a taker that found a dead owner renames the stale lock to a name unique to it, which only one taker can do, then re-reads what it renamed: a lock other than the stale one it saw was a live lock taken in between and is put back, and only a confirmed stale lock is replaced")
fn ! sessLockTakeover! ctx: SessCtx name: String token: String -> String
  (let [(seen (sessLockTarget! ctx name))
        (lock (sessLockPath ctx name))]
    (cond
      ((stringEmpty? seen) (match (pathSymlink token lock) ((ok _) token) ((err _) "")))
      ((sessAlivePid? (sessLockPidOf seen)) "")
      (else
       (let [(stale (str lock ".stale-" (stringReplace token ":" "-")))]
         (match (pathRename lock stale)
           ((err _) "")
           ((ok _)
            (let [(got (resultOr (fileReadlink stale) ""))
                  (_rm (pathRemove stale))]
              (if (= got seen)
                (match (pathSymlink token lock) ((ok _) token) ((err _) ""))
                (let [(_put (pathSymlink got lock))] "")))))))))

; (:m :do "one turn at a time per session: the lock is a symlink NAME.lock whose target is OWNERPID:NONCE, created atomically and failing while it exists; the returned token is the proof of ownership, empty when busy, and every later write checks the lock still holds that token")
fn ! sessLockTake! ctx: SessCtx name: String -> String
  (let [(token (str (stringFromInt64 (procSelf)) ":" (stringFromInt64 (nowNs))))
        (_d (dirCreate ctx.dir))]
    (match (pathSymlink token (sessLockPath ctx name))
      ((ok _) token)
      ((err _) (sessLockTakeover! ctx name token))))

fn ! sessLock! ctx: SessCtx name: String -> Bool
  (not (stringEmpty? (sessLockTake! ctx name)))

fn ! sessLeaseWrite! ctx: SessCtx name: String child: Int64 -> Bool
  (match (sessWriteFile! ctx (sessLeasePath ctx name) (str "(:lease :owner " (stringFromInt64 (procSelf)) " :child " (stringFromInt64 child) ")\n"))
    ((ok _) true)
    ((err _) false))

; (:m :do "release only a lock this turn still holds: a stop or a later taker replaced it otherwise, and removing theirs would let two turns run")
fn ! sessUnlock! ctx: SessCtx name: String token: String -> Unit
  (if (sessLockHeld? ctx name token)
    (do (pathRemove (sessLockPath ctx name)) (pathRemove (sessLeasePath ctx name)) ())
    ())

; (:m :do "the vendor child of a turn in flight is killed only when the lease names it, it is still the child of the lease owner and leads its own group; the owner, which may be the gateway serving other requests, and this process are never signalled")
fn ! sessChildLive? owner: Int64 child: Int64 -> Bool
  (and (> owner 0) (and (> child 0) (and (!= child (procSelf)) (and (!= child owner)
    (listAny? (fn [(p fr/Proc)] -> Bool (and (= p.pid child) (and (= p.ppid owner) (= p.pgid child)))) (fr/procSnapshot))))))

fn ! sessStopChild! ctx: SessCtx name: String -> Bool
  (let [(lease (resultOr (fileReadString (sessLeasePath ctx name)) ""))
        (owner (optionOr (stringToInt64 (sessFirst (sessKeyValues lease "owner"))) 0))
        (child (optionOr (stringToInt64 (sessFirst (sessKeyValues lease "child"))) 0))]
    (if (sessChildLive? owner child)
      (do (fr/killTree! child) true)
      false))

fn sessVendorNamed ctx: SessCtx vendor: String -> (Option SessVendor)
  (listHead (filter (fn [(v SessVendor)] -> Bool (= v.name vendor)) ctx.vendors))

fn sessReceipt op: String name: String extra: String -> String
  (str "(:session :op " op " :status ok :name " (sessQuote name) (if (stringEmpty? extra) "" (str " " extra)) ")")

fn sessFirst xs: (List String) -> String
  (optionOr (listHead xs) "")

fn sessLast xs: (List String) -> String
  (optionOr (listLast xs) "")

fn sessClip s: String n: Int64 -> String
  (if (> (stringLength s) n) (optionOr (stringSlice s 0 n) s) s)

fn sessUsageText out: String -> String
  (let [(i (sessFirst (sessKeyValues out "input_tokens")))
        (o (sessFirst (sessKeyValues out "output_tokens")))]
    (if (and (stringEmpty? i) (stringEmpty? o)) "" (str " :usage (:in " (if (stringEmpty? i) "0" i) " :out " (if (stringEmpty? o) "0" o) ")")))

; (:m :do "the reply is the last value of the reply key (a JSON-lines run ends with its final message), or the whole trimmed output when the vendor row names no key")
fn sessReplyOf out: String key: String -> String
  (if (stringEmpty? key) (stringTrim out) (sessLast (sessKeyValues out key)))

; (:m :do "a turn in flight: guardStart! spawns the vendor through fleet/run and the lease file names the child so a stop can find it; sessAdvance! steps it without blocking, which is how a server parks a turn instead of waiting on it")
fn ! sessBegin! ctx: SessCtx name: String v: SessVendor cwd: String id: String extra: (List String) prompt: String -> (Result SessRun String)
  (match (fr/guardStart! (sessArgv v id extra prompt) cwd (sessVendorEnv ctx v) (fr/limits ctx.timeoutSec 256))
    ((err o) (err (sessErr "vendorFailed" (str "exit " (stringFromInt64 o.exitCode) ": " (sessClip (stringTrim o.stderr) 300)))))
    ((ok g)
     (let [(_l (sessLeaseWrite! ctx name g.run.pid))]
       (ok (SessRun :g g :idFrom v.idFrom :replyFrom v.replyFrom :prevId id)))))

fn sessTurnOf r: SessRun o: fr/ProcOut -> (Result SessTurn String)
  (if (!= o.exitCode 0)
    (err (sessErr "vendorFailed" (str "exit " (stringFromInt64 o.exitCode) ": " (sessClip (stringTrim o.stderr) 300))))
    (let [(newId (sessFirst (sessKeyValues o.stdout r.idFrom)))
          (reply (sessReplyOf o.stdout r.replyFrom))]
      (ok (SessTurn :id (if (stringEmpty? newId) r.prevId newId) :reply reply :usage (sessUsageText o.stdout)
                     :inTok (optionOr (stringToInt64 (sessFirst (sessKeyValues o.stdout "input_tokens"))) 0)
                     :outTok (optionOr (stringToInt64 (sessFirst (sessKeyValues o.stdout "output_tokens"))) 0)))))

fn sessRunWith r: SessRun g: fr/Guarded -> SessRun
  (with r :g g)

fn ! sessAdvance! r: SessRun -> (Pair (Option (Result SessTurn String)) SessRun)
  (let [(s (fr/guardAdvance! r.g))
        (r2 (sessRunWith r s.guard))]
    (match s.out
      ((none) (pair none r2))
      ((some o) (pair (some (sessTurnOf r o)) r2))))

fn sessRunFds r: SessRun -> (List (Pair Int64 Int64))
  (fr/guardFds r.g)

fn ! sessWait! r: SessRun -> (Result SessTurn String)
  (let [(s (sessAdvance! r))]
    (match (pairFirst s)
      ((some res) res)
      ((none) (do (fdPoll (sessRunFds (pairSecond s)) 50) (sessWait! (pairSecond s))))))

; (:m :do "run one headless turn and wait: id empty means a first turn; the result carries the reply, the id the vendor reported, or an (:err ...) with the clipped stderr")
fn ! sessTurn! ctx: SessCtx name: String v: SessVendor cwd: String id: String extra: (List String) prompt: String -> (Result SessTurn String)
  (match (sessBegin! ctx name v cwd id extra prompt)
    ((err e) (err e))
    ((ok r) (sessWait! r)))

fn sessNewRow name: String vendor: String cwd: String args: (List String) id: String now: Int64 t: SessTurn -> SessRow
  (SessRow :name name :vendor vendor :cwd cwd :args args :sessionId id :startedAt now :updatedAt now :turns 1 :key name :model "" :digest "" :delivered 0
           :usageIn t.inTok :usageOut t.outTok :fork false :kind "named" :ctxDigest "")

fn ! sessStart! ctx: SessCtx name: String vendor: String cwd: String args: (List String) text: String -> String
  (cond
    ((not (sessNameOk? name)) (sessErr "badName" "name must match [A-Za-z0-9-]+ and be at most 64 characters"))
    ((not (sessUserNameOk? name)) (sessErr "badName" "names starting with b- are the binding namespace"))
    ((not (sessCwdOk? cwd)) (sessErr "badCwd" "cwd must be an absolute path without #"))
    ((not (sessDir? cwd)) (sessErr "badCwd" "cwd is not an existing directory"))
    ((stringEmpty? text) (sessErr "badText" "start needs the first turn text"))
    (else
      (match (sessVendorNamed ctx vendor)
        ((none) (sessErr "vendorNotAllowed" (str vendor " is not in the sessions allowlist of gateway.asn")))
        ((some v)
         (let [(token (sessLockTake! ctx name))]
           (if (stringEmpty? token)
             (sessErr "busy" (str "session " name " has a turn in flight"))
             (let [(receipt
                     (if (fileExists? (sessRowPath ctx name))
                       (sessErr "nameInUse" (str "session " name " exists"))
                       (match (sessTurn! ctx name v cwd "" args text)
                         ((err e) e)
                         ((ok t)
                          (cond
                            ((stringEmpty? t.id) (sessErr "noSessionId" "the vendor output carried no session id under :idFrom; nothing was stored"))
                            ((not (sessLockHeld? ctx name token)) (sessErr "stopped" "the session was stopped during its first turn; nothing was stored"))
                            (else
                             (let [(now (/ (nowNs) 1000000000))
                                   (w (sessWriteRow! ctx (sessNewRow name vendor cwd args t.id now t)))
                                   (wr (sessWriteFile! ctx (sessReplyPath ctx name) t.reply))]
                               (sessReceipt "start" name (str ":sessionId " (sessQuote t.id) " :exit 0 :reply " (sessQuote t.reply) t.usage)))))))))
                   (_u (sessUnlock! ctx name token))]
               receipt)))))))

fn ! sessSend! ctx: SessCtx name: String text: String extra: (List String) -> String
  (cond
    ((not (sessNameOk? name)) (sessErr "badName" "name must match [A-Za-z0-9-]+"))
    ((stringEmpty? text) (sessErr "badText" "send needs text"))
    (else
      (match (sessReadRow! ctx name)
        ((none) (sessErr "noSession" (str "no session " name)))
        ((some r)
         (match (sessVendorNamed ctx r.vendor)
           ((none) (sessErr "vendorNotAllowed" (str r.vendor " is no longer in the sessions allowlist")))
           ((some v)
            (let [(token (if (= r.kind "binding") "" (sessLockTake! ctx name)))]
              (cond
                ((= r.kind "binding") (sessErr "notNamed" "a binding is driven by its caller key, not by send"))
                ((stringEmpty? token) (sessErr "busy" (str "session " name " has a turn in flight")))
                (else
                 (let [(receipt
                         (match (sessTurn! ctx name v r.cwd r.sessionId (listAppend (if (listEmpty? extra) r.args extra) (if r.fork v.fork (list))) text)
                           ((err e) e)
                           ((ok t)
                            (if (not (sessLockHeld? ctx name token))
                              (sessErr "stopped" "the session was stopped during the turn; nothing was stored")
                              (let [(w (sessWriteRow! ctx (sessRowAfterTurn r t.id (/ (nowNs) 1000000000) t.inTok t.outTok)))
                                    (wr (sessWriteFile! ctx (sessReplyPath ctx name) t.reply))]
                                (sessReceipt "send" name (str ":sessionId " (sessQuote t.id) " :resumed true :exit 0 :reply " (sessQuote t.reply) t.usage)))))))
                       (_u (sessUnlock! ctx name token))]
                   receipt))))))))))

fn ! sessList! ctx: SessCtx -> String
  (let [(rows (fold (fn [(acc (List SessRow)) (n String)] -> (List SessRow)
                      (listAppend acc (sessParseRows (resultOr (fileReadString (str ctx.dir "/" n)) ""))))
                    (list) (listSort (sessRowFiles! ctx))))]
    (str "(:sessions :status ok :count " (stringFromInt64 (listLength rows)) " :rows (" (stringJoin (map sessRowText rows) " ") "))"))

fn ! sessShow! ctx: SessCtx name: String -> String
  (cond
    ((not (sessNameOk? name)) (sessErr "badName" "name must match [A-Za-z0-9-]+"))
    (else
      (match (sessReadRow! ctx name)
        ((none) (sessErr "noSession" (str "no session " name)))
        ((some r) (sessReceipt "show" name (str ":row " (sessRowText r) " :replyPath " (sessQuote (sessReplyPath ctx name))))))))

; (:m :do "stop aborts a turn in flight by killing the vendor child named in the lease, never the lock owner, then removes the row, reply, lease and lock; the turn that was running sees its lock gone and stores nothing; stop on a missing session is an error")
fn ! sessStop! ctx: SessCtx name: String -> String
  (cond
    ((not (sessNameOk? name)) (sessErr "badName" "name must match [A-Za-z0-9-]+"))
    ((not (fileExists? (sessRowPath ctx name))) (sessErr "noSession" (str "no session " name)))
    (else
      (let [(killed (sessStopChild! ctx name))
            (_r1 (pathRemove (sessRowPath ctx name)))
            (_r2 (pathRemove (sessReplyPath ctx name)))
            (_r3 (pathRemove (sessLockPath ctx name)))
            (_r4 (pathRemove (sessLeasePath ctx name)))]
        (sessReceipt "stop" name (str ":aborted " (if killed "true" "false"))))))

fn ! sessDir? path: String -> Bool
  (match (fileStat path) ((ok st) st.isDir) ((err _) false))

; (:m :do "a caller key is never a name: its row is b- plus the first 24 hex of its sha256, so keys cannot collide with, traverse into or shadow a named session, and the key itself is not stored")
fn sessKeyName key: String -> String
  (str "b-" (optionOr (stringSlice (bytesSha256 (stringToBytes key)) 0 24) ""))

; (:m :do "fork copies a row to a new name with the same vendor session id and delivered-prefix digest; the next turn on the copy runs the vendor row :fork args so the vendor branches its conversation, and is refused when the row names none; a binding forks to another binding (the target is a caller key), a named session to a named one")
fn ! sessFork! ctx: SessCtx name: String to: String -> String
  (cond
    ((not (sessNameOk? name)) (sessErr "badName" "name must match [A-Za-z0-9-]+"))
    ((stringEmpty? to) (sessErr "badName" "fork needs a target"))
    (else
      (match (sessReadRow! ctx name)
        ((none) (sessErr "noSession" (str "no session " name)))
        ((some r)
         (let [(dest (if (= r.kind "binding") (sessKeyName to) to))]
           (cond
             ((not (sessNameOk? dest)) (sessErr "badName" "target must match [A-Za-z0-9-]+"))
             ((and (!= r.kind "binding") (not (sessUserNameOk? dest))) (sessErr "badName" "names starting with b- are the binding namespace"))
             ((fileExists? (sessRowPath ctx dest)) (sessErr "nameInUse" (str "session " dest " exists")))
             (else
              (match (sessVendorNamed ctx r.vendor)
                ((none) (sessErr "vendorNotAllowed" (str r.vendor " is no longer in the sessions allowlist")))
                ((some v)
                 (if (listEmpty? v.fork)
                   (sessErr "noFork" (str r.vendor " has no :fork args in its sessions row"))
                   (match (sessWriteRow! ctx (sessRowForked r dest (/ (nowNs) 1000000000)))
                     ((err e) (sessErr "registryWrite" e))
                     ((ok _) (sessReceipt "fork" dest (str ":from " (sessQuote name) " :sessionId " (sessQuote r.sessionId)))))))))))))))

fn sessionsUsage -> String
  (sessErr "usage" "asl gateway session start|send|list|show|stop|forget '(:name N ...)'")

fn ! sessionsRun! ctx: SessCtx op: String g: (Map String rd/SExpr) -> String
  (let [(name (let [(n (sessPropStr g "name"))] (if (and (stringEmpty? n) (not (stringEmpty? (sessPropStr g "key")))) (sessKeyName (sessPropStr g "key")) n)))]
    (cond
      ((= op "fork") (sessFork! ctx name (sessPropStr g "to")))
      ((= op "start") (sessStart! ctx name (sessPropStr g "vendor") (sessPropStr g "cwd") (sessPropList g "args") (sessPropStr g "text")))
      ((= op "send") (sessSend! ctx name (sessPropStr g "text") (sessPropList g "args")))
      ((or (= op "list") (= op "bindings")) (sessList! ctx))
      ((= op "show") (sessShow! ctx name))
      ((or (= op "stop") (= op "forget")) (sessStop! ctx name))
      (else (sessionsUsage))))

; (:m :do "ASN in, ASN receipt out: args are the op then one property list such as (:name \"n\" :vendor \"claude\" :cwd \"/p\" :text \"hi\"); exit 0 on an ok receipt, 1 on (:err ...)")
fn ! sessionsCli! args: (List String) -> (Result Int64 String)
  (let [(op (optionOr (listHead args) ""))
        (src (optionOr (listGet args 1) "()"))
        (receipt
          (match (ast/readForms (lx/tokenize src))
            ((err e) (sessErr "badAsn" "argument is not a readable ASN form"))
            ((ok forms)
             (match (listHead forms)
               ((none) (sessionsRun! (sessCtxHome!) op (mapEmpty)))
               ((some pf)
                (match (cfg/asn_props pf.expr none)
                  ((err e) (sessErr "badAsn" "argument is not a readable ASN form"))
                  ((ok g) (sessionsRun! (sessCtxHome!) op g))))))))]
    (do (sys/say! receipt)
        (ok (if (sessErrIs? receipt) 1 0))))
