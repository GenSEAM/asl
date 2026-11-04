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
  (cg/Cfg :repo dir :aslRoot root :range "" :msgFile msgFile :warn warn :perFileS 30 :totalS 90 :gitS 30)

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
    (assert (= (listLength (cg/conflictHits (list (pair "f" (str (strRep "=") "")) (pair "f" (str (strRep ">") " main")) (pair "f" (str (strRep "<") " HEAD")) (pair "f" "a = b") (pair "f" (str (strRep "=") "="))))) 3) "each of the three marker shapes is a hit and near-misses are not")
    (assert (not (cg/secretLine? "let x = 1")) "ordinary code is no secret")
    (assert (cg/secretLine? (str "key " "sk-" "abcdefghijklmnopqrstuvwxyz0123")) "a provider key shape is a secret")
    (assert (cg/secretLine? (str "AK" "IA" "ABCDEFGHIJKLMNOP")) "an access key id is a secret")
    (assert (cg/secretLine? (str "OPENAI_API_" "KEY=" "abcdefghijklmnopqrstuvwxyz")) "NAME_API_KEY=longvalue is a secret")
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
      (assert (= (pairFirst rIgn) 1) (str "a new file under an ignored path blocks: " (pairSecond rIgn)))
      (assert (stringContains? (pairSecond rIgn) ":rule :ignoredPath") "the row names the ignored path rule")
      (assert (= (pairFirst rSec) 1) (str "a credential value blocks: " (pairSecond rSec)))
      (assert (stringContains? (pairSecond rSec) ":rule :secret") "the row names the secret rule")
      (assert (not (stringContains? (pairSecond rSec) "abcdefghijklmnopqrstuvwxyz0123")) "the receipt never prints the value")
      (assert (= (pairFirst warnU) 0) "--warn on an unbalanced file plus a bad message exits 0")
      (assert (stringContains? (pairSecond warnU) ":status :wouldBlock") "--warn still reports the rows as wouldBlock")
      (assert (stringContains? (pairSecond warnU) ":rule :balance") "--warn keeps the rows")
      (assert (= (pairFirst warnF) 0) "--warn on foreign growth plus a trailer exits 0")
      true))

fn ! runTests -> Bool
  (let [(base (scratch))
        (root (resultOr (realPath ".") "."))]
    (do (assert (= (sh "." (list "mkdir" "-p" base)).exit 0) "private base")
        (assert (pureRules) "pure rules")
        (assert (fixtures root base) "fixture repos")
        (assert (= (sh "." (list "rm" "-rf" base)).exit 0) "private base removed")
        true))

fn strRep c: String -> String
  (str c c c c c c c)
