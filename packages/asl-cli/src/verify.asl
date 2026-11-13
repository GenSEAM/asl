(module asl-cli/verify
  :x [checkFiles! checkRoots nativeCheckPaths! nativeCheckStaged! checkStaged! Staged normalisePaths formatDiag formatDiags formatDiagsHinted! diagHints! indentFields! balanceReceipt!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-gates/src/dyck :a dyck) (asl-forms/indent :a ind) (asl-checker/checkCached :a cc) (asl-checker/types :a ty) (asl-checker/hints :a hn)])

fn checkRoots -> (List String)
  (list "." "asl/packages" "asl")

; (:m :ref U4-MARKER-PARITY :do "the one shared formatter for a checker Diagnostic's path:line:col CODE message line; asl check (printDiag! below) and asl/tools/nativeTest.asl's test/run checker gate both render through this, so a failing fixture names the same site in check, test and run alike")
fn formatDiag d: ty/Diagnostic -> String
  (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message (hn/priorFix d))

fn formatDiags diags: (List ty/Diagnostic) -> String
  (stringJoin (map formatDiag diags) "\n")

fn balanceError rc: Int64 -> String
  (if (= rc 2) "ERR_NO_FILE" "ERR_UNBALANCED")

; (:m :ref PAREN-CHECK-DIAG :do "an unbalanced file's receipt carries the closer edits its indentation implies, each naming its opener and deciding line, and the (:fix) form that stages them; none when indentation implies no edit")
fn indentFields! path: String -> String
  (match (fileReadString path)
    ((err _) "")
    ((ok text)
      (let [(g (ind/guideBroken text))]
        (if (listEmpty? g.edits)
          ""
          (str " :indent " (ind/editsAsnIn text g.edits) " :fix \"(:fix :file \\\"" (dyck/esc (dyck/esc path)) "\\\" :by :indent :apply true)\"")))))

fn balanceReceipt! path: String -> String
  (pairSecond (dyck/reportFile! path (fn [(p String)] -> String (indentFields! p))))

; (:m :ref PAREN-CHECK-HOST-MSG :do "a reader balance error (ERR_READ_UNBALANCED, or the checker's parse code with an unmatched/unclosed/closes/unterminated message, which asl test and run hit with no balance pass first) is followed by one (:indentFix ...) line per file naming the closer edits indentation implies; the diagnostic lines themselves keep their path:line:col CODE form")
fn unbalancedRead? d: ty/Diagnostic -> Bool
  (or (or (stringStartsWith? d.code "ERR_READ_UNBALANCED") (= d.code "ERR_UNBALANCED"))
      (and (= d.code "parse") (listAny? (fn [(w String)] -> Bool (stringContains? d.message w)) (list "unmatched" "unclosed" " closes " "unterminated"))))

fn ! indentLine! path: String -> String
  (let [(fields (indentFields! path))]
    (if (stringEmpty? fields) "" (str "(:indentFix :file \"" (dyck/esc path) "\"" fields ")")))

fn ! diagHints! diags: (List ty/Diagnostic) -> (List String)
  (let [(paths (fold (fn [(acc (List String)) (d ty/Diagnostic)] -> (List String) (if (and (unbalancedRead? d) (not (listContains? acc d.path))) (listAppend acc (list d.path)) acc))
                     (list) diags))]
    (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map (fn [(p String)] -> String (indentLine! p)) paths)))

fn ! formatDiagsHinted! diags: (List ty/Diagnostic) -> String
  (stringJoin (listAppend (map formatDiag diags) (diagHints! diags)) "\n")

fn ! balance! paths: (List String) -> Int64
  (match (dyck/mainWith paths (fn [(p String)] -> String (indentFields! p))) ((ok rc) rc) ((err e) (do (sys/sayErr! e) 2)))

fn ! checkOther! paths: (List String) -> Int64
  (if (listEmpty? paths)
    0
    (let [(rc (balance! paths))]
      (if (!= rc 0)
        (do (sys/say! (str "(:audit :sub check :status :failed (:check :id balance :status :failed :err " (balanceError rc) "))")) 1)
        (do (sys/say! "(:audit :sub check :status :passed (:check :id balance :status :passed))") 0))))

fn ! printDiag! d: ty/Diagnostic -> Bool
  (sys/sayErr! (formatDiag d))

; (:m :ref CHECK-FOREIGN-LOWS :do "a Staged names the file checked in the staged mirror (actual), the path the caller gave (shown) and the other mirror prefixes mapped back to the package's own (maps): every line, the file's own and an imported staged file's, absolute or root-relative, is rewritten through all of them, so no staged path leaks")
(schema Staged
  (:f actual String)
  (:f shown String)
  (:f maps (List (Pair String String))))

fn normalisePaths maps: (List (Pair String String)) line: String -> String
  (fold (fn [(l String) (m (Pair String String))] -> String (stringReplace l (pairFirst m) (pairSecond m))) line maps)

fn ! reportStaged! s: Staged verdict: (Result cc/Verdict String) -> Int64
  (let [(maps (cons (pair s.actual s.shown) s.maps))]
    (match verdict
      ((err _) (do (sys/sayErr! (str s.shown ":0:0: ERR_IO cannot open file"))
                   (sys/sayErr! (str "check failed: " s.shown ": 1 error(s)"))
                   1))
      ((ok v)
        (if (listEmpty? v.diags)
          (do (sys/say! (str "ok " s.shown ": " (cc/countsText v))) 0)
          (let [(lines (map (fn [(d ty/Diagnostic)] -> Bool (sys/sayErr! (normalisePaths maps (formatDiag d)))) v.diags))
                (hinted (map (fn [(l String)] -> Bool (sys/sayErr! (normalisePaths maps l))) (diagHints! v.diags)))]
            (do (sys/sayErr! (str "check failed: " s.shown ": " (stringFromInt64 (listLength v.diags)) " error(s)")) 1))))))

