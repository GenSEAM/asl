(module aslGateway/tests/bindingTest
  :x [runTests]
  :i [(sessions :a s)
      (binding :a b)])

fn fakeProgram -> String
  "BEGIN{sd=ARGV[1]; n=ARGC-1; prompt=ARGV[n]; id=\"\"; for(i=2;i<n;i++) if(ARGV[i]==\"--resume\") id=ARGV[i+1]; resumed=(id!=\"\"); if(!resumed){f=sd \"/counter\"; c=0; getline c < f; close(f); c++; print c > f; close(f); id=\"fake-\" c} ctxf=sd \"/ctx-\" id; mem=\"\"; while((getline l < ctxf)>0) mem=mem l \"|\"; close(ctxf); print prompt >> ctxf; close(ctxf); af=sd \"/argv-\" id; print \"TURN resumed=\" resumed >> af; for(i=2;i<=n;i++) print \"ARG<\" ARGV[i] \">\" >> af; close(af); printf \"{\\\"session_id\\\":\\\"%s\\\",\\\"result\\\":\\\"seen=%s now=%s can=%s lst=%s\\\",\\\"usage\\\":{\\\"input_tokens\\\":3,\\\"output_tokens\\\":4}}\\n\", id, mem, prompt, ENVIRON[\"ASLCANARY\"], ENVIRON[\"ASLLISTED\"]; exit 0}"

fn fakeVendor name: String sd: String -> s/SessVendor
  (s/SessVendor :name name :bin "/usr/bin/awk" :env (list) :first (list (fakeProgram) sd) :resume (list (fakeProgram) sd "--resume" "{id}")
                :idFrom "session_id" :replyFrom "result" :wrap "" :wrapResume "" :sep "" :modelArgs (list "--model" "{model}") :fork (list "--fork-session"))

fn noForkVendor name: String sd: String -> s/SessVendor
  (s/SessVendor :name name :bin "/usr/bin/awk" :env (list) :first (list (fakeProgram) sd) :resume (list (fakeProgram) sd "--resume" "{id}")
                :idFrom "session_id" :replyFrom "result" :wrap "" :wrapResume "" :sep "" :modelArgs (list) :fork (list))

fn jsonEsc t: String -> String
  (stringReplace (stringReplace (stringReplace t "\\" "\\\\") "\"" "\\\"") "\n" "\\n")

fn msg role: String text: String -> String
  (str "{\"role\":\"" role "\",\"content\":\"" (jsonEsc text) "\"}")

fn body model: String user: String msgs: (List String) -> String
  (str "{\"model\":\"" model "\"" (if (stringEmpty? user) "" (str ",\"session\":\"" user "\"")) ",\"messages\":[" (stringJoin msgs ",") "]}")

fn nm key: String -> String
  (s/sessKeyName key)

fn replyOf receipt: String -> String
  (optionOr (listHead (s/sessKeyValues receipt "reply")) "")

fn lastTurn text: String -> String
  (optionOr (listLast (stringSplit text "TURN resumed=")) "")

fn ! sendBody! ctx: s/SessCtx vendor: String header: String model: String user: String msgs: (List String) -> String
  (b/boundChatBody! ctx vendor header (body model user msgs))

fn ! rd path: String -> String
  (resultOr (fileReadString path) "")

(schema Seen
  (:f r1 String)
  (:f r2 String)
  (:f argv1 String)
  (:f row1 String)
  (:f r3 String)
  (:f argv3 String)
  (:f c2a String)
  (:f c2b String)
  (:f c3a String)
  (:f c3b String)
  (:f ttlA String)
  (:f ttlB String)
  (:f argvModel String)
  (:f ledger String)
  (:f hdr String)
  (:f hdrFile Bool)
  (:f userFile Bool)
  (:f noKey String)
  (:f spaceKey String)
  (:f spaceFile Bool)
  (:f busy String)
  (:f fork String)
  (:f forkSend String)
  (:f argvFork String)
  (:f noFork String)
  (:f forget String)
  (:f forgetAgain String)
  (:f short String))

