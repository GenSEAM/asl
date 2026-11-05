(module asl/tools/vcs/tests/vcsTest
  :x [runTests]
  :i [(asl-tools/vcs/vcs :a v) (asl-tools/vcs/git :a gb) (asl-tools/fleet/run :a fr)])

; (:m :ref VCS-LAYER-CORE :do "the vcs layer over temp repos: a commit with an unbalanced file, a partial check (slow stub as asl binary), an empty or widening path list refuse and leave HEAD; a good file commits exactly the named path even with another file staged; a repo-level core.hooksPath hook that writes a marker does not run; stage never touches unnamed paths")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/vcsTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> fr/Done
  (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args))

fn goodAsl -> String
  "(module fx/good\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"

fn goodMsg -> String
  "(:c :a fixture :do \"a clean change\" :g \"gate\" :ev (VCS-LAYER-CORE))\n"

fn ! repoAt base: String name: String -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/scripts/audit"))).exit 0) (str name ": dir"))
        (assert (= (git dir (list "init" "-q" "-b" "main")).exit 0) (str name ": init"))
        (assert (put (str dir "/scripts/audit/foreignBaseline.asn") "(:foreignBaseline :v 1\n)\n") (str name ": baseline"))
        (assert (= (git dir (list "add" "-A")).exit 0) (str name ": add"))
        (assert (= (git dir (list "commit" "-q" "-m" "base")).exit 0) (str name ": base commit"))
        dir))

fn ! head dir: String -> String
  (stringTrim (git dir (list "rev-parse" "HEAD")).out)

fn ! committed dir: String -> String
  (stringTrim (git dir (list "show" "--name-only" "--format=" "HEAD")).out)

fn ! stubRoot! base: String name: String body: String -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/bin"))).exit 0) (str name ": stub dir"))
        (assert (put (str dir "/bin/asl") body) (str name ": stub body"))
        (assert (= (sh "." (list "chmod" "+x" (str dir "/bin/asl"))).exit 0) (str name ": stub exec"))
        (assert (put (str dir "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 1\n)\n") (str name ": stub config"))
        dir))

