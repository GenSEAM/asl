(module ws/auditForeignInlineTest
  :x [runTests]
  :i [(asl-gates/auditForeign :a af) (asl-foreign/block :a f) (asl-proc/coreProcess :a p)])

fn fixture -> String
  (str "(module sample :i [(asl-foreign/block :a f)])\n"
       "; (bad/c \"comment text\nnot a block\")\n"
       "\"(bad/sql \\\"string text\nnot a block\\\")\"\n"
       "(fn script -> String\n"
       "  (f/js \"first\nsecond\nthird\nfourth\")\n"
       "  (f/py (str \"one\ntwo\n\" \"three\")))\n")

fn commentedCall -> String
  (str "(module sample :i [(asl-foreign/block :a f)])\n"
       "; (f/c \"commented out\")\n"
       "(f/js \"live\nline\")\n")

fn importAfterList -> String
  (str "(module sample :i [(other/module :a q)])\n"
       "(fn helper -> Unit (asl-foreign/block :a f))\n"
       "(f/js \"not imported\nline\")\n")

fn aliasAtEnd -> String
  "(module sample :i [(asl-foreign/block :a fff)])\n(ff"

fn wrongAlias -> String
  (str "(module sample :i [(asl-foreign/block :a g)])\n"
       "(f/js \"not imported\nline\")\n")

fn withoutImport -> String
  (str "(module sample)\n"
       "(f/js \"not imported\nline\")\n")

fn aliasFromDifferentImport -> String
  (str "(module sample :i [(asl-foreign/block) (other/module :a f)])\n"
       "(f/js \"must not count\nline\")\n")

fn prefixImport -> String
  (str "(module sample :i [(asl-foreign/blocking :a f)])\n"
       "(f/js \"must not count\nline\")\n")

fn nestedLiteral -> String
  (str "(module sample :i [(asl-foreign/block :a f)])\n"
       "(f/sql (str (str \"nested\nthree\nlines\") \"outer\nline\"))\n")

fn countOf counts: (Map String Int64) lang: String -> Int64
  (optionOr (mapGet counts lang) 0)

fn escaperCalls -> String
  (str "(module sample :i [(asl-foreign/block :a f)])\n"
       "(f/jsStr \"a\nb\") (f/pyStr \"c\nd\") (f/shArg \"e\nf\")\n"
       "(f/sqlStr \"g\nh\") (f/htmlText \"i\nj\") (f/cssStr \"k\nl\")\n")

fn everyLanguage -> String
  (str "(module sample :i [(asl-foreign/block :a f)])\n"
       "(f/c \"one\") (f/css \"one\ntwo\") (f/html \"one\ntwo\nthree\")\n"
       "(f/llvm \"1\n2\n3\n4\") (f/sh \"1\n2\n3\n4\n5\") (f/sql \"1\n2\n3\n4\n5\n6\")\n")

fn aliasWithoutSlash -> String
  (str "(module sample :i [(asl-foreign/block :a f)])\n"
       "(fxjs \"must not count\nline\") (f.py \"must not\ncount\")\n")

fn packageLocalAlias -> String
  (str "(module asl-foreign/test :i [(block :a f)])\n"
       "(f/js \"one\ntwo\")\n")

fn nonStrHead -> String
  (str "(module sample :i [(asl-foreign/block :a f)])\n"
       "(f/js (cat \"a\nb\"))\n")

fn headerAfterBlankLine -> String
  (str "(module sample)\n"
       "\n"
       ":i [(asl-foreign/block :a f)]\n"
       "(f/js \"must not count\nline\")\n")

fn countsText counts: (Map String Int64) -> String
  (stringJoin (map (fn [(k String)] -> String (str k " " (stringFromInt64 (countOf counts k)))) (listSort (mapKeys counts))) " ")

