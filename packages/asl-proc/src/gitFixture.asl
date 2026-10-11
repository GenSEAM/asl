(module asl-proc/gitFixture
  :x [ceilingFor! safeGitCmd! gitSafe! gitWrite! verifyContained! initContained!]
  :i [(asl-proc/coreProcess :a cp)])

fn parentDir p: String -> String
  (let [(parts (stringSplit p "/"))]
    (if (<= (listLength parts) 1) "." (stringJoin (listTake parts (- (listLength parts) 1)) "/")))

fn ! ceilingFor! root: String -> String
  (let [(real (resultOr (realPath root) root))]
    (str (parentDir real) "/"))

fn ! safeGitCmd! root: String args: (List String) -> cp/ProcessCmd
  (cp/withEnv (cp/withTimeout (cp/withCwd (cp/cmd "git" (listAppend (list "-C" root) args)) root) 600000)
              "GIT_CEILING_DIRECTORIES" (ceilingFor! root))

fn ! gitExec! root: String args: (List String) stdin: (Option String) -> (Result cp/ProcessOutput String)
  (let [(c0 (safeGitCmd! root args))
        (c1 (mt stdin ((some s) (cp/withStdin c0 s)) ((none) c0)))]
    (mt (cp/exec! c1)
      ((err _) (err (str "git " (stringJoin args " ") " could not run")))
      ((ok o) (ok o))))

fn ! gitSafe! root: String args: (List String) -> (Result String String)
  (mt (gitExec! root args (none))
    ((err e) (err e))
    ((ok o) (if (= o.exitCode 0) (ok (stringTrim o.stdout)) (err (str "git " (stringJoin args " ") ": " (stringTrim o.stderr))))))

fn ! verifyContained! root: String -> (Result String String)
  (let [(real (resultOr (realPath root) root))]
    (mt (gitSafe! root (list "rev-parse" "--show-toplevel"))
      ((err e) (err (str "fixture root " root " is not its own git repository: " e)))
      ((ok top)
       (let [(topReal (resultOr (realPath top) top))]
         (if (= topReal real)
           (ok topReal)
           (err (str "git toplevel " topReal " for fixture root " real " does not match; refusing to touch it")))))))

fn ! gitWrite! root: String args: (List String) stdin: (Option String) -> (Result String String)
  (mt (verifyContained! root)
    ((err e) (err e))
    ((ok _)
     (mt (gitExec! root args stdin)
       ((err e) (err e))
       ((ok o) (if (= o.exitCode 0) (ok (stringTrim o.stdout)) (err (str "git " (stringJoin args " ") ": " (stringTrim o.stderr))))))))

fn ! initContained! root: String -> (Result String String)
  (mt (dirCreate root)
    ((err e) (err (str "cannot create fixture root " root ": " e)))
    ((ok _)
     (mt (gitSafe! root (list "init" "-q"))
       ((err e) (err (str "git init failed in " root ": " e)))
       ((ok _) (verifyContained! root)))))
