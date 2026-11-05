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

; (:m :ref VCS-CLI-ENTRY :do "flags (--asl-root V --repo V --msg V --warn) are read anywhere before the -- and removed, the positionals are what remains, so an injected or reordered flag never shifts BASE HEAD or RANGE")
fn positionals xs: (List String) -> (List String)
  (match (listHead xs)
    ((none) (list))
    ((some a)
      (let [(rest (optionOr (listTail xs) (list)))]
        (cond
          ((listContains? (list "--asl-root" "--repo" "--msg") a) (positionals (optionOr (listTail rest) (list))))
          ((= a "--warn") (positionals rest))
          (else (cons a (positionals rest)))))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(op (optionOr (listHead args) ""))
        (rest (optionOr (listTail args) (list)))
        (pre (beforeDashes rest))
        (paths (pathsAfter rest))
        (pos (positionals pre))
        (repoFlag (cg/flagVal pre "--repo"))
        (repo (if (stringEmpty? repoFlag) (resultOr (realPath ".") ".") repoFlag))
        (root (let [(f (cg/flagVal pre "--asl-root"))] (if (stringEmpty? f) repo f)))]
    (cond
      ((= op "commit")
        (cond
          ((not (cg/hasFlag pre "--msg")) (usage "commit needs --msg M"))
          ((listEmpty? paths) (usage "commit needs paths after --"))
          (else (show (v/commit! repo root paths (cg/flagVal pre "--msg") (if (cg/hasFlag pre "--warn") "warn" "commit"))))))
      ((= op "status") (show (v/status! repo paths)))
      ((= op "head") (show (v/head! repo)))
      ((= op "diff")
        (if (< (listLength pos) 2)
          (usage "diff needs BASE HEAD")
          (show (v/diff! repo (optionOr (listGet pos 0) "") (optionOr (listGet pos 1) "") paths))))
      ((= op "log")
        (if (listEmpty? pos) (usage "log needs RANGE") (show (v/log! repo (optionOr (listHead pos) "") paths "%h %s"))))
      (else (usage (str "unknown op " op)))))