fn ! scenarios root: String base: String -> Bool
  (let [(slow (stubRoot! base "slowRoot" "#!/bin/sh\nsleep 20\n"))
        (r1 (repoAt base "bad"))
        (_a (put (str r1 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (h1 (head r1))
        (o1 (v/commit! r1 root (list "bad.asl") (goodMsg) "commit"))
        (r2 (repoAt base "slow"))
        (_b (put (str r2 "/good.asl") (goodAsl)))
        (h2 (head r2))
        (o2 (v/commit! r2 slow (list "good.asl") (goodMsg) "commit"))
        (r3 (repoAt base "empty"))
        (h3 (head r3))
        (o3 (v/commit! r3 root (list) (goodMsg) "commit"))
        (o3b (v/commit! r3 root (list ".") (goodMsg) "commit"))
        (o3c (v/stage! r3 (list)))
        (r4 (repoAt base "good"))
        (_c (put (str r4 "/good.asl") (goodAsl)))
        (_d (put (str r4 "/other.asl") "(module fx/other\n"))
        (_e (git r4 (list "add" "other.asl")))
        (_f0 (sh "." (list "mkdir" "-p" (str r4 "/hooks"))))
        (_f (put (str r4 "/hooks/pre-commit") "#!/bin/sh\ntouch hookRan\n"))
        (_g (sh r4 (list "chmod" "+x" "hooks/pre-commit")))
        (_h (git r4 (list "config" "core.hooksPath" (str r4 "/hooks"))))
        (_n (put (str r4 "/stray.txt") "stray\n"))
        (h4 (head r4))
        (o4 (v/commit! r4 root (list "good.asl") (goodMsg) "commit"))
        (st4 (v/status! r4 (list)))
        (r5 (repoAt base "ctl"))
        (_i (sh "." (list "mkdir" "-p" (str r5 "/hooks"))))
        (_j (put (str r5 "/hooks/pre-commit") "#!/bin/sh\ntouch hookRan\n"))
        (_k (sh r5 (list "chmod" "+x" "hooks/pre-commit")))
        (_l (put (str r5 "/x.txt") "x\n"))
        (_m (git r5 (list "add" "x.txt")))
        (ctl (git r5 (list "-c" (str "core.hooksPath=" r5 "/hooks") "commit" "-q" "-m" "x")))]
    (do
      (assert (= o1.code 1) (str "an unbalanced file refuses: " o1.text))
      (assert (stringContains? o1.text ":status :refused") "refused status")
      (assert (stringContains? o1.text ":rule :balance") (str "the guard row names balance: " o1.text))
      (assert (= (head r1) h1) "HEAD unchanged after the balance refusal")
      (assert (= o2.code 1) (str "a partial check refuses: " o2.text))
      (assert (stringContains? o2.text ":unchecked (\"good.asl\")") "the unchecked file is named")
      (assert (= (head r2) h2) "HEAD unchanged after the partial refusal")
      (assert (= o3.code 1) "an empty path list refuses")
      (assert (stringContains? o3.text "no paths named") "and says why")
      (assert (= o3b.code 1) "the whole-tree path . refuses")
      (assert (= o3c.code 1) "stage with no paths refuses")
      (assert (= (head r3) h3) "HEAD unchanged after empty and widening refusals")
      (assert (= o4.code 0) (str "a good named file commits: " o4.text))
      (assert (and (stringContains? o4.text ":status :done") (stringContains? o4.text " :sha ")) "done with a sha")
      (assert (!= (head r4) h4) "HEAD moved")
      (assert (= (committed r4) "good.asl") (str "exactly the named path is committed: " (committed r4)))
      (assert (and (= ctl.exit 0) (fileExists? (str r5 "/hookRan"))) "control: the same hook does run under a plain git commit")
      (assert (fileExists? (str r4 "/hooks/pre-commit")) "the hook file exists in the guarded repo")
      (assert (not (fileExists? (str r4 "/hookRan"))) "the repo-level hooksPath hook did not run")
      (assert (stringContains? st4.text "other.asl") "the unnamed staged file stays out of the commit")
      (assert (stringContains? st4.text "?? stray.txt") (str "an unnamed untracked file is never staged: " st4.text))
      true))

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (scenarios root base) "scenarios")
        (assert (pathProbes root base) "pathspec probes")
        (assert (toctou root base) "judged blob is the committed blob")
        (assert (refProbes root base) "ref probes")
        (assert (hardening root base) "hardening")
        (assert (warnGate root base) "warn record")
        (assert (listEmpty? (leftoverIdx)) (str "private index dirs are removed: " (stringJoin (leftoverIdx) ",")))
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))

fn ! indexOf dir: String -> String
  (str (stringTrim (git dir (list "ls-files" "-s")).out) "|" (stringTrim (git dir (list "status" "--porcelain")).out))

fn ! probeRepo base: String name: String -> String
  (let [(dir (repoAt base name))
        (_a (put (str dir "/kee1.txt") "one\n"))
        (_b (sh "." (list "mkdir" "-p" (str dir "/sub"))))
        (_c (put (str dir "/sub/a.txt") "a\n"))
        (_d (git dir (list "add" "-A")))
        (_e (git dir (list "commit" "-q" "-m" "files")))
        (_f (put (str dir "/untracked.txt") "u\n"))]
    dir)

