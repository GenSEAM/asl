(module aslPack/tests/pkgTest
  :x [runTests]
  :i [(pkgStore :a st) (pkgIndex :a ix) (asl-checker/resolve :a inst) (pkgCli :a pkg) (asl-tools/fleet/run :a fr)])

fn ! baseDir -> String
  (str (optionOr (envGet "TMPDIR") "/tmp") "/aslPkgTest-" (procSelf))

fn ! run! argv: (List String) cwd: String -> fr/ProcOut
  (fr/runGuarded argv cwd (fr/childEnv (list)) (fr/limits 60 8))

fn ! aslBin -> String
  (match (fr/nativeCliPath!) ((ok p) p) ((err _) ""))

fn ! writeOk! path: String text: String -> Bool
  (match (fileWrite path text) ((ok _) true) ((err _) false))

fn pkgSource name: String ver: String -> String
  (str "(module " name "/main :x [value] :i [])\n\nfn value -> Int64\n  " (stringReplace ver "." "") "\n")

; (:m :ref PKG-CLIENT :do "makeTgz! builds the tiny fixture package NAME-VER (manifest.asn plus src/main.asl) with the system tar and returns the archive path; broken=true writes unbalanced source so the source-install check fails")
fn ! makeTgz! name: String ver: String broken: Bool -> String
  (let [(dir (str (baseDir) "/fix/" name "-" ver))
        (tgz (str (baseDir) "/fix/" name "-" ver ".tgz"))
        (_ (dirCreate (str dir "/src")))
        (_ (writeOk! (str dir "/manifest.asn") (str "(:package " name " :version \"" ver "\" :entry \"src/main.asl\")\n")))
        (_ (writeOk! (str dir "/src/main.asl") (if broken (str (pkgSource name ver) "(oops\n") (pkgSource name ver))))
        (_ (run! (list "/usr/bin/tar" "-czf" tgz "-C" dir "manifest.asn" "src") (baseDir)))]
    tgz)

fn ! sha! path: String -> String
  (match (fileReadBytes path) ((ok b) (bytesSha256 b)) ((err _) ""))

fn ! art triple: String tgz: String -> String
  (str "(:triple \"" triple "\" :url \"file://" tgz "\" :sha256 \"" (sha! tgz) "\")")

fn ! badArt triple: String tgz: String -> String
  (str "(:triple \"" triple "\" :url \"file://" tgz "\" :sha256 \"" (stringRepeat "a" 64) "\")")

fn ! src tgz: String -> String
  (str "(:url \"file://" tgz "\" :sha256 \"" (sha! tgz) "\")")

fn ver v: String arts: String source: String deps: String -> String
  (str "(:v \"" v "\" :artefacts (" arts ") " (if (stringEmpty? source) "" (str ":source " source " ")) ":deps (" deps "))")

fn pkgRow name: String versions: String -> String
  (str "(:pkg :name \"" name "\" :versions (" versions "))")

fn ! ctxFor! label: String rows: String -> st/Ctx
  (let [(home (str (baseDir) "/home-" label))
        (idx (str (baseDir) "/index-" label ".asn"))
        (_ (writeOk! idx (str "(:index :v 1 " rows ")")))]
    (st/makeCtx home (str "file://" idx) "test-x64" (aslBin)))

fn ! rewriteIndex! label: String rows: String -> Bool
  (writeOk! (str (baseDir) "/index-" label ".asn") (str "(:index :v 1 " rows ")"))

fn ! lockNames! ctx: st/Ctx -> (List String)
  (match (st/readLock! ctx) ((ok rows) (map (fn [(r st/LockRow)] -> String (str r.name "@" r.version "/" r.how)) rows)) ((err e) (list e)))

fn ! currentOf! ctx: st/Ctx name: String -> String
  (match (fileReadlink (st/currentPath ctx name)) ((ok t) t) ((err _) "none"))

fn errHas? r: (Result A String) code: String -> Bool
  (match r ((err e) (stringContains? e code)) ((ok _) false))

fn okHas? r: (Result String String) text: String -> Bool
  (match r ((ok s) (stringContains? s text)) ((err _) false))

