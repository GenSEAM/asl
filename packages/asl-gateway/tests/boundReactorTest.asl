(module aslGateway/tests/boundReactorTest
  :x [runTests]
  :i [(server :a srv)
      (sessions :a s)
      (aslGateway/chat :a ch)
      (aslGateway/config :a c)
      (aslGateway/poolDispatch :a pd)
      (aslGateway/breaker :a b)
      (aslGateway/upstream :a u)
      (aslGateway/dispatch :a dp)
      (aslGateway/omniApi :a om)
      (asl-json/json :a j)])

; (:m :ref GW-SESSION-BIND :do "REACTOR-BLOCK gate by ordering, not timing: while a bound CLI turn runs (the vendor sleeps), a second request is served to completion first, and the bound turn stays parked until the child ends")
fn fakeProgram -> String
  "BEGIN{sd=ARGV[1]; n=ARGC-1; prompt=ARGV[n]; id=\"\"; for(i=2;i<n;i++) if(ARGV[i]==\"--resume\") id=ARGV[i+1]; resumed=(id!=\"\"); if(!resumed){f=sd \"/counter\"; c=0; getline c < f; close(f); c++; print c > f; close(f); id=\"fake-\" c} ctxf=sd \"/ctx-\" id; mem=\"\"; while((getline l < ctxf)>0) mem=mem l \"|\"; close(ctxf); print prompt >> ctxf; close(ctxf); af=sd \"/argv-\" id; print \"TURN resumed=\" resumed >> af; for(i=2;i<=n;i++) print \"ARG<\" ARGV[i] \">\" >> af; close(af); printf \"{\\\"session_id\\\":\\\"%s\\\",\\\"result\\\":\\\"seen=%s now=%s can=%s lst=%s\\\",\\\"usage\\\":{\\\"input_tokens\\\":3,\\\"output_tokens\\\":4}}\\n\", id, mem, prompt, ENVIRON[\"ASLCANARY\"], ENVIRON[\"ASLLISTED\"]; exit 0}"

fn slowProgram -> String
  (stringReplace (fakeProgram) "BEGIN{sd=ARGV[1];" "BEGIN{sd=ARGV[1]; slowf=sd \"/slow\"; if((getline z < slowf)>0){close(slowf); system(\"sleep \" z)} ")

fn emptyLoop home: String -> srv/GatewayLoop
  (srv/GatewayLoop :listener -1 :upstreamPort 0 :env (mapEmpty) :home home :rootDir "/tmp" :registryPath "/tmp/absent.asn"
     :promptMaxBytes 188000 :conns (list) :pools (pd/emptyPoolRegistry) :replies (list) :breaker (b/defaultBreakerState)
     :buckets (u/emptyBucketRegistry) :profiles (c/emptyProfilesCache)
     :wiring (dp/emptyWiring (u/UpstreamSettings :geminiUrl "" :geminiKey "" :groqUrl "" :ollamaUrl "" :groqKey "" :url "" :key "" :ollamaTimeoutSec 45.0))
     :wiringText none :families (list) :outbox (list) :pendingCall none :spreadState (mapEmpty) :spreadLast429 (mapEmpty) :omni (om/emptyOmniState (om/Word64 :hi 0 :lo 0) (om/Word64 :hi 0 :lo 0)) :admitWaits (list) :limitRows (list) :limitSeededMs 0 :startMs 0)

fn onlyConn lp: srv/GatewayLoop fd: Int64 -> srv/GatewayLoop
  (with lp :conns (filter (fn [(cn srv/GatewayConn)] -> Bool (= cn.fd fd)) lp.conns))

fn phaseOf lp: srv/GatewayLoop fd: Int64 -> String
  (match (listHead (filter (fn [(cn srv/GatewayConn)] -> Bool (= cn.fd fd)) lp.conns))
    ((none) "gone")
    ((some cn) (match cn.phase
                 ((srv/connCli _ _ _ _) "cli")
                 ((srv/connWriting _) "writing")
                 ((srv/connReading) "reading")
                 (_ "other"))))