fn ! observe! ctx: s/SessCtx ttlCtx: s/SessCtx dir: String sd: String -> Seen
  (let [(r1 (sendBody! ctx "fake" "" "m1" "caller-1" (list (msg "user" "hello"))))
        (a1 (replyOf r1))
        (r2 (sendBody! ctx "fake" "" "m1" "caller-1" (list (msg "user" "hello") (msg "assistant" a1) (msg "user" "again"))))
        (argv1 (lastTurn (rd (str sd "/argv-fake-1"))))
        (row1 (rd (str dir "/sessions/" (nm "caller-1") ".asn")))
        (a2 (replyOf r2))
        (r3 (sendBody! ctx "fake" "" "m1" "caller-1" (list (msg "user" "changed") (msg "assistant" a1) (msg "user" "x") (msg "assistant" a2) (msg "user" "y"))))
        (argv3 (rd (str sd "/argv-fake-2")))
        (k2a (sendBody! ctx "fake" "" "m1" "caller-2" (list (msg "user" "q1"))))
        (k2b (sendBody! ctx "fake2" "" "m1" "caller-2" (list (msg "user" "q1") (msg "assistant" (replyOf k2a)) (msg "user" "q2"))))
        (k3a (sendBody! ctx "fake" "" "m1" "caller-3" (list (msg "user" "q1"))))
        (k3b (sendBody! ctx "fake" "" "m2" "caller-3" (list (msg "user" "q1") (msg "assistant" (replyOf k3a)) (msg "user" "q2"))))
        (t1 (sendBody! ttlCtx "fake" "" "m1" "caller-ttl" (list (msg "user" "q1"))))
        (slept (sleepMs 2100))
        (t2 (sendBody! ttlCtx "fake" "" "m1" "caller-ttl" (list (msg "user" "q1") (msg "assistant" (replyOf t1)) (msg "user" "q2"))))
        (argvModel (rd (str sd "/argv-fake-1")))
        (ledger (rd (str dir "/ledger.asn")))
        (hdr (sendBody! ctx "fake" "hdr-1" "m1" "body-user" (list (msg "user" "h"))))
        (hdrFile (fileExists? (str dir "/sessions/" (nm "hdr-1") ".asn")))
        (userFile (fileExists? (str dir "/sessions/" (nm "body-user") ".asn")))
        (noKey (sendBody! ctx "fake" "" "m1" "" (list (msg "user" "h"))))
        (spaceKey (sendBody! ctx "fake" "" "m1" "has space/key" (list (msg "user" "h"))))
        (spaceFile (fileExists? (str dir "/sessions/" (s/sessKeyName "has space/key") ".asn")))
        (lockB (pathSymlink (str (stringFromInt64 (procSelf)) ":1") (str dir "/sessions/" (nm "caller-2") ".lock")))
        (busy (sendBody! ctx "fake" "" "m1" "caller-2" (list (msg "user" "z"))))
        (unlock (pathRemove (str dir "/sessions/" (nm "caller-2") ".lock")))
        (fork (s/sessFork! ctx (nm "caller-1") "caller-1-fork"))
                (forkSend (sendBody! ctx "fake" "" "m1" "caller-1-fork" (list (msg "user" "changed") (msg "assistant" a1) (msg "user" "x") (msg "assistant" a2) (msg "user" "y") (msg "assistant" (replyOf r3)) (msg "user" "after fork"))))
        (argvFork (rd (str sd "/argv-fake-2")))
        (nf (sendBody! ctx "nofork" "" "m1" "caller-nf" (list (msg "user" "q"))))
        (noFork (s/sessFork! ctx (nm "caller-nf") "caller-nf-fork"))
        (forget (s/sessStop! ctx (nm "caller-2")))
        (forgetAgain (s/sessStop! ctx (nm "caller-2")))
        (short (sendBody! ctx "fake" "" "m1" "caller-3" (list (msg "user" "only one"))))]
    (Seen :r1 r1 :r2 r2 :argv1 argv1 :row1 row1 :r3 r3 :argv3 argv3 :c2a k2a :c2b k2b :c3a k3a :c3b k3b :ttlA t1 :ttlB t2
          :argvModel argvModel :ledger ledger :hdr hdr :hdrFile hdrFile :userFile userFile :noKey noKey :spaceKey spaceKey
          :spaceFile spaceFile :busy busy :fork fork :forkSend forkSend :argvFork argvFork :noFork noFork :forget forget
          :forgetAgain forgetAgain :short short))

