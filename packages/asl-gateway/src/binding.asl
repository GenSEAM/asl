(module aslGateway/binding
  :x [BMsg
      BindPlan
      bindDigest
      bindCtxDigest
      bindRender
      bindDecide
      boundChat!
      boundChatBody!
      boundTurn!
      boundTurnWith!
      boundBegin!
      boundAdvance!
      boundFds
      BoundPend
      BoundStart
      boundDone
      boundRunning
      BoundOut
      boundCliEligible?
      boundCliEffect!
      BoundCli
      boundCliNow
      boundCliRunning
      boundCliBegin!
      boundCliFinish]
  :i [(sessions :a s)
      (usageLedger :a ul)
      (asl-json/json :a j)
      (cliDispatch :a cli)
      (wire :a w)
      (chat :a ch)])

; (:m :ref GW-SESSION-BIND :do "a chat request that carries a caller session key and lands on a CLI vendor reuses the vendor's own conversation: the binding (one row per caller key, in the b- namespace of the session store, kind binding) holds the vendor session id and a digest of the messages already delivered; a request whose prefix, system prompt and cwd match sends only its new messages with the vendor resume flag, any mismatch replays the whole transcript into a fresh vendor session. The caller key is the bearer of the request on a loopback single-user gateway and is never stored: rows, ledger and logs carry its hash name")
(schema BMsg (:f role String) (:f text String))
(schema BindPlan (:f resume Bool) (:f why String) (:f id String) (:f prompt String))

fn bindLp s: String -> String
  (str (stringFromInt64 (stringLength s)) ":" s)

; (:m :do "every field is length-prefixed, so no text can imitate a field boundary: the digest of a message list is the sha256 of role and text pairs, each as LENGTH:VALUE")
fn bindJoinMsgs msgs: (List BMsg) -> String
  (stringJoin (map (fn [(m BMsg)] -> String (str (bindLp m.role) (bindLp m.text))) msgs) "")

fn bindDigest msgs: (List BMsg) -> String
  (bytesSha256 (stringToBytes (bindJoinMsgs msgs)))

; (:m :do "what the vendor conversation was started under besides the messages: the system prompt text and the working directory; a binding whose context digest differs is replayed")
fn bindCtxDigest sysText: String cwd: String -> String
  (bytesSha256 (stringToBytes (str (bindLp sysText) (bindLp cwd))))

; (:m :do "one user message is sent as its bare text; anything else as role-labelled blocks, which is also how a full replay is written")
fn bindRender msgs: (List BMsg) -> String
  (match (listHead msgs)
    ((some m)
     (if (and (= (listLength msgs) 1) (= m.role "user"))
       m.text
       (stringJoin (map (fn [(x BMsg)] -> String (str x.role ": " x.text)) msgs) "\n\n")))
    ((none) ""))

fn bindTail msgs: (List BMsg) n: Int64 -> (List BMsg)
  (listReverse (listTake (listReverse msgs) (- (listLength msgs) n)))

fn bindFresh why: String msgs: (List BMsg) -> BindPlan
  (BindPlan :resume false :why why :id "" :prompt (bindRender msgs))

; (:m :do "the resume decision: a binding is used only if the vendor and model are unchanged, the system prompt and cwd are unchanged, it has not outlived the TTL, it holds a vendor session id, and the delivered prefix digest matches the start of this request; every other case is a replay with the reason named")
fn bindDecide row: (Option s/SessRow) vendor: String model: String ctxDigest: String msgs: (List BMsg) now: Int64 ttl: Int64 -> BindPlan
  (match row
    ((none) (bindFresh "noBinding" msgs))
    ((some r)
     (cond
       ((!= r.vendor vendor) (bindFresh "vendorSwitch" msgs))
       ((and (!= r.model model) (> r.delivered 0)) (bindFresh "modelSwitch" msgs))
       ((and (!= r.ctxDigest ctxDigest) (> r.delivered 0)) (bindFresh "contextChanged" msgs))
       ((and (> ttl 0) (> (- now r.updatedAt) ttl)) (bindFresh "expired" msgs))
       ((stringEmpty? r.sessionId) (bindFresh "noVendorSession" msgs))
       ((<= r.delivered 0)
        (BindPlan :resume true :why "resumed" :id r.sessionId :prompt (bindRender (listReverse (listTake (listReverse msgs) 1)))))
       ((<= (listLength msgs) r.delivered) (bindFresh "noNewMessage" msgs))
       ((!= (bindDigest (listTake msgs r.delivered)) r.digest) (bindFresh "diverged" msgs))
       (else (BindPlan :resume true :why "resumed" :id r.sessionId :prompt (bindRender (bindTail msgs r.delivered)))))))

