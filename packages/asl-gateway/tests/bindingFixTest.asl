(module aslGateway/tests/bindingFixTest
  :x [runTests]
  :i [(sessions :a s)
      (binding :a b)
      (cliDispatch :a cli)
      (chat :a ch)
      (wire :a w)
      (asl-tools/fleet/run :a fr)
      (asl-json/json :a j)])

; (:m :do "GWSESS-FIX1 gates: stop never kills the gateway, digest forgery and context, namespace, ledger, tool traffic, argv per vendor; the fake vendor sleeps when STATE/slow holds a number of seconds")

fn fakeBase -> String
  "BEGIN{sd=ARGV[1]; n=ARGC-1; prompt=ARGV[n]; id=\"\"; for(i=2;i<n;i++) if(ARGV[i]==\"--resume\") id=ARGV[i+1]; resumed=(id!=\"\"); if(!resumed){f=sd \"/counter\"; c=0; getline c < f; close(f); c++; print c > f; close(f); id=\"fake-\" c} ctxf=sd \"/ctx-\" id; mem=\"\"; while((getline l < ctxf)>0) mem=mem l \"|\"; close(ctxf); print prompt >> ctxf; close(ctxf); af=sd \"/argv-\" id; print \"TURN resumed=\" resumed >> af; for(i=2;i<=n;i++) print \"ARG<\" ARGV[i] \">\" >> af; close(af); printf \"{\\\"session_id\\\":\\\"%s\\\",\\\"result\\\":\\\"seen=%s now=%s can=%s lst=%s\\\",\\\"usage\\\":{\\\"input_tokens\\\":3,\\\"output_tokens\\\":4}}\\n\", id, mem, prompt, ENVIRON[\"ASLCANARY\"], ENVIRON[\"ASLLISTED\"]; exit 0}"

fn fakeProgram -> String
  (stringReplace (fakeBase) "BEGIN{sd=ARGV[1];" "BEGIN{sd=ARGV[1]; slowf=sd \"/slow\"; if((getline z < slowf)>0){close(slowf); system(\"sleep \" z)} ")

fn vendor name: String sd: String forkArgs: (List String) -> s/SessVendor
  (s/SessVendor :name name :bin "/usr/bin/awk" :env (list) :first (list (fakeProgram) sd) :resume (list (fakeProgram) sd "--resume" "{id}")
                :idFrom "session_id" :replyFrom "result" :wrap "" :wrapResume "" :sep "" :modelArgs (list "--model" "{model}") :fork forkArgs)

fn codexVendor sd: String -> s/SessVendor
  (s/SessVendor :name "codex" :bin "/usr/bin/awk" :env (list) :first (list (fakeProgram) sd "exec" "--json" "--skip-git-repo-check")
                :resume (list (fakeProgram) sd "exec" "resume" "--json" "--skip-git-repo-check" "--resume" "{id}")
                :idFrom "session_id" :replyFrom "result" :wrap "" :wrapResume "" :sep "" :modelArgs (list) :fork (list))

fn agyVendor sd: String -> s/SessVendor
  (s/SessVendor :name "agy" :bin "/usr/bin/awk" :env (list) :first (list (fakeProgram) sd "--output-format" "json")
                :resume (list (fakeProgram) sd "--output-format" "json" "--resume" "{id}")
                :idFrom "session_id" :replyFrom "result" :wrap "" :wrapResume "" :sep "-p" :modelArgs (list) :fork (list))

fn badVendor -> s/SessVendor
  (s/SessVendor :name "bad" :bin "/usr/bin/false" :env (list) :first (list) :resume (list) :idFrom "session_id" :replyFrom "result"
                :wrap "" :wrapResume "" :sep "" :modelArgs (list) :fork (list))

fn nm key: String -> String
  (s/sessKeyName key)

fn um text: String -> b/BMsg
  (b/BMsg :role "user" :text text)

fn am text: String -> b/BMsg
  (b/BMsg :role "assistant" :text text)

