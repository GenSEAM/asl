(module asl/tools/coord/tests/commitGuardTest
  :x [runTests]
  :i [(asl-tools/coord/commitGuard :a cg) (asl-tools/fleet/run :a fr)])

; (:m :ref COMMIT-GUARD :do "pure rules over given text, then fixture repos: each block rule (unbalanced .asl, unresolved import, foreign growth, new foreign file, multi-line message, trailer, conflict marker, ignored path, secret) blocks with exit 1, a clean change passes with exit 0 and no rows, and --warn never exits 1; every assert goes red when its rule is removed from commitGuard.asl")
fn ! scratch -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/commitGuardTest-" (stringFromInt64 (procSelf)))

fn ! sh dir: String argv: (List String) -> fr/Done
  (fr/runOneLimited (fr/job argv dir (fr/childEnv (list))) (fr/limits 60 16))

fn ! put path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn ! git dir: String args: (List String) -> Bool
  (= (sh dir (listAppend (list "git" "-c" "user.name=t" "-c" "user.email=t@example.invalid" "-c" "commit.gpgsign=false") args)).exit 0)

fn baseline -> String
  "(:foreignBaseline :v 1\n  (:file :path \"keep.sh\" :lang :shell :lines 2 :py 0)\n)\n"

fn goodAsl -> String
  "(module fx/good\n  :x [f]\n  :i [])\n\nfn f -> Int64\n  1\n"

fn goodMsg -> String
  "(:c :a fixture :do \"a clean change\" :g \"gate\" :ev (COMMIT-GUARD))\n"

; (:m :do "a fixture repo with a committed baseline, keep.sh and an ignore file, then the given files written and staged")
fn ! fixture base: String name: String files: (List (Pair String String)) -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/scripts/audit"))).exit 0) (str name ": dir"))
        (assert (git dir (list "init" "-q" "-b" "main")) (str name ": init"))
        (assert (git dir (list "config" "user.name" "t")) (str name ": user"))
        (assert (git dir (list "config" "user.email" "t@example.invalid")) (str name ": email"))
        (assert (put (str dir "/scripts/audit/foreignBaseline.asn") (baseline)) (str name ": baseline"))
        (assert (put (str dir "/keep.sh") "#!/bin/sh\necho a\n") (str name ": keep.sh"))
        (assert (put (str dir "/.gitignore") ".asl/mem/sessions/\n") (str name ": gitignore"))
        (assert (git dir (list "add" "-A")) (str name ": add base"))
        (assert (git dir (list "commit" "-q" "-m" "base")) (str name ": commit base"))
        (assert (listAll? (fn [(f (Pair String String))] -> Bool
                            (and (= (sh "." (list "mkdir" "-p" (str dir "/" (parentOf (pairFirst f))))).exit 0)
                                 (put (str dir "/" (pairFirst f)) (pairSecond f))))
                          files) (str name ": files"))
        (assert (git dir (list "add" "-A" "-f")) (str name ": stage"))
        dir))

fn parentOf p: String -> String
  (let [(parts (stringSplit p "/"))]
    (if (<= (listLength parts) 1) "." (stringJoin (listTake parts (- (listLength parts) 1)) "/")))

fn ! cfgFor root: String dir: String msgFile: String warn: Bool -> cg/Cfg
  (cg/Cfg :repo dir :aslRoot root :range "" :msg (resultOr (fileReadString msgFile) "") :hasMsg true :paths (list) :warn warn :perFileS 30 :totalS 90 :gitS 30)

fn ! msgAt base: String name: String text: String -> String
  (let [(p (str base "/" name ".msg"))]
    (do (assert (put p text) (str name ": message file")) p))