fn ! reportOne! path: String verdict: (Result cc/Verdict String) -> Int64
  (reportStaged! (Staged :actual path :shown path :maps (list)) verdict)

fn ! nativeCheckStagedStep! staged: (List Staged) cache: cc/Cache rc: Int64 -> Int64
  (match (listHead staged)
    ((none) rc)
    ((some s)
      (let [(r (cc/checkFileCached! s.actual (checkRoots) cache))
            (one (reportStaged! s (pairFirst r)))]
        (nativeCheckStagedStep! (optionOr (listTail staged) (list)) (pairSecond r) (if (!= one 0) one rc)))))

fn ! nativeCheckStaged! staged: (List Staged) -> Int64
  (nativeCheckStagedStep! staged (cc/stampedCache!) 0)

; (:m :ref MAIN-RED-FORMS3 :do "asl check of files outside the toolchain root checks their staged mirrors and ends with ONE one-line (:audit :sub check) receipt for the whole call, other in-root paths (balance only) included, whose status and exit are the overall result: balance of the mirrors (quiet) and the host verdict, so a caller reads one receipt shape whichever side of the root the file lies on")
fn ! checkStaged! staged: (List Staged) other: (List String) -> Int64
  (let [(sbal (fold (fn [(w Int64) (s Staged)] -> Int64 (let [(r (pairFirst (dyck/reportFile! s.actual (fn [(p String)] -> String ""))))] (if (> r w) r w))) 0 staged))
        (obal (if (listEmpty? other) 0 (balance! other)))
        (bal (if (> sbal obal) sbal obal))
        (rc (nativeCheckStaged! staged))
        (status (if (and (= rc 0) (= bal 0)) ":passed" ":failed"))]
    (do (sys/say! (if (!= bal 0)
                    (str "(:audit :sub check :status :failed (:check :id balance :status :failed :err " (balanceError bal) ") (:check :id hostCheck :status :skipped))")
                    (str "(:audit :sub check :status " status " (:check :id balance :status :passed) (:check :id hostCheck :status " status " :exit " (stringFromInt64 rc) "))")))
        (if (!= rc 0) rc bal)))

fn ! nativeCheckStep! paths: (List String) cache: cc/Cache rc: Int64 -> Int64
  (match (listHead paths)
    ((none) rc)
    ((some p)
      (let [(r (cc/checkFileCached! p (checkRoots) cache))
            (one (reportOne! p (pairFirst r)))]
        (nativeCheckStep! (optionOr (listTail paths) (list)) (pairSecond r) (if (!= one 0) one rc)))))

fn ! nativeCheckPaths! paths: (List String) -> Int64
  (nativeCheckStep! paths (cc/stampedCache!) 0)

fn ! checkAsl! paths: (List String) otherRc: Int64 -> Int64
  (let [(rc (balance! paths))]
    (if (!= rc 0)
      (do (sys/say! (str "(:audit :sub check :status :failed (:check :id balance :status :failed :err " (balanceError rc) ") (:check :id hostCheck :status :skipped))")) 1)
      (let [(checkRc (nativeCheckPaths! paths))
            (status (if (= checkRc 0) ":passed" ":failed"))]
        (do (sys/say! (str "(:audit :sub check :status " status " (:check :id balance :status :passed) (:check :id hostCheck :status " status " :exit " (stringFromInt64 checkRc) "))"))
            (if (!= checkRc 0) checkRc otherRc)))))

; (:m :ref ASL-CHECK-DOT-DIR :do "a directory argument stands for the tracked .asl files under it (git ls-files, the set the sweep checks), dot for the whole tree, the same in a worktree and in the main checkout; before it was read as a file and answered Is a directory, exit 1; a directory git cannot list is left as given")
fn ! dirFiles! dir: String -> (Option (List String))
  (let [(base (if (stringEndsWith? dir "/") (optionOr (stringSlice dir 0 (- (stringLength dir) 1)) dir) dir))
        (pat (if (or (= base ".") (stringEmpty? base)) "*.asl" (str base "/*.asl")))]
    (match (sys/capture! (list "git" "ls-files" "--" pat) (none))
      ((err _) (none))
      ((ok c) (if (= c.exitCode 0)
                (some (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (map stringTrim (stringLines c.stdout))))
                (none)))))

fn ! expandDirs! args: (List String) -> (List String)
  (fold (fn [(acc (List String)) (a String)] -> (List String)
          (if (sys/isDir? a)
            (match (dirFiles! a) ((some fs) (listAppend acc fs)) ((none) (listAppend acc (list a))))
            (listAppend acc (list a))))
        (list) args)

fn ! checkFiles! ctx: sys/Context given: (List String) -> Int64
  (let [(args (expandDirs! given))
        (aslArgs (filter (fn [(a String)] -> Bool (stringEndsWith? a ".asl")) args))
        (otherArgs (filter (fn [(a String)] -> Bool (not (stringEndsWith? a ".asl"))) args))
        (otherRc (checkOther! otherArgs))]
    (if (listEmpty? aslArgs) otherRc (checkAsl! aslArgs otherRc)))