fn testDecide -> Bool
  (let [(m1 (b/BMsg :role "user" :text "a"))
        (m2 (b/BMsg :role "assistant" :text "b"))
        (m3 (b/BMsg :role "user" :text "c"))
        (row (s/SessRow :name "k" :vendor "v" :cwd "/" :args (list) :sessionId "S1" :startedAt 10 :updatedAt 100 :turns 1
                        :key "k" :model "m" :digest (b/bindDigest (list m1 m2)) :delivered 2 :usageIn 0 :usageOut 0 :fork false :kind "binding" :ctxDigest "cd"))]
    (do (assert (= (b/bindRender (list m1)) "a") "one user message renders as its bare text")
        (assert (= (b/bindRender (list m1 m2)) "user: a\n\nassistant: b") "several messages render with role labels")
        (assert (not (= (b/bindDigest (list m1 m2)) (b/bindDigest (list m2 m1)))) "the digest depends on order")
        (assert (not (= (b/bindDigest (list m1)) (b/bindDigest (list (b/BMsg :role "user" :text "a2"))))) "the digest depends on content")
        (assert (let [(p (b/bindDecide (some row) "v" "m" "cd" (list m1 m2 m3) 150 0))] (and p.resume (and (= p.id "S1") (= p.prompt "c")))) "a matching prefix resumes with only the new message")
        (assert (= (b/bindDecide none "v" "m" "cd" (list m1) 150 0).why "noBinding") "no row is a replay")
        (assert (= (b/bindDecide (some row) "w" "m" "cd" (list m1 m2 m3) 150 0).why "vendorSwitch") "another vendor replays")
        (assert (= (b/bindDecide (some row) "v" "n" "cd" (list m1 m2 m3) 150 0).why "modelSwitch") "another model replays")
        (assert (= (b/bindDecide (some row) "v" "m" "cd" (list m3 m2 m3) 150 0).why "diverged") "a changed prefix replays")
        (assert (= (b/bindDecide (some row) "v" "m" "cd" (list m1 m2 m3) 150 20).why "expired") "an old binding replays")
        (assert (b/bindDecide (some row) "v" "m" "cd" (list m1 m2 m3) 150 100).resume "a binding inside its TTL resumes")
        (assert (= (b/bindDecide (some row) "v" "m" "cd" (list m1 m2) 150 0).why "noNewMessage") "a request with nothing new replays")
        (assert (not (b/bindDecide (some row) "v" "m" "cd" (list m3 m2 m3) 150 0).resume) "a diverged request carries no resume id")
        true))