fn ! pureRules -> Bool
  (do
    (assert (listEmpty? (cg/messageHits (goodMsg))) "a one-line ASN message passes")
    (assert (listEmpty? (cg/messageHits (str (goodMsg) "# Please enter the commit message\n"))) "git comment lines are ignored")
    (assert (not (listEmpty? (cg/messageHits "(:c :a x :do \"y\")\n\nbody text\n"))) "a body is a second line and blocks")
    (assert (not (listEmpty? (cg/messageHits "(:c :a x :do \"y\")\nCo-Authored-By: someone\n"))) "a co-author trailer blocks")
    (assert (not (listEmpty? (cg/messageHits "(:c :a x :do \"y\" Signed-off-by: me)\n"))) "an inline sign-off blocks")
    (assert (not (listEmpty? (cg/messageHits "fix the thing\n"))) "plain prose is not an ASN line")
    (assert (not (listEmpty? (cg/messageHits "(:c :a x :do \"y\"\n"))) "an unbalanced ASN line blocks")
    (assert (not (listEmpty? (cg/messageHits ""))) "an empty message blocks")
    (assert (listEmpty? (cg/messageHits "Merge branch 'x' into main\n")) "a git-made merge line passes")
    (assert (= (listLength (cg/parseNameStatus "A\ta.asl\nD\tb.asl\nM\tc/d.sh\n")) 2) "name-status keeps added and modified, drops deleted")
    (assert (= (listLength (cg/addedLines "+++ b/x.asl\n@@ -0,0 +1,2 @@\n+one\n+two\n+++ /dev/null\n+drop\n")) 2) "added lines come with their file and skip /dev/null headers")
    (assert (not (listEmpty? (cg/messageHits "(:c :a x :do \"Co-Authored-By: y\")\n"))) "a co-author text inside the single line blocks")
    (assert (= (listLength (cg/conflictHits (list (ad (str (strRep "=") "")) (ad (str (strRep ">") " main")) (ad (str (strRep "<") " HEAD")) (ad "a = b") (ad (str (strRep "=") "="))))) 3) "each of the three marker shapes is a hit and near-misses are not")
    (assert (not (cg/secretLine? "let x = 1")) "ordinary code is no secret")
    (assert (cg/secretLine? (str "key " "sk-" "abcdefghijklmnopqrstuvwxyz0123")) "a provider key shape is a secret")
    (assert (cg/secretLine? (str "AK" "IA" "ABCDEFGHIJKLMNOP")) "an access key id is a secret")
    (assert (cg/secretLine? (str "OPENAI_API_" "KEY=" "abcdefghijklmnopqrstuvwxyz0123")) "NAME_API_KEY=longvalue is a secret")
    (assert (not (cg/secretLine? "(envGet \"OPENAI_API_KEY\")")) "reading a key by name is no secret")
    (assert (cg/secretLine? (str "-----BEGIN RSA " "PRIVATE KEY-----")) "a private key header is a secret")
    true)