fn liveJs -> String
  (f/js "first
second
third
fourth")

fn livePy -> String
  (f/py (str "one
two
" "three"))

fn selfPath -> String
  "asl/packages/asl-gates/tests/auditForeignInlineTest.asl"

fn blockTestPath -> String
  "asl/packages/asl-foreign/tests/blockTest.asl"

fn actualFileCounts! -> (Map String Int64)
  (mt (fileReadString (selfPath))
    ((ok raw) (af/inlineForeignCounts raw (selfPath)))
    ((err _) (mapEmpty)))

fn ! actualInlineReport -> (Result af/InlineReport String)
  (af/inlineAll! "." (list (selfPath))
    (af/InlineReport :counts (mapEmpty) :files (list) :total 0))

fn blockTestFileCounts! -> (Map String Int64)
  (mt (fileReadString (blockTestPath))
    ((ok raw) (af/inlineForeignCounts raw (blockTestPath)))
    ((err _) (mapEmpty)))

fn fixtureTwo -> String
  (str "(module sample2 :i [(asl-foreign/block :a f)])\n"
       "(f/sh \"only\nline\")\n")

fn git! root: String args: (List String) -> (Result String String)
  (let [(c (p/withTimeout (p/withCwd (p/cmd "git" (listAppend (list "-c" "init.defaultBranch=work" "-c" "commit.gpgsign=false" "-c" "user.name=inline" "-c" "user.email=inline@localhost") args)) root) 60000))]
    (mt (p/exec! c)
      ((err _) (err (str "git " (stringJoin args " ") " could not run")))
      ((ok o) (if (= o.exitCode 0) (ok o.stdout) (err (str "git " (stringJoin args " ") ": " o.stderr))))))

fn writeAll! root: String -> (Result Bool String)
  (mt (dirCreate (str root "/scripts/audit"))
    ((err e) (err e))
    ((ok _)
     (mt (dirCreate (str root "/src"))
       ((err e) (err e))
       ((ok _)
        (mt (fileWrite (str root "/scripts/audit/foreignAllowlist.asn") "(:foreignAllowlist :v 1)\n")
          ((err e) (err e))
          ((ok _)
           (mt (fileWrite (str root "/scripts/audit/foreignBaseline.asn") "(:foreignBaseline :v 1)\n")
             ((err e) (err e))
             ((ok _) (resultMap (fileWrite (str root "/src/sample.asl") (fixture)) (fn [(u Unit)] -> Bool true))))))))))

fn fixtureReceipt! root: String -> (Result String String)
  (let [(built (mt (writeAll! root)
                 ((err e) (err e))
                 ((ok _)
                  (mt (git! root (list "init" "-q"))
                    ((err e) (err e))
                    ((ok _)
                     (mt (git! root (list "add" "-A"))
                       ((err e) (err e))
                       ((ok _) (git! root (list "commit" "-q" "-m" "fixture")))))))))
        (receipt (mt built ((err e) (err (str "fixture: " e))) ((ok _) (ok (af/runForeign! root (list) "HEAD").receipt))))]
    (mt (pathRemove root)
      ((err e) (err (str "cleanup: " e)))
      ((ok _) receipt)))

fn writeAllTwo! root: String -> (Result Bool String)
  (mt (dirCreate (str root "/scripts/audit"))
    ((err e) (err e))
    ((ok _)
     (mt (dirCreate (str root "/src"))
       ((err e) (err e))
       ((ok _)
        (mt (fileWrite (str root "/scripts/audit/foreignAllowlist.asn") "(:foreignAllowlist :v 1)\n")
          ((err e) (err e))
          ((ok _)
           (mt (fileWrite (str root "/scripts/audit/foreignBaseline.asn") "(:foreignBaseline :v 1)\n")
             ((err e) (err e))
             ((ok _)
              (mt (fileWrite (str root "/src/aaa.asl") (fixtureTwo))
                ((err e) (err e))
                ((ok _) (resultMap (fileWrite (str root "/src/sample.asl") (fixture)) (fn [(u Unit)] -> Bool true))))))))))))

fn twoFileReceipt! root: String -> (Result String String)
  (let [(built (mt (writeAllTwo! root)
                 ((err e) (err e))
                 ((ok _)
                  (mt (git! root (list "init" "-q"))
                    ((err e) (err e))
                    ((ok _)
                     (mt (git! root (list "add" "-A"))
                       ((err e) (err e))
                       ((ok _) (git! root (list "commit" "-q" "-m" "fixture")))))))))
        (receipt (mt built ((err e) (err (str "fixture: " e))) ((ok _) (ok (af/runForeign! root (list) "HEAD").receipt))))]
    (mt (pathRemove root)
      ((err e) (err (str "cleanup: " e)))
      ((ok _) receipt)))

fn ! extFilterRoot! -> String
  (str (optionOr (envGet "TMPDIR") "/tmp/") "aslInlineExtFilter." (stringFromInt64 (nowNs)))

fn ! extFilterReport! -> (Result af/InlineReport String)
  (let [(root (extFilterRoot!))
        (made (and (ok? (dirCreate root))
                   (and (ok? (fileWrite (str root "/sample.asl") (fixture)))
                        (ok? (fileWrite (str root "/sample.txt") (fixture))))))
        (rep (if made
               (af/inlineAll! root (list "sample.asl" "sample.txt") (af/InlineReport :counts (mapEmpty) :files (list) :total 0))
               (err "extFilter fixture setup failed")))
        (cleaned (pathRemove root))]
    (mt cleaned
      ((err e) (err (str "cleanup: " e)))
      ((ok _) rep)))

fn ! runTests -> Bool
  (let [(counts (af/inlineForeignCounts (fixture) "")) (receipt (mt (fixtureReceipt! (str "/tmp/aslForeignInline." (stringFromInt64 (nowNs)))) ((ok r) r) ((err e) e)))
        (twoReceipt (mt (twoFileReceipt! (str "/tmp/aslForeignInlineTwo." (stringFromInt64 (nowNs)))) ((ok r) r) ((err e) e)))
        (extReport (extFilterReport!))
        (localCounts (af/inlineForeignCounts (packageLocalAlias) "asl/packages/asl-foreign/tests/local.asl"))
        (localCountsOutside (af/inlineForeignCounts (packageLocalAlias) "asl/packages/asl-other/tests/local.asl"))
        (blockCounts (blockTestFileCounts!))]
    (do
      (assert (= (countOf counts "javascript") 4) "four JS lines attributed through the imported alias")
      (assert (= (countOf counts "python") 3) "three Python lines summed across str literals")
      (assert (= (listSort (mapKeys (af/inlineForeignCounts (commentedCall) ""))) (list "javascript")) "a call behind ; with the imported alias is not counted")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (importAfterList) ""))) 0) "the import scan stops at the closing ] of :i")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (aliasAtEnd) ""))) 0) "text ending inside an alias prefix scans without a range error")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (wrongAlias) ""))) 0) "a foreign-looking head with the wrong alias is ignored")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (withoutImport) ""))) 0) "foreign-looking heads require the module import")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (aliasFromDifferentImport) ""))) 0) "an alias from another import is not borrowed")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (prefixImport) ""))) 0) "a prefix module name is not the foreign block import")
      (assert (= (countOf (af/inlineForeignCounts (nestedLiteral) "") "sql") 2) "str counts its two-line direct literal, not the three-line nested one")
      (assert (= (countOf (actualFileCounts!) "javascript") (af/countLines (liveJs))) "scanned JavaScript lines equal the lines of the live js block")
      (assert (= (countOf (actualFileCounts!) "python") (af/countLines (livePy))) "scanned Python lines equal the lines of the live py block")
      (assert (= (mt (actualInlineReport) ((ok r) r.total) ((err _) -1)) 7) "the listed .asl file reports seven inline lines total")
      (assert (mt (actualInlineReport) ((ok r) (listContains? r.files (str (selfPath) " 7"))) ((err _) false)) "the report includes the per-file seven-line count")
      (assert (stringContains? receipt ":inlineForeignLines 7 :inlineForeignByFile (src/sample.asl 7)") "the fixture receipt reports inline lines by file")
      (assert (stringContains? receipt ":lines 0 :limit 0 :embeddedPy 0 :byLang () :base") "inline lines stay out of :lines and :byLang, so :byLang sums to :lines")
      (assert (stringContains? receipt ":inlineByLang (:javascript 4 :python 3)") "the fixture receipt reports inline lines by language in their own field")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (escaperCalls) ""))) 0) "escaper calls sharing a language prefix are not blocks")
      (assert (= (countsText (af/inlineForeignCounts (everyLanguage) "")) "c 1 css 2 html 3 llvm 4 shell 5 sql 6") "each block head counts under its own language")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (aliasWithoutSlash) ""))) 0) "the alias must be followed by a slash")
      (assert (= (countOf localCounts "javascript") 2) "a package-local bare block alias inside asl/packages/asl-foreign/ is recognized")
      (assert (= (listLength (mapKeys localCountsOutside)) 0) "the same bare block alias outside asl/packages/asl-foreign/ is not the foreign import")
      (assert (= (countOf blockCounts "javascript") 4) "asl-foreign's own blockTest.asl, which imports block :a f package-locally, is counted (js)")
      (assert (= (countOf blockCounts "python") 1) "asl-foreign's own blockTest.asl is counted (python)")
      (assert (= (countOf (af/inlineForeignCounts (nonStrHead) "") "javascript") 0) "a block body that is not a direct str call (f/js (cat ...)) counts no literal")
      (assert (= (listLength (mapKeys (af/inlineForeignCounts (headerAfterBlankLine) ""))) 0) "the header scan stops at the first blank line, so a later :i [ in the file body is not the module's import list")
      (assert (stringContains? twoReceipt ":inlineForeignByFile (src/aaa.asl 2 src/sample.asl 7)") "the per-file list keeps git ls-files order across more than one file, not the reverse of processing order")
      (assert (mt extReport ((ok r) (= r.total 7)) ((err _) false)) "only the .asl sibling of an identical .txt file is scanned, so the total is not doubled")
      (assert (mt extReport ((ok r) (= (listLength r.files) 1)) ((err _) false)) "the non-.asl file adds no entry to the per-file report")
      true))
