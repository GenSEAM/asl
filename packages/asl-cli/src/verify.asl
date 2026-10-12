(module asl-cli/verify
  :x [checkFiles! checkRoots nativeCheckPaths!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-gates/src/dyck :a dyck) (asl-checker/checkCached :a cc) (asl-checker/types :a ty)])

fn checkRoots -> (List String)
  (list "." "asl/packages" "asl")

fn balanceError rc: Int64 -> String
  (if (= rc 2) "ERR_NO_FILE" "ERR_UNBALANCED")

fn ! balance! paths: (List String) -> Int64
  (mt (dyck/main paths) ((ok rc) rc) ((err e) (do (sys/sayErr! e) 2)))

fn ! checkOther! paths: (List String) -> Int64
  (if (listEmpty? paths)
    0
    (let [(rc (balance! paths))]
      (if (!= rc 0)
        (do (sys/say! (str "(:audit :sub check :status :failed (:check :id balance :status :failed :err " (balanceError rc) "))")) 1)
        (do (sys/say! "(:audit :sub check :status :passed (:check :id balance :status :passed))") 0))))

fn ! printDiag! d: ty/Diagnostic -> Bool
  (sys/sayErr! (str d.path ":" (stringFromInt64 d.line) ":" (stringFromInt64 d.col) ": " d.code " " d.message))

fn ! reportOne! path: String verdict: (Result cc/Verdict IoError) -> Int64
  (mt verdict
    ((err _) (do (sys/sayErr! (str path ":0:0: ERR_IO cannot open file"))
                 (sys/sayErr! (str "check failed: " path ": 1 error(s)"))
                 1))
    ((ok v)
      (if (listEmpty? v.diags)
        (do (sys/say! (str "ok " path ": " (stringFromInt64 v.moduleCount) " module(s) checked")) 0)
        (let [(shown (map printDiag! v.diags))]
          (do (sys/sayErr! (str "check failed: " path ": " (stringFromInt64 (listLength v.diags)) " error(s)")) 1)))))

fn ! nativeCheckStep! paths: (List String) cache: cc/Cache rc: Int64 -> Int64
  (mt (listHead paths)
    ((none) rc)
    ((some p)
      (let [(r (cc/checkFileCached! p (checkRoots) cache))
            (one (reportOne! p (pairFirst r)))]
        (nativeCheckStep! (optionOr (listTail paths) (list)) (pairSecond r) (if (!= one 0) one rc)))))

fn ! nativeCheckPaths! paths: (List String) -> Int64
  (nativeCheckStep! paths (cc/emptyCache) 0)

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