; (:m :ref VCS-LAYER-CORE :do "pathspec magic and escaping paths never widen a stage or a commit: each probe is refused (a glob name is a literal that matches nothing) and HEAD, the shared index and the status are unchanged; a name like a..b.txt is fine")
fn ! pathProbes root: String base: String -> Bool
  (let [(dir (probeRepo base "pathProbe"))
        (h0 (head dir))
        (i0 (indexOf dir))
        (bad (list ":/" "./" "./kee1.txt" "kee?.txt" "sub" "sub/.." "." ".." "a/" "/etc/passwd" "-x" ".git/config" ""))
        (staged (map (fn [(p String)] -> Int64 (v/stage! dir (list p)).code) bad))
        (committed (map (fn [(p String)] -> Int64 (v/commit! dir root (list p) (goodMsg) "commit").code) bad))
        (hAfter (head dir))
        (iAfter (indexOf dir))
        (lit (gb/stageNamed! dir (list ":/" "sub" "kee?.txt")))
        (iLit (indexOf dir))
        (_g (put (str dir "/a..b.txt") "dots\n"))
        (okDots (v/commit! dir root (list "a..b.txt") (goodMsg) "commit"))]
    (do
      (assert (= hAfter h0) "HEAD unchanged by the probes")
      (assert (= iAfter i0) "the shared index and status unchanged by the probes")
      (assert (= iLit i0) (str "literal pathspecs: :/ sub and a glob name stage nothing even straight at the backend: " iLit))
      (assert (= (listLength (filter (fn [(c Int64)] -> Bool (= c 1)) committed)) (listLength bad)) (str "every probe commit is refused: " (stringJoin (map stringFromInt64 committed) ",")))
      (assert (= (listLength (filter (fn [(c Int64)] -> Bool (= c 1)) (listDrop (listTake staged 3) 0))) 3) "the pathspec-shaped stage probes are refused")
      (assert (= (optionOr (listGet staged 4) 9) 1) "a directory is refused for stage")
      (assert (= (optionOr (listGet staged 5) 9) 1) "sub/.. is refused for stage")
      (assert (= (optionOr (listGet staged 6) 9) 1) "the dot is refused for stage")
      (assert (= (optionOr (listGet staged 12) 9) 1) "an empty path is refused for stage")
      (assert (gb/pathOk? "a..b.txt") "a..b.txt is an accepted name")
      (assert (not (gb/pathOk? "a/../b")) "a dotdot segment is refused")
      (assert (not (gb/pathOk? "a/./b")) "a dot segment is refused")
      (assert (= okDots.code 0) (str "a..b.txt commits: " okDots.text))
      (assert (= (committed2 dir) "a..b.txt") "and only that name")
      (assert (stringContains? (indexOf dir) "untracked.txt") "the untracked file stays untracked")
      (assert (< (stringLength (gb/capOut (strRep2 300000))) 200100) "diff and log text is capped")
      (assert (stringContains? (gb/capOut (strRep2 300000)) ":truncated") "with a marker")
      (assert (not (stringEmpty? i0)) "index probe is meaningful")
      true))

fn strRep2 n: Int64 -> String
  (stringRepeat "x" n)

fn ! committed2 dir: String -> String
  (committed dir)

