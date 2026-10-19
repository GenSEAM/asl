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
    (mt (fileReadString (str dir "/deps"))
      ((err _) false)
      ((ok text) (let [(paths (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringLines text)))]
                   (if (listEmpty? paths) false (allSame? root dir paths))))))

fn ! headDirIn! cache: String root: String -> String
  (stringTrim (resultOr (fileReadString (headPath cache root)) ""))

fn ! resolveFrom cache: String root: String fallback: String -> String
  (let [(dir (headDirIn! cache root))]
    (if (fresh? root dir) (str dir "/bin") fallback))

; (:m :ref HL-FIXWAVE :do "HL-DELETE retired asl/host/out/asl-host for good: this used to be the fallback resolveFrom/runnerDisplay!/runnerBin! hand back when the native cache has no fresh entry for root; there is no host binary left to fall back to, so the fallback is root's own bin/asl, which self-verifies and rebuilds (asl/bin/asl's own lock protocol) rather than trusting a second, always-ready binary that no longer exists")
fn builtFallback root: String -> String
  (str root "/bin/asl")

fn ! runnerDisplay! root: String -> String
  (resolveFrom (cacheDirOf!) root (builtFallback root))

fn ! runnerBin! root: String -> String
  (let [(given (optionOr (envGet "ASL_HOST") ""))]
    (if (and (not (stringEmpty? given)) (isExe? given)) (resultOr (realPath given) given) (runnerDisplay! root)))