fn outText r: (Result b/BoundOut String) -> String
  (match r ((ok o) o.text) ((err e) e))

fn outWhy r: (Result b/BoundOut String) -> String
  (match r ((ok o) o.why) ((err e) e))

fn ! rd path: String -> String
  (resultOr (fileReadString path) "")

fn ! turn! ctx: s/SessCtx key: String msgs: (List b/BMsg) sys: String cwd: String sanitize: Bool -> (Result b/BoundOut String)
  (b/boundTurnWith! ctx key "fake" "m" msgs (list) cwd false sys sanitize "")

fn ! pidAlive? pid: Int64 -> Bool
  (listContains? (map (fn [(p fr/Proc)] -> Int64 p.pid) (fr/procSnapshot)) pid)

fn ! drain! p: b/BoundPend fuel: Int64 -> (Result b/BoundOut String)
  (if (<= fuel 0)
    (err "drain out of fuel")
    (let [(s (b/boundAdvance! p))]
      (match (pairFirst s)
        ((some r) r)
        ((none) (do (sleepMs 20) (drain! (pairSecond s) (- fuel 1)))))))

fn ! beginPend! ctx: s/SessCtx key: String msgs: (List b/BMsg) -> (Option b/BoundPend)
  (match (b/boundBegin! ctx key "fake" "m" msgs (list) "" false "" false (str "/tmp/aslBfTmp" (stringFromInt64 (procSelf))))
    ((b/boundRunning p) (some p))
    ((b/boundDone _) none))

fn ledgerCount ledger: String needle: String -> Int64
  (listLength (filter (fn [(l String)] -> Bool (stringContains? l needle)) (stringLines ledger)))

fn jbody sessionKey: String msgsJson: String -> String
  (str "{\"model\":\"m\",\"session\":\"" sessionKey "\",\"messages\":[" msgsJson "]}")

fn jmsg role: String content: String -> String
  (str "{\"role\":\"" role "\",\"content\":\"" content "\"}")

fn replyField receipt: String -> String
  (optionOr (listHead (s/sessKeyValues receipt "reply")) "")

fn argList session: String msgs: (List (Pair String String)) model: String sanitize: Bool -> (List (Pair String j/Json))
  (list (pair "session" (j/jstr session))
        (pair "messages" (j/jarr (map (fn [(m (Pair String String))] -> j/Json (j/jobj (list (pair "role" (j/jstr (pairFirst m))) (pair "content" (j/jstr (pairSecond m)))))) msgs)))
        (pair "system_prompt" (j/jstr "SYS")) (pair "no_tools" (j/jbool true)) (pair "workspace" (j/jstr "/tmp"))
        (pair "model" (j/jstr model)) (pair "effort" (j/jstr "low")) (pair "sanitize" (j/jbool sanitize)))

fn testPure -> Bool
  (let [(forged (b/bindDigest (list (um "x\u0002user\u0001y"))))
        (honest (b/bindDigest (list (um "x") (um "y"))))]
    (do (assert (!= forged honest) "separator bytes inside a message cannot imitate a message boundary: fields are length-prefixed")
        (assert (!= (b/bindDigest (list (b/BMsg :role "a" :text "bc"))) (b/bindDigest (list (b/BMsg :role "ab" :text "c")))) "role and text lengths are part of the digest")
        (assert (!= (b/bindCtxDigest "S1" "/tmp") (b/bindCtxDigest "S2" "/tmp")) "the context digest depends on the system prompt")
        (assert (!= (b/bindCtxDigest "S1" "/tmp") (b/bindCtxDigest "S1" "/usr")) "the context digest depends on the cwd")
        (assert (!= (b/bindCtxDigest "ab" "c") (b/bindCtxDigest "a" "bc")) "the context fields are length-prefixed too")
        (assert (= (ch/cliCallerKey (list) (j/jobj (list (pair "user" (j/jstr "u1"))))) "") "the body user field is not a caller key")
        (assert (= (ch/cliCallerKey (list (pair "X-ASL-Session" "asl-run-3-4")) (j/jobj (list (pair "user" (j/jstr "u1"))))) "") "a server fallback header plus a body user is still keyless")
        (assert (= (ch/cliCallerKey (list) (j/jobj (list (pair "session" (j/jstr "s1"))))) "s1") "the body session field is a caller key")
        (assert (stringStartsWith? (nm "named-1") "b-") "every caller key maps into the b- namespace, even a plain name")
        (assert (!= (nm "named-1") "named-1") "a caller key never maps onto a named session of the same text")
        true))