fn bindModelArgs v: s/SessVendor model: String -> (List String)
  (if (stringEmpty? model) (list) (map (fn [(a String)] -> String (stringReplace a "{model}" model)) v.modelArgs))

; (:m :do "one ledger row per bound turn, success or failure, tagged with the binding name (the hash name, never the caller key); the ledger file is 0600")
fn bindLedgerRow name: String v: String model: String inTok: Int64 outTok: Int64 outcome: String promptBytes: Int64 ms: Int64 -> ul/CallRow
  (ul/CallRow :atMs (/ (nowNs) 1000000) :profile "" :intent "binding" :alias name :provider v :model model
              :inTokens inTok :cachedTokens 0 :outTokens outTok :reasoningTokens 0 :ttftMs none :ms (some ms)
              :outcome outcome :charge 0 :tag (some (str "binding:" name)) :temperature none :topP none :maxTokens none
              :effort none :api "cliBinding" :stream false :toolCount 0 :promptBytes promptBytes :sysHash "" :session none :turn none :consumer none :cacheWriteTokens none)

fn ! bindLedger! ctx: s/SessCtx name: String v: String model: String inTok: Int64 outTok: Int64 outcome: String promptBytes: Int64 ms: Int64 -> Unit
  (if (stringEmpty? ctx.ledger)
    ()
    (let [(_w (ul/appendCallRow! ctx.ledger (bindLedgerRow name v model inTok outTok outcome promptBytes ms)))
          (_c (fileChmod ctx.ledger 384))]
      ()))

(schema BoundOut
  (:f text String) (:f resumed Bool) (:f why String) (:f sessionId String) (:f turns Int64) (:f name String)
  (:f inTok Int64) (:f outTok Int64) (:f usage String) (:f totalIn Int64) (:f totalOut Int64))

(schema BoundPend
  (:f ctx s/SessCtx) (:f name String) (:f token String) (:f vendor String) (:f model String) (:f msgs (List BMsg))
  (:f resume Bool) (:f why String) (:f row (Option s/SessRow)) (:f cwd String) (:f baseArgs (List String)) (:f ctxDigest String)
  (:f promptBytes Int64) (:f t0 Int64) (:f run s/SessRun) (:f sanitize Bool) (:f tmpDir String))

(enum BoundStart
  (:c boundDone [(res (Result BoundOut String))])
  (:c boundRunning [(p BoundPend)]))

fn boundPendWith p: BoundPend run: s/SessRun -> BoundPend
  (with p :run run)

fn ! boundFail! ctx: s/SessCtx name: String token: String vendor: String model: String tmpDir: String outcome: String e: String promptBytes: Int64 t0: Int64 -> (Result BoundOut String)
  (let [(_l (bindLedger! ctx name vendor model 0 0 outcome promptBytes (/ (- (monotonicNs) t0) 1000000)))
        (_u (s/sessUnlock! ctx name token))
        (_t (if (stringEmpty? tmpDir) (ok ()) (pathRemove tmpDir)))]
    (err e))