fn testLive -> Bool
  (let [(me (stringFromInt64 (procSelf)))
        (dir (str "/tmp/aslBindingTest" me))
        (sd (str dir "/state"))
        (vendors (list (fakeVendor "fake" sd) (fakeVendor "fake2" sd) (noForkVendor "nofork" sd)))
        (ctx (s/SessCtx :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 0 :ledger (str dir "/ledger.asn") :vendors vendors))
        (ttlCtx (s/SessCtx :dir (str dir "/sessions") :env (envList) :timeoutSec 20 :ttlSec 1 :ledger "" :vendors vendors))
        (_mk (dirCreate sd))
        (seen (observe! ctx ttlCtx dir sd))
        (_rm (pathRemove dir))]
    (do (assert (stringContains? seen.r1 ":resumed false :why \"noBinding\"") "the first request replays into a new vendor session")
        (assert (stringContains? seen.r1 ":sessionId \"fake-1\"") "the vendor session id is stored")
        (assert (stringContains? seen.r2 ":resumed true :why \"resumed\"") "the second request with the same caller key resumes")
        (assert (stringContains? seen.r2 ":sessionId \"fake-1\"") "it resumes the same vendor session")
        (assert (stringContains? seen.r2 "seen=hello|") "the vendor remembered the first turn")
        (assert (stringContains? seen.argv1 "ARG<--resume>\nARG<fake-1>") "the resume flag and stored id reach the vendor")
        (assert (stringContains? seen.argv1 "ARG<again>") "only the new message is sent")
        (assert (not (stringContains? seen.argv1 "hello")) "the earlier messages are not replayed")
        (assert (stringContains? seen.row1 ":delivered 4") "the row counts the delivered messages including the reply")
        (assert (stringContains? seen.row1 ":usageIn 6 :usageOut 8") "usage accumulates per binding")
        (assert (stringContains? seen.r3 ":resumed false :why \"diverged\"") "a changed prefix starts a fresh vendor session")
        (assert (stringContains? seen.r3 ":sessionId \"fake-2\"") "the fresh session has a new id")
        (assert (not (stringContains? seen.argv3 "--resume")) "a diverged request carries no resume flag")
        (assert (stringContains? seen.argv3 "user: changed") "the diverged request replays the whole transcript")
        (assert (stringContains? seen.argv3 "user: y") "the replay includes the newest message")
        (assert (stringContains? seen.c2b ":resumed false :why \"vendorSwitch\"") "a vendor switch invalidates the binding")
        (assert (stringContains? seen.c3b ":resumed false :why \"modelSwitch\"") "a model switch invalidates the binding")
        (assert (stringContains? seen.ttlB ":resumed false :why \"expired\"") "a binding past its TTL replays")
        (assert (stringContains? seen.argvModel "ARG<--model>\nARG<m1>") "the model flag comes from the vendor row")
        (assert (stringContains? seen.ledger (str "binding:" (nm "caller-1"))) "a usage ledger row is tagged with the binding name")
        (assert (stringContains? seen.ledger "cliBinding") "the ledger row names the binding api")
        (assert (stringContains? seen.hdr (str ":name \"" (nm "hdr-1") "\"")) "the header key wins over the body user")
        (assert seen.hdrFile "the header-keyed binding is stored")
        (assert (not seen.userFile) "the body user is not used when a header key exists")
        (assert (stringContains? seen.noKey ":code noCallerKey") "a request without a key is refused for binding")
        (assert (stringContains? seen.spaceKey ":status ok") "an arbitrary key is accepted")
        (assert seen.spaceFile "an arbitrary key is stored under a hashed file name")
        (assert (stringContains? seen.busy ":code busy") "a second concurrent turn on one binding is busy")
        (assert (stringContains? seen.fork ":op fork") "fork copies a binding")
        (assert (stringContains? seen.forkSend ":resumed true") "the forked binding resumes the copied session")
        (assert (stringContains? seen.argvFork "ARG<--fork-session>") "the first turn of a fork runs the vendor's fork args")
        (assert (stringContains? seen.noFork ":code noFork") "fork is refused when the vendor row has no fork args")
        (assert (stringStartsWith? seen.forget "(:session :op stop :status ok") "forget removes a binding")
        (assert (stringContains? seen.forgetAgain ":code noSession") "a forgotten binding is gone")
        (assert (stringContains? seen.short ":resumed false") "a request that adds nothing new replays")
        true))

fn ! runTests -> Bool
  (do (assert (testDecide) "decision checks")
      (assert (testLive) "live bindings")
      true)