fn ! testPure -> Bool
  (do
    (assert (ix/versionSatisfies? "^1.2" "1.9.0") "caret accepts a higher minor of the same major")
    (assert (not (ix/versionSatisfies? "^1.2" "2.0.0")) "caret refuses the next major")
    (assert (not (ix/versionSatisfies? ">=1.10" "1.9.9")) "numeric not lexical: 1.9.9 is below 1.10")
    (assert (ix/versionSatisfies? "1.2.0" "1.2") "missing parts count as zero")
    (assert (errHas? (ix/parseRequest "../evil") "ERR_PKG_NAME") "a path-like name is refused")
    (assert (errHas? (ix/parseRequest "Foo") "ERR_PKG_NAME") "uppercase is refused")
    (assert (stringContains? (diagsOf "(:index :v 1 (:pkg :name \"a\" :versions ((:v \"1.0.0\" :artefacts ((:triple \"t\" :url \"u\" :sha256 \"xyz\"))))))") "sha256") "a version row with a non-hex digest is skipped with a diagnostic")
    (assert (= (versionsIn "(:index :v 1 (:pkg :name \"a\" :versions ((:v \"1.0.0\" :artefacts ((:triple \"t\" :url \"u\" :sha256 \"xyz\"))) (:v \"2.0\" :artefacts ()))))") 1) "the good version row survives its bad neighbour")
    (assert (= (versionsIn "(:index :v 1 (:pkg :name \"a\" :versions ((:v \"1\") (:v \"1.0.0\"))))") 1) "1 and 1.0.0 are the same version")
    (assert (stringContains? (diagsOf "(:index :v 1 (:pkg :name \"a/b\" :versions ()))") "package name") "a slash in a package name is skipped with a diagnostic")
    (assert (errHas? (ix/parseIndex "(:index :v 2)") "unsupported") "an unknown index version is refused")
    (assert (not (st/safeEntry? "../evil")) "dot-dot entry is unsafe")
    (assert (not (st/safeEntry? "a/../../b")) "nested dot-dot entry is unsafe")
    (assert (not (st/safeEntry? "/etc/passwd")) "absolute entry is unsafe")
    (assert (st/safeEntry? "src/main.asl") "plain relative entry is safe")
    (assert (errHas? (st/tarListsOk "src/a\n" "lrwxr-xr-x 0 u g 0 Jan 1 src/a -> /etc\n" 1000 10) "not a plain file") "a symlink entry type is refused")
    (assert (errHas? (st/tarListsOk "" "" 1000 10) "empty archive") "an empty archive is refused")
    (assert (errHas? (st/tarListsOk "src/a\n" "hrw-r--r--  2 u g 5 Jan 1 src/a\n" 1000 10) "not a plain file") "a hardlink entry type is refused")
    (assert (errHas? (st/tarListsOk "a\nb\n" "-rw-r--r--  1 u g 600 Jan 1 a\n-rw-r--r--  1 u g 600 Jan 1 b\n" 1000 10) "ERR_PKG_SIZE") "listed sizes are summed against the byte cap")
    (assert (errHas? (st/tarListsOk "a\nb\nc\n" "-rw-r--r--  1 u g 1 Jan 1 a\n-rw-r--r--  1 u g 1 Jan 1 b\n-rw-r--r--  1 u g 1 Jan 1 c\n" 1000 2) "ERR_PKG_SIZE") "more entries than the cap are refused")
    (assert (not (errHas? (st/tarListsOk "a\n" "-rw-r--r-- u/g 700 2026-01-01 00:00 a\n" 1000 10) "ERR_PKG")) "GNU tar listing columns are read too")
    (assert (ix/versionSatisfies? "^0.2.3" "0.2.9") "caret on 0.x keeps the minor")
    (assert (not (ix/versionSatisfies? "^0.2.3" "0.3.0")) "caret on 0.2.3 refuses 0.3.0")
    (assert (not (ix/versionSatisfies? "^0.0.3" "0.0.4")) "caret on 0.0.3 is exact")
    (assert (= (ix/normVersion "01.2") "1.2.0") "versions are normalised to three parts")
    true)