; (:m :do "start one turn for a caller key without waiting: take the per-binding lock, decide resume or replay, and spawn the vendor headless through fleet/run with the policy flags the caller supplies; the vendor runs while the caller does other work, and boundAdvance! finishes it. The system messages are the system prompt (sysText), not part of the delivered transcript")
fn ! boundBegin! ctx: s/SessCtx key: String vendor: String model: String msgs: (List BMsg) policy: (List String) cwdIn: String modelFlags: Bool sysText: String sanitize: Bool tmpDir: String -> BoundStart
  (cond
    ((stringEmpty? key) (boundDone (err (s/sessErr "noCallerKey" "no caller session key"))))
    ((listEmpty? msgs) (boundDone (err (s/sessErr "noMessages" "the request has no messages"))))
    (else
      (match (s/sessVendorNamed ctx vendor)
        ((none) (boundDone (err (s/sessErr "vendorNotAllowed" (str vendor " is not in the sessions allowlist of gateway.asn")))))
        ((some v)
         (let [(name (s/sessKeyName key))
               (token (s/sessLockTake! ctx name))
               (t0 (monotonicNs))]
           (if (stringEmpty? token)
             (boundDone (err (s/sessErr "busy" "this binding has a turn in flight")))
             (let [(now (/ (nowNs) 1000000000))
                   (row (s/sessReadRow! ctx name))
                   (cwd (cond ((not (stringEmpty? cwdIn)) cwdIn) (else (match row ((some r) r.cwd) ((none) "/tmp")))))
                   (ctxD (bindCtxDigest sysText cwd))
                   (plan0 (bindDecide row vendor model ctxD msgs now ctx.ttlSec))
                   (forkArgs (match row ((some r) (if (and r.fork plan0.resume) v.fork (list))) ((none) (list))))
                   (baseArgs (match row ((some r) (if (= r.vendor vendor) r.args (list))) ((none) (list))))
                   (extra (listAppend (listAppend (listAppend baseArgs (if modelFlags (bindModelArgs v model) (list))) policy) forkArgs))
                   (foreign (match row ((some r) (!= r.kind "binding")) ((none) false)))]
               (if foreign
                 (boundDone (boundFail! ctx name token vendor model tmpDir "error" (s/sessErr "namespace" "the row under this binding name is not a binding") 0 t0))
                 (match (s/sessBegin! ctx name v cwd plan0.id extra plan0.prompt)
                   ((err e) (boundDone (boundFail! ctx name token vendor model tmpDir "error" e (stringLength plan0.prompt) t0)))
                   ((ok run)
                    (boundRunning (BoundPend :ctx ctx :name name :token token :vendor vendor :model model :msgs msgs :resume plan0.resume :why plan0.why
                                             :row row :cwd cwd :baseArgs baseArgs :ctxDigest ctxD :promptBytes (stringLength plan0.prompt) :t0 t0
                                             :run run :sanitize sanitize :tmpDir tmpDir))))))))))))

fn boundFds p: BoundPend -> (List (Pair Int64 Int64))
  (s/sessRunFds p.run)

fn boundOutText p: BoundPend text: String -> String
  (if p.sanitize (w/sanitizeAsnContent text) text)

; (:m :do "a finished turn is stored only if its lock is still held (a stop removed it otherwise and nothing may come back), with the digest taken over the reply text the client received, so the client's next request matches")
fn ! boundFinish! p: BoundPend t: s/SessTurn -> (Result BoundOut String)
  (let [(ms (/ (- (monotonicNs) p.t0) 1000000))]
    (cond
      ((stringEmpty? t.id) (boundFail! p.ctx p.name p.token p.vendor p.model p.tmpDir "error" (s/sessErr "noSessionId" "the vendor output carried no session id; the binding was not stored") p.promptBytes p.t0))
      ((not (s/sessLockHeld? p.ctx p.name p.token)) (boundFail! p.ctx p.name p.token p.vendor p.model p.tmpDir "stopped" (s/sessErr "stopped" "the binding was forgotten during the turn; nothing was stored") p.promptBytes p.t0))
      (else
       (let [(now (/ (nowNs) 1000000000))
             (text (boundOutText p t.reply))
             (all (listAppend p.msgs (list (BMsg :role "assistant" :text text))))
             (old (if p.resume p.row none))
             (turns (match old ((some r) (+ r.turns 1)) ((none) 1)))
             (uIn (+ t.inTok (match old ((some r) r.usageIn) ((none) 0))))
             (uOut (+ t.outTok (match old ((some r) r.usageOut) ((none) 0))))
             (started (match old ((some r) r.startedAt) ((none) now)))
             (w (s/sessWriteRow! p.ctx (s/SessRow :name p.name :vendor p.vendor :cwd p.cwd :args p.baseArgs :sessionId t.id :startedAt started :updatedAt now :turns turns
                                                  :key p.name :model p.model :digest (bindDigest all) :delivered (listLength all) :usageIn uIn :usageOut uOut :fork false
                                                  :kind "binding" :ctxDigest p.ctxDigest)))
             (wr (s/sessWriteFile! p.ctx (s/sessReplyPath p.ctx p.name) t.reply))
             (wl (bindLedger! p.ctx p.name p.vendor p.model t.inTok t.outTok "ok" p.promptBytes ms))
             (_u (s/sessUnlock! p.ctx p.name p.token))
             (_t (if (stringEmpty? p.tmpDir) (ok ()) (pathRemove p.tmpDir)))]
         (ok (BoundOut :text text :resumed p.resume :why p.why :sessionId t.id :turns turns :name p.name
                       :inTok t.inTok :outTok t.outTok :usage t.usage :totalIn uIn :totalOut uOut))))))

