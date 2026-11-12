(module asl-cli/tests/remoteTargetTest
  :x [runTests]
  :i [(asl/packages/asl-cli/src/remoteTarget :a rt) (asl/packages/asl-cli/src/nativeCli :a nc)])

; (:m :ref REMOTE-TARGET :do "pure gate for the routing decision and the batch framing: profile parse (remote, local, malformed), --on NODE:UNIT and UNIT, --local overriding a profile, which verbs a profile routes and which stay local, that a forms batch is one remote argv element, and the launcher line; no child, no network, no file")
fn some? x: (Result (Option rt/Route) String) -> Bool
  (match x ((ok (some _)) true) (_ false))

fn local? x: (Result (Option rt/Route) String) -> Bool
  (match x ((ok (none)) true) (_ false))

fn refused? x: (Result (Option rt/Route) String) -> Bool
  (match x ((err e) (stringStartsWith? e "ERR_TARGET")) (_ false))

fn routed x: (Result (Option rt/Route) String) -> rt/Route
  (match x ((ok (some r)) r) (_ (rt/Route :node "?" :unit "?" :verb "?" :args (list))))

fn verbOf x: (Result (Option rt/Route) String) -> String
  (let [(r (routed x))] r.verb)

fn prof -> (Option rt/Target)
  (some (rt/Target :node "node2" :unit "RTPROBE"))

fn ! profiles -> Unit
  (let [(remote (rt/parseProfile "(:target :exec remote :node node2 :wt RTPROBE)\n"))
        (quotedNode (rt/parseProfile "(:target :exec remote :node \"node2\" :wt \"RTPROBE\")"))
        (dflt (rt/parseProfile "(:target :exec remote :wt RTPROBE)"))
        (named (rt/parseProfile "(:target :exec remote :node default :wt RTPROBE)"))]
    (do (assert (= remote (ok (some (rt/Target :node "node2" :unit "RTPROBE")))) "a remote profile names its node and worktree")
        (assert (= quotedNode remote) "quoted values read the same as symbols")
        (assert (= dflt (ok (some (rt/Target :node "" :unit "RTPROBE")))) "no :node is the default node")
        (assert (= named dflt) ":node default is the default node")
        (assert (= (rt/parseProfile "(:target :exec local :wt RTPROBE)") (ok (none))) ":exec local is no remote target")
        (assert (ok? (rt/parseProfile "(:target :exec remote :wt RTPROBE)")) "a well-formed profile parses")
        (assert (not (ok? (rt/parseProfile "(:target :exec remote :node node2)"))) "a remote profile without :wt is refused")
        (assert (not (ok? (rt/parseProfile "(:target :exec remote :wt a;rm)"))) "a worktree name outside [A-Za-z0-9-] is refused")
        (assert (not (ok? (rt/parseProfile "(:target :exec cloud :wt X)"))) "an unknown :exec is refused")
        (assert (not (ok? (rt/parseProfile "(:remote :host x)"))) "a file that is not a (:target ...) form is refused")))

fn ! onFlag -> Unit
  (let [(forms (rt/routeOf (list "--on" "node2:RTPROBE" "(:read :file \"a.asl\")" "(:flush)") (none)))
        (test (rt/routeOf (list "--on" "RTPROBE" "test" "x/aTest.asl") (none)))]
    (do (assert (some? forms) "--on routes forms with no profile")
        (assert (= (routed forms) (rt/Route :node "node2" :unit "RTPROBE" :verb "forms" :args (list "(:read :file \"a.asl\") (:flush)"))) "--on joins every forms argument into one batch")
        (assert (= (routed test) (rt/Route :node "" :unit "RTPROBE" :verb "test" :args (list "x/aTest.asl"))) "--on UNIT is the default node")
        (assert (= (routed (rt/routeOf (list "--on" "default:RTPROBE" "check" "a.asl") (none))) (rt/Route :node "" :unit "RTPROBE" :verb "check" :args (list "a.asl"))) "--on default:UNIT is the default node")
        (assert (= (verbOf (rt/routeOf (list "--on" "n:U" "rpc" "(:tools)") (none))) "forms") "rpc is a forms batch")
        (assert (refused? (rt/routeOf (list "--on" "node2:RTPROBE" "audit" "consistency") (none))) "--on refuses a verb it does not route")
        (assert (refused? (rt/routeOf (list "--on" "node2:RTPROBE" "test") (none))) "--on test without files is refused")
        (assert (refused? (rt/routeOf (list "--on" "a:b:c" "(:tools)") (none))) "--on with two colons is refused")
        (assert (refused? (rt/routeOf (list "--on" "node2:a/b" "(:tools)") (none))) "--on with a path-like unit is refused")
        (assert (refused? (rt/routeOf (list "--on") (none))) "--on without a spec is refused")))