fn ! testInstallAndImport -> Bool
  (let [(tgz (makeTgz! "pkga" "1.0.0" false))
        (ctx (ctxFor! "a" (pkgRow "pkga" (ver "1.0.0" (art "test-x64" tgz) "" ""))))
        (r (st/install! ctx (list (pair "pkga" "*"))))
        (again (st/install! ctx (list (pair "pkga" "*"))))
        (found (inst/installedModule ctx.home "pkga/main"))
        (_ (writeOk! (str ctx.home "/.asl/pkgs/pkga/x.asl") "(module x :x [] :i [])\n"))
        (escaped (inst/installedModule ctx.home "pkga/../../x"))
        (_ (dirCreate (str (baseDir) "/outside/src")))
        (_ (writeOk! (str (baseDir) "/outside/src/main.asl") "(module pkgo/main :x [] :i [])\n"))
        (_ (dirCreate (str ctx.home "/.asl/pkgs/pkgo")))
        (_ (pathSymlink (str (baseDir) "/outside") (str ctx.home "/.asl/pkgs/pkgo/current")))
        (linkedOut (inst/installedModule ctx.home "pkgo/main"))]
    (do
      (assert (okHas? r "(pkga \"1.0.0\" binary)") "install reports the binary install")
      (assert (= (lockNames! ctx) (list "pkga@1.0.0/binary")) "the lock holds exactly one row for the installed package")
      (assert (= (currentOf! ctx "pkga") "1.0.0") "current points at the installed version")
      (assert (fileExists? (str ctx.home "/.asl/pkgs/pkga/1.0.0/src/main.asl")) "the unpacked source is in the version dir")
      (assert (okHas? again "up to date") "installing again changes nothing")
      (assert (some? found) "an installed package module resolves through ~/.asl/pkgs/NAME/current")
      (assert (stringEndsWith? (optionOr found "") "/pkga/1.0.0/src/main.asl") "the resolved path is the real file in the version dir")
      (assert (none? escaped) "a dot-dot module name never resolves even when the target file exists")
      (assert (none? linkedOut) "a package whose current link leads outside ~/.asl/pkgs does not resolve")
      (assert (none? (inst/installedModule ctx.home "pkgz/main")) "a package that is not installed does not resolve")
      (assert (okHas? (st/installed! ctx) "(pkga \"1.0.0\" binary)") "list shows the installed package")
      (assert (okHas? (st/verify! ctx) ":ok 1") "verify passes on an untouched install")
      true))

fn ! testShaMismatch -> Bool
  (let [(tgz (makeTgz! "pkgb" "1.0.0" false))
        (ctx (ctxFor! "b" (pkgRow "pkgb" (ver "1.0.0" (badArt "test-x64" tgz) "" ""))))
        (r (st/install! ctx (list (pair "pkgb" "*"))))]
    (do
      (assert (errHas? r "ERR_PKG_SHA256") "a digest that differs from the index is refused")
      (assert (not (stringContains? (errText r) (sha! tgz))) "the refusal of a local file does not echo that file digest")
      (assert (= (lockNames! ctx) (list)) "nothing is in the lock after the refusal")
      (assert (not (fileExists? (str ctx.home "/.asl/pkgs/pkgb"))) "no package dir is left after the refusal")
      (assert (not (fileExists? (str ctx.home "/.asl/pkgs/.lock"))) "the lock file is released after a failure")
      true))

fn ! testSourceFallback -> Bool
  (let [(tgz (makeTgz! "pkgc" "1.0.0" false))
        (other (makeTgz! "pkgc" "1.0.0" false))
        (ctx (ctxFor! "c" (pkgRow "pkgc" (ver "1.0.0" (art "other-arm" other) (src tgz) ""))))
        (r (st/install! ctx (list (pair "pkgc" "*"))))
        (brokenTgz (makeTgz! "pkgcb" "1.0.0" true))
        (_ (rewriteIndex! "c" (str (pkgRow "pkgc" (ver "1.0.0" (art "other-arm" other) (src tgz) "")) (pkgRow "pkgcb" (ver "1.0.0" "" (src brokenTgz) "")))))
        (bad (st/install! ctx (list (pair "pkgcb" "*"))))
        (none (st/install! (ctxFor! "c2" (pkgRow "pkgn" (ver "1.0.0" (art "other-arm" other) "" ""))) (list (pair "pkgn" "*"))))]
    (do
      (assert (okHas? r "(pkgc \"1.0.0\" source)") "a host triple with no artefact installs from source")
      (assert (= (lockNames! ctx) (list "pkgc@1.0.0/source")) "the lock records how the package was installed")
      (assert (errHas? bad "ERR_PKG_BUILD") "a source package that fails asl check is refused")
      (assert (not (fileExists? (str ctx.home "/.asl/pkgs/pkgcb"))) "a failed source build leaves nothing installed")
      (assert (errHas? none "ERR_PKG_NOARTEFACT") "no artefact for the triple and no source is an error")
      true))