fn ! fixtures root: String base: String -> Bool
  (let [(ok0 (msgAt base "ok" (goodMsg)))
        (clean (fixture base "clean" (list (pair "a/good.asl" (goodAsl)) (pair "a/data.asn" "(:row :a 1)\n"))))
        (rClean (cg/report! (cfgFor root clean ok0 false)))
        (unbal (fixture base "unbal" (list (pair "a/bad.asl" "(module fx/bad\n  :x [f]\n"))))
        (rUnbal (cg/report! (cfgFor root unbal ok0 false)))
        (unbalAsn (fixture base "unbalAsn" (list (pair "a/bad.asn" "(:row :a (1\n"))))
        (rUnbalAsn (cg/report! (cfgFor root unbalAsn ok0 false)))
        (imp (fixture base "imp" (list (pair "a/imp.asl" "(module fx/imp\n  :x [f]\n  :i [(nope/missingModule :a m)])\n\nfn f -> Int64\n  1\n"))))
        (rImp (cg/report! (cfgFor root imp ok0 false)))
        (grow (fixture base "grow" (list (pair "keep.sh" "#!/bin/sh\necho a\necho b\necho c\n"))))
        (rGrow (cg/report! (cfgFor root grow ok0 false)))
        (shrink (fixture base "shrink" (list (pair "keep.sh" "#!/bin/sh\n"))))
        (rShrink (cg/report! (cfgFor root shrink ok0 false)))
        (newf (fixture base "newf" (list (pair "tools/new.sh" "#!/bin/sh\necho hi\n"))))
        (rNewf (cg/report! (cfgFor root newf ok0 false)))
        (multi (msgAt base "multi" "(:c :a x :do \"y\")\n\nlong body\n"))
        (rMulti (cg/report! (cfgFor root clean multi false)))
        (trailer (msgAt base "trailer" "(:c :a x :do \"y\")\nCo-Authored-By: Someone <s@example.invalid>\n"))
        (rTrailer (cg/report! (cfgFor root clean trailer false)))
        (conf (fixture base "conf" (list (pair "notes.txt" (str "a\n" (str "<<<<" "<<<") " HEAD\nb\n")))))
        (rConf (cg/report! (cfgFor root conf ok0 false)))
        (ign (fixture base "ign" (list (pair ".asl/mem/sessions/s1.asn" "(:s 1)\n"))))
        (rIgn (cg/report! (cfgFor root ign ok0 false)))
        (sec (fixture base "sec" (list (pair "env.txt" (str "OPENAI_API_" "KEY=" "abcdefghijklmnopqrstuvwxyz0123\n")))))
        (rSec (cg/report! (cfgFor root sec ok0 false)))
        (warnU (cg/report! (cfgFor root unbal multi true)))
        (warnF (cg/report! (cfgFor root grow trailer true)))]
    (do
      (assert (= (pairFirst rClean) 0) (str "a clean change passes: " (pairSecond rClean)))
      (assert (stringContains? (pairSecond rClean) ":status :ok :files 2") (str "clean receipt is ok over 2 files: " (pairSecond rClean)))
      (assert (stringContains? (pairSecond rClean) ":rows ())") "clean receipt has no rows")
      (assert (= (pairFirst rUnbal) 1) (str "an unbalanced .asl blocks: " (pairSecond rUnbal)))
      (assert (stringContains? (pairSecond rUnbal) ":rule :balance") "the row names the balance rule")
      (assert (stringContains? (pairSecond rUnbal) "a/bad.asl") "the row names the file")
      (assert (= (pairFirst rUnbalAsn) 1) "an unbalanced .asn blocks")
      (assert (= (pairFirst rImp) 1) (str "an unresolved import blocks: " (pairSecond rImp)))
      (assert (stringContains? (pairSecond rImp) "ERR_UNRESOLVED_IMPORT") "the row carries the asl check error")
      (assert (= (pairFirst rGrow) 1) (str "foreign growth blocks: " (pairSecond rGrow)))
      (assert (stringContains? (pairSecond rGrow) "foreign growth :lines 4 > baseline 2") "the growth row gives both counts")
      (assert (= (pairFirst rShrink) 0) (str "shrinking a baseline file is fine: " (pairSecond rShrink)))
      (assert (= (pairFirst rNewf) 1) (str "a new foreign file blocks: " (pairSecond rNewf)))
      (assert (stringContains? (pairSecond rNewf) "new foreign file :shell") "the row says the file is new")
      (assert (= (pairFirst rMulti) 1) (str "a multi-line message blocks: " (pairSecond rMulti)))
      (assert (stringContains? (pairSecond rMulti) ":rule :message") "the row names the message rule")
      (assert (= (pairFirst rTrailer) 1) (str "a trailer blocks: " (pairSecond rTrailer)))
      (assert (= (pairFirst rConf) 1) (str "a conflict marker blocks: " (pairSecond rConf)))
      (assert (stringContains? (pairSecond rConf) ":rule :conflictMarker") "the row names the marker rule")
      (assert (= (pairFirst rIgn) 0) (str "a new file under an ignored path with no tracked sibling only warns: " (pairSecond rIgn)))
      (assert (stringContains? (pairSecond rIgn) ":rule :ignoredPath") "the row names the ignored path rule")
      (assert (= (pairFirst rSec) 1) (str "a credential value blocks: " (pairSecond rSec)))
      (assert (stringContains? (pairSecond rSec) ":rule :secret") "the row names the secret rule")
      (assert (not (stringContains? (pairSecond rSec) "abcdefghijklmnopqrstuvwxyz0123")) "the receipt never prints the value")
      (assert (= (pairFirst warnU) 0) "--warn on an unbalanced file plus a bad message exits 0")
      (assert (stringContains? (pairSecond warnU) ":status :wouldBlock") "--warn still reports the rows as wouldBlock")
      (assert (stringContains? (pairSecond warnU) ":rule :balance") "--warn keeps the rows")
      (assert (= (pairFirst warnF) 0) "--warn on foreign growth plus a trailer exits 0")
      true))

fn ad text: String -> cg/Added
  (cg/Added :path "f" :line 1 :text text)

fn ! head dir: String -> String
  (stringTrim (sh dir (list "git" "rev-parse" "HEAD")).out)

fn ! committed dir: String -> String
  (stringTrim (sh dir (list "git" "show" "--name-only" "--format=" "HEAD")).out)