fn ! boundAdvance! p: BoundPend -> (Pair (Option (Result BoundOut String)) BoundPend)
  (let [(s (s/sessAdvance! p.run))
        (p2 (boundPendWith p (pairSecond s)))]
    (match (pairFirst s)
      ((none) (pair none p2))
      ((some res)
       (match res
         ((err e) (pair (some (boundFail! p.ctx p.name p.token p.vendor p.model p.tmpDir "error" e p.promptBytes p.t0)) p2))
         ((ok t) (pair (some (boundFinish! p t)) p2))))))

fn ! boundWait! p: BoundPend -> (Result BoundOut String)
  (let [(s (boundAdvance! p))]
    (match (pairFirst s)
      ((some r) r)
      ((none) (do (fdPoll (boundFds (pairSecond s)) 50) (boundWait! (pairSecond s))))))

fn ! boundTurnWith! ctx: s/SessCtx key: String vendor: String model: String msgs: (List BMsg) policy: (List String) cwdIn: String modelFlags: Bool sysText: String sanitize: Bool tmpDir: String -> (Result BoundOut String)
  (match (boundBegin! ctx key vendor model msgs policy cwdIn modelFlags sysText sanitize tmpDir)
    ((boundDone r) r)
    ((boundRunning p) (boundWait! p)))

fn ! boundTurn! ctx: s/SessCtx key: String vendor: String model: String msgs: (List BMsg) policy: (List String) cwdIn: String modelFlags: Bool -> (Result BoundOut String)
  (boundTurnWith! ctx key vendor model msgs policy cwdIn modelFlags "" false "")

fn boundReceipt vendor: String model: String o: BoundOut -> String
  (str "(:bound :status ok :name " (s/sessQuote o.name) " :vendor " (s/sessQuote vendor) " :model " (s/sessQuote model)
       " :resumed " (if o.resumed "true" "false") " :why " (s/sessQuote o.why) " :sessionId " (s/sessQuote o.sessionId)
       " :turns " (stringFromInt64 o.turns) " :reply " (s/sessQuote o.text) o.usage
       " :bindingUsage (:in " (stringFromInt64 o.totalIn) " :out " (stringFromInt64 o.totalOut) ")" ")")

fn ! boundChat! ctx: s/SessCtx key: String vendor: String model: String msgs: (List BMsg) -> String
  (match (boundTurn! ctx key vendor model msgs (list) "" true)
    ((err e) e)
    ((ok o) (boundReceipt vendor model o)))

fn jsonStr d: j/Json key: String -> String
  (match (j/jsonGet d key)
    ((some (j/jstr x)) x)
    (_ ""))

; (:m :do "the text of a message as delivered: its content, then its tool calls and tool call id when it has them, so tool traffic is part of both the prompt and the digest")
fn bodyMsgText m: j/Json -> String
  (let [(content (match (j/jsonGet m "content") ((some c) (cli/cliMessageText c)) ((none) "")))
        (calls (match (j/jsonGet m "tool_calls") ((some (j/jnull)) "") ((some c) (j/jsonEmit c)) ((none) "")))
        (callId (jsonStr m "tool_call_id"))]
    (str content (if (stringEmpty? calls) "" (str "\n[tool_calls " calls "]")) (if (stringEmpty? callId) "" (str "\n[tool_call_id " callId "]"))))

fn bodyMessages d: j/Json -> (List BMsg)
  (match (j/jsonGet d "messages")
    ((some (j/jarr xs)) (map (fn [(m j/Json)] -> BMsg (BMsg :role (jsonStr m "role") :text (bodyMsgText m))) xs))
    (_ (list)))

; (:m :do "the caller key is the X-ASL-Session header when present, else the body field session; model comes from the body; without a key the caller keeps the ordinary stateless CLI dispatch")
fn ! boundChatBody! ctx: s/SessCtx vendor: String headerKey: String body: String -> String
  (match (cli/cliJsonObject body)
    ((err _) (s/sessErr "badBody" "the request body is not a JSON object"))
    ((ok d)
     (let [(key (if (not (stringEmpty? headerKey)) headerKey (jsonStr d "session")))]
       (boundChat! ctx key vendor (jsonStr d "model") (bodyMessages d)))))