fn ! testMalicious -> Bool
  (let [(fixDir (str (baseDir) "/fix"))
        (evilDir (str (baseDir) "/evilsrc"))
        (_ (dirCreate evilDir))
        (_ (writeOk! (str (baseDir) "/evil") "x"))
        (_ (writeOk! (str evilDir "/manifest.asn") "(:package evil)\n"))
        (escape (str fixDir "/escape.tgz"))
        (_ (run! (list "/usr/bin/tar" "-czPf" escape "-C" evilDir "manifest.asn" "../evil") evilDir))
        (linky (str fixDir "/linky.tgz"))
        (_ (pathSymlink "/etc" (str evilDir "/lnk")))
        (_ (run! (list "/usr/bin/tar" "-czf" linky "-C" evilDir "manifest.asn" "lnk") evilDir))
        (ctx (ctxFor! "d" (str (pkgRow "evil" (ver "1.0.0" (art "test-x64" escape) "" "")) (pkgRow "linky" (ver "1.0.0" (art "test-x64" linky) "" "")))))
        (r1 (st/install! ctx (list (pair "evil" "*"))))
        (r2 (st/install! ctx (list (pair "linky" "*"))))]
    (do
      (assert (errHas? r1 "ERR_PKG_TAR") "a tarball with a ../ entry is refused")
      (assert (errHas? r2 "ERR_PKG_TAR") "a tarball with a symlink entry is refused")
      (assert (= (lockNames! ctx) (list)) "nothing is installed after the refusals")
      (assert (not (fileExists? (str ctx.home "/.asl/pkgs/evil"))) "no dir for the escaping package")
      (assert (not (fileExists? (str ctx.home "/.asl/evil"))) "nothing was written outside the destination")
      true))

fn ! testRemoveAndDeps -> Bool
  (let [(e1 (makeTgz! "pkge" "1.0.0" false))
        (e2 (makeTgz! "pkge" "2.0.0" false))
        (d1 (makeTgz! "pkgd" "1.0.0" false))
        (f1 (makeTgz! "pkgf" "1.0.0" false))
        (rows (str (pkgRow "pkge" (str (ver "1.0.0" (art "test-x64" e1) "" "") (ver "2.0.0" (art "test-x64" e2) "" "")))
                   (pkgRow "pkgd" (ver "1.0.0" (art "test-x64" d1) "" "(pkge \"^1.0\")"))
                   (pkgRow "pkgf" (ver "1.0.0" (art "test-x64" f1) "" "(pkge \"^2.0\")"))))
        (ctx (ctxFor! "e" rows))
        (clash (st/install! ctx (list (pair "pkgd" "*") (pair "pkgf" "*"))))
        (afterClash (lockNames! ctx))
        (r (st/install! ctx (list (pair "pkgd" "*"))))
        (afterInstall (lockNames! ctx))
        (refused (st/remove! ctx "pkge"))
        (afterRefused (lockNames! ctx))
        (gone (st/remove! ctx "pkgd"))
        (afterGone (lockNames! ctx))
        (second (st/remove! ctx "pkge"))
        (missing (st/remove! ctx "pkge"))]
    (do
      (assert (errHas? clash "ERR_PKG_CONFLICT") "two requirements on one package with no common version are a conflict")
      (assert (= afterClash (list)) "a conflict installs nothing")
      (assert (okHas? r "pkge") "installing a package installs its dependency")
      (assert (= afterInstall (list "pkgd@1.0.0/binary" "pkge@1.0.0/binary")) "the dependency took the highest version its spec allows")
      (assert (errHas? refused "ERR_PKG_REQUIRED") "a package another installed package needs cannot be removed")
      (assert (= afterRefused afterInstall) "a refused removal leaves the lock unchanged")
      (assert (okHas? gone ":op remove") "removing a leaf package succeeds")
      (assert (= afterGone (list "pkge@1.0.0/binary")) "remove drops exactly that lock row")
      (assert (not (fileExists? (str ctx.home "/.asl/pkgs/pkgd"))) "remove deletes the package dir")
      (assert (okHas? second ":op remove") "the dependency can go once nothing needs it")
      (assert (errHas? missing "ERR_PKG_NOTINSTALLED") "removing what is not installed is an error")
      true))

fn ! testUpdate -> Bool
  (let [(u1 (makeTgz! "pkgu" "1.0.0" false))
        (u2 (makeTgz! "pkgu" "2.0.0" false))
        (ctx (ctxFor! "u" (pkgRow "pkgu" (ver "1.0.0" (art "test-x64" u1) "" ""))))
        (first (st/install! ctx (list (pair "pkgu" "*"))))
        (_ (rewriteIndex! "u" (pkgRow "pkgu" (str (ver "1.0.0" (art "test-x64" u1) "" "") (ver "2.0.0" (badArt "test-x64" u2) "" "")))))
        (failed (st/update! ctx (list "pkgu")))
        (afterFail (lockNames! ctx))
        (currentAfterFail (currentOf! ctx "pkgu"))
        (dirAfterFail (fileExists? (str ctx.home "/.asl/pkgs/pkgu/2.0.0")))
        (_ (rewriteIndex! "u" (pkgRow "pkgu" (str (ver "1.0.0" (art "test-x64" u1) "" "") (ver "2.0.0" (art "test-x64" u2) "" "")))))
        (updated (st/update! ctx (list)))
        (verified (st/verify! ctx))
        (_ (writeOk! (str ctx.home "/.asl/pkgs/pkgu/2.0.0/src/main.asl") "tampered\n"))
        (tampered (st/verify! ctx))]
    (do
      (assert (okHas? first "(pkgu \"1.0.0\" binary)") "the first version installs")
      (assert (errHas? failed "ERR_PKG_SHA256") "an update whose artefact fails sha256 is refused")
      (assert (= afterFail (list "pkgu@1.0.0/binary")) "a failed update keeps the lock row of the old version")
      (assert (= currentAfterFail "1.0.0") "a failed update keeps current on the old version")
      (assert (not dirAfterFail) "a failed update leaves no half-installed dir")
      (assert (okHas? updated "(pkgu \"2.0.0\" binary)") "update with no names moves every installed package to its newest version")
      (assert (= (currentOf! ctx "pkgu") "2.0.0") "current points at the new version")
      (assert (not (fileExists? (str ctx.home "/.asl/pkgs/pkgu/1.0.0"))) "the replaced version dir is pruned")
      (assert (okHas? verified ":ok 1") "verify passes after an update")
      (assert (errHas? tampered "ERR_PKG_VERIFY") "verify catches an edited installed file")
      true))

