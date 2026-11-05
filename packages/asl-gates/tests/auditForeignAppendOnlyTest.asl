(module ws/auditForeignAppendOnlyTest
  :x [runTests]
  :i [(asl-gates/auditForeign :a af) (asl-gates/suiteRunner :a sr) (asl-proc/coreProcess :a p)])

fn gitArgs args: (List String) -> (List String)
  (listAppend (list "-c" "init.defaultBranch=work" "-c" "commit.gpgsign=false" "-c" "core.autocrlf=false"
                    "-c" "user.name=fba" "-c" "user.email=fba@localhost")
              args)

fn runGit! root: String args: (List String) -> (Result String String)
  (let [(c0 (p/withTimeout (p/withCwd (p/cmd "git" (gitArgs args)) root) 120000))]
    (match (p/exec! c0)
      ((err _) (err (str "git " (stringJoin args " ") " could not run")))
      ((ok o) (if (= o.exitCode 0) (ok o.stdout) (err (str "git " (stringJoin args " ") ": " o.stderr))))))

fn gitStep! root: String args: (List String) -> (Result Bool String)
  (resultMap (runGit! root args) (fn [(s String)] -> Bool true))


fn allowText -> String
  (str "(:foreignAllowlist :v 1 :owner \"FBA\" :date \"2026-11-05\"\n"
       "  :doc \"fixture\"\n"
       "  (:path \"a.sh\" :kind :shell :rationale \"fixture\" :until :none :reason \"fixture\"))\n")

fn baseLines -> String
  (str "(:foreignBaseline :v 1 :owner \"FBA\" :date \"2026-11-05\"\n"
       "  :doc \"fixture\"\n"
       "  (:file :path \"a.sh\" :lang :shell :lines 3 :py 0)\n")

fn pastRaise lines: String -> String
  (str "  (:raise :path \"a.sh\" :lang :shell :lines " lines " :py 0 :reason \"fixture\" :date \"2026-10-01\")")

fn baseOnly -> String
  (str (baseLines) (pastRaise "4") ")\n")

fn appendedOnly -> String
  (str (baseLines) (pastRaise "4") "\n"
       "  (:raise :path \"a.sh\" :lang :shell :lines 3 :py 0 :reason \"fixture\" :date \"2026-11-01\")"
       ")\n")

fn rewrittenPast -> String
  (str (baseLines) (pastRaise "7") ")\n")

fn deletedPast -> String
  (str (baseLines) ")\n")

fn writeFile! root: String rel: String text: String -> (Result Bool String)
  (match (fileWrite (str root "/" rel) (stringToBytes text))
    ((ok _) (ok true))
    ((err e) (err (str "write " rel ": " e))))

fn writeFixture! root: String -> (Result Bool String)
  (match (dirCreate (str root "/scripts/audit"))
    ((err e) (err e))
    ((ok _) (match (writeFile! root "a.sh" "#!/bin/sh\necho one\necho two\n")
      ((err e) (err e))
      ((ok _) (match (writeFile! root "scripts/audit/foreignAllowlist.asn" (allowText))
        ((err e) (err e))
        ((ok _) (writeFile! root "scripts/audit/foreignBaseline.asn" (baseOnly))))))))

fn buildRepo! root: String -> (Result String String)
  (match (writeFixture! root)
    ((err e) (err e))
    ((ok _) (match (gitStep! root (list "init" "-q"))
      ((err e) (err e))
      ((ok _) (match (gitStep! root (list "add" "-A"))
        ((err e) (err e))
        ((ok _) (match (gitStep! root (list "commit" "-q" "--no-verify" "-m" "base"))
          ((err e) (err e))
          ((ok _) (resultMap (runGit! root (list "rev-parse" "HEAD")) (fn [(s String)] -> String (stringTrim s)))))))))))

fn auditWith! root: String base: String baseTxt: String -> (Result Audit String)
  (match (writeFile! root "scripts/audit/foreignBaseline.asn" baseTxt)
    ((err e) (err e))
    ((ok _) (af/foreignAudit! root false base)))

fn failingIds au: Audit -> (List String)
  (map (fn [(c Check)] -> String c.id) (filter (fn [(c Check)] -> Bool (!= c.status ":passed")) au.checks))

fn failingEv au: Audit -> String
  (stringJoin (map (fn [(c Check)] -> String c.ev) (filter (fn [(c Check)] -> Bool (and (= c.id "foreignRaise") (!= c.status ":passed"))) au.checks)) " ")

fn appendOnlyStatus au: Audit -> String
  (stringJoin (map (fn [(c Check)] -> String c.status) (filter (fn [(c Check)] -> Bool (= c.id "foreignRaise")) au.checks)) " ")

fn ! runTests -> Bool
  (match (sr/makeTempDir! "aslFbAppendOnly")
    ((err e) (do (assert false (str "temp dir: " e)) false))
    ((ok root)
     (match (buildRepo! root)
       ((err e) (do (assert false (str "fixture repo: " e)) false))
       ((ok base)
        (match (auditWith! root base (appendedOnly))
          ((err e) (do (assert false (str "appended audit errored: " e)) false))
          ((ok appended)
           (match (auditWith! root base (rewrittenPast))
             ((err e) (do (assert false (str "rewritten audit errored: " e)) false))
             ((ok rewritten)
              (match (auditWith! root base (deletedPast))
                ((err e) (do (assert false (str "deleted audit errored: " e)) false))
                ((ok deleted)
                 (do
                   (assert (listEmpty? (failingIds appended)) (str "unchanged base plus an appended row is green, failing: " (stringJoin (failingIds appended) " ")))
                   (assert (= (appendOnlyStatus appended) ":passed") "the append-only check exists and passes for an appended row")
                   (assert (listContains? (failingIds rewritten) "foreignRaise") "a past :raise row rewritten to other numbers fails foreignRaise")
                   (assert (stringContains? (failingEv rewritten) "a.sh") "the rewrite finding names the path")
                   (assert (stringContains? (failingEv rewritten) ":lines 4 :py 0") "the rewrite finding quotes the old form")
                   (assert (listContains? (failingIds deleted) "foreignRaise") "a past :raise row deleted at head fails foreignRaise")
                   (assert (stringContains? (failingEv deleted) "a.sh") "the deletion finding names the path")
                   true)))))))))))
