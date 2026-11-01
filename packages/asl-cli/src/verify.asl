(module asl-cli/verify
  :x [checkFiles! checkRoots nativeCheckPaths! nativeCheckStaged! formatDiag formatDiags formatDiagsHinted! diagHints! indentFields! balanceReceipt!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-gates/src/dyck :a dyck) (asl-forms/indent :a ind) (asl-checker/checkCached :a cc) (asl-checker/types :a ty)])

fn checkRoots -> (List String)
  (list "." "asl/packages" "asl")

; (:m :ref U4-MARKER-PARITY :do "the one shared formatter for a checker Diagnostic's path:line:col CODE message line; asl check (printDiag! below) and asl/tools/nativeTest.asl's test/run checker gate both render through this, so a failing fixture names the same site in check, test and run alike")
fn formatDiag d: ty/Diagnostic -> String
  (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message)

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
          (str " :indent " (ind/editsAsn g.edits) " :fix \"(:fix :file \\\"" (dyck/esc (dyck/esc path)) "\\\" :by :indent :apply true)\"")))))

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

; (:m :ref CHECK-FOREIGN-ASL-PKGS :do "reportOneAs! checks the file at ACTUAL and names it SHOWN in every line: asl check of a file outside the toolchain root reads its staged mirror (where the asl-* packages resolve, as asl test does) and still reports the path the caller gave")
fn ! reportOneAs! actual: String shown: String verdict: (Result cc/Verdict String) -> Int64
  (match verdict
    ((err _) (do (sys/sayErr! (str shown ":0:0: ERR_IO cannot open file"))
                 (sys/sayErr! (str "check failed: " shown ": 1 error(s)"))
                 1))
    ((ok v)
      (if (listEmpty? v.diags)
        (do (sys/say! (str "ok " shown ": " (cc/countsText v))) 0)
        (let [(lines (map (fn [(d ty/Diagnostic)] -> Bool (sys/sayErr! (stringReplace (formatDiag d) actual shown))) v.diags))
              (hinted (map (fn [(l String)] -> Bool (sys/sayErr! (stringReplace l actual shown))) (diagHints! v.diags)))]
          (do (sys/sayErr! (str "check failed: " shown ": " (stringFromInt64 (listLength v.diags)) " error(s)")) 1)))))

fn ! reportOne! path: String verdict: (Result cc/Verdict String) -> Int64
  (reportOneAs! path path verdict)

fn ! nativeCheckStagedStep! pairs: (List (Pair String String)) cache: cc/Cache rc: Int64 -> Int64
  (match (listHead pairs)
    ((none) rc)
    ((some pr)
      (let [(r (cc/checkFileCached! (pairFirst pr) (checkRoots) cache))
            (one (reportOneAs! (pairFirst pr) (pairSecond pr) (pairFirst r)))]
        (nativeCheckStagedStep! (optionOr (listTail pairs) (list)) (pairSecond r) (if (!= one 0) one rc)))))

fn ! nativeCheckStaged! pairs: (List (Pair String String)) -> Int64
  (nativeCheckStagedStep! pairs (cc/stampedCache!) 0)

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

fn ! checkFiles! ctx: sys/Context args: (List String) -> Int64
  (let [(aslArgs (filter (fn [(a String)] -> Bool (stringEndsWith? a ".asl")) args))
        (otherArgs (filter (fn [(a String)] -> Bool (not (stringEndsWith? a ".asl"))) args))
        (otherRc (checkOther! otherArgs))]
    (if (listEmpty? aslArgs) otherRc (checkAsl! aslArgs otherRc)))