fn ! testPartialUpdate -> Bool
  (let [(x1 (makeTgz! "pkgx" "1.0.0" false))
        (x2 (makeTgz! "pkgx" "2.0.0" false))
        (y1 (makeTgz! "pkgy" "1.0.0" false))
        (y2 (makeTgz! "pkgy" "2.0.0" false))
        (ctx (ctxFor! "p" (str (pkgRow "pkgx" (ver "1.0.0" (art "test-x64" x1) "" "")) (pkgRow "pkgy" (ver "1.0.0" (art "test-x64" y1) "" "")))))
        (_ (st/install! ctx (list (pair "pkgx" "*") (pair "pkgy" "*"))))
        (_ (rewriteIndex! "p" (str (pkgRow "pkgx" (str (ver "1.0.0" (art "test-x64" x1) "" "") (ver "2.0.0" (badArt "test-x64" x2) "" "")))
                                   (pkgRow "pkgy" (str (ver "1.0.0" (art "test-x64" y1) "" "") (ver "2.0.0" (art "test-x64" y2) "" ""))))))
        (failed (st/update! ctx (list)))]
    (do
      (assert (errHas? failed "ERR_PKG_SHA256") "one bad artefact fails the whole update")
      (assert (= (lockNames! ctx) (list "pkgx@1.0.0/binary" "pkgy@1.0.0/binary")) "the lock still names both old versions")
      (assert (= (currentOf! ctx "pkgy") "1.0.0") "the package that staged fine is not switched")
      (assert (not (fileExists? (str ctx.home "/.asl/pkgs/pkgy/2.0.0"))) "the dir staged before the failure is removed again")
      true))

fn ! testCli -> Bool
  (let [(tgz (makeTgz! "pkgl" "1.0.0" false))
        (ctx (ctxFor! "l" (pkgRow "pkgl" (ver "1.0.0" (art "test-x64" tgz) "" ""))))
        (badScheme (st/fetch! ctx "http://example.invalid/x" (str (baseDir) "/never")))]
    (do
      (assert (= (pkg/mainIn! ctx (list "install" "pkgl")) 0) "asl pkg install exits 0")
      (assert (= (pkg/mainIn! ctx (list "list")) 0) "asl pkg list exits 0")
      (assert (= (pkg/mainIn! ctx (list "verify")) 0) "asl pkg verify exits 0 on a clean install")
      (assert (= (pkg/mainIn! ctx (list "install" "../x")) 2) "a path-like name is a usage error, exit 2")
      (assert (= (pkg/mainIn! ctx (list "bogus")) 2) "an unknown verb is exit 2")
      (assert (= (pkg/mainIn! ctx (list "remove" "pkgl")) 0) "asl pkg remove exits 0")
      (assert (= (pkg/mainIn! ctx (list "remove" "pkgl")) 1) "removing again fails with exit 1")
      (assert (errHas? badScheme "ERR_PKG_URL") "only file:/// and https:// are fetched")
      true))

fn ! runImporter! verb: String home: String -> fr/ProcOut
  (let [(realHome (resultOr (getHomeDir) "/nonexistent"))]
    (fr/runGuarded (list (aslBin) verb (str (baseDir) "/ws/app.asl")) (str (baseDir) "/ws")
                    (fr/childEnv (list (str "HOME=" home) (str "ASL_NATIVE_CLI_CACHE=" realHome "/.asl/run/nativeCli")))
                    (fr/limits 900 64)))

