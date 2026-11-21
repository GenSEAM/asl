(module asl-cli/nativeRefreshKeyTest :x [runTests]
  :i [(asl-tools/fleet/run :a run) (asl/packages/asl-cli/src/nativeCli :a nc) (asl/packages/asl-cli/src/nativeRefresh :a nr) (asl/prelude/native/sha256 :a sh) (asl/packages/asl-cli/src/system :a sys)])

; (:m :ref CLI-STALE-BY-CONTENT :do "a suspect head is judged by content before any lock, the build lock is per key, a tree without asl/host/out takes the stored builder of its key. The refresh cases drive nr/refreshKeyed! with lookup and build closures that log what they see in a scratch cache: a hit repoints the head with no build and while it runs no lock of its key exists, though the shared lock and another key's lock are held by a live foreign pid; a miss under key 1 whose build starts a refresh of another root under key 2 holds both lock dirs at once; a miss that turns into a hit under the lock builds nothing. The launcher case copies bin/asl into a scratch root with no asl/host/out, a fake clang and a fake host store whose keys this test computes with its own sha256; the stored builder serves the call, and the same root with no stored builder fails as before. Children are bounded by fleet/run, the scratch dir is removed at the end")
fn ! put! path: String text: String -> Bool
  (ok? (fileWrite path text))

fn ! exe! path: String text: String -> Bool
  (and (put! path text) (ok? (fileChmod path 493)))

fn ! slurp path: String -> String
  (resultOr (fileReadString path) "")

fn ! mkdirs! dirs: (List String) -> Bool
  (listAll? (fn [(d String)] -> Bool (ok? (dirCreate d))) dirs)

fn ! locks cache: String -> String
  (stringJoin (listSort (filter (fn [(n String)] -> Bool (stringStartsWith? n "lock")) (resultOr (dirList cache) (list)))) " ")

; (:m :ref NATIVE-LOCK-PIDNS :do "a live holder that is neither this test nor one of its ancestors, recorded with its start time and namespace, so the lock would not count it stale")
fn ! otherLive! -> Int64
  (let [(skip (cons (procSelf) (nc/ancestorsOf! (procSelf) 64)))]
    (optionOr (listHead (filter (fn [(p Int64)] -> Bool (and (nc/alive? p) (not (listContains? skip p)))) (map (fn [(q (Pair Int64 Int64))] -> Int64 (pairFirst q)) (run/psSnapshot)))) 0))

fn ! hold! lock: String pid: Int64 -> Bool
  (and (ok? (dirCreate lock)) (put! (str lock "/pid") (str (stringFromInt64 pid) "\n"))
       (put! (str lock "/id." (stringFromInt64 pid)) (str "ns=" (nc/nsId!) "\nstart=" (nc/startOf! pid) "\ncreated=" (stringFromInt64 (nowNs)) "\n")))

fn ! cliDir! dir: String word: String -> Bool
  (and (ok? (dirCreate dir)) (exe! (str dir "/bin") (str "#!/bin/sh\necho \"served " word " $*\"\n")) (put! (str dir "/deps") "src/in.asl\n"))

; (:m :ref CLI-STALE-BY-CONTENT :do "a root whose one dep src/in.asl is newer than its head, which names cli-old")
fn ! staleRoot! r: String cache: String -> Bool
  (and (mkdirs! (list r (str r "/src")))
       (put! (str r "/src/in.asl") "a\n")
       (ok? (fileUtime (str r "/src/in.asl") (- (nowNs) 10000000000)))
       (put! (nc/headPath cache r) (str cache "/cli-old\n"))
       (ok? (fileUtime (nc/headPath cache r) (- (nowNs) 20000000000))))