fn testContextAndDigest -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslBfCtx" me))
        (sd (str dir "/state"))
        (ctx (s/SessCtx :secretsFile "" :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger "" :vendors (list (vendor "fake" sd (list)))))
        (_mk (dirCreate sd))
        (t1 (turn! ctx "sys-1" (list (um "q1")) "S1" "/tmp" false))
        (t2 (turn! ctx "sys-1" (list (um "q1") (am (outText t1)) (um "q2")) "S1" "/tmp" false))
        (t3 (turn! ctx "sys-1" (list (um "q1") (am (outText t1)) (um "q2") (am (outText t2)) (um "q3")) "S2" "/tmp" false))
        (t4 (turn! ctx "sys-1" (list (um "q1") (am (outText t1)) (um "q2") (am (outText t2)) (um "q3") (am (outText t3)) (um "q4")) "S2" "/usr" false))
        (s1 (turn! ctx "san-1" (list (um "q1")) "S" "/tmp" true))
        (s2 (turn! ctx "san-1" (list (um "q1") (am (outText s1)) (um "q2")) "S" "/tmp" true))
        (c1 (s/sessCtxFromText "" (str dir "/sessions") (envList)))
        (tcA1 (b/boundChatBody! ctx "fake" "" (jbody "tc-a" (jmsg "user" "q"))))
        (tcA2 (b/boundChatBody! ctx "fake" "" (jbody "tc-a" (str (jmsg "user" "q") "," "{\"role\":\"assistant\",\"content\":\"" (replyField tcA1) "\",\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f\",\"arguments\":\"{}\"}}]}," "{\"role\":\"tool\",\"tool_call_id\":\"c1\",\"content\":\"res\"}," (jmsg "user" "n")))))
        (tcB1 (b/boundChatBody! ctx "fake" "" (jbody "tc-b" (jmsg "user" "q"))))
        (tcB2 (b/boundChatBody! ctx "fake" "" (jbody "tc-b" (str (jmsg "user" "q") "," "{\"role\":\"assistant\",\"content\":\"" (replyField tcB1) "\"}," (jmsg "user" "n")))))
        (userOnly (b/boundChatBody! ctx "fake" "" "{\"model\":\"m\",\"user\":\"u1\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"))
        (_rm (pathRemove dir))]
    (do (assert (= (outWhy t1) "noBinding") "the first turn replays")
        (assert (= (outWhy t2) "resumed") "the same system prompt and cwd resume")
        (assert (= (outWhy t3) "contextChanged") "a changed system prompt replays into a fresh vendor session")
        (assert (= (outWhy t4) "contextChanged") "a changed cwd replays into a fresh vendor session")
        (assert (stringStartsWith? (outText s1) "(:error") "sanitize turns a non-ASN reply into the error form the client receives")
        (assert (= (outWhy s2) "resumed") "the digest covers the reply text the client received, so its next request resumes")
        (assert (stringContains? tcA2 ":why \"diverged\"") "tool_calls in a client message are part of the compared prefix")
        (assert (stringContains? tcB2 ":resumed true") "the same history without tool traffic resumes")
        (assert (stringContains? userOnly ":code noCallerKey") "a body user field alone is not a caller key")
        (assert (= (listLength c1.vendors) 0) "an empty config allows no vendor")
        true))

