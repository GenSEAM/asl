(module asl-cli/cacheFallback
  :x [reroot! writable? gitRootOf overlayDirs overlayFor!]
  :i [(asl/packages/asl-cli/src/system :a sys) (asl/packages/asl-cli/src/nativeCli :a nc)])

; (:m :ref TOOLCACHE-SANDBOX :do "the toolchain root's .asl/cache is read-only for a sandboxed caller (codex workspace-write, Claude sandbox, CI on a release dir); every cache path of a native verb is root-relative and imports climb from the wrapper to a root, so the cache moves as a whole: an overlay root of symlinks to the real root with its own real .asl/cache, the CLI re-exec'd with ASL_CLI_ROOT at it; cache keys are relative to the root, so they match the real root's")
fn ! writable? dir: String -> Bool
  (match (dirCreate dir)
    ((err _) false)
    ((ok _) (let [(probe (str dir "/.probe." (stringFromInt64 (procSelf))))]
              (match (fileWrite probe "")
                ((err _) false)
                ((ok _) (do (pathRemove probe) true))))))

fn ! gitRootOf dir: String -> (Option String)
  (cond
    ((stringEmpty? dir) (none))
    ((fileExists? (str dir "/.git")) (some dir))
    (else (let [(parent (sys/parentOf dir))] (if (= parent dir) (none) (gitRootOf parent)))))
fn ! linkIfAbsent! target: String link: String -> Bool
  (if (ok? (fileLstat link)) true (ok? (pathSymlink target link)))
fn ! mirror! src: String dst: String skip: String -> Bool
  (match (dirList src)
    ((err _) false)
    ((ok names) (fold (fn [(acc Bool) (n String)] -> Bool
                        (if (= n skip) acc (and (linkIfAbsent! (str src "/" n) (str dst "/" n)) acc)))
                      true names)))
; (:m :ref TOOLCACHE-SANDBOX :do "the overlay: every entry of the real root and of its .asl except cache is a symlink; .asl/cache is a real directory")
fn ! overlayFor! root: String dir: String -> Bool
  (and (ok? (dirCreate (str dir "/.asl/cache")))
       (and (mirror! root dir ".asl")
            (mirror! (str root "/.asl") (str dir "/.asl") "cache")))
fn ! userId! -> String
  (match (sys/capture! (list "/usr/bin/id" "-u") (none))
    ((ok c) (if (= c.exitCode 0) (stringTrim c.stdout) "0"))
    ((err _) "0"))
; (:m :ref TOOLCACHE-SANDBOX :do "fallback order after the toolchain root cache: $TMPDIR/asl-cache-<uid>/<sha16 of root> only; the foreign project tree is never written")
fn ! overlayDirs root: String -> (List String)
  (let [(id (stringSlice (bytesSha256 (stringToBytes root)) 0 16))
        (tmp (optionOr (envGet "TMPDIR") "/tmp"))]
    (list (str (if (stringEndsWith? tmp "/") (optionOr (stringSlice tmp 0 (- (stringLength tmp) 1)) tmp) tmp) "/asl-cache-" (userId!) "/" (optionOr id "x"))))
fn ! firstUsable! root: String dirs: (List String) -> (Option String)
  (match (listHead dirs)
    ((none) (none))
    ((some d) (if (and (overlayFor! root d) (writable? (str d "/.asl/cache")))
                (some d)
                (firstUsable! root (optionOr (listTail dirs) (list))))))
fn cliEnvKept e: String -> Bool
  (and (stringStartsWith? e "ASL_CLI_") (not (stringStartsWith? e "ASL_CLI_ROOT=")))

fn ! reroot! ctx: sys/Context args: (List String) -> (Option Int64)
  (cond
    ((!= (nc/verbKind args) "native") (none))
    ((not (stringEmpty? (optionOr (envGet "ASL_CLI_OVERLAY") ""))) (none))
    ((writable? (str ctx.root "/.asl/cache")) (none))
    (else
      (let [(real (resultOr (realPath ctx.root) ctx.root))]
        (match (firstUsable! real (overlayDirs real))
          ((none) (none))
          ((some dir)
            (let [(dirEnv (optionOr (envGet "ASL_NATIVE_CLI_DIR") ""))
                  (exeDir (if (stringEmpty? dirEnv) (stringTrim (resultOr (fileReadString (nc/headPath (nc/cacheDir!) ctx.root)) "")) dirEnv))
                  (exe (str exeDir "/bin"))]
              (if (or (stringEmpty? exeDir) (not (sys/executable? exe)))
                (none)
                (some (sys/execv! (cons exe args)
                                          (cons (str "ASL_CLI_ROOT=" dir)
                                                (cons (str "ASL_CLI_OVERLAY=" real)
                                                      (filter cliEnvKept (envList)))))))))))))