fn writingData lp: srv/GatewayLoop fd: Int64 -> String
  (match (listHead (filter (fn [(cn srv/GatewayConn)] -> Bool (= cn.fd fd)) lp.conns))
    ((none) "")
    ((some cn) (match cn.phase ((srv/connWriting d) d) (_ ""))))

fn ! spin! lp: srv/GatewayLoop fd: Int64 fuel: Int64 -> srv/GatewayLoop
  (if (or (<= fuel 0) (!= (phaseOf lp fd) "cli"))
    lp
    (do (sleepMs 30) (spin! (srv/gatewayTurn! lp (list)) fd (- fuel 1))))

fn doneStep body: String -> ch/ChatStep
  (ch/stepDone (ch/ChatResponse :head (list (ch/headStatus 200)) :body body))

fn cliStep args: (List (Pair String j/Json)) -> ch/ChatStep
  (ch/stepEffect (ch/effCli "claude" args)
    (fn [(o ch/ChatOutcome)] -> ch/ChatStep
      (match o
        ((ch/outCli (some r)) (doneStep r.text))
        (_ (doneStep "none")))))

fn ! testReactor -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (home (str "/tmp/aslBrt" me))
        (sd (str home "/state"))
        (_d1 (dirCreate home))
        (_d2 (dirCreate (str home "/.asl")))
        (_d3 (dirCreate sd))
        (_prog (fileWrite (str home "/fake.awk") (slowProgram)))
        (_slow (fileWrite (str sd "/slow") "3"))
        (_cfg (fileWrite (str home "/.asl/gateway.asn")
                (str "(:gateway :sessionsTimeoutSec 30 :sessions ((:vendor \"claude\" :bin \"/usr/bin/awk\" :first (\"-f\" \"" home "/fake.awk\" \"" sd "\") :resume (\"-f\" \"" home "/fake.awk\" \"" sd "\" \"--resume\" \"{id}\") :idFrom \"session_id\" :replyFrom \"result\")))")))
        (ctx (s/sessCtxAt! home (envList)))
        (args (list (pair "session" (j/jstr "reactor-1"))
                    (pair "messages" (j/jarr (list (j/jobj (list (pair "role" (j/jstr "user")) (pair "content" (j/jstr "hello")))))))
                    (pair "system_prompt" (j/jstr "SYS")) (pair "no_tools" (j/jbool true)) (pair "workspace" (j/jstr "/tmp")) (pair "model" (j/jstr ""))))
        (loop0 (emptyLoop home))
        (loop1 (srv/drive! loop0 71 "" (cliStep args)))
        (loop2 (srv/drive! loop1 72 "" (doneStep "second")))
        (phase71 (phaseOf loop2 71))
        (phase72 (phaseOf loop2 72))
        (rowEarly (fileExists? (s/sessRowPath ctx (s/sessKeyName "reactor-1"))))
        (second (writingData loop2 72))
        (loop3 (spin! (onlyConn loop2 71) 71 600))
        (phase71b (phaseOf loop3 71))
        (first (writingData loop3 71))
        (rowLate (fileExists? (s/sessRowPath ctx (s/sessKeyName "reactor-1"))))
        (_rm (pathRemove home))]
    (do (assert (= phase71 "cli") "the bound turn is parked in connCli, not run to completion inside drive!")
        (assert (= phase72 "writing") "a request that arrives while the vendor runs is served to completion")
        (assert (not rowEarly) "at that moment the vendor has not finished: the second reply arrived before the first")
        (assert (stringContains? second "second") "the second request's reply is the one written first")
        (assert (= phase71b "writing") "the parked bound turn resumes when the child ends")
        (assert (stringContains? first "now=hello") "and carries the vendor's reply")
        (assert rowLate "the binding is stored when the turn finishes")
        true))

fn ! runTests -> Bool
  (do (assert (testReactor) "reactor")
      true)
