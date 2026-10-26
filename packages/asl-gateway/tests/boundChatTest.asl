(module aslGateway/tests/boundChatTest
  :x [runTests]
  :i [(sessions :a s)
      (binding :a b)
      (chat :a ch)
      (upstream :a u)
      (config :a c)
      (pyText :a pt)
      (asl-json/json :a j)])

fn fakeProgram -> String
  "BEGIN{sd=ARGV[1]; n=ARGC-1; prompt=ARGV[n]; id=\"\"; for(i=2;i<n;i++) if(ARGV[i]==\"--resume\") id=ARGV[i+1]; resumed=(id!=\"\"); if(!resumed){f=sd \"/counter\"; c=0; getline c < f; close(f); c++; print c > f; close(f); id=\"fake-\" c} ctxf=sd \"/ctx-\" id; mem=\"\"; while((getline l < ctxf)>0) mem=mem l \"|\"; close(ctxf); print prompt >> ctxf; close(ctxf); af=sd \"/argv-\" id; print \"TURN resumed=\" resumed >> af; for(i=2;i<=n;i++) print \"ARG<\" ARGV[i] \">\" >> af; close(af); printf \"{\\\"session_id\\\":\\\"%s\\\",\\\"result\\\":\\\"seen=%s now=%s can=%s lst=%s\\\",\\\"usage\\\":{\\\"input_tokens\\\":3,\\\"output_tokens\\\":4}}\\n\", id, mem, prompt, ENVIRON[\"ASLCANARY\"], ENVIRON[\"ASLLISTED\"]; exit 0}"

fn fakeVendor name: String sd: String -> s/SessVendor
  (s/SessVendor :name name :bin "/usr/bin/awk" :env (list) :first (list (fakeProgram) sd) :resume (list (fakeProgram) sd "--resume" "{id}")
                :idFrom "session_id" :replyFrom "result" :wrap "" :wrapResume "" :sep "" :modelArgs (list) :fork (list))

(schema Run
  (:f body String)
  (:f clis (List (List (Pair String j/Json)))))

fn ! world! -> (Option ch/ChatWorld)
  (let [(text (resultOr (fileReadString "asl/packages/asl-gateway/tests/fixtures/chatBuiltinConfig/gateway.asn") ""))
        (table (c/gatewayProfilesLoadText! "/test" true (ok text) ""))]
    (match (u/upstreamSettings (mapEmpty))
      ((err _) none)
      ((ok st) (some (ch/ChatWorld :env (mapEmpty) :rootDir "/tmp" :settings st :agyPromptMaxBytes 10000 :table table)))))

fn ! driveWith! ctx: s/SessCtx step: ch/ChatStep clis: (List (List (Pair String j/Json))) fuel: Int64 -> Run
  (if (<= fuel 0)
    (Run :body "out of fuel" :clis clis)
    (match step
      ((ch/stepDone resp) (Run :body resp.body :clis clis))
      ((ch/stepRaised kind msg) (Run :body (str "raised " kind ": " msg) :clis clis))
      ((ch/stepEffect eff k)
       (match eff
         ((ch/effRealpath _) (driveWith! ctx (k (ch/outPath "/tmp")) clis (- fuel 1)))
         ((ch/effIsDir _) (driveWith! ctx (k (ch/outBool true)) clis (- fuel 1)))
         ((ch/effClock) (driveWith! ctx (k (ch/outFloat 1.0)) clis (- fuel 1)))
         ((ch/effBreakerDown _) (driveWith! ctx (k (ch/outFloat 0.0)) clis (- fuel 1)))
         ((ch/effBreakerDownAll _) (driveWith! ctx (k (ch/outFloats (list 0.0))) clis (- fuel 1)))
         ((ch/effBucket _ _ _) (driveWith! ctx (k (ch/outBool true)) clis (- fuel 1)))
         ((ch/effCli client args)
          (driveWith! ctx
            (k (ch/outCli (if (b/boundCliEligible? ctx client args) (b/boundCliEffect! ctx client args) none)))
            (cons args clis) (- fuel 1)))
         (_ (driveWith! ctx (k ch/outDone) clis (- fuel 1)))))))

fn ! post! ctx: s/SessCtx w: ch/ChatWorld headers: (List (Pair String String)) body: String -> Run
  (driveWith! ctx (ch/chatStart! (ch/ChatRequest :path "/v1/chat/completions" :headers headers :body body) w) (list) 80)