fn testNamespace -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslBfNs" me))
        (sd (str dir "/state"))
        (ctx (s/SessCtx :secretsFile "" :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger "" :vendors (list (vendor "fake" sd (list)))))
        (_mk (dirCreate sd))
        (named (s/sessStart! ctx "named-1" "fake" dir (list) "alpha"))
        (before (rd (s/sessRowPath ctx "named-1")))
        (bound (b/boundChatBody! ctx "fake" "named-1" (jbody "" (jmsg "user" "beta"))))
        (after (rd (s/sessRowPath ctx "named-1")))
        (boundRow (rd (s/sessRowPath ctx (nm "named-1"))))
        (badPrefix (s/sessStart! ctx "b-abc" "fake" dir (list) "x"))
        (sendBinding (s/sessSend! ctx (nm "named-1") "hello" (list)))
        (forgedRow (s/SessRow :name (nm "forged") :vendor "fake" :cwd "/tmp" :args (list) :sessionId "fake-9" :startedAt 1 :updatedAt 1 :turns 1 :key "forged" :model "m" :digest "d" :delivered 1 :usageIn 0 :usageOut 0 :fork false :kind "named" :ctxDigest ""))
        (_w (s/sessWriteRow! ctx forgedRow))
        (forgedBefore (rd (s/sessRowPath ctx (nm "forged"))))
        (forged (b/boundChatBody! ctx "fake" "forged" (jbody "" (jmsg "user" "x"))))
        (forgedAfter (rd (s/sessRowPath ctx (nm "forged"))))
        (_rm (pathRemove dir))]
    (do (assert (stringContains? named ":status ok") "a named session starts")
        (assert (stringContains? bound ":status ok") "the keyed request is served")
        (assert (= before after) "a caller key equal to a named session's name does not touch the named row")
        (assert (stringContains? boundRow ":kind \"binding\"") "the binding lives under its hashed name, kind binding")
        (assert (not (stringContains? boundRow "named-1\"")) "the caller key itself is not stored in the binding row")
        (assert (stringContains? badPrefix ":code badName") "a named session may not start with b-")
        (assert (stringContains? sendBinding ":code notNamed") "send does not drive a binding")
        (assert (stringContains? forged ":code namespace") "a binding never resumes a row that is not a binding")
        (assert (= forgedBefore forgedAfter) "and leaves that row untouched")
        true))

fn testLedger -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslBfLed" me))
        (sd (str dir "/state"))
        (ledgerPath (str dir "/ledger.asn"))
        (ctx (s/SessCtx :secretsFile "" :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger ledgerPath :vendors (list (vendor "fake" sd (list)) (badVendor))))
        (_mk (dirCreate sd))
        (t1 (turn! ctx "led-1" (list (um "q1")) "S" "/tmp" false))
        (t2 (turn! ctx "led-1" (list (um "q1") (am (outText t1)) (um "q2")) "S" "/tmp" false))
        (bad (b/boundTurnWith! ctx "led-bad" "bad" "m" (list (um "q")) (list) "/tmp" false "" false ""))
        (ledger (rd ledgerPath))
        (mode (match (fileStat ledgerPath) ((ok st) (& st.mode 511)) ((err _) 0)))
        (_rm (pathRemove dir))]
    (do (assert (= (ledgerCount ledger (str "binding:" (nm "led-1"))) 2) "exactly one ledger row per bound turn")
        (assert (= (ledgerCount ledger (str "binding:" (nm "led-bad"))) 1) "a failed bound turn also writes one row")
        (assert (stringContains? ledger "\"error\"") "the failed turn's row carries the error outcome")
        (assert (not (stringContains? ledger "led-1")) "the ledger never carries the raw caller key")
        (assert (= mode 384) "the ledger file is 0600")
        (assert (stringContains? (outText bad) ":code vendorFailed") "the failed turn reports the vendor failure")
        true))

