(module asl-tools/coord/tests/stubHostJailTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (aslAgent/jail :a jl) (aslAgent/gitOps :a go)])

; (:m :ref N2-COORD-REDS :do "the stand-in host of hermetic gate fixtures must exist inside the jail of a unit child, because Leon runs a unit's gates there: on node2 (bwrap) it lived under /tmp, which the jail replaces with an empty tmpfs, so the gate ended 127 and conductorWireTest and pipeE2eTest were red on Linux only. Two claims: the stand-in dir is under no directory the Linux jail masks (read from bwrapArgs, so it fails on any host), and a gate in the declared form run through runGatesIn!, the jailed path, executes the stand-in on this host")
fn ! scratch -> String
  (str (resultOr (realPath ".") ".") "/.asl/cache/stubHostJailTest-" (stringFromInt64 (procSelf)))

fn ! cleanup dir: String -> Bool
  (= (fr/runOneLimited (fr/job (list "rm" "-rf" dir) "." (fr/childEnv (list))) (fr/limits 60 4)).exit 0)

fn under? p: String base: String -> Bool
  (or (= p base) (stringStartsWith? p (str base "/")))

; (:m :do "the directories a bwrap argv replaces with an empty tmpfs: every word after --tmpfs")
fn maskedOf args: (List String) acc: (List String) -> (List String)
  (match (listHead args)
    ((none) (listReverse acc))
    ((some a)
      (let [(rest (optionOr (listTail args) (list)))]
        (if (= a "--tmpfs")
          (maskedOf (optionOr (listTail rest) (list)) (cons (optionOr (listHead rest) "") acc))
          (maskedOf rest acc)))))

fn ! runTests -> Bool
  (let [(root (scratch))
        (_ (cleanup root))
        (made (and (ok? (dirCreate root)) (ok? (fileWrite (str root "/green3.asl") "\n"))))
        (stub (fr/stubHost!))
        (stubDir (optionOr (stringSlice stub 0 (- (stringLength stub) (stringLength "/bin/asl"))) ""))
        (realHome (resultOr (realPath (optionOr (envGet "HOME") "")) ""))
        (linux (jl/Jail :mode "os" :tool "/usr/bin/bwrap" :root root :writes (list root (jl/jailHome root)) :reads (list) :lists (list) :realHome realHome :net false))
        (masked (maskedOf (jl/bwrapArgs linux) (list)))
        (hiding (filter (fn [(m String)] -> Bool (under? stubDir m)) masked))
        (recs (go/runGatesIn! (list (pair "g1" (str stub " test green3.asl"))) root 60 (none) (none) (str root "/gateTimes.asn")))
        (gateText (go/serRecs "gates" recs))
        (removed (fr/stubRemove!))
        (gone (and (cleanup root) (not (fileExists? root))))]
    (do (assert (and made (and (stringEndsWith? stub "/bin/asl") (stringStartsWith? stubDir (fr/stubPrefix)))) (str "fixture: a scratch root and this process's stand-in host: " stub))
        (assert (and (listContains? masked "/tmp") (and (listContains? masked "/run") (or (stringEmpty? realHome) (listContains? masked realHome)))) (str "control: the Linux jail masks /tmp, /run and the real HOME: " (stringJoin masked " ")))
        (assert (listEmpty? hiding) (str "the stand-in host dir " stubDir " is under no directory the Linux jail masks, found under: " (stringJoin hiding " ")))
        (assert (stringContains? gateText "green3.asl: 3 assertion(s) executed (3 passed)") (str "a gate in the declared form, run as a jailed unit child, executes the stand-in host: " gateText))
        (assert (and removed gone) "the stand-in and the scratch root are removed")
        true))
