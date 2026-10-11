(module asl-proc/runnerBin
  :x [cacheDirOf! headPath isExe? sameBytes? allSame? fresh? headDirIn! resolveFrom builtFallback runnerDisplay! runnerBin!]
  :i [])

fn ! cacheDirOf! -> String
  (let [(configured (optionOr (envGet "ASL_NATIVE_CLI_CACHE") ""))
        (home (optionOr (envGet "HOME") ""))]
    (cond
      ((not (stringEmpty? configured)) configured)
      ((stringEmpty? home) "/tmp/.asl/run/nativeCli")
      (else (str home "/.asl/run/nativeCli"))))

fn headPath cache: String root: String -> String
  (str cache "/head" (stringReplace root "/" "_"))

fn ! isExe? path: String -> Bool
  (mt (fileStat path) ((ok st) st.isFile) ((err _) false))

fn ! sameBytes? a: String b: String -> Bool
  (mt (fileReadBytes a)
    ((err _) false)
    ((ok x) (mt (fileReadBytes b) ((err _) false) ((ok y) (= x y)))))

fn ! allSame? root: String dir: String paths: (List String) -> Bool
  (mt (listHead paths)
    ((none) true)
    ((some p) (if (sameBytes? (str root "/" p) (str dir "/src/" p)) (allSame? root dir (optionOr (listTail paths) (list))) false)))

fn ! fresh? root: String dir: String -> Bool
  (if (or (stringEmpty? dir) (not (isExe? (str dir "/bin"))))
    false
    (mt (fileRead (str dir "/deps"))
      ((err _) false)
      ((ok text) (let [(paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines text)))]
                   (if (listEmpty? paths) false (allSame? root dir paths))))))

fn ! headDirIn! cache: String root: String -> String
  (stringTrim (resultOr (fileRead (headPath cache root)) ""))

fn ! resolveFrom cache: String root: String fallback: String -> String
  (let [(dir (headDirIn! cache root))]
    (if (fresh? root dir) (str dir "/bin") fallback))

fn builtFallback root: String -> String
  (str root "/asl/host/out/asl-host")

fn ! runnerDisplay! root: String -> String
  (resolveFrom (cacheDirOf!) root (builtFallback root))

fn ! runnerBin! root: String -> String
  (let [(given (optionOr (envGet "ASL_HOST") ""))]
    (if (and (not (stringEmpty? given)) (isExe? given)) (resultOr (realPath given) given) (runnerDisplay! root)))