; (:m :ref PKG-CLIENT :do "end to end: asl check of a module that imports pkga/main passes when HOME holds the installed package and fails with ERR_UNRESOLVED_IMPORT when it does not, so the resolver hook is what makes the import work")
fn ! testImportable -> Bool
  (let [(tgz (makeTgz! "pkgi" "1.0.0" false))
        (ctx (ctxFor! "i" (pkgRow "pkgi" (ver "1.0.0" (art "test-x64" tgz) "" ""))))
        (_ (dirCreate (str (baseDir) "/ws")))
        (_ (writeOk! (str (baseDir) "/ws/.asl.config.asn") "(:aslConfig :root true :version \"1.0.0\")\n"))
        (_ (writeOk! (str (baseDir) "/ws/app.asl") "(module app/main :x [answer main] :i [(pkgi/main :a pi)])\n\nfn answer -> Int64\n  (pi/value)\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (do (println (pi/value)) (ok 0))\n"))
        (before (runImporter! "check" ctx.home))
        (runBefore (runImporter! "run" ctx.home))
        (_ (st/install! ctx (list (pair "pkgi" "*"))))
        (after (runImporter! "check" ctx.home))
        (runAfter (runImporter! "run" ctx.home))]
    (do
      (assert (!= before.exitCode 0) "without the package installed the import does not resolve")
      (assert (stringContains? (str before.stdout before.stderr) "ERR_UNRESOLVED_IMPORT") "the failure names the unresolved import")
      (assert (= after.exitCode 0) "after asl pkg install the importing module checks clean")
      (assert (!= runBefore.exitCode 0) "asl run of a program importing an absent package fails")
      (assert (stringContains? (str runBefore.stdout runBefore.stderr) "ERR_UNRESOLVED_IMPORT") "the run failure names the unresolved import")
      (assert (= runAfter.exitCode 0) "asl run of a program importing an installed package succeeds")
      (assert (stringContains? runAfter.stdout "100") "the program prints the installed package value")
      true))

fn errText r: (Result A String) -> String
  (match r ((err e) e) ((ok _) ""))

fn diagsOf text: String -> String
  (match (ix/parseIndex text) ((ok i) (stringJoin i.diags ";")) ((err e) e))

fn versionsIn text: String -> Int64
  (match (ix/parseIndex text) ((ok i) (listLength (listFlatMap (fn [(p ix/Pkg)] -> (List ix/Version) p.versions) i.pkgs))) ((err _) -1))

fn ! lockFile! ctx: st/Ctx -> String
  (str (st/pkgsRoot ctx) "/.lock")

fn ! readOr! path: String -> String
  (match (fileReadString path) ((ok s) s) ((err _) "none"))

; (:m :ref PKG-CLIENT :do "lock ownership: a live owner with the same start time holds the lock (ERR_PKG_BUSY, lock untouched), a dead pid or a reused pid with another start time is taken over, and finish! removes the lock only when its token is the one in the file")
fn ! testLock -> Bool
  (let [(ctx (ctxFor! "k" ""))
        (_ (dirCreate (st/pkgsRoot ctx)))
        (self (procSelf))
        (foreign (str self "|" (st/startIdOf! self) "|foreign-token"))
        (_ (writeOk! (lockFile! ctx) foreign))
        (busy (st/begin! ctx))
        (afterBusy (readOr! (lockFile! ctx)))
        (_ (writeOk! (lockFile! ctx) "2147483646|Thu Jan  1 00:00:00 1970|dead-token"))
        (dead (st/begin! ctx))
        (_ (match dead ((ok tmp) (st/finish! ctx tmp)) ((err _) ())))
        (afterDead (readOr! (lockFile! ctx)))
        (_ (writeOk! (lockFile! ctx) (str self "|Thu Jan  1 00:00:00 1970|reused-token")))
        (reused (st/begin! ctx))
        (_ (match reused ((ok tmp) (st/finish! ctx tmp)) ((err _) ())))
        (afterReused (readOr! (lockFile! ctx)))
        (mine (st/begin! ctx))
        (_ (writeOk! (lockFile! ctx) (str self "|" (st/startIdOf! self) "|someone-else")))
        (_ (match mine ((ok tmp) (st/finish! ctx tmp)) ((err _) ())))
        (afterForeignFinish (readOr! (lockFile! ctx)))]
    (do
      (assert (errHas? busy "ERR_PKG_BUSY") "a lock held by a live process with its start time is busy")
      (assert (= afterBusy foreign) "a busy begin leaves the holder's lock file untouched")
      (assert (okHas? dead "") "a lock whose pid is dead is taken over")
      (assert (= afterDead "none") "finish! releases the lock it took over")
      (assert (okHas? reused "") "a live pid with a different start time (pid reuse) is taken over")
      (assert (= afterReused "none") "finish! releases the lock after a pid-reuse takeover")
      (assert (okHas? mine "") "a free lock is taken")
      (assert (stringContains? afterForeignFinish "someone-else") "finish! does not remove a lock that carries another token")
      true))