fn jesc t: String -> String
  (stringReplace (stringReplace (stringReplace t "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn msg role: String text: String -> String
  (str "{\"role\":\"" role "\",\"content\":\"" (jesc text) "\"}")

fn body model: String extra: String msgs: (List String) -> String
  (str "{\"model\":\"" model "\"" extra ",\"messages\":[" (stringJoin msgs ",") "]}")

fn contentOf resp: String -> String
  (match (pt/jsonLoads resp)
    ((ok v)
     (match (pt/jget v "choices")
       ((some (j/jarr xs))
        (match (listHead xs)
          ((some ch0) (match (pt/jget ch0 "message") ((some m) (match (pt/jget m "content") ((some (j/jstr t)) t) (_ "")) ) ((none) "")))
          ((none) "")))
       (_ "")))
    ((err _) ""))

fn keysOf args: (List (Pair String j/Json)) -> (List String)
  (map pairFirst args)

fn ! rd path: String -> String
  (resultOr (fileReadString path) "")

fn lastTurn text: String -> String
  (optionOr (listLast (stringSplit text "TURN resumed=")) "")

(schema Seen
  (:f keyless Run)
  (:f keyed1 Run)
  (:f keyed2 Run)
  (:f argv1 String)
  (:f bodyKey Run)
  (:f userKey Run)
  (:f fallbackHeader Run)
  (:f files (List String)))

fn ! observe! ctx: s/SessCtx w: ch/ChatWorld dir: String sd: String -> Seen
  (let [(keyless (post! ctx w (list (pair "X-ASL-Session" "asl-run-3-100")) (body "claude/opus" "" (list (msg "user" "hello")))))
        (k1 (post! ctx w (list (pair "X-ASL-Session" "sess-1")) (body "claude/opus" "" (list (msg "system" "be terse") (msg "user" "hello")))))
        (r1 (contentOf k1.body))
        (k2 (post! ctx w (list (pair "X-ASL-Session" "sess-1")) (body "claude/opus" "" (list (msg "system" "be terse") (msg "user" "hello") (msg "assistant" r1) (msg "user" "again")))))
        (argv1 (rd (str sd "/argv-fake-1")))
        (bodyKey (post! ctx w (list (pair "X-ASL-Session" "asl-run-4-200")) (body "claude/opus" ",\"session\":\"body-1\"" (list (msg "user" "hi")))))
        (userKey (post! ctx w (list) (body "claude/opus" ",\"user\":\"user-1\"" (list (msg "user" "hi")))))
        (files (listSort (filter (fn [(n String)] -> Bool (stringEndsWith? n ".asn")) (resultOr (dirList (str dir "/sessions")) (list)))))]
    (Seen :keyless keyless :keyed1 k1 :keyed2 k2 :argv1 argv1 :bodyKey bodyKey :userKey userKey :fallbackHeader keyless :files files))

fn ! testLive -> Bool
  (match (world!)
    ((none) (do (assert false "the test world builds") false))
    ((some w)
     (let [(me (stringFromInt64 (procSelf)))
           (dir (str "/tmp/aslBoundChatTest" me))
           (sd (str dir "/state"))
           (ctx (s/SessCtx :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger "" :vendors (list (fakeVendor "claude" sd))))
           (_mk (dirCreate sd))
           (seen (observe! ctx w dir sd))
           (_rm (pathRemove dir))]
       (do (assert (= (length1 seen.keyless.clis) 1) "the keyless request reached the CLI effect once")
           (assert (not (listContains? (keysOf (firstArgs seen.keyless.clis)) "session")) "a request without a caller key carries no session argument")
           (assert (not (listContains? (keysOf (firstArgs seen.keyless.clis)) "messages")) "and no messages argument, so the effect is the old one")
           (assert (not (b/boundCliEligible? (s/SessCtx :dir "/x" :env (list) :timeoutSec 1 :ttlSec 0 :ledger "" :vendors (list (fakeVendor "claude" "/s"))) "claude" (firstArgs seen.keyless.clis))) "the old effect is not served by a binding")
           (assert (listContains? (keysOf (firstArgs seen.keyed1.clis)) "session") "a keyed request carries its caller key to the CLI effect")
           (assert (listContains? (keysOf (firstArgs seen.keyed1.clis)) "messages") "and its messages")
           (assert (stringContains? (contentOf seen.keyed1.body) "now=hello") "the first keyed request is answered by the vendor")
           (assert (stringContains? (contentOf seen.keyed2.body) "seen=hello|") "the second keyed request continues the vendor's conversation")
           (assert (stringContains? (contentOf seen.keyed2.body) "now=again") "and shows only the new message as the turn")
           (assert (stringContains? seen.argv1 "ARG<--resume>\nARG<fake-1>") "the second request resumes the stored vendor session id")
           (assert (not (stringContains? (lastTurn seen.argv1) "hello")) "the resumed turn does not replay earlier messages")
           (assert (stringContains? (lastTurn seen.argv1) "ARG<again>") "the resumed turn carries the new message")
           (assert (stringContains? seen.argv1 "ARG<--system-prompt-file>") "the dispatch's system prompt flag is kept on a bound turn")
           (assert (stringContains? seen.argv1 "ARG<--strict-mcp-config>") "the dispatch's tool lean flags are kept on a bound turn")
           (assert (not (stringContains? seen.argv1 "--no-session-persistence")) "the flag that stops the vendor keeping its conversation is removed")
           (assert (not (stringContains? seen.argv1 "ARG<-p>")) "the headless flag comes from the session row, not twice")
           (assert (= seen.files (listSort (list (str (s/sessKeyName "body-1") ".asn") (str (s/sessKeyName "sess-1") ".asn")))) "bindings exist, under hashed names, for header and body session keys only: not for the keyless, server-fallback or body user requests")
           (assert (= (bindingWhy seen.keyed2.body) "resumed") "the HTTP response carries asl.binding with the resume reason")
           (assert (= (bindingWhy seen.keyed1.body) "noBinding") "the first keyed response says why it replayed")
           (assert (= (bindingWhy seen.keyless.body) "") "a keyless response carries no binding object")
           true))))

fn bindingWhy resp: String -> String
  (match (pt/jsonLoads resp)
    ((ok v)
     (match (pt/jget v "asl")
       ((some a) (match (pt/jget a "binding") ((some b) (match (pt/jget b "why") ((some (j/jstr w)) w) (_ "")) ) ((none) "")))
       ((none) "")))
    ((err _) ""))

fn length1 xs: (List (List (Pair String j/Json))) -> Int64
  (listLength xs)

fn firstArgs xs: (List (List (Pair String j/Json))) -> (List (Pair String j/Json))
  (optionOr (listHead (listReverse xs)) (list))

fn ! runTests -> Bool
  (do (assert (testLive) "live bound chat")
      true)
