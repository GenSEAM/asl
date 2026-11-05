(module asl-tools/vcs/vcsMain
  :x [main]
  :i [(asl-tools/vcs/vcs :a v) (asl-tools/coord/commitGuard :a cg)])

; (:m :ref VCS-CLI-ENTRY :do "asl vcs OP: commit --msg M [--warn] [--repo DIR] [--asl-root DIR] -- PATH... | status [-- PATH...] | diff BASE HEAD [-- PATH...] | log RANGE [-- PATH...] | head; prints the ASN receipt; exit 0 ok, 1 refused or failed, 2 usage")
fn usage why: String -> (Result Int64 String)
  (do (println (str "(:vcs :status :usage :why \"" why "\" :ops \"commit --msg M -- PATH... | status | diff BASE HEAD | log RANGE | head\")"))
      (ok 2))

fn pathsAfter args: (List String) -> (List String)
  (match (listIndexOf args "--")
    ((none) (list))
    ((some i) (listDrop args (+ i 1))))

fn beforeDashes args: (List String) -> (List String)
  (match (listIndexOf args "--")
    ((none) args)
    ((some i) (listTake args i)))

fn ! show r: v/VcsReceipt -> (Result Int64 String)
  (do (println r.text) (ok r.code))

fn ! rootOf repo: String args: (List String) -> String
  (let [(f (cg/flagVal args "--asl-root"))
        (e (optionOr (envGet "ASL_ROOT") ""))]
    (cond ((not (stringEmpty? f)) f) ((not (stringEmpty? e)) e) (else repo)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(op (optionOr (listHead args) ""))
        (rest (optionOr (listTail args) (list)))
        (repoFlag (cg/flagVal args "--repo"))
        (repo (if (stringEmpty? repoFlag) (resultOr (realPath ".") ".") repoFlag))
        (paths (pathsAfter rest))
        (pre (beforeDashes rest))]
    (cond
      ((= op "commit")
        (cond
          ((not (cg/hasFlag args "--msg")) (usage "commit needs --msg M"))
          ((listEmpty? paths) (usage "commit needs paths after --"))
          (else (show (v/commit! repo (rootOf repo args) paths (cg/flagVal args "--msg") (if (cg/hasFlag args "--warn") "warn" "commit"))))))
      ((= op "status") (show (v/status! repo paths)))
      ((= op "head") (show (v/head! repo)))
      ((= op "diff")
        (if (< (listLength (filter (fn [(a String)] -> Bool (not (stringStartsWith? a "--"))) pre)) 2)
          (usage "diff needs BASE HEAD")
          (show (v/diff! repo (optionOr (listGet pre 0) "") (optionOr (listGet pre 1) "") paths))))
      ((= op "log")
        (if (listEmpty? pre) (usage "log needs RANGE") (show (v/log! repo (optionOr (listHead pre) "") paths "%h %s"))))
      (else (usage (str "unknown op " op)))))
