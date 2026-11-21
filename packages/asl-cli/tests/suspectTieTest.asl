(module asl-cli/tests/suspectTieTest
  :x [runTests]
  :i [(asl-tools/fleet/run :a fr) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-cli/src/nativeRefresh :a nr)])

; (:m :ref SUSPECT-TIE-ALIGN :do "a dep whose mtime ties the stamp is stale in all three judges (tools/fleet/train.asl#suspect? >=, bin/asl#suspect, asl-cli/nativeRefresh#depSuspect?), so a same-tick edit is never served by the old CLI; bin/asl runs on bash 3.2 on macOS, whose -nt and -ot compare whole seconds, so a refresh that finds the CLI fresh rewrites its head and the next call is warm once the second has passed")
fn sec -> Int64
  1000000000

fn ! mtime path: String -> Int64
  (match (fileStat path) ((ok st) st.mtimeNs) ((err _) 0))

fn ! suspectLine! root: String -> String
  (optionOr (listHead (filter (fn [(l String)] -> Bool (stringStartsWith? l "suspect() {")) (stringLines (resultOr (fileReadString (str root "/bin/asl")) "")))) "")

fn ! bashSays! line: String tree: String dir: String stamp: String -> String
  (bashMode! line tree dir stamp "")

; (:m :ref SUSPECT-TIE-ALIGN :do "a third argument asks bin/asl#suspect whether a source moved past a mark (the failed-rebuild mark of bg): there a tie is not a move, or a rebuild that failed in the same second as its mark would start again")
fn ! bashMode! line: String tree: String dir: String stamp: String mode: String -> String
  (let [(script (str line "\nR=$1; if suspect \"$2\" \"$3\" $4; then echo suspect; else echo fresh; fi\n"))
        (d (fr/runOneLimited (fr/job (list "/bin/bash" "-c" script "suspectTie" tree dir stamp mode) tree (fr/childEnv (list))) (fr/limits 30 4)))]
    (if (= d.exit 0) (stringTrim d.out) (str "exit " (stringFromInt64 d.exit) " " d.out)))

fn ! at! path: String ns: Int64 -> Bool
  (ok? (fileUtime path ns))

fn noBuild r: String c: String -> Int64
  99

fn ! runTests -> Bool
  (let [(ws (resultOr (realPath ".") "."))
        (base (optionOr (envGet "TMPDIR") "/tmp"))
        (tree (str base "/suspectTieTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs))))
        (dir (str tree "/cli"))
        (cache (str tree "/cache"))
        (dep (str tree "/a.asl"))
        (made (and (ok? (dirCreate dir)) (ok? (dirCreate cache))))
        (wrote (and made (and (ok? (fileWrite dep "x\n")) (and (ok? (fileWrite (str dir "/deps") "a.asl\n")) (ok? (fileWrite (str dir "/bin") "#!/bin/sh\n"))))))
        (head (nc/headPath cache tree))
        (headed (and wrote (ok? (fileWrite head (str dir "\n")))))
        (t (- (nowNs) (* 100 (sec))))
        (line (suspectLine! ws))
        (tieSet (and (at! dep t) (at! head t)))
        (tieAsl (nr/suspect? tree dir head))
        (tieSh (bashSays! line tree dir head))
        (tieMark (bashMode! line tree dir head "moved"))
        (olderSet (at! dep (- t (* 2 (sec)))))
        (olderAsl (nr/suspect? tree dir head))
        (olderSh (bashSays! line tree dir head))
        (newerSet (at! dep (+ t (* 2 (sec)))))
        (newerAsl (nr/suspect? tree dir head))
        (newerSh (bashSays! line tree dir head))
        (newerMark (bashMode! line tree dir head "moved"))
        (freshSet (and (at! dep (- t (* 20 (sec)))) (at! head (- t (* 10 (sec))))))
        (began (nowNs))
        (rc (nr/refreshBody! tree cache (list "version") noBuild))
        (headAfter (mtime head))
        (removed (fr/runOneLimited (fr/job (list "/bin/rm" "-rf" tree) base (fr/childEnv (list))) (fr/limits 60 4)))]
    (do
      (assert (and headed (stringStartsWith? line "suspect() {")) (str "fixture CLI dir, head and bin/asl#suspect are in place: " line))
      (assert (and tieSet tieAsl) "nativeRefresh: a dep whose mtime equals the head's is suspect")
      (assert (= tieSh "suspect") (str "bin/asl: a dep whose mtime equals the head's is suspect: " tieSh))
      (assert (= tieMark "fresh") (str "bin/asl: against the failed mark a tie is no move: " tieMark))
      (assert (and olderSet (not olderAsl)) "nativeRefresh: a dep 2 s older than the head is fresh")
      (assert (= olderSh "fresh") (str "bin/asl: a dep 2 s older than the head is fresh: " olderSh))
      (assert (and newerSet newerAsl) "nativeRefresh: a dep 2 s newer than the head is suspect")
      (assert (= newerSh "suspect") (str "bin/asl: a dep 2 s newer than the head is suspect: " newerSh))
      (assert (= newerMark "suspect") (str "bin/asl: against the failed mark a dep 2 s newer has moved: " newerMark))
      (assert (and freshSet (= rc 0)) (str "a refresh that finds the CLI fresh exits 0 without building: rc " (stringFromInt64 rc)))
      (assert (>= headAfter (- began (sec))) (str "that refresh rewrites the head, so a whole-second shell tie clears: head mtime " (stringFromInt64 headAfter) " began " (stringFromInt64 began)))
      (assert (= removed.exit 0) "the fixture tree is removed")
      true))
