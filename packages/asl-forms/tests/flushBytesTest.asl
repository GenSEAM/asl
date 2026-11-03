(module asl-forms/tests/flushBytesTest :x [runTests] :i [(asl-forms/kernel :a k) (asl-forms/tests/formsDriver :a fd) (asl-tools/fleet/run :a fr)])

fn scratchDir! tag: String -> String
  (str (optionOr (envGet "TMPDIR") "/tmp/") tag "_" (stringFromInt64 (mod (nowNs) 1000000000)))

; (:m :ref FORMS-FLUSH-CR :do "the forms host runs through fleet/run with a 60 s timeout and a descendant limit, so a hung or forking child is killed with its tree")
fn txnRun! root: String payload: String -> fr/Done
  (let [(repo (resultOr (realPath ".") ""))
        (host (fd/formsBin! repo))
        (env (list (str "PATH=" (optionOr (envGet "PATH") "")) (str "ASL_VFS_DIR=" (k/joinPath root ".asl/vfs"))))]
    (fr/runOneLimited (fr/job (list host "--root" root payload) repo env) (fr/limits 60 16)))

fn editForm file: String old: String new: String -> String
  (str "(:txn :owns (\"" file "\") (:edit :file \"" file "\" :old \"" old "\" :new \"" new "\"))")

fn diskText root: String file: String -> String
  (resultOr (fileReadString (k/joinPath root file)) "<unreadable>")

; (:m :ref FORMS-FLUSH-CR :do "bytes outside the edited span reach the disk unchanged: CRLF, a lone CR, a tab, trailing spaces and a missing final newline")
fn testBytesOutsideHunk! -> Bool
  (let [(root (scratchDir! "aslFormsFlushBytes"))
        (before "first line\r\nsecond\rthird\tx  \r\nfour\n\r\nlast")
        (made (and (ok? (dirCreate root)) (ok? (fileWrite (k/joinPath root "t.txt") before))))
        (out (txnRun! root (editForm "t.txt" "first line" "FIRST line")))
        (after (diskText root "t.txt"))
        (_ (pathRemove root))]
    (do
      (assert made "scratch file written")
      (assert (stringContains? out.out ":status \"ok\"") (str "the edit commits: " out.out))
      (assert (= after "FIRST line\r\nsecond\rthird\tx  \r\nfour\n\r\nlast") (str "only the hunk changed, every other byte is as it was: " (stringFromInt64 (stringLength after)) " bytes"))
      true))

; (:m :ref FORMS-FLUSH-CR :do "an :old or :new that spans lines matches a CRLF file by its LF form and is written back with CRLF, so the file keeps one line ending")
fn testMultiLineOnCrlf! -> Bool
  (let [(root (scratchDir! "aslFormsFlushCrlf"))
        (made (and (ok? (dirCreate root)) (ok? (fileWrite (k/joinPath root "c.txt") "a\r\nb\r\nc\r\n"))))
        (out (txnRun! root (editForm "c.txt" "a\\nb" "x\\ny\\nz")))
        (after (diskText root "c.txt"))
        (_ (pathRemove root))]
    (do
      (assert made "scratch file written")
      (assert (stringContains? out.out ":status \"ok\"") (str "the multi-line edit commits on a CRLF file: " out.out))
      (assert (= after "x\r\ny\r\nz\r\nc\r\n") (str "the replaced lines carry CRLF and the rest is untouched: " (stringFromInt64 (stringLength after)) " bytes"))
      true))

fn editFormAll file: String old: String new: String -> String
  (str "(:txn :owns (\"" file "\") (:edit :file \"" file "\" :old \"" old "\" :new \"" new "\" :all true))")

; (:m :ref FORMS-FLUSH-CR :do "a file with both endings keeps each: a span whose first break is CRLF is written with CRLF, a span with no break takes the file's first break (LF here), and bytes outside the spans are untouched")
fn testMixedEndings! -> Bool
  (let [(root (scratchDir! "aslFormsFlushMixed"))
        (made (and (ok? (dirCreate root)) (ok? (fileWrite (k/joinPath root "m.txt") "a\nb\r\nc\n"))))
        (crlfSpan (txnRun! root (editForm "m.txt" "b\\nc" "X\\nY")))
        (afterCrlf (diskText root "m.txt"))
        (lfSpan (txnRun! root (editForm "m.txt" "a" "A\\nA2")))
        (afterLf (diskText root "m.txt"))
        (_ (pathRemove root))]
    (do
      (assert made "scratch file written")
      (assert (stringContains? crlfSpan.out ":status \"ok\"") (str "the edit over a CRLF break commits: " crlfSpan.out))
      (assert (= afterCrlf "a\nX\r\nY\n") (str "the CRLF span is rewritten with CRLF and the LF lines stay LF: " (stringFromInt64 (stringLength afterCrlf)) " bytes"))
      (assert (stringContains? lfSpan.out ":status \"ok\"") (str "the edit on a line with no break commits: " lfSpan.out))
      (assert (= afterLf "A\nA2\nX\r\nY\n") (str "a span with no break takes the file's first break, LF: " (stringFromInt64 (stringLength afterLf)) " bytes"))
      true))

; (:m :ref FORMS-FLUSH-CR :do "every occurrence of an :all edit is located in the LF view and written back at its raw offset, so the CRLF between occurrences survives")
fn testAllOnCrlf! -> Bool
  (let [(root (scratchDir! "aslFormsFlushAll"))
        (made (and (ok? (dirCreate root)) (ok? (fileWrite (k/joinPath root "q.txt") "q\r\nq\r\nz\rq"))))
        (out (txnRun! root (editFormAll "q.txt" "q" "r")))
        (after (diskText root "q.txt"))
        (_ (pathRemove root))]
    (do
      (assert made "scratch file written")
      (assert (stringContains? out.out ":replacements 3") (str "three occurrences are replaced: " out.out))
      (assert (= after "r\r\nr\r\nz\rr") (str "line ends and the lone CR between the occurrences are untouched: " (stringFromInt64 (stringLength after)) " bytes"))
      true))

; (:m :ref FORMS-FLUSH-CR :do "a CRLF .asl source still validates and is edited in place: a multi-line :old matches by its LF form, the replaced lines carry CRLF and every other byte is as it was")
fn testCrlfSource! -> Bool
  (let [(root (scratchDir! "aslFormsFlushSrc"))
        (before "(module crlfMod :x [f])\r\n\r\nfn f -> Int\r\n  1\r\n\r\nfn g -> Int\r\n  2\r\n")
        (made (and (ok? (dirCreate root)) (ok? (fileWrite (k/joinPath root "m.asl") before))))
        (out (txnRun! root (editForm "m.asl" "fn f -> Int\\n  1" "fn f -> Int\\n  3")))
        (after (diskText root "m.asl"))
        (_ (pathRemove root))]
    (do
      (assert made "scratch file written")
      (assert (stringContains? out.out ":status \"ok\"") (str "the edit validates and commits on a CRLF source: " out.out))
      (assert (= after "(module crlfMod :x [f])\r\n\r\nfn f -> Int\r\n  3\r\n\r\nfn g -> Int\r\n  2\r\n") (str "the edited lines carry CRLF and the rest is untouched: " (stringFromInt64 (stringLength after)) " bytes"))
      true))

fn runTests -> Bool
  (do (testBytesOutsideHunk!) (testMultiLineOnCrlf!) (testMixedEndings!) (testAllOnCrlf!) (testCrlfSource!) true)