; (:m :ref VCS-LAYER-CORE :do "the guard judges the blob that lands: a stub asl binary rewrites good.asl with a broken module while it runs, and the committed blob is still the good text; a refusal leaves the shared index as it was")
fn ! toctou root: String base: String -> Bool
  (let [(dir (repoAt base "toctou"))
        (_a (put (str dir "/good.asl") (goodAsl)))
        (stub (stubRoot! base "rewriteRoot" (str "#!/bin/sh\nprintf '(module fx/bad\\n' > " dir "/good.asl\nshift\nfor f in \"$@\"; do echo \"ok $f: (:checked 1)\"; done\nexit 0\n")))
        (_s (put (str stub "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 30\n)\n"))
        (o (v/commit! dir stub (list "good.asl") (goodMsg) "commit"))
        (blob (stringTrim (git dir (list "show" "HEAD:good.asl")).out))
        (work (resultOr (fileReadString (str dir "/good.asl")) ""))
        (r2 (repoAt base "refuseIdx"))
        (_b (put (str r2 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (i0 (indexOf r2))
        (o2 (v/commit! r2 root (list "bad.asl") (goodMsg) "commit"))]
    (do
      (assert (= o.code 0) (str "the commit lands: " o.text))
      (assert (= blob (stringTrim (goodAsl))) (str "the committed blob is the judged blob: " blob))
      (assert (stringContains? work "fx/bad") "the working file was rewritten during the guard")
      (assert (= o2.code 1) "a broken file is refused")
      (assert (= (indexOf r2) i0) "the refusal leaves the shared index as it was")
      true))

fn ancIs r: (Result Bool String) want: Bool -> Bool
  (match r ((ok b) (= b want)) ((err _) false))

fn ancErr r: (Result Bool String) -> Bool
  (match r ((ok _) false) ((err _) true))

; (:m :ref VCS-LAYER-CORE :do "ref arguments never become options: -D, --no-ff and --output=F are refused and nothing is deleted or written; mergeFf refuses a diverged source without a merge commit and fast-forwards an ahead one; isAncestor answers err for an unknown commit or a missing repo; log, diff and branch work on real refs")
fn ! refProbes root: String base: String -> Bool
  (let [(dir (probeRepo base "refProbe"))
        (h0 (head dir))
        (_a (git dir (list "branch" "div")))
        (_b (git dir (list "branch" "side")))
        (_c (put (str dir "/main.txt") "m\n"))
        (_d (git dir (list "add" "main.txt")))
        (_e (git dir (list "commit" "-q" "-m" "main moves")))
        (h1 (head dir))
        (_f (git dir (list "checkout" "-q" "side")))
        (_g (put (str dir "/side.txt") "s\n"))
        (_h (git dir (list "add" "side.txt")))
        (_i (git dir (list "commit" "-q" "-m" "ahead moves")))
        (hSide (head dir))
        (_j (git dir (list "checkout" "-q" "main")))
        (out (str base "/injected.txt"))
        (_p (git dir (list "checkout" "-q" "-b" "ahead")))
        (_q (put (str dir "/ahead.txt") "x\n"))
        (_r (git dir (list "add" "ahead.txt")))
        (_s (git dir (list "commit" "-q" "-m" "ahead moves")))
        (hAhead (head dir))
        (_t (git dir (list "checkout" "-q" "main")))
        (bD (v/branch! dir "-D" "main"))
        (bBase (v/branch! dir "newb" "--no-ff"))
        (bOk (v/branch! dir "newb" "main"))
        (mNoFf (v/mergeFf! dir "--no-ff"))
        (mDiv (v/mergeFf! dir "side"))
        (merges (stringTrim (git dir (list "rev-list" "--merges" "--count" "HEAD")).out))
        (hMid (head dir))
        (_o (git dir (list "checkout" "-q" "main")))
        (mSide (v/mergeFf! dir "ahead"))
        (lOut (v/log! dir (str "--output=" out) (list) "%h"))
        (lOk (v/log! dir "HEAD" (list) "%s"))
        (dOut (v/diff! dir (str "--output=" out) "HEAD" (list)))
        (dOk (v/diff! dir h0 "main" (list)))
        (branches (stringTrim (git dir (list "branch" "--list")).out))
        (cleanRepo (strRepo dir))]
    (do
      (assert (= bD.code 1) (str "-D as a branch name is refused: " bD.text))
      (assert (= bBase.code 1) "--no-ff as a base is refused")
      (assert (= bOk.code 0) (str "a real branch is created: " bOk.text))
      (assert (stringContains? branches "main") "main was not deleted")
      (assert (= mNoFf.code 1) "--no-ff as a source is refused")
      (assert (= mDiv.code 1) (str "a diverged source is refused: " mDiv.text))
      (assert (= merges "0") "and no merge commit was made")
      (assert (= hMid h1) (str "HEAD is main's after the refusals " (head dir) " " h1))
      (assert (= mSide.code 0) (str "an ahead source fast-forwards: " mSide.text))
      (assert (= (head dir) hAhead) "HEAD moved to the source")
      (assert (= lOut.code 1) "--output=F as a range is refused")
      (assert (not (fileExists? out)) "and nothing was written")
      (assert (and (= lOk.code 0) (stringContains? lOk.text "ahead moves")) (str "log shows commits: " lOk.text))
      (assert (= dOut.code 1) "--output=F as a diff ref is refused")
      (assert (and (= dOk.code 0) (stringContains? dOk.text "main.txt")) "diff shows the change")
      (assert (ancIs (v/isAncestor! dir h0 hAhead) true) "an ancestor is ok true")
      (assert (ancIs (v/isAncestor! dir hAhead h0) false) "a non-ancestor is ok false")
      (assert (ancErr (v/isAncestor! dir "0123456789abcdef0123456789abcdef01234567" h0)) "an unknown sha is err")
      (assert (ancErr (v/isAncestor! (str base "/noSuchRepo") h0 h0)) "a missing repo is err")
      (assert (ancErr (v/isAncestor! dir "--all" h0)) "an option-shaped ref is err")
      (assert (not (stringEmpty? cleanRepo)) "repo probe")
      true))

fn ! strRepo dir: String -> String
  dir

fn ! leftoverIdx -> (List String)
  (filter (fn [(l String)] -> Bool (stringStartsWith? l (str "vcsIdx-" (stringFromInt64 (procSelf)) "-")))
          (stringLines (sh "." (list "ls" (optionOr (envGet "TMPDIR") "/tmp"))).out))

; (:m :ref VCS-LAYER-CORE :do "hardening gates: a hostile GIT_DIR in the caller env does not redirect the layer or the guard; a peer commit between the read of HEAD and update-ref is refused and kept; the shared index entry of a committed path is reset to HEAD while a peer-staged file stays staged; a failed reset reports partial and indexStale; a peer-staged blob that differs from HEAD and the working file refuses; the private index dirs are removed")
fn ! hardening root: String base: String -> Bool
  (let [(a (repoAt base "envA"))
        (b (repoAt base "envB"))
        (_a (put (str a "/good.asl") (goodAsl)))
        (hA (head a))
        (hB (head b))
        (child (fr/runOneLimited (fr/job (list (str root "/bin/asl") "run" (str root "/asl/tools/vcs/tests/vcsChild.asl") a root "good.asl" (goodMsg)) root (fr/childEnv (list (str "GIT_DIR=" b "/.git")))) (fr/limits 240 16)))
        (c (repoAt base "peerCommit"))
        (_b (put (str c "/good.asl") (goodAsl)))
        (peer (stubRoot! base "peerRoot" (str "#!/bin/sh\ngit -C " c " -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m peer\nshift\nfor f in \"$@\"; do echo \"ok $f: (:checked 1)\"; done\nexit 0\n")))
        (_c (put (str peer "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 30\n)\n"))
        (oc (v/commit! c peer (list "good.asl") (goodMsg) "commit"))
        (subj (stringTrim (git c (list "log" "-1" "--format=%s")).out))
        (inHead (stringTrim (git c (list "ls-tree" "HEAD" "good.asl")).out))
        (d (repoAt base "resetRepo"))
        (_d (put (str d "/good.asl") (goodAsl)))
        (_e (put (str d "/other.asl") "(module fx/other\n"))
        (_f (git d (list "add" "other.asl")))
        (od (v/commit! d root (list "good.asl") (goodMsg) "commit"))
        (std (stringTrim (git d (list "status" "--porcelain")).out))
        (e (repoAt base "staleRepo"))
        (_g (put (str e "/good.asl") (goodAsl)))
        (_h (put (str e "/.git/index.lock") ""))
        (oe (v/commit! e root (list "good.asl") (goodMsg) "commit"))
        (_i (sh "." (list "rm" "-f" (str e "/.git/index.lock"))))
        (p (repoAt base "peerStaged"))
        (_j (put (str p "/good.asl") (goodAsl)))
        (_k (git p (list "add" "good.asl")))
        (_l (put (str p "/good.asl") (str (goodAsl) "\n; edited after the peer staged\n")))
        (hP (head p))
        (op (v/commit! p root (list "good.asl") (goodMsg) "commit"))
        (q (repoAt base "sameStaged"))
        (_m (put (str q "/good.asl") (goodAsl)))
        (_n (git q (list "add" "good.asl")))
        (oq (v/commit! q root (list "good.asl") (goodMsg) "commit"))]
    (do
      (assert (= child.exit 0) (str "the layer commits under a hostile GIT_DIR: " child.out))
      (assert (!= (head a) hA) "the target repo got the commit")
      (assert (= (committed a) "good.asl") "exactly the named path")
      (assert (= (head b) hB) "the repo GIT_DIR pointed at is untouched")
      (assert (= oc.code 1) (str "a peer commit during the guard refuses: " oc.text))
      (assert (stringContains? oc.text "HEAD moved") "and says HEAD moved")
      (assert (= subj "peer") (str "the peer commit is kept as HEAD: " subj))
      (assert (stringEmpty? inHead) "and the refused file is not in it")
      (assert (= od.code 0) (str "the commit lands beside a peer-staged file: " od.text))
      (assert (not (stringContains? std "good.asl")) (str "the committed path is reset in the shared index: " std))
      (assert (stringContains? std "A  other.asl") "a peer-staged unnamed file stays staged")
      (assert (= oe.code 0) (str "a landed commit with a failed reset is code 0: " oe.text))
      (assert (stringContains? oe.text ":status :partial") "status partial")
      (assert (stringContains? oe.text ":indexStale true") "and marks the stale index")
      (assert (= op.code 1) (str "a peer-staged differing blob refuses: " op.text))
      (assert (stringContains? op.text ":peerStaged (\"good.asl\")") "naming the path")
      (assert (= (head p) hP) "HEAD unchanged on peerStaged")
      (assert (= oq.code 0) (str "a staged blob equal to the working file commits: " oq.text))
      true))

; (:m :ref VCS-LAYER-CORE :do "warn mode commits over a block, says :status :warned with the aslRoot, and records the blocking rows in .asl/log/commitGuard.asn like commitGuard commit --warn")
fn ! warnGate root: String base: String -> Bool
  (let [(w (repoAt base "warnRepo"))
        (_a (put (str w "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (hW (head w))
        (ow (v/commit! w root (list "bad.asl") (goodMsg) "warn"))
        (log (resultOr (fileReadString (str w "/.asl/log/commitGuard.asn")) ""))
        (w2 (repoAt base "warnStale"))
        (_b (put (str w2 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (_c (put (str w2 "/.git/index.lock") ""))
        (ow2 (v/commit! w2 root (list "bad.asl") (goodMsg) "warn"))
        (_d (sh "." (list "rm" "-f" (str w2 "/.git/index.lock"))))
        (log2 (resultOr (fileReadString (str w2 "/.asl/log/commitGuard.asn")) ""))]
    (do
      (assert (= ow.code 0) (str "warn commits over a block: " ow.text))
      (assert (!= (head w) hW) "HEAD moved under warn")
      (assert (stringContains? ow.text ":status :warned") "the status is warned, not done")
      (assert (stringContains? ow.text ":aslRoot \"") "the receipt carries the aslRoot")
      (assert (stringContains? log ":rule :balance") (str "the blocking rows are recorded: " log))
      (assert (and (= ow2.code 0) (stringContains? ow2.text ":status :warned")) (str "warn over a block with a failed index reset is still warned: " ow2.text))
      (assert (stringContains? ow2.text ":indexStale true") "and marks the stale index")
      (assert (stringContains? ow2.text ":aslRoot \"") "and carries the aslRoot")
      (assert (stringContains? log2 ":rule :balance") (str "and records the rows: " log2))
      true))