fn argStr args: (List (Pair String j/Json)) key: String -> String
  (match (listHead (filter (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) key)) args))
    ((some p) (match (pairSecond p) ((j/jstr x) x) (_ "")))
    ((none) ""))

fn argBool args: (List (Pair String j/Json)) key: String -> Bool
  (match (listHead (filter (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) key)) args))
    ((some p) (match (pairSecond p) ((j/jbool x) x) (_ false)))
    ((none) false))

fn argMessages args: (List (Pair String j/Json)) -> (List BMsg)
  (match (listHead (filter (fn [(p (Pair String j/Json))] -> Bool (= (pairFirst p) "messages")) args))
    ((some p)
     (match (pairSecond p)
       ((j/jarr xs)
        (filter (fn [(m BMsg)] -> Bool (!= m.role "system"))
                (map (fn [(m j/Json)] -> BMsg (BMsg :role (jsonStr m "role") :text (bodyMsgText m))) xs)))
       (_ (list))))
    ((none) (list)))

fn optNonEmpty s: String -> (Option String)
  (if (stringEmpty? s) none (some s))

; (:m :do "a chat CLI effect is served by a binding only when the request carried a caller key and the client is in the sessions allowlist of gateway.asn; every other CLI effect keeps the path it had")
fn boundCliEligible? ctx: s/SessCtx client: String args: (List (Pair String j/Json)) -> Bool
  (and (not (stringEmpty? (argStr args "session"))) (some? (s/sessVendorNamed ctx client)))

fn bindingJson o: BoundOut -> j/Json
  (j/jobj (list (pair "resumed" (j/jbool o.resumed)) (pair "why" (j/jstr o.why)) (pair "turns" (j/jint o.turns)) (pair "name" (j/jstr o.name))))

fn boundCliReply o: BoundOut ms: Int64 -> ch/CliReply
  (ch/CliReply :text o.text
               :usage (j/jobj (list (pair "inputTokens" (j/jint o.inTok)) (pair "outputTokens" (j/jint o.outTok)) (pair "cachedTokens" (j/jint 0))))
               :dedup false :queueWaitSec 0.0 :execSec (/ (int64ToFloat64 ms) 1000.0) :pool "" :binding (bindingJson o))

(enum BoundCli
  (:c boundCliNow [(reply (Option ch/CliReply))])
  (:c boundCliRunning [(p BoundPend)]))

; (:m :do "a bound CLI turn keeps the ordinary dispatch's policy: cliBoundFlags! runs the same builders (system prompt file, tool lean flags, model, effort), minus the flags that would stop the vendor keeping its conversation, and the session row supplies headless output; the system prompt and workspace are part of what a binding was started under")
fn ! boundCliBegin! ctx: s/SessCtx client: String args: (List (Pair String j/Json)) -> BoundCli
  (let [(model (argStr args "model"))
        (ws (argStr args "workspace"))
        (sys (argStr args "system_prompt"))]
    (match (cli/cliBoundFlags! client sys (argBool args "no_tools") (optNonEmpty model) (optNonEmpty (argStr args "effort")) ws)
      ((err _) (boundCliNow none))
      ((ok flags)
       (match (boundBegin! ctx (argStr args "session") client model (argMessages args) flags.args ws false sys (argBool args "sanitize") flags.tmpDir)
         ((boundDone r) (boundCliNow (match r ((ok o) (some (boundCliReply o 0))) ((err _) none))))
         ((boundRunning p) (boundCliRunning p))))))

fn boundCliFinish r: (Result BoundOut String) ms: Int64 -> (Option ch/CliReply)
  (match r
    ((ok o) (some (boundCliReply o ms)))
    ((err _) none))

fn ! boundCliEffect! ctx: s/SessCtx client: String args: (List (Pair String j/Json)) -> (Option ch/CliReply)
  (let [(t0 (monotonicNs))]
    (match (boundCliBegin! ctx client args)
      ((boundCliNow r) r)
      ((boundCliRunning p) (boundCliFinish (boundWait! p) (/ (- (monotonicNs) t0) 1000000)))))