fn testStop -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslBfStop" me))
        (sd (str dir "/state"))
        (ctx (s/SessCtx :secretsFile "" :dir (str dir "/sessions") :env (envList) :timeoutSec 30 :ttlSec 0 :ledger "" :vendors (list (vendor "fake" sd (list)))))
        (_mk (dirCreate sd))
        (key "stop-1")
        (name (nm key))
        (t1 (turn! ctx key (list (um "q1")) "" "" false))
        (_slow (fileWrite (str sd "/slow") "20"))
        (pend (beginPend! ctx key (list (um "q1") (am (outText t1)) (um "q2"))))
        (lease (rd (s/sessLeasePath ctx name)))
        (child (optionOr (stringToInt64 (optionOr (listHead (s/sessKeyValues lease "child")) "")) 0))
        (owner (optionOr (stringToInt64 (optionOr (listHead (s/sessKeyValues lease "owner")) "")) 0))
        (childUp (pidAlive? child))
        (stop (s/sessStop! ctx name))
        (res (match pend ((some p) (drain! p 200)) ((none) (err "no pending turn"))))
        (childGone (not (pidAlive? child)))
        (rowGone (not (fileExists? (s/sessRowPath ctx name))))
        (selfAlive (pidAlive? (procSelf)))
        (tmpGone (not (fileExists? (str "/tmp/aslBfTmp" me))))
        (_slow2 (fileWrite (str sd "/slow") "1"))
        (_key2 (turn! ctx "stop-2" (list (um "q1")) "" "" false))
        (pend2 (beginPend! ctx "stop-2" (list (um "q1") (am "x") (um "q2"))))
        (_rm1 (pathRemove (s/sessLockPath ctx (nm "stop-2"))))
        (_rm2 (pathRemove (s/sessRowPath ctx (nm "stop-2"))))
        (res2 (match pend2 ((some p) (drain! p 200)) ((none) (err "no pending turn"))))
        (row2Gone (not (fileExists? (s/sessRowPath ctx (nm "stop-2")))))
        (_rm (pathRemove dir))]
    (do (assert (some? pend) "the second turn is in flight")
        (assert (= owner (procSelf)) "the lease names this process as the lock owner")
        (assert (and (> child 0) childUp) "the lease names a live vendor child")
        (assert (!= child owner) "the vendor child is not the lock owner")
        (assert (stringContains? stop ":aborted true") "forget aborts the turn in flight")
        (assert selfAlive "forget does not kill the process that owns the lock")
        (assert childGone "forget kills the vendor child")
        (assert (stringContains? (outText res) ":code") "the aborted turn reports a failure")
        (assert rowGone "the aborted turn stores nothing after the forget")
        (assert tmpGone "the per-turn temp dir is removed when the turn is killed")
        (assert (stringContains? (outText res2) ":code stopped") "a turn whose lock was removed finishes as stopped")
        (assert row2Gone "a finishing turn does not resurrect a deleted row")
        true))

fn tmpMode dir: String -> Int64
  (match (fileStat dir) ((ok st) (& st.mode 511)) ((err _) 0))