fn ! testDepSpecs -> Bool
  (let [(b1 (makeTgz! "pkgb2" "1.0.0" false))
        (b2 (makeTgz! "pkgb2" "2.0.0" false))
        (a1 (makeTgz! "pkga2" "1.0.0" false))
        (rows (str (pkgRow "pkgb2" (str (ver "1.0.0" (art "test-x64" b1) "" "") (ver "2.0.0" (art "test-x64" b2) "" "")))
                   (pkgRow "pkga2" (ver "1.0.0" (art "test-x64" a1) "" "(pkgb2 \"^1.0\")"))))
        (ctx (ctxFor! "s" rows))
        (_ (st/install! ctx (list (pair "pkga2" "*"))))
        (before (lockNames! ctx))
        (upd (st/update! ctx (list "pkgb2")))
        (pin (st/install! ctx (list (pair "pkgb2" "2.0.0"))))
        (after (lockNames! ctx))]
    (do
      (assert (= before (list "pkga2@1.0.0/binary" "pkgb2@1.0.0/binary")) "a with its dependency b installed")
      (assert (errHas? upd "ERR_PKG_CONFLICT") "update b to 2.0 is refused because installed a needs ^1.0")
      (assert (errHas? pin "ERR_PKG_CONFLICT") "installing b 2.0.0 is refused for the same reason")
      (assert (= after before) "a refused update or install leaves the lock as it was")
      (assert (= (currentOf! ctx "pkgb2") "1.0.0") "b stays on 1.0.0")
      true))

fn ! makeBigTgz! name: String ver: String bytes: Int64 -> String
  (let [(dir (str (baseDir) "/fix/" name "-" ver))
        (tgz (str (baseDir) "/fix/" name "-" ver ".tgz"))
        (_ (dirCreate (str dir "/src")))
        (_ (writeOk! (str dir "/manifest.asn") (str "(:package " name " :version \"" ver "\" :entry \"src/main.asl\")\n")))
        (_ (writeOk! (str dir "/src/main.asl") (pkgSource name ver)))
        (_ (writeOk! (str dir "/src/big.txt") (stringRepeat "b" bytes)))
        (_ (run! (list "/usr/bin/tar" "-czf" tgz "-C" dir "manifest.asn" "src") (baseDir)))]
    tgz)

; (:m :ref PKG-CLIENT :do "caps: a tiny archive that unpacks over the byte cap, an archive over the entry cap and a local file over the fetch cap are refused with ERR_PKG_SIZE before anything is unpacked; a 1.5 MB file spans two digest chunks and verify still catches a change in the second chunk")
fn ! testCaps -> Bool
  (let [(big (makeBigTgz! "pkgz" "1.0.0" 50000))
        (ctx (ctxFor! "z" (pkgRow "pkgz" (ver "1.0.0" (art "test-x64" big) "" ""))))
        (bytesCap (st/install! (st/withCaps ctx 10000 100) (list (pair "pkgz" "*"))))
        (entryCap (st/install! (st/withCaps ctx 1000000 2) (list (pair "pkgz" "*"))))
        (src (str (baseDir) "/fix/capsrc.bin"))
        (_ (writeOk! src (stringRepeat "c" 5000)))
        (copied (st/copyFile! (st/withCaps ctx 1000 100) src (str (baseDir) "/fix/capdst.bin")))
        (fine (st/install! ctx (list (pair "pkgz" "*"))))
        (huge (makeBigTgz! "pkgh" "1.0.0" 1500000))
        (ctx2 (ctxFor! "z2" (pkgRow "pkgh" (ver "1.0.0" (art "test-x64" huge) "" ""))))
        (_ (st/install! ctx2 (list (pair "pkgh" "*"))))
        (ok1 (st/verify! ctx2))
        (_ (fileAppend (str ctx2.home "/.asl/pkgs/pkgh/1.0.0/src/big.txt") "x"))
        (bad1 (st/verify! ctx2))]
    (do
      (assert (errHas? bytesCap "ERR_PKG_SIZE") "an archive that unpacks over the byte cap is refused")
      (assert (errHas? entryCap "ERR_PKG_SIZE") "an archive over the entry cap is refused")
      (assert (errHas? copied "ERR_PKG_SIZE") "a local file over the fetch cap is refused")
      (assert (not (fileExists? (str (baseDir) "/fix/capdst.bin"))) "the oversize copy wrote nothing")
      (assert (= (lockNames! (st/withCaps ctx 10000 100)) (list "pkgz@1.0.0/binary")) "only the install under the default caps is in the lock")
      (assert (okHas? fine "pkgz") "the same archive installs under the default caps")
      (assert (okHas? ok1 ":ok 1") "a multi-chunk file verifies after install")
      (assert (errHas? bad1 "ERR_PKG_VERIFY") "a change after the first digest chunk is caught by verify")
      true))

