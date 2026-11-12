(module asl-forms/tests/flushCheckTest
  :x [runTests]
  :i [(asl-forms/kernel :a k) (asl-forms/vfs :a v) (asl-forms/edit :a e) (asl-proc/jobPool :a jp)])

; (:m :ref FLUSH-AFTER-CHECK :do "the checker is a stub keyed on the text so the flush gate is tested alone: TYPEERR is an error, SKIPME is a check that did not run, SLOW sleeps past a one millisecond limit, PREEXIST is an error the disk file already had")
fn stub -> e/Checkers
  (e/Checkers :aslCheck (fn [(p String) (after String) (before (Option String))] -> e/SyntaxResult
                          (cond
                            ((stringContains? after "TYPEERR") (e/SyntaxResult :status "error" :message (str p ":7:3: ERR_TYPE_MISMATCH argument expected Int64") :before "" :host ""))
                            ((stringContains? after "PREEXIST") (e/SyntaxResult :status "error" :message "old error" :before "error" :host ""))
                            ((stringContains? after "SKIPME") (e/SyntaxResult :status "skipped" :message "native check did not run" :before "" :host ""))
                            ((stringContains? after "SLOW") (do (sleepMs 30) (e/SyntaxResult :status "ok" :message "" :before "" :host "")))
                            (else (e/SyntaxResult :status "ok" :message "" :before "" :host ""))))
              :foreignCheck (fn [(p String) (c String)] -> e/SyntaxResult (e/SyntaxResult :status "skipped" :message "" :before "" :host "")))

fn goodText -> String
  "(module m :x [f])\n\nfn f n: Int64 -> Int64\n  (+ n 1)\n"

fn ! flushOf! vs: v/Vfs target: String extra: (Map String String) -> k/EditOutcome
  (e/flushCheckedStep! vs (stub) (list) 1 (mapSet extra "file" target) (list))

fn ! onDisk target: String -> String
  (resultOr (fileReadString target) "<absent>")

fn ! caseTypeError! vs: v/Vfs dir: String -> Bool
  (let [(t (str dir "/bad.asl"))
        (_ (fileWrite t (goodText)))
        (st (v/stage! vs t (str (goodText) ";TYPEERR\n")))
        (out (flushOf! vs t (mapEmpty)))
        (lines (stringJoin out.lines "\n"))]
    (do (assert (ok? st) "stage the type-error text")
        (assert (= out.errCount 1) (str "a type-error flush is one error: " lines))
        (assert (stringContains? lines ":error-code \":ERR_CHECK\"") (str "the code is ERR_CHECK: " lines))
        (assert (stringContains? lines ":file \"bad.asl\"") (str "the receipt names the file: " lines))
        (assert (stringContains? lines ":line 7") (str "the receipt names the line: " lines))
        (assert (stringContains? lines ":checkCode \"ERR_TYPE_MISMATCH\"") (str "the receipt names the check code: " lines))
        (assert (= (onDisk t) (goodText)) "the file on disk is unchanged")
        (assert (some? (v/stagedContent! vs t)) "the edit stays staged so it can be fixed")
        true))

fn ! caseGood! vs: v/Vfs dir: String -> Bool
  (let [(t (str dir "/good.asl"))
        (_ (fileWrite t (goodText)))
        (st (v/stage! vs t (str (goodText) ";ok\n")))
        (out (flushOf! vs t (mapEmpty)))
        (lines (stringJoin out.lines "\n"))]
    (do (assert (= out.errCount 0) (str "a clean flush has no error: " lines))
        (assert (stringContains? (onDisk t) ";ok") "the clean file is written")
        true))

fn ! caseTxt! vs: v/Vfs dir: String -> Bool
  (let [(t (str dir "/note.txt"))
        (st (v/stage! vs t "TYPEERR in a txt\n"))
        (out (flushOf! vs t (mapEmpty)))]
    (do (assert (= out.errCount 0) "a .txt flush is never type checked")
        (assert (stringContains? (onDisk t) "TYPEERR") "the .txt text is written")
        true))

fn ! caseUnchecked! vs: v/Vfs dir: String -> Bool
  (let [(t (str dir "/skip.asl"))
        (u (str dir "/slow.asl"))
        (_ (fileWrite t (goodText)))
        (_ (fileWrite u (goodText)))
        (a (v/stage! vs t (str (goodText) ";SKIPME\n")))
        (b (v/stage! vs u (str (goodText) ";SLOW\n")))
        (outA (flushOf! vs t (mapEmpty)))
        (outB (flushOf! vs u (mapSet (mapEmpty) "checkMs" "1")))
        (la (stringJoin outA.lines "\n"))
        (lb (stringJoin outB.lines "\n"))]
    (do (assert (and (= outA.errCount 1) (stringContains? la ":unchecked true") (stringContains? la "ERR_CHECK")) (str "a check that did not run refuses with :unchecked: " la))
        (assert (= (onDisk t) (goodText)) "the unchecked file is not written")
        (assert (and (= outB.errCount 1) (stringContains? lb ":unchecked true") (stringContains? lb "deadline")) (str "a check over the deadline refuses with :unchecked: " lb))
        (assert (= (onDisk u) (goodText)) "the overrun file is not written")
        true))