; (:m :do "the own commit entry over fixture repos: ok commits only the named paths, a block commits nothing and leaves HEAD, a partly staged broken blob is blocked though the working copy is fine, warn commits and records the rows")
fn ! commitGates root: String base: String -> Bool
  (let [(c1 (fixture base "cOk" (list)))
        (_a (put (str c1 "/good.asl") (goodAsl)))
        (_b (put (str c1 "/note.txt") "not named\n"))
        (_c (put (str c1 "/other.asl") "(module fx/other\n"))
        (_d (git c1 (list "add" "other.asl")))
        (h1 (head c1))
        (r1 (cg/commit! c1 root (list "good.asl") (goodMsg) false))
        (c2 (fixture base "cBlock" (list)))
        (_e (put (str c2 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (h2 (head c2))
        (r2 (cg/commit! c2 root (list "bad.asl") (goodMsg) false))
        (r2b (cg/commit! c2 root (list) (goodMsg) false))
        (c3 (fixture base "cPart" (list (pair "p.asl" "(module fx/p\n  :x [f]\n"))))
        (_f (put (str c3 "/p.asl") (goodAsl)))
        (r3 (cg/guard! c3 root (list "p.asl") (goodMsg) false))
        (c4 (fixture base "cWarn" (list)))
        (_g (put (str c4 "/bad.asl") "(module fx/bad\n  :x [f]\n"))
        (h4 (head c4))
        (r4 (cg/commit! c4 root (list "bad.asl") (goodMsg) true))
        (c5 (fixture base "cDel" (list)))
        (_h (sh c5 (list "rm" "-f" "keep.sh")))
        (r5 (cg/commit! c5 root (list "keep.sh") (goodMsg) false))
        (log4 (resultOr (fileReadString (str c4 "/.asl/log/commitGuard.asn")) ""))]
    (do
      (assert (= r1.code 0) (str "a clean named path commits: " r1.text))
      (assert (stringContains? r1.text ":commit :done :sha ") "the receipt says done with a sha")
      (assert (!= (head c1) h1) "HEAD moved on ok")
      (assert (= (committed c1) "good.asl") (str "only the named path is in the commit: " (committed c1)))
      (assert (= r2.code 1) (str "a broken named path is refused: " r2.text))
      (assert (stringContains? r2.text ":commit :refused") "the receipt says refused")
      (assert (= (head c2) h2) "HEAD is unchanged after a refusal")
      (assert (= r2b.code 1) "no paths named is refused")
      (assert (= r3.code 1) (str "a partly staged broken blob is blocked though the working copy is good: " r3.text))
      (assert (stringContains? r3.text ":rule :balance") "the blob row names balance")
      (assert (= r5.code 0) (str "a deleted path commits: " r5.text))
      (assert (= (committed c5) "keep.sh") "the deletion is the commit")
      (assert (= r4.code 0) (str "--warn commits anyway: " r4.text))
      (assert (!= (head c4) h4) "HEAD moved under --warn")
      (assert (stringContains? r4.text ":status :wouldBlock") "the warn receipt keeps the rows")
      (assert (stringContains? r4.text ":commit :done") "the warn receipt says done")
      (assert (stringContains? log4 ":rule :balance") (str "the rows are recorded in .asl/log/commitGuard.asn: " log4))
      true))

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (pureRules) "pure rules")
        (assert (fixtures root base) "fixture repos")
        (assert (commitGates root base) "commit entry")
        (assert (partialGates root base) "partial check blocks the commit")
        (assert (fixPure) "fix-round pure gates")
        (assert (fixFixtures root base) "fix-round fixtures")
        (assert (fix2 root base) "fix2")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))

fn strRep c: String -> String
  (str c c c c c c c)

fn cherryMsg -> String
  "(:c :a agentLoop :do \"autofixCloserTest covers the edit-branch repair\" :g \"autofixCloserTest 14 asserts; mutants balanceRepair-off and edit-branch-skip red\" :ev (LEON-AUTOFIX-CLOSER))\n\n(cherry picked from commit 455d350eb)\n"