fn ! profileRouting -> Unit
  (do (assert (local? (rt/routeOf (list "(:tools)") (none))) "no profile and no --on: forms stay local")
      (assert (local? (rt/routeOf (list "test" "a.asl") (none))) "no profile: test stays local")
      (assert (= (routed (rt/routeOf (list "(:tools)") (prof))) (rt/Route :node "node2" :unit "RTPROBE" :verb "forms" :args (list "(:tools)"))) "a remote profile routes forms")
      (assert (= (verbOf (rt/routeOf (list "  (:read :file \"x\")") (prof))) "forms") "leading blanks still read as forms")
      (assert (= (routed (rt/routeOf (list "test" "a.asl" "b.asl") (prof))) (rt/Route :node "node2" :unit "RTPROBE" :verb "test" :args (list "a.asl" "b.asl"))) "a remote profile routes test with its files")
      (assert (= (verbOf (rt/routeOf (list "check" "a.asl") (prof))) "check") "a remote profile routes check")
      (assert (local? (rt/routeOf (list "--local" "(:tools)") (prof))) "--local keeps forms local under a remote profile")
      (assert (local? (rt/routeOf (list "test" "--all") (prof))) "test --all stays local: a whole sweep is not sent")
      (assert (local? (rt/routeOf (list "test") (prof))) "a bare test stays local and is refused there as before")
      (assert (local? (rt/routeOf (list "audit" "consistency") (prof))) "audit stays local under a profile")
      (assert (local? (rt/routeOf (list "run" "tools/x.asl") (prof))) "run stays local under a profile")
      (assert (local? (rt/routeOf (list "launch" "claude") (prof))) "launch stays local under a profile"))

fn ! framing -> Unit
  (let [(batch "(:read :file \"a.asl\" :symbol \"f\") (:edit :file \"a.asl\" :old \"x\" :new \"y\") (:flush)")
        (fr (rt/remoteArgv (rt/Route :node "node2" :unit "U" :verb "forms" :args (list batch))))
        (tr (rt/remoteArgv (rt/Route :node "node2" :unit "U" :verb "test" :args (list "a/xTest.asl" "b/yTest.asl"))))]
    (do (assert (= fr (list "env" "-u" "ASL_ROOT" "-u" "ASL_PRELUDE" "./bin/asl" batch)) "a forms batch is one argv element after a clean env: one remote asl call")
        (assert (= (listLength (filter (fn [(a String)] -> Bool (stringContains? a "(:")) fr)) 1) "exactly one element carries forms")
        (assert (= tr (list "env" "-u" "ASL_ROOT" "-u" "ASL_PRELUDE" "nice" "-n" "10" "./bin/asl" "test" "a/xTest.asl" "b/yTest.asl")) "test runs niced with its files in order")
        (assert (= (rt/timeoutOf (rt/Route :node "" :unit "U" :verb "test" :args (list))) 1800) "a remote test may run 30 minutes")
        (assert (= (rt/timeoutOf (rt/Route :node "" :unit "U" :verb "forms" :args (list))) 600) "remote forms are bounded at 10 minutes")
        (assert (= (rt/onArgv "/r" (rt/Route :node "" :unit "U" :verb "forms" :args (list batch))) (list "/r/tools/remote/on.asl" "default" "U" "forms" batch)) "the local hop names on.asl with the default node spelled out")
        (assert (= (rt/onArgv "/r" (rt/Route :node "node2" :unit "U" :verb "check" :args (list "a.asl"))) (list "/r/tools/remote/on.asl" "node2" "U" "check" "a.asl")) "the local hop keeps a named node")))

fn ! promptHook -> Unit
  (let [(line (rt/promptLine (rt/Target :node "node2" :unit "RTPROBE")))]
    (do (assert (stringContains? line "node2:wt/RTPROBE") "the launcher line names node and worktree")
        (assert (stringContains? line "asl forms") "the launcher line points at asl forms")
        (assert (stringContains? line "stale") "the launcher line warns that local tools see a stale tree")
        (assert (not (stringContains? line "\n")) "the launcher line is one line")
        (assert (= (rt/profileRel) ".asl/target.asn") "the profile lives at .asl/target.asn")))

fn ! nativeLane -> Unit
  (do (assert (= (nc/verbKind (list "--on" "node2:U" "(:tools)")) "native") "--on runs on the native CLI, never the retired host")
      (assert (= (nc/verbKind (list "--local" "(:tools)")) "native") "--local runs on the native CLI, never the retired host"))

fn ! runTests -> Bool
  (do (profiles) (onFlag) (profileRouting) (framing) (promptHook) (nativeLane) true)