fn ! hitCase base: String -> Bool
  (let [(cache (str base "/hitCache"))
        (r (str base "/hitRoot"))
        (made (and (mkdirs! (list cache)) (cliDir! (str cache "/cli-old") "old") (cliDir! (str cache "/cli-K") "hit") (staleRoot! r cache)))
        (holder (otherLive!))
        (held (and (> holder 1) (hold! (str cache "/lock") holder) (hold! (str cache "/lock-cli-OTHER") holder)))
        (log (str base "/hit.log"))
        (lookup (fn [(root String) (c String)] -> (Pair String String)
                  (do (fileAppend log (if (fileExists? (str c "/lock-cli-K")) "lookup locked\n" "lookup free\n"))
                      (pair (str c "/cli-K") "cli-K"))))
        (build (fn [(root String) (c String)] -> Int64 (do (fileAppend log "build\n") 0)))
        (rc (nr/refreshKeyed! r cache (list "x") lookup build))
        (events (slurp log))
        (headNow (stringTrim (slurp (nc/headPath cache r))))
        (globalPid (stringTrim (slurp (str cache "/lock/pid"))))
        (otherPid (stringTrim (slurp (str cache "/lock-cli-OTHER/pid"))))
        (left (locks cache))]
    (do (assert (and made held) (str "the hit fixture and two locks held by live pid " (stringFromInt64 holder) " were made"))
        (assert (= rc 0) (str "a content hit refreshes with exit 0: " (stringFromInt64 rc)))
        (assert (= events "lookup free\n") (str "the lookup ran once with no lock of its key taken and no build followed: " events))
        (assert (= headNow (str cache "/cli-K")) (str "the head was repointed at the hit: " headNow))
        (assert (and (= globalPid (stringFromInt64 holder)) (= otherPid (stringFromInt64 holder))) (str "the shared lock and the other key's lock were left to their holder: " globalPid " " otherPid))
        (assert (= left "lock lock-cli-OTHER") (str "no lock of the hit's key was made: " left))
        true))

fn ! nestedCase base: String -> Bool
  (let [(cache (str base "/nestCache"))
        (r1 (str base "/nestRoot1"))
        (r2 (str base "/nestRoot2"))
        (made (and (mkdirs! (list cache)) (cliDir! (str cache "/cli-old") "old") (cliDir! (str cache "/cli-new1") "new1") (cliDir! (str cache "/cli-new2") "new2")
                   (staleRoot! r1 cache) (staleRoot! r2 cache)))
        (log (str base "/nest.log"))
        (build2 (fn [(root String) (c String)] -> Int64
                  (do (fileAppend log (str "build2 " (locks c) "\n")) (if (put! (nc/headPath c root) (str c "/cli-new2\n")) 0 1))))
        (build1 (fn [(root String) (c String)] -> Int64
                  (let [(seen (fileAppend log (str "build1 " (locks c) "\n")))
                        (inner (nr/refreshKeyed! r2 c (list "x") (fn [(x String) (y String)] -> (Pair String String) (pair "" "cli-K2")) build2))
                        (wrote (put! (nc/headPath c root) (str c "/cli-new1\n")))]
                    (if (and (ok? seen) wrote) inner 1))))
        (rc (nr/refreshKeyed! r1 cache (list "x") (fn [(x String) (y String)] -> (Pair String String) (pair "" "cli-K1")) build1))
        (events (slurp log))
        (left (locks cache))
        (head1 (stringTrim (slurp (nc/headPath cache r1))))
        (head2 (stringTrim (slurp (nc/headPath cache r2))))]
    (do (assert made "the nested fixture was made")
        (assert (= rc 0) (str "both refreshes built and returned 0: " (stringFromInt64 rc) " " events))
        (assert (= events "build1 lock-cli-K1\nbuild2 lock-cli-K1 lock-cli-K2\n") (str "the build of key 2 ran while key 1's build held its own lock, two distinct lock dirs at once: " events))
        (assert (stringEmpty? left) (str "both locks were released: " left))
        (assert (and (= head1 (str cache "/cli-new1")) (= head2 (str cache "/cli-new2"))) (str "each root's head names its own build: " head1 " " head2))
        (assert (= (nr/lockPath cache "cli-K1") (str cache "/lock-cli-K1")) "two roots with the same key name the same lock")
        (assert (= (nr/lockPath cache "") (str cache "/lock")) "a key that could not be computed falls back to the shared lock")
        true))

fn ! coalesceCase base: String -> Bool
  (let [(cache (str base "/coCache"))
        (r (str base "/coRoot"))
        (made (and (mkdirs! (list cache)) (cliDir! (str cache "/cli-old") "old") (cliDir! (str cache "/cli-K3") "k3") (staleRoot! r cache)))
        (log (str base "/co.log"))
        (lookup (fn [(root String) (c String)] -> (Pair String String)
                  (let [(before (not (stringContains? (slurp log) "lookup")))
                        (_ (fileAppend log (str "lookup " (locks c) "\n")))]
                    (if before (pair "" "cli-K3") (pair (str c "/cli-K3") "cli-K3")))))
        (build (fn [(root String) (c String)] -> Int64 (do (fileAppend log "build\n") 0)))
        (rc (nr/refreshKeyed! r cache (list "x") lookup build))
        (events (slurp log))
        (headNow (stringTrim (slurp (nc/headPath cache r))))
        (left (locks cache))]
    (do (assert made "the coalesce fixture was made")
        (assert (= rc 0) (str "a miss that a same-key build turned into a hit returns 0: " (stringFromInt64 rc)))
        (assert (= events "lookup \nlookup lock-cli-K3\n") (str "the second lookup ran under the key's lock and nothing was built: " events))
        (assert (= headNow (str cache "/cli-K3")) (str "the head names the entry the other build installed: " headNow))
        (assert (stringEmpty? left) (str "the key's lock was released: " left))
        true))