fn testArgv -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslBfArgv" me))
        (sd (str dir "/state"))
        (ctx (s/SessCtx :secretsFile "" :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger "" :vendors (list (codexVendor sd) (agyVendor sd))))
        (_mk (dirCreate sd))
        (cx (cli/cliBoundFlags! "codex" "SYS" true (some "gpt-x") (some "low") "/tmp"))
        (ax (cli/cliBoundFlags! "agy" "SYS" true (some "gemini-3.8-flash") (some "low") "/tmp"))
        (clx (cli/cliBoundFlags! "claude" "SYS" true (some "opus") (some "low") "/tmp"))
        (codexArgs (match cx ((ok f) f.args) ((err e) (list e))))
        (codexTmp (match cx ((ok f) f.tmpDir) ((err _) "")))
        (agyArgs (match ax ((ok f) f.args) ((err e) (list e))))
        (agyTmp (match ax ((ok f) f.tmpDir) ((err _) "")))
        (claudeArgs (match clx ((ok f) f.args) ((err e) (list e))))
        (claudeTmp (match clx ((ok f) f.tmpDir) ((err _) "")))
        (modes (list (tmpMode codexTmp) (tmpMode agyTmp) (tmpMode claudeTmp)))
        (codexRun (b/boundCliEffect! ctx "codex" (argList "cx-1" (list (pair "user" "hello codex")) "gpt-x" false)))
        (codexArgv (rd (str sd "/argv-fake-1")))
        (agyRun (b/boundCliEffect! ctx "agy" (argList "ag-1" (list (pair "system" "ignored") (pair "user" "hello agy")) "gemini-3.8-flash" false)))
        (agyArgv (rd (str sd "/argv-fake-2")))
        (execSec (match agyRun ((some r) r.execSec) ((none) -1.0)))
        (binding (match agyRun ((some r) (j/jsonEmit r.binding)) ((none) "")))
        (sanRun (b/boundCliEffect! ctx "agy" (argList "ag-2" (list (pair "user" "san")) "gemini-3.8-flash" true)))
        (sanText (match sanRun ((some r) r.text) ((none) "")))
        (_c1 (pathRemove codexTmp))
        (_c2 (pathRemove agyTmp))
        (_c3 (pathRemove claudeTmp))
        (_rm (pathRemove dir))]
    (do (assert (= codexArgs (list "-c" (str "model_instructions_file=" codexTmp "/system.md") "-c" "project_doc_max_bytes=0" "-c" "model_reasoning_effort=\"low\"" "-m" "gpt-x")) "codex bound flags are exactly the policy flags, headless and workspace flags removed by name")
        (assert (= agyArgs (list "--model" "gemini-3.8-flash" "--effort" "low" "--agent" "aslGateway" "--add-dir" agyTmp "--add-dir" "/tmp")) "agy bound flags drop --output-format and the -p placeholder, keep model, agent and dirs")
        (assert (= claudeArgs (list "--system-prompt-file" (str claudeTmp "/system.md") "--tools" "" "--strict-mcp-config" "--disable-slash-commands" "--setting-sources" "" "--model" "opus" "--effort" "low")) "claude bound flags drop -p, --output-format and --no-session-persistence")
        (assert (= modes (list 448 448 448)) "the per-turn temp dir is 0700")
        (assert (stringContains? codexArgv "ARG<exec>") "the codex row supplies exec")
        (assert (= (listLength (filter (fn [(l String)] -> Bool (= l "ARG<exec>")) (stringLines codexArgv))) 1) "exec appears once on the codex bound turn")
        (assert (not (stringContains? codexArgv "ARG<-C>")) "no -C workspace flag on a bound codex turn")
        (assert (not (stringContains? codexArgv "ARG<--ephemeral>")) "no --ephemeral on a bound codex turn")
        (assert (stringContains? codexArgv "ARG<hello codex>") "the codex prompt is the last argument")
        (assert (stringContains? agyArgv "ARG<-p>\nARG<hello agy>") "the agy prompt is the value of -p")
        (assert (not (stringContains? agyArgv "Answer the last turn")) "the agy placeholder prompt is gone")
        (assert (= (listLength (filter (fn [(l String)] -> Bool (= l "ARG<--output-format>")) (stringLines agyArgv))) 1) "--output-format appears once on the agy bound turn")
        (assert (and (> execSec 0.0) (< execSec 5.0)) (str "execSec is in seconds, got " (stringFromFloat64 execSec)))
        (assert (stringContains? binding "\"resumed\":false") "the reply carries the binding object")
        (assert (stringStartsWith? sanText "(:error") "the live path sanitizes the reply text as the client will receive it")
        true))

fn ! runTests -> Bool
  (do (assert (testPure) "pure checks")
      (assert (testContextAndDigest) "context and digest")
      (assert (testNamespace) "namespace")
      (assert (testLedger) "ledger")
      (assert (testStop) "stop")
      (assert (testArgv) "argv")
      true)