fn ! testCycleRemove -> Bool
  (let [(p (makeTgz! "pkgca" "1.0.0" false))
        (q (makeTgz! "pkgcb" "1.0.0" false))
        (r (makeTgz! "pkgcc" "1.0.0" false))
        (rows (str (pkgRow "pkgca" (ver "1.0.0" (art "test-x64" p) "" "(pkgcb \"*\")"))
                   (pkgRow "pkgcb" (ver "1.0.0" (art "test-x64" q) "" "(pkgca \"*\")"))
                   (pkgRow "pkgcc" (ver "1.0.0" (art "test-x64" r) "" "(pkgca \"*\")"))))
        (ctx (ctxFor! "y" rows))
        (_ (st/install! ctx (list (pair "pkgca" "*") (pair "pkgcc" "*"))))
        (blocked (st/remove! ctx "pkgca"))
        (_ (st/remove! ctx "pkgcc"))
        (gone (st/remove! ctx "pkgca"))]
    (do
      (assert (errHas? blocked "ERR_PKG_REQUIRED") "a package outside the cycle that needs it blocks the removal")
      (assert (okHas? gone "pkgcb") "removing one member of a dependency cycle removes the whole cycle")
      (assert (= (lockNames! ctx) (list)) "nothing is left in the lock")
      true))

fn ! testRecovery -> Bool
  (let [(p (makeTgz! "pkgrr" "1.0.0" false))
        (q (makeTgz! "pkgrs" "1.0.0" false))
        (ctx (ctxFor! "r" (str (pkgRow "pkgrr" (ver "1.0.0" (art "test-x64" p) "" "")) (pkgRow "pkgrs" (ver "1.0.0" (art "test-x64" q) "" "")))))
        (_ (st/install! ctx (list (pair "pkgrr" "*"))))
        (_ (pathRemove (st/currentPath ctx "pkgrr")))
        (_ (dirCreate (str (st/pkgsRoot ctx) "/.tmp-dead/unpack")))
        (_ (st/install! ctx (list (pair "pkgrs" "*"))))]
    (do
      (assert (= (currentOf! ctx "pkgrr") "1.0.0") "a current link lost in a crash is set back from the lock")
      (assert (not (fileExists? (str (st/pkgsRoot ctx) "/.tmp-dead"))) "the temp dir of a dead operation is deleted")
      true))

fn ! testFileRefusal -> Bool
  (let [(ctx (st/makeCtx (str (baseDir) "/home-f") "https://example.invalid/index.asn" "test-x64" ""))
        (r (st/fetch! ctx "file:///etc/hosts" (str (baseDir) "/fix/hosts.copy")))]
    (do
      (assert (errHas? r "ERR_PKG_URL") "a file:/// artefact is refused when the index is not a file:/// index")
      (assert (not (fileExists? (str (baseDir) "/fix/hosts.copy"))) "nothing was copied")
      true))

fn ! testShadow -> Bool
  (let [(ws (str (baseDir) "/ws"))
        (_ (dirCreate (str ws "/pkgi/src")))
        (_ (writeOk! (str ws "/pkgi/manifest.asn") "(:package pkgi :version \"0.0.1\" :entry \"src/other.asl\")\n"))
        (_ (writeOk! (str ws "/pkgi/src/other.asl") "(module pkgi/other :x [] :i [])\n"))
        (home (str (baseDir) "/home-i"))
        (shadowed (runImporter! "check" home))]
    (do
      (assert (!= shadowed.exitCode 0) "an installed package does not fill in for a module of a workspace package of the same name")
      true))

fn ! cleanup! -> Unit
  (match (pathRemove (baseDir)) ((ok _) ()) ((err _) ()))

fn ! runTests -> Bool
  (do
    (cleanup!)
    (dirCreate (str (baseDir) "/fix"))
    (testPure)
    (testInstallAndImport)
    (testShaMismatch)
    (testSourceFallback)
    (testMalicious)
    (testRemoveAndDeps)
    (testUpdate)
    (testPartialUpdate)
    (testCli)
    (testImportable)
    (testShadow)
    (testLock)
    (testDepSpecs)
    (testCaps)
    (testCycleRemove)
    (testRecovery)
    (testFileRefusal)
    (cleanup!)
    true)
