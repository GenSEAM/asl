(module asl-cli/verify
  :x [checkFiles!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-gates/src/dyck :a dyck)])

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

fn ! checkAsl! ctx: sys/Context paths: (List String) otherRc: Int64 -> Int64
  (if (not (sys/executable? ctx.hostBin))
    (do (sys/say! (sys/hostAbsent "check")) 2)
    (let [(rc (balance! paths))]
      (if (!= rc 0)
        (do (sys/say! (str "(:audit :sub check :status :failed (:check :id balance :status :failed :err " (balanceError rc) ") (:check :id hostCheck :status :skipped))")) 1)
        (let [(hostRc (sys/run! (cons ctx.hostBin (cons "check" paths))))
              (status (if (= hostRc 0) ":passed" ":failed"))]
          (do (sys/say! (str "(:audit :sub check :status " status " (:check :id balance :status :passed) (:check :id hostCheck :status " status " :exit " (stringFromInt64 hostRc) "))"))
              (if (!= hostRc 0) hostRc otherRc))))))

fn ! checkFiles! ctx: sys/Context args: (List String) -> Int64
  (let [(aslArgs (filter (fn [(a String)] -> Bool (stringEndsWith? a ".asl")) args))
        (otherArgs (filter (fn [(a String)] -> Bool (not (stringEndsWith? a ".asl"))) args))
        (otherRc (checkOther! otherArgs))]
    (if (listEmpty? aslArgs) otherRc (checkAsl! ctx aslArgs otherRc)))