; (:m :ref COMMIT-GUARD-FIX :do "pure gates built from the real false blocks: the 2612b8fa1 cherry-pick message, scissors and revert bodies, the task-queue-runner-identifier-longname line, MAX_TOKENS and path values, tracked-sibling ledgers, the stale-native and attribution rows, and the partial status")
fn ! fixPure -> Bool
  (do
    (assert (listEmpty? (cg/messageHits (cherryMsg))) (str "the exact 2612b8fa1 cherry-pick message passes: " (stringJoin (map (fn [(h cg/Hit)] -> String h.why) (cg/messageHits (cherryMsg))) ";")))
    (assert (not (listEmpty? (cg/messageHits (str (goodMsg) "\nsecond real line\n")))) "a real second line still blocks beside the cherry-pick rule")
    (assert (listEmpty? (cg/messageHits (str (goodMsg) "# ------------------------ >8 ------------------------\ndiff --git a/x b/x\n+Co-Authored-By: a\n"))) "everything after the commit -v scissors line is cut")
    (assert (listEmpty? (cg/messageHits "Revert \"(:c :a x :do y)\"\n\nThis reverts commit 0123abc.\n")) "a git revert message passes")
    (assert (not (listEmpty? (cg/messageHits (str (goodMsg) "Merge branch x\n")))) "the Merge exemption is for the first line only")
    (assert (listEmpty? (cg/messageHits "Merge branch 'x' into main\n\nbody line\n")) "a Merge first line passes with its body")
    (assert (not (cg/secretLine? "task-queue-runner-identifier-longname")) "task-... is no sk- key")
    (assert (not (cg/secretLine? "(:task \"task-queue-runner-identifier-longname-extra\")")) "task-... inside a form is no key")
    (assert (cg/secretLine? (str "x sk-" "abcdefghijklmnopqrstuvwxyz0123")) "a real sk- key after a space is a secret")
    (assert (cg/secretLine? (str "sk-" "abcdefghijklmnopqrstuvwxyz0123")) "a real sk- key at the line start is a secret")
    (assert (not (cg/secretLine? "MAX_TOKENS=1000000000000000000000")) "a digit run is no secret")
    (assert (not (cg/secretLine? "ASL_TOKEN_FILE=/Users/purplelephant/.asl/secrets/tokenfile12345")) "a path value is no secret")
    (assert (not (cg/secretLine? "ASL_TOKEN_FILE=~/.asl/secrets/tokenfile12345678")) "a home path value is no secret")
    (assert (cg/secretLine? (str "GH_TOKEN=" "Ab3dEf6hIj9kLm2nOp5qRs8t")) "a high entropy token value is a secret")
    (let [(rows (cg/secretHits (list (cg/Added :path "e.txt" :line 7 :text (str "OPENAI_API_" "KEY=" "Ab3dEf6hIj9kLm2nOp5qRs8t")))))]
      (do (assert (= (listLength rows) 1) "one secret row")
          (assert (stringContains? (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.why) rows)) "") "line 7") "the secret row names its line")
          (assert (not (stringContains? (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.why) rows)) "") "Ab3dEf6hIj9kLm2n")) "the secret row never prints the value")))
    (let [(rows (cg/conflictHits (list (cg/Added :path "c.txt" :line 3 :text (str (strRep "<") " leakedBranchName")))))]
      (do (assert (= (listLength rows) 1) "one conflict row")
          (assert (not (stringContains? (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.why) rows)) "") "leakedBranchName")) "the conflict row never prints the line")
          (assert (stringContains? (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.why) rows)) "") "line 3") "the conflict row names the line")))
    (assert (= (listLength (cg/addedLines "+++ b/x.txt\n@@ -0,0 +5,2 @@\n+a\n+b\n")) 2) "line numbers come from the hunk header")
    (assert (= (optionOr (listHead (map (fn [(a cg/Added)] -> Int64 a.line) (cg/addedLines "+++ b/x.txt\n@@ -0,0 +5,2 @@\n+a\n+b\n"))) 0) 5) "the first added line is line 5")
    (let [(newP (list ".asl/mem/work/CAL/kimiCal.asn"))
          (ign ".asl/mem/work/CAL/kimiCal.asn\n")
          (sib (cg/ignoredHits newP ign ".asl/mem/work/CAL/kimiCal.asn\n.asl/mem/work/CAL/other.asn\n"))
          (alone (cg/ignoredHits newP ign ".asl/mem/work/CAL/kimiCal.asn\n.asl/mem/work/X/other.asn\n"))]
      (do (assert (listEmpty? sib) "the kimiCal path with a tracked sibling is allowed")
          (assert (= (listLength alone) 1) "an ignored new path with no tracked sibling is reported")
          (assert (not (cg/hitBlocks? (optionOr (listHead alone) (cg/Hit :rule "" :path "" :why "" :block true)))) "and it is a warning, not a block")))
    (let [(stale (cg/chunkRows "/src" (list "a.asl" "b.asl") 30 1 "" "/src/a.asl:0:0: ERR_NATIVE_STALE the native CLI is older than the tree\ncheck failed\n"))]
      (do (assert (= (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.rule) stale)) "") "toolchain") "ERR_NATIVE_STALE is one toolchain row")
          (assert (stringContains? (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.why) stale)) "") "native CLI stale: a.asl:0:0: ERR_NATIVE_STALE") "the row quotes the first error without the temp prefix")
          (assert (= (listLength (filter (fn [(h cg/Hit)] -> Bool (= h.rule "unchecked")) stale)) 2) "both files are reported unchecked")
          (assert (not (listAny? (fn [(h cg/Hit)] -> Bool (and h.block (= h.rule "check"))) stale)) "no file is blamed for a stale toolchain")))
    (let [(att (cg/chunkRows "/src" (list "a.asl" "b.asl") 30 1 "" "/src/b.asl:2:3: ERR_UNRESOLVED_IMPORT nope not declared\n"))]
      (do (assert (= (listLength att) 1) "only the failing file gets a row")
          (assert (= (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.path) att)) "") "b.asl") "the row is attributed to b.asl")))
    (assert (= (listLength (filter (fn [(h cg/Hit)] -> Bool (= h.rule "unchecked")) (cg/chunkRows "/src" (list "a.asl") 30 124 "timeout" ""))) 1) "a timeout reports the file unchecked, not clean")
    (assert (= (cg/statusOf (cg/chunkRows "/src" (list "a.asl") 30 124 "timeout" "") false) "partial") "unchecked files give status partial")
    (assert (= (cg/statusOf (list) false) "ok") "no rows is ok")
    (let [(decoys "ok /src/other.asl: (:checked 1)\nok /src/a.asl.bak: (:checked 1)\n  ok /src/a.asl: (:checked 1)\nsome ok /src/a.asl: text\n")
          (exact "noise\nok /src/a.asl: (:checked 1)\n")]
      (do (assert (= (listLength (cg/chunkRows "/src" (list "a.asl") 30 0 "" decoys)) 1) "an ok line of another file, a .bak name, an indented line or one with text before it does not clear the file")
          (assert (= (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.rule) (cg/chunkRows "/src" (list "a.asl") 30 0 "" decoys))) "") "unchecked") "and it is reported unchecked")
          (assert (listEmpty? (cg/chunkRows "/src" (list "a.asl") 30 0 "" exact)) "the exact ok line at the line start clears it")
          (assert (= (listLength (cg/chunkRows "/src" (list "a.asl" "b.asl") 30 0 "" exact)) 1) "a second file without its own ok line stays unchecked")))
    true)