fn ! casePreexisting! vs: v/Vfs dir: String -> Bool
  (let [(t (str dir "/old.asl"))
        (_ (fileWrite t (goodText)))
        (st (v/stage! vs t (str (goodText) ";PREEXIST\n")))
        (out (flushOf! vs t (mapEmpty)))]
    (do (assert (= out.errCount 0) "an error the disk file already had does not block the flush")
        (assert (stringContains? (onDisk t) "PREEXIST") "the file is written")
        true))

fn ! caseAllOrNothing! vs: v/Vfs dir: String -> Bool
  (let [(a (str dir "/aa.asl"))
        (b (str dir "/bb.asl"))
        (_ (fileWrite a (goodText)))
        (_ (fileWrite b (goodText)))
        (s1 (v/stage! vs a (str (goodText) ";fine\n")))
        (s2 (v/stage! vs b (str (goodText) ";TYPEERR\n")))
        (out (e/flushCheckedStep! vs (stub) (list) 1 (mapEmpty) (list)))]
    (do (assert (= out.errCount 1) "a flush of everything staged refuses when any file fails")
        (assert (= (onDisk a) (goodText)) "the clean file staged beside the bad one is not written either")
        (assert (= (onDisk b) (goodText)) "the bad file is not written")
        true))

fn ! caseBadFirst! vs: v/Vfs dir: String -> Bool
  (let [(a (str dir "/ab.asl"))
        (b (str dir "/ac.asl"))
        (_ (fileWrite a (goodText)))
        (_ (fileWrite b (goodText)))
        (s1 (v/stage! vs a (str (goodText) ";TYPEERR\n")))
        (s2 (v/stage! vs b (str (goodText) ";fine\n")))
        (out (e/flushCheckedStep! vs (stub) (list) 1 (mapEmpty) (list)))]
    (do (assert (= out.errCount 1) "a bad file first and a good file after it still refuses the flush")
        (assert (and (= (onDisk a) (goodText)) (= (onDisk b) (goodText))) "neither file is written when the bad one comes first")
        true))

; (:m :ref FLUSH-AFTER-CHECK :do "the (:flush) path: editOp! with op flush must reach the checked flush, so a type error staged for a file is refused with ERR_CHECK and the disk stays as it was")
fn ! caseEditOp! vs: v/Vfs dir: String -> Bool
  (let [(t (str dir "/viaop.asl"))
        (_ (fileWrite t (goodText)))
        (st (v/stage! vs t (str (goodText) ";TYPEERR\n")))
        (run (fn [(i Int64) (c String) (a (List String))] -> k/EditOutcome (k/EditOutcome :lines (list) :errCount 0)))
        (res (e/editOp! vs (stub) run (list) 1 "flush" (mapSet (mapEmpty) "file" t) (list)))
        (lines (match res ((some o) (stringJoin o.lines "\n")) ((none) "")))]
    (do (assert (some? res) "editOp! handles op flush")
        (assert (stringContains? lines "ERR_CHECK") (str "the flush op refuses a type error: " lines))
        (assert (= (onDisk t) (goodText)) "the flush op leaves the disk unchanged")
        true))

fn ! caseClamp! -> Bool
  (do (assert (= (e/flushLimit (mapEmpty)) (e/flushCheckDeadlineMs)) "no :checkMs is the default limit")
      (assert (= (e/flushLimit (mapSet (mapEmpty) "checkMs" "99999999")) (e/flushCheckDeadlineMs)) "a caller cannot raise the limit above the default")
      (assert (= (e/flushLimit (mapSet (mapEmpty) "checkMs" "5")) 5) "a caller may lower the limit")
      (assert (= (e/flushLimit (mapSet (mapEmpty) "checkMs" "abc")) (e/flushCheckDeadlineMs)) "a non-numeric :checkMs is the default")
      (assert (= (e/flushLimit (mapSet (mapEmpty) "checkMs" "0")) (e/flushCheckDeadlineMs)) "a zero :checkMs is the default")
      true)

fn ! runTests -> Bool
  (let [(made (jp/runOne (jp/job (list "mktemp" "-d") "." (jp/childEnv (list)))))
        (rawDir (stringReplace made.out "\n" ""))
        (dir (match (realPath rawDir) ((ok r) r) ((err _) rawDir)))
        (vdir (str dir "/.asl/vfs"))]
    (do (assert (= made.exit 0) "mktemp -d makes a workspace directory")
        (assert (ok? (dirCreate vdir)) "vfs dir created")
        (assert (ok? (fileWrite (str dir "/manifest.asn") "(:package flushcheck)\n")) "manifest written")
        (let [(vs (v/vfsAt dir vdir "flushCheckTest"))]
          (do (caseAllOrNothing! (v/vfsAt dir vdir "flushCheckAll") dir) (caseBadFirst! (v/vfsAt dir vdir "flushCheckBad") dir) (caseEditOp! (v/vfsAt dir vdir "flushCheckOp") dir) (caseClamp!) (caseTypeError! vs dir) (caseGood! vs dir) (caseTxt! vs dir) (caseUnchecked! vs dir) (casePreexisting! vs dir)
              (assert (= (jp/runOne (jp/job (list "rm" "-rf" dir) "." (jp/childEnv (list)))).exit 0) "workspace removed")
              true))))