fn hex16 s: String -> String
  (optionOr (stringSlice s 0 16) s)

fn sha text: String -> String
  (sh/bytesSha256 (stringToBytes text))

; (:m :ref CLI-STALE-BY-CONTENT :do "the fixture tree for the launcher case: every file the build.sh keys read, a seed row per supported triple, one stale head; the store keys are restated here from asl/host/build.sh (runtime: clang line, then name and bytes of prelude.asl and the asl-ir and asl-target-llvm sources; asl1: STORE/seed/LLSHA-RT16/asl1; builder: asl1 path, clang line, then path and bytes of the nativeBuild closure, prelude.asl and the prelude natives)")
fn ! hostlessRoot! r: String cache: String tools: String -> Bool
  (and (mkdirs! (list r (str r "/bin") (str r "/src") (str r "/asl") (str r "/asl/seed") (str r "/asl/prelude") (str r "/asl/prelude/native") (str r "/asl/packages")
                      (str r "/asl/packages/asl-cli") (str r "/asl/packages/asl-cli/src") (str r "/asl/packages/asl-ir") (str r "/asl/packages/asl-ir/src")
                      (str r "/asl/packages/asl-target-llvm") (str r "/asl/packages/asl-target-llvm/src") tools))
       (put! (str r "/asl/seed/seed.asn") (str "(:seed :triple \"arm64-apple-darwin\" :file \"s.gz\" :llSha256 \"aa11\")\n(:seed :triple \"aarch64-unknown-linux-gnu\" :file \"s.gz\" :llSha256 \"aa11\")\n"
                                               "(:seed :triple \"x86_64-unknown-linux-gnu\" :file \"s.gz\" :llSha256 \"aa11\")\n"))
       (put! (str r "/asl/prelude/prelude.asl") "p\n") (put! (str r "/asl/prelude/native/n.asl") "n\n")
       (put! (str r "/asl/packages/asl-ir/src/i.asl") "i\n") (put! (str r "/asl/packages/asl-target-llvm/src/t.asl") "t\n")
       (put! (str r "/asl/packages/asl-cli/src/nativeBuild.asl") "nb\n") (put! (str r "/asl/packages/asl-cli/src/x.asl") "x\n")
       (exe! (str tools "/clang") "#!/bin/sh\ncase \"$1\" in --version) echo 'fakeclang 1.0' ;; -print-target-triple) echo arm64-apple-darwin ;; esac\n")
       (cliDir! (str cache "/cli-old") "old") (cliDir! (str cache "/cli-new") "new")
       (staleRoot! r cache))

fn ! store! r: String store: String cache: String withBuilder: Bool -> Bool
  (let [(rtKey (sha "fakeclang 1.0\nprelude.asl\np\ni.asl\ni\nt.asl\nt\n"))
        (asl1 (str store "/seed/aa11-" (hex16 (sha "rt\n")) "/asl1"))
        (nbKey (sha (str asl1 "\nfakeclang 1.0\nasl/packages/asl-cli/src/nativeBuild.asl\nnb\nasl/packages/asl-cli/src/x.asl\nx\nasl/prelude/prelude.asl\np\nasl/prelude/native/n.asl\nn\n")))
        (nbDir (str store "/nativeBuild/" nbKey))]
    (and (mkdirs! (list store (str store "/rt") (str store "/rt/" rtKey) (str store "/seed") (sys/parentOf asl1) (str store "/nativeBuild")))
         (put! (str store "/rt/" rtKey "/libaslrt.a") "rt\n")
         (exe! asl1 "#!/bin/sh\n[ \"$1\" = deps ] && echo asl/packages/asl-cli/src/x.asl\n")
         (if withBuilder
           (and (ok? (dirCreate nbDir))
                (exe! (str nbDir "/aslNativeBuild") (str "#!/bin/sh\necho \"$*\" >> '" r "/builder.log'\n[ \"$1\" = refresh ] || exit 0\n"
                                                         "printf '%s\\n' '" cache "/cli-new' > '" (nc/headPath cache r) ".part' && mv -f '" (nc/headPath cache r) ".part' '" (nc/headPath cache r) "'\n")))
           true)))