fn ! fixFixtures root: String base: String -> Bool
  (let [(ok0 (msgAt base "okF" (goodMsg)))
        (cm (msgAt base "cherry" (cherryMsg)))
        (clean (fixture base "fClean" (list (pair "a/good.asl" (goodAsl)))))
        (rCherry (cg/report! (cfgFor root clean cm false)))
        (rNo (cg/report! (cg/Cfg :repo clean :aslRoot root :range "nosuch..x" :msg "" :hasMsg false :paths (list) :warn false :perFileS 30 :totalS 90 :gitS 30)))
        (rNoW (cg/report! (cg/Cfg :repo clean :aslRoot root :range "nosuch..x" :msg "" :hasMsg false :paths (list) :warn true :perFileS 30 :totalS 90 :gitS 30)))
        (rPart (cg/report! (cg/Cfg :repo clean :aslRoot root :range "" :msg (goodMsg) :hasMsg true :paths (list) :warn false :perFileS 30 :totalS 0 :gitS 30)))
        (tr (fixture base "fTracked" (list (pair ".asl/mem/sessions/old.asn" "(:s 0)\n"))))
        (_a (git tr (list "commit" "-q" "-m" "tracked ledger")))
        (_b (put (str tr "/.asl/mem/sessions/new.asn") "(:s 1)\n"))
        (_c (git tr (list "add" "-f" ".asl/mem/sessions/new.asn")))
        (rTr (cg/report! (cfgFor root tr ok0 false)))
        (lone (fixture base "fLone" (list (pair ".asl/mem/sessions/s.asn" "(:s 1)\n"))))
        (rLone (cg/report! (cfgFor root lone ok0 false)))]
    (do
      (assert (= (pairFirst rCherry) 0) (str "a cherry-pick message commits clean: " (pairSecond rCherry)))
      (assert (= (pairFirst rNo) 1) (str "an unknown range is a block, not a pass: " (pairSecond rNo)))
      (assert (stringContains? (pairSecond rNo) ":rule :git") "the row names the git failure")
      (assert (= (pairFirst rNoW) 0) "an unknown range under --warn exits 0")
      (assert (stringContains? (pairSecond rNoW) ":status :wouldBlock") "and reports wouldBlock")
      (assert (= (pairFirst rPart) 1) (str "an exhausted check budget blocks: " (pairSecond rPart)))
      (assert (stringContains? (pairSecond rPart) ":status :partial") (str "the status is partial: " (pairSecond rPart)))
      (assert (stringContains? (pairSecond rPart) ":unchecked (\"a/good.asl\")") "the file is listed as unchecked")
      (assert (= (pairFirst rTr) 0) (str "a new file beside a tracked ignored sibling passes: " (pairSecond rTr)))
      (assert (not (stringContains? (pairSecond rTr) ":rule :ignoredPath")) "with no ignoredPath row")
      (assert (stringContains? (pairSecond rLone) ":rule :ignoredPath") "a lone ignored new file is still reported")
      (assert (stringContains? (pairSecond rLone) ":sev :warn") "as a warning")
      true))

; (:m :ref COMMIT-GUARD-FIX2 :do "a checkout-index export that fails (a path not in the index) is a git block row; a Merge first line is exempt only from the line-count and shape rules, never from the trailer rule; a stale native CLI blocks")
fn ! fix2 root: String base: String -> Bool
  (let [(ok0 (msgAt base "ok2" (goodMsg)))
        (dir (fixture base "fExp" (list (pair "a.txt" "x\n"))))
        (ex (cg/exportStaged! (cfgFor root dir ok0 false) (list "not-in-the-index.txt")))
        (rows (cg/exportHits (pairSecond ex)))
        (good (cg/exportStaged! (cfgFor root dir ok0 false) (list "a.txt")))
        (stale (cg/chunkRows "/src" (list "a.asl") 30 1 "" "/src/a.asl:0:0: ERR_NATIVE_STALE old\n"))]
    (do
      (assert (= (listLength rows) 1) (str "a failed export gives one row: " (pairSecond ex)))
      (assert (= (optionOr (listHead (map (fn [(h cg/Hit)] -> String h.rule) rows)) "") "git") "the row is a git row")
      (assert (listAll? (fn [(h cg/Hit)] -> Bool h.block) rows) "and it blocks")
      (assert (stringContains? (pairSecond ex) "checkout-index failed") "naming checkout-index")
      (assert (stringEmpty? (pairSecond good)) (str "an export of an indexed path succeeds: " (pairSecond good)))
      (assert (listEmpty? (cg/exportHits (pairSecond good))) "with no row")
      (assert (= (sh "." (list "rm" "-rf" (pairFirst ex) (pairFirst good))).exit 0) "export dirs removed")
      (assert (not (listEmpty? (cg/messageHits "Merge x\n\nCo-authored-by: a <a@example.invalid>\n"))) "a Merge first line with a Co-authored-by trailer blocks")
      (assert (not (listEmpty? (cg/messageHits "Revert \"x\"\n\nSigned-off-by: a\n"))) "a Revert first line with a sign-off blocks")
      (assert (listEmpty? (cg/messageHits "Merge x\n\nplain body\n")) "a Merge message with a plain body still passes")
      (assert (listAny? (fn [(h cg/Hit)] -> Bool (and h.block (= h.rule "toolchain"))) stale) "a stale native CLI is a blocking toolchain row")
      true))