fn ! launch! r: String cache: String store: String tools: String -> run/Done
  (run/runOneLimited
    (run/job (list (str r "/bin/asl") "x") r
      (listAppend (list "PATH=/usr/bin:/bin" (str "CLANG=" tools "/clang") (str "ASL_HOST_CACHE_DIR=" store) (str "ASL_NATIVE_CLI_CACHE=" cache))
        (filter (fn [(row String)] -> Bool (not (listAny? (fn [(p String)] -> Bool (stringStartsWith? row p)) (list "PATH=" "CLANG=" "ASL_HOST_CACHE" "ASL_NATIVE_" "ASL_ROOT=" "ASL_PRELUDE=" "ASL_CLI_"))))
                (run/childEnv (list)))))
    (run/limits 60 16))

fn ! hostlessCase root: String base: String -> Bool
  (let [(r0 (str base "/hl"))
        (n0 (str base "/hlNone"))
        (made0 (mkdirs! (list r0 n0)))
        (r (resultOr (realPath r0) r0))
        (n (resultOr (realPath n0) n0))
        (cache (str base "/hlCache"))
        (tools (str base "/hlTools"))
        (made (and made0 (mkdirs! (list cache)) (hostlessRoot! r cache tools) (hostlessRoot! n cache tools)
                   (exe! (str r "/bin/asl") (slurp (str root "/bin/asl"))) (exe! (str n "/bin/asl") (slurp (str root "/bin/asl")))
                   (store! r (str base "/hlStore") cache true) (store! n (str base "/hlStoreNone") cache false)))
        (noOut (and (not (fileExists? (str r "/asl/host/out"))) (not (fileExists? (str n "/asl/host/out")))))
        (served (launch! r cache (str base "/hlStore") tools))
        (calls (slurp (str r "/builder.log")))
        (builder (fileExists? (str r "/asl/host/out/aslNativeBuild")))
        (lib (slurp (str r "/asl/host/out/libaslrt.a")))
        (stampDeps (slurp (str r "/asl/host/out/aslNativeBuild-fresh/deps")))
        (stampSrc (slurp (str r "/asl/host/out/aslNativeBuild-fresh/src/asl/packages/asl-cli/src/x.asl")))
        (refused (launch! n cache (str base "/hlStoreNone") tools))
        (noBuilder (not (fileExists? (str n "/asl/host/out/aslNativeBuild"))))]
    (do (assert (and made noOut) "two hostless roots, a fake clang and two host stores (one without the builder) were made")
        (assert (and (= served.exit 0) (stringContains? served.out "served new x")) (str "a root with no asl/host/out is refreshed by the stored builder of its key and serves: " (stringFromInt64 served.exit) " " served.out))
        (assert (= (stringTrim calls) (str "refresh " r " " cache " -- x")) (str "the stored builder ran the refresh once: " calls))
        (assert (and builder (= lib "rt\n")) "the stored builder and the stored runtime of the key were installed into asl/host/out")
        (assert (and (= stampDeps "asl/packages/asl-cli/src/nativeBuild.asl\nasl/packages/asl-cli/src/x.asl\n") (= stampSrc "x\n")) (str "the builder's source stamp lists its closure: " stampDeps))
        (assert (and (= refused.exit 2) (stringContains? refused.out "ERR_NATIVE_STALE") noBuilder) (str "with no stored builder of the key the stale head still fails with ERR_NATIVE_STALE: " refused.out))
        true))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (top (str root "/.asl/cache/nativeRefreshKey"))
        (base0 (str top "/" (stringFromInt64 (procSelf))))
        (made (mkdirs! (list (str root "/.asl") (str root "/.asl/cache") top base0)))
        (base (resultOr (realPath base0) base0))
        (ok1 (hitCase base))
        (ok2 (nestedCase base))
        (ok3 (coalesceCase base))
        (ok4 (hostlessCase root base))
        (cleaned (pathRemove base0))]
    (do (assert made "the scratch dir was made")
        (assert (and (ok? cleaned) (not (fileExists? base0))) "the scratch dir was removed")
        (and ok1 ok2 ok3 ok4)))