; (:m :ref COMMIT-GUARD-PARTIAL-BLOCK :do "a slow-check stub as the asl binary of a private aslRoot with a 1 s deadline from its config: commit mode refuses, HEAD stays, the receipt names the file and the timeout; warn mode commits and records; a fast stub commits; the per-KB term scales the deadline")
fn ! stubRoot! base: String name: String body: String -> String
  (let [(dir (str base "/" name))]
    (do (assert (= (sh "." (list "mkdir" "-p" (str dir "/bin"))).exit 0) (str name ": stub dir"))
        (assert (put (str dir "/bin/asl") body) (str name ": stub body"))
        (assert (= (sh "." (list "chmod" "+x" (str dir "/bin/asl"))).exit 0) (str name ": stub exec"))
        (assert (put (str dir "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 1\n  :commitGuardWarmS 1\n  :commitGuardPerKbMs 2000\n)\n") (str name ": stub config"))
        dir))

; (:m :ref COMMIT-GUARD-PARTIAL-BLOCK :do "an instant stub gets a 5 s deadline so load cannot make it miss; timing-out stubs keep 1 s")
fn roomyCfg -> String
  "(:aslConfig\n  :commitGuardPerFileS 5\n  :commitGuardWarmS 5\n  :commitGuardPerKbMs 2000\n)\n"

fn ! partialGates root: String base: String -> Bool
  (let [(slow (stubRoot! base "slowRoot" "#!/bin/sh\nsleep 20\n"))
        (fast (stubRoot! base "fastRoot" "#!/bin/sh\nshift\nfor f in \"$@\"; do echo \"ok $f: (:checked 1)\"; done\nexit 0\n"))
        (_kf (put (str fast "/.asl.config.asn") (roomyCfg)))
        (cold (stubRoot! base "coldRoot" "#!/bin/sh\nshift\ncase \"$1\" in *guardWarmProbe*) echo \"ok $1: (:checked 1)\"; exit 0;; esac\nm=\"$(dirname \"$0\")/../coldMarker\"\nif [ ! -e \"$m\" ]; then : > \"$m\"; sleep 20; exit 0; fi\nfor f in \"$@\"; do echo \"ok $f: (:checked 1)\"; done\nexit 0\n"))
        (_k (put (str cold "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 1\n  :commitGuardWarmS 8\n  :commitGuardPerKbMs 2000\n)\n"))
        (stuck (stubRoot! base "stuckRoot" "#!/bin/sh\nshift\ncase \"$1\" in *guardWarmProbe*) echo \"ok $1: (:checked 1)\"; exit 0;; esac\nsleep 20\n"))
        (_k2 (put (str stuck "/.asl.config.asn") "(:aslConfig\n  :commitGuardPerFileS 1\n  :commitGuardWarmS 3\n  :commitGuardPerKbMs 2000\n)\n"))
        (c8 (fixture base "pStuck" (list)))
        (_c8 (put (str c8 "/good.asl") (goodAsl)))
        (h8 (head c8))
        (r8 (cg/commit! c8 stuck (list "good.asl") (goodMsg) false))
        (c7 (fixture base "pCold" (list)))
        (_c7 (put (str c7 "/good.asl") (goodAsl)))
        (h7 (head c7))
        (r7 (cg/commit! c7 cold (list "good.asl") (goodMsg) false))
        (silent (stubRoot! base "silentRoot" "#!/bin/sh\nexit 0\n"))
        (_ks (put (str silent "/.asl.config.asn") (roomyCfg)))
        (c6 (fixture base "pSilent" (list)))
        (_s (put (str c6 "/good.asl") (goodAsl)))
        (h6 (head c6))
        (r6 (cg/commit! c6 silent (list "good.asl") (goodMsg) false))
        (c1 (fixture base "pSlow" (list)))
        (_a (put (str c1 "/good.asl") (goodAsl)))
        (h1 (head c1))
        (r1 (cg/commit! c1 slow (list "good.asl") (goodMsg) false))
        (c2 (fixture base "pWarn" (list)))
        (_b (put (str c2 "/good.asl") (goodAsl)))
        (h2 (head c2))
        (r2 (cg/commit! c2 slow (list "good.asl") (goodMsg) true))
        (log2 (resultOr (fileReadString (str c2 "/.asl/log/commitGuard.asn")) ""))
        (c3 (fixture base "pFast" (list)))
        (_c (put (str c3 "/good.asl") (goodAsl)))
        (h3 (head c3))
        (r3 (cg/commit! c3 fast (list "good.asl") (goodMsg) false))
        (cfgS (cg/cfgFor! c1 slow))
        (big (fixture base "pBig" (list (pair "big.asl" (str (goodAsl) (stringRepeat "; padding line for the size term\n" 100))))))
        (secsBig (cg/scaledSecs! cfgS big (list "big.asl")))
        (secsNone (cg/scaledSecs! cfgS big (list)))]
    (do
      (assert (= r1.code 1) (str "commit mode with an unchecked file exits 1: " r1.text))
      (assert (stringContains? r1.text ":commit :refused") "the receipt says refused")
      (assert (stringContains? r1.text ":status :partial") "with status partial")
      (assert (stringContains? r1.text ":unchecked (\"good.asl\")") "and names the unchecked file")
      (assert (stringContains? r1.text "asl check exceeded 1 s") (str "and the timeout cause: " r1.text))
      (assert (= (head c1) h1) "HEAD is unchanged after the refusal")
      (assert (= r2.code 0) (str "warn mode commits despite an unchecked file: " r2.text))
      (assert (!= (head c2) h2) "HEAD moved under warn")
      (assert (stringContains? r2.text ":status :partial") "the warn receipt stays partial")
      (assert (stringContains? log2 ":rule :unchecked") (str "warn records the unchecked row: " log2))
      (assert (= r6.code 1) (str "a checker that exits 0 with no output leaves the file unchecked and blocks: " r6.text))
      (assert (stringContains? r6.text "no ok verdict") "naming the missing verdict")
      (assert (= (head c6) h6) "HEAD unchanged for a silent checker")
      (assert (= r7.code 0) (str "a first check that times out cold passes on the one rerun under warmS: " r7.text))
      (assert (!= (head c7) h7) "HEAD moved after the cold rerun")
      (assert (= r8.code 1) (str "a check that times out on the rerun too blocks: " r8.text))
      (assert (stringContains? r8.text ":status :partial") "with status partial")
      (assert (stringContains? r8.text "asl check exceeded 3 s") (str "the rerun ran under warmS (3 s), not the first deadline: " r8.text))
      (assert (= (head c8) h8) "HEAD unchanged after the second timeout")
      (assert (= r3.code 0) (str "a stub that checks in time commits: " r3.text))
      (assert (!= (head c3) h3) "HEAD moved on a checked file")
      (assert (= cfgS.perFileS 1) "perFileS comes from the config, not an env var")
      (assert (= secsNone 1) "no files add no per-KB term")
      (assert (> secsBig 1) (str "the deadline grows with the size: " (stringFromInt64 secsBig)))
      true))
