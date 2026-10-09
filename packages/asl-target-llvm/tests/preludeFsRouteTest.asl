(module asl-target-llvm/tests/preludeFsRouteTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/ssa :a ssa)])

fn host -> String
  "asl/host/out/asl-host"

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn ! hostTriple -> String
  (let [(k (stringReplace (sh "uname -s").stdout "\n" ""))
        (m (stringReplace (sh "uname -m").stdout "\n" ""))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (mt (libc/libcFacts (hostTriple))
    ((some f) f)
    ((none) (do (assert false (str "hostFacts: libc.asl has no row for this host's triple \"" (hostTriple) "\"")) (libc/emptyTripleFacts))))

fn lines xs: (List String) -> String
  (str (stringJoin xs "\n") "\n")

fn routedNames -> (List String)
  (list "fileReadBytes" "fileReadString" "realPath" "fileWrite" "dirList" "fileStat" "fileReadRange" "envGet" "getHomeDir" "fileCreateExclusive"
        "dirCreate" "pathRemove" "pathRename" "fileChmod" "fileFsync" "fileReadlink" "fileLstat" "pathSymlink" "fileUtime")

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn ! lowered src: String -> (Option ty/SsaModule)
  (let [(preludeText (resultOr (fileRead (lk/preludePath)) ""))]
    (do (assert (not (stringEmpty? preludeText)) (str (lk/preludePath) " is readable"))
        (mt (lk/lowerSourceWith src preludeText)
          ((err ds) (do (assert false (str "lowerSourceWith: " (diagText ds))) (none)))
          ((ok m) (some m)))))

fn ! build work: String src: String -> String
  (do (assert (ok? (fileWrite (str work "/fsRoute.asl") src)) "fsRoute.asl written")
      (mt (lowered src)
        ((none) "")
        ((some m)
          (mt (llvm/emitLlvmProgramFor (hostFacts) m "main")
            ((err ds) (do (assert false (str "emitLlvmProgramFor: " (diagText ds))) ""))
            ((ok text) (do (assert (ok? (fileWrite (str work "/fsRoute.ll") text)) "fsRoute.ll written") text))))))

fn ! linkBin work: String -> Bool
  (let [(out (sh (str (clang) " -x ir " work "/fsRoute.ll -x none " (lib) " -lm -o " work "/fsRoute")))]
    (do (assert (= out.exitCode 0) (str "fsRoute links; " out.stderr))
        (= out.exitCode 0)))

fn coreCall name: String -> String
  (str "@asl_rt_builtin(ptr @name." (ssa/llvmName name) ",")

fn wrapperDef name: String -> String
  (str "define internal tailcc %Val @" (ssa/llvmName (str "asl-target-llvm/sysRoute." name)) "(")

fn ! checkIr ll: String -> Bool
  (do (assert (> (stringLength ll) 0) "IR emitted")
      (map (fn [(n String)] -> Bool (do (assert (not (stringContains? ll (coreCall n))) (str n " is not called through asl_rt_builtin")) true)) (routedNames))
      (map (fn [(n String)] -> Bool (do (assert (stringContains? ll (wrapperDef n)) (str "IR defines the " n " wrapper internal")) true)) (routedNames))
      true)

fn fsSource -> String
  (lines (list
    "(module fsRoute :x [main] :i [])"
    ""
    "fn bytesText b: Bytes i: Int64 acc: String -> String"
    "  (if (>= i (bytesLength b)) acc (bytesText b (+ i 1) (str acc (bytesGet b i) \",\")))"
    ""
    "fn ! showBytes label: String r: (Result Bytes String) -> Bool"
    "  (do (mt r ((ok b) (println label \"ok\" (bytesLength b) (bytesText b 0 \"\"))) ((err e) (println label \"err\" e))) true)"
    ""
    "fn ! showSize label: String r: (Result Bytes String) -> Bool"
    "  (do (mt r ((ok b) (println label \"ok\" (bytesLength b) (bytesGet b 0) (bytesGet b 1048576) (bytesGet b (- (bytesLength b) 1)))) ((err e) (println label \"err\" e))) true)"
    ""
    "fn ! showStat label: String r: (Result FileStat String) -> Bool"
    "  (do (mt r ((ok s) (println label \"ok\" s.isFile s.isDir s.size (mod s.mode 4096) (/ s.mode 4096))) ((err e) (println label \"err\" e))) true)"
    ""
    "fn ! showLink label: String r: (Result LinkStat String) -> Bool"
    "  (do (mt r ((ok s) (println label \"ok\" s.isFile s.isDir s.isSymlink s.size (/ s.mode 4096))) ((err e) (println label \"err\" e))) true)"
    ""
    "fn ! showFresh label: String before: Int64 r: (Result FileStat String) -> Bool"
    "  (do (mt r ((ok s) (println label \"ok\" (= s.mtime (/ s.mtimeNs 1000000000)) (>= s.mtimeNs (- before 2000000000)) (<= s.mtimeNs (+ (nowNs) 2000000000))))"
    "            ((err e) (println label \"err\" e)))"
    "      true)"
    ""
    "fn ! viaText f: (fn [String] -> (Result String String)) p: String -> (Result String String)"
    "  (f p)"
    ""
    "fn ! viaBytes f: (fn [String] -> (Result Bytes String)) p: String -> (Result Bytes String)"
    "  (f p)"
    ""
    "fn ! viaStat f: (fn [String] -> (Result FileStat String)) p: String -> (Result FileStat String)"
    "  (f p)"
    ""
    "fn ! viaList f: (fn [String] -> (Result (List String) String)) p: String -> (Result (List String) String)"
    "  (f p)"
    ""
    "fn ! viaUnit f: (fn [String] -> (Result Unit String)) p: String -> (Result Unit String)"
    "  (f p)"
    ""
    "fn ! viaPair f: (fn [String String] -> (Result Unit String)) a: String b: String -> (Result Unit String)"
    "  (f a b)"
    ""
    "fn ! viaEnv f: (fn [String] -> (Option String)) name: String -> (Option String)"
    "  (f name)"
    ""
    "fn ! viaHome f: (fn [] -> (Result String String)) -> (Result String String)"
    "  (f)"
    ""
    "fn ! longName n: Int64 acc: String -> String"
    "  (if (<= n 0) acc (longName (- n 1) (str acc \"a\")))"
    ""
    "fn ! reads root: String -> Bool"
    "  (do (showBytes \"empty bytes\" (fileReadBytes (str root \"/empty\")))"
    "      (println \"empty string\" (fileReadString (str root \"/empty\")))"
    "      (showBytes \"one bytes\" (fileReadBytes (str root \"/one\")))"
    "      (println \"one string\" (fileReadString (str root \"/one\")))"
    "      (showSize \"large bytes\" (fileReadBytes (str root \"/large\")))"
    "      (println \"large string\" (mt (fileReadString (str root \"/large\")) ((ok s) (stringLength s)) ((err e) e)))"
    "      (println \"missing bytes\" (mt (fileReadBytes (str root \"/missing\")) ((ok b) (bytesLength b)) ((err e) e)))"
    "      (println \"missing string\" (fileReadString (str root \"/missing\")))"
    "      (showBytes \"directory bytes\" (fileReadBytes root))"
    "      (println \"directory string\" (fileReadString root))"
    "      (println \"fifo string\" (fileReadString (str root \"/fifo\")))"
    "      (println \"nul string\" (fileReadString (str root \"/one\\x00tail\")))"
    "      (showStat \"nul stat\" (fileStat (str root \"/one\\x00tail\")))"
    "      (println \"long stat\" (mt (fileStat (str root \"/\" (longName 1500 \"\"))) ((ok s) \"ok\") ((err e) (str (stringLength e) \" \" e))))"
    "      true)"
    ""
    "fn ! ranges root: String -> Bool"
    "  (do (showBytes \"range zero\" (fileReadRange (str root \"/one\") 0 1))"
    "      (showBytes \"range zero length\" (fileReadRange (str root \"/one\") 0 0))"
    "      (showBytes \"range mid\" (fileReadRange (str root \"/large\") 1048570 12))"
    "      (showBytes \"range clamp\" (fileReadRange (str root \"/large\") 3145720 100))"
    "      (showBytes \"range past\" (fileReadRange (str root \"/one\") 8 3))"
    "      (showBytes \"range negative offset\" (fileReadRange (str root \"/one\") -1 3))"
    "      (showBytes \"range negative length\" (fileReadRange (str root \"/one\") 0 -1))"
    "      (showBytes \"range cap\" (fileReadRange (str root \"/one\") 0 2000000000))"
    "      (showBytes \"range missing\" (fileReadRange (str root \"/missing\") 0 1))"
    "      (showBytes \"range device\" (fileReadRange \"/dev/zero\" 5 3))"
    "      (showBytes \"range fifo offset\" (fileReadRange (str root \"/fifo2\") 1 3))"
    "      (showBytes \"range fifo\" (fileReadRange (str root \"/fifo3\") 0 3))"
    "      (showBytes \"range nul\" (fileReadRange (str root \"/one\\x00tail\") 0 1))"
    "      true)"
    ""
    "fn ! writes root: String -> Bool"
    "  (let [(before (nowNs))]"
    "    (do (println \"write\" (fileWrite (str root \"/written\") \"data\"))"
    "        (showStat \"written stat\" (fileStat (str root \"/written\")))"
    "        (showFresh \"written time\" before (fileStat (str root \"/written\")))"
    "        (println \"write bytes\" (fileWrite (str root \"/wbytes\") (stringToBytes \"a\\x00b\")))"
    "        (showBytes \"wbytes\" (fileReadBytes (str root \"/wbytes\")))"
    "        (println \"write truncates\" (fileWrite (str root \"/wbytes\") \"z\") (fileReadString (str root \"/wbytes\")))"
    "        (println \"write missing dir\" (fileWrite (str root \"/absent/file\") \"x\"))"
    "        (println \"write nul\" (fileWrite (str root \"/wnul\\x00tail\") \"n\") (fileReadString (str root \"/wnul\")))"
    "        (println \"exclusive\" (fileCreateExclusive (str root \"/excl\") \"e\") (fileReadString (str root \"/excl\")))"
    "        (println \"exclusive again\" (fileCreateExclusive (str root \"/excl\") \"f\") (fileReadString (str root \"/excl\")))"
    "        (println \"exclusive nul\" (fileCreateExclusive (str root \"/ex\\x00cl\") \"g\"))"
    "        (println \"exclusive missing dir\" (fileCreateExclusive (str root \"/absent/excl\") \"h\"))"
    "        true))"
    ""
    "fn ! dirs root: String -> Bool"
    "  (do (println \"list empty\" (dirList (str root \"/emptydir\")))"
    "      (println \"list dots\" (dirList (str root \"/dots\")))"
    "      (println \"list missing\" (dirList (str root \"/missing\")))"
    "      (println \"list file\" (dirList (str root \"/one\")))"
    "      (println \"create deep\" (dirCreate (str root \"/made/deep//er/\")))"
    "      (println \"create again\" (dirCreate (str root \"/made/deep\")))"
    "      (println \"list made\" (dirList (str root \"/made\")))"
    "      (println \"create under file\" (dirCreate (str root \"/one/sub\")))"
    "      (println \"create empty\" (dirCreate \"\"))"
    "      (println \"create nul\" (dirCreate (str root \"/nul\\x00dir\")))"
    "      (println \"remove tree\" (pathRemove (str root \"/removeMe\")) (fileReadString (str root \"/keep/kept\")))"
    "      (println \"remove missing\" (pathRemove (str root \"/missing\")))"
    "      (println \"remove nul\" (pathRemove (str root \"/one\\x00tail\")))"
    "      true)"
    ""
    "fn ! renames root: String -> Bool"
    "  (do (println \"rename over\" (pathRename (str root \"/source\") (str root \"/target\")) (fileReadString (str root \"/target\")) (fileReadString (str root \"/source\")))"
    "      (println \"rename missing parent\" (pathRename (str root \"/one\") (str root \"/absent/dest\")))"
    "      (println \"rename missing\" (pathRename (str root \"/missing\") (str root \"/other\")))"
    "      (println \"rename nul\" (pathRename (str root \"/one\") (str root \"/to\\x00nul\")))"
    "      true)"
    ""
    "fn ! modes root: String -> Bool"
    "  (do (println \"chmod zero\" (fileChmod (str root \"/locked\") 0))"
    "      (println \"read chmod zero\" (fileReadString (str root \"/locked\")))"
    "      (println \"range chmod zero\" (mt (fileReadRange (str root \"/locked\") 0 1) ((ok b) (bytesLength b)) ((err e) e)))"
    "      (showStat \"stat chmod zero\" (fileStat (str root \"/locked\")))"
    "      (println \"chmod restore\" (fileChmod (str root \"/locked\") 420) (fileReadString (str root \"/locked\")))"
    "      (println \"chmod bad mode\" (fileChmod (str root \"/locked\") 5000))"
    "      (println \"chmod negative\" (fileChmod (str root \"/locked\") -1))"
    "      (println \"chmod missing\" (fileChmod (str root \"/missing\") 420))"
    "      (println \"chmod nul\" (fileChmod (str root \"/one\\x00tail\") 420))"
    "      (println \"fsync closed\" (fileFsync (str root \"/one\")))"
    "      (println \"fsync dir\" (fileFsync root))"
    "      (println \"fsync missing\" (fileFsync (str root \"/missing\")))"
    "      (println \"fsync nul\" (fileFsync (str root \"/one\\x00tail\")))"
    "      true)"
    ""
    "fn ! links root: String -> Bool"
    "  (do (println \"symlink\" (pathSymlink \"one\" (str root \"/link\")))"
    "      (println \"symlink again\" (pathSymlink \"one\" (str root \"/link\")))"
    "      (println \"symlink empty target\" (pathSymlink \"\" (str root \"/link2\")))"
    "      (println \"symlink nul target\" (pathSymlink \"o\\x00ne\" (str root \"/link2\")))"
    "      (println \"symlink nul link\" (pathSymlink \"one\" (str root \"/li\\x00nk2\")))"
    "      (println \"symlink dangling\" (pathSymlink \"nowhere\" (str root \"/dangling\")))"
    "      (println \"readlink\" (fileReadlink (str root \"/link\")))"
    "      (println \"readlink long\" (mt (fileReadlink (str root \"/longlink\")) ((ok t) (stringLength t)) ((err e) e)))"
    "      (println \"readlink file\" (fileReadlink (str root \"/one\")))"
    "      (println \"readlink missing\" (fileReadlink (str root \"/missing\")))"
    "      (println \"readlink nul\" (fileReadlink (str root \"/link\\x00x\")))"
    "      (showLink \"lstat link\" (fileLstat (str root \"/link\")))"
    "      (showStat \"stat link\" (fileStat (str root \"/link\")))"
    "      (showLink \"lstat dangling\" (fileLstat (str root \"/dangling\")))"
    "      (showStat \"stat dangling\" (fileStat (str root \"/dangling\")))"
    "      (showLink \"lstat dir\" (fileLstat root))"
    "      (showLink \"lstat nul\" (fileLstat (str root \"/link\\x00x\")))"
    "      (println \"realpath link\" (realPath (str root \"/link\")))"
    "      (println \"realpath dangling\" (realPath (str root \"/dangling\")))"
    "      true)"
    ""
    "fn ! times root: String -> Bool"
    "  (do (println \"utime\" (fileUtime (str root \"/one\") 1767225600123456789))"
    "      (println \"utime stat\" (fileStat (str root \"/one\")))"
    "      (println \"utime lstat\" (fileLstat (str root \"/one\")))"
    "      (println \"utime negative\" (fileUtime (str root \"/two\") -1500000000) (mt (fileStat (str root \"/two\")) ((ok s) (str s.mtime \" \" s.mtimeNs)) ((err e) e)))"
    "      (println \"utime through link\" (fileUtime (str root \"/link\") 1000000000000000001) (mt (fileStat (str root \"/one\")) ((ok s) s.mtimeNs) ((err e) e)))"
    "      (println \"utime missing\" (fileUtime (str root \"/missing\") 0))"
    "      (println \"utime nul\" (fileUtime (str root \"/one\\x00tail\") 0))"
    "      true)"
    ""
    "fn ! environment root: String -> Bool"
    "  (do (println \"env set\" (envGet \"PRELUDE_FS_SET\"))"
    "      (println \"env empty\" (envGet \"PRELUDE_FS_EMPTY\"))"
    "      (println \"env unset\" (envGet \"PRELUDE_FS_UNSET\"))"
    "      (println \"env nul\" (envGet \"PRELUDE_FS\\x00SET\"))"
    "      (println \"home\" (getHomeDir))"
    "      true)"
    ""
    "fn ! values root: String -> Bool"
    "  (do (showBytes \"value fileReadBytes\" (viaBytes fileReadBytes (str root \"/one\")))"
    "      (println \"value fileReadString\" (viaText fileReadString (str root \"/one\")))"
    "      (println \"value realPath\" (viaText realPath (str root \"/link\")))"
    "      (println \"value fileReadlink\" (viaText fileReadlink (str root \"/link\")))"
    "      (println \"value dirList\" (viaList dirList (str root \"/dots\")))"
    "      (showStat \"value fileStat\" (viaStat fileStat (str root \"/one\")))"
    "      (println \"value dirCreate\" (viaUnit dirCreate (str root \"/valueDir/a\")))"
    "      (println \"value pathRemove\" (viaUnit pathRemove (str root \"/valueDir\")))"
    "      (println \"value pathRename\" (viaPair pathRename (str root \"/excl\") (str root \"/exclMoved\")))"
    "      (println \"value envGet\" (viaEnv envGet \"PRELUDE_FS_SET\"))"
    "      (println \"value fileWrite\" (viaPair (fn [(p String) (c String)] -> (Result Unit String) (fileWrite p c)) (str root \"/valueWritten\") \"v\"))"
    "      (showBytes \"value fileReadRange\" (viaBytes (fn [(p String)] -> (Result Bytes String) (fileReadRange p 0 1)) (str root \"/valueWritten\")))"
    "      (println \"value getHomeDir\" (viaHome getHomeDir))"
    "      (println \"value fileCreateExclusive\" (viaPair fileCreateExclusive (str root \"/valueExcl\") \"w\"))"
    "      (println \"value fileChmod\" (viaUnit (fn [(p String)] -> (Result Unit String) (fileChmod p 384)) (str root \"/valueExcl\")))"
    "      (println \"value fileFsync\" (viaUnit fileFsync (str root \"/valueExcl\")))"
    "      (showLink \"value fileLstat\" (mt (viaUnit (fn [(p String)] -> (Result Unit String) (mt (fileLstat p) ((ok _) (ok ())) ((err e) (err e)))) (str root \"/link\")) ((ok _) (fileLstat (str root \"/link\"))) ((err e) (err e))))"
    "      (println \"value pathSymlink\" (viaPair pathSymlink \"one\" (str root \"/valueLink\")))"
    "      (println \"value fileUtime\" (viaUnit (fn [(p String)] -> (Result Unit String) (fileUtime p 5000000000)) (str root \"/valueExcl\")) (mt (fileStat (str root \"/valueExcl\")) ((ok s) s.mtimeNs) ((err e) e)))"
    "      true)"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(root (optionOr (listHead args) \"/nonexistent\"))]"
    "    (do (reads root) (ranges root) (writes root) (dirs root) (renames root) (modes root) (links root) (times root) (environment root) (values root)"
    "        (ok 0)))"
    ))

fn setupScript -> String
  (lines (list
    "root=\"$1\""
    "rm -rf \"$root\" && mkdir -p \"$root/emptydir\" \"$root/dots\" \"$root/removeMe/a/b\" \"$root/keep\" &&"
    ": > \"$root/empty\" && printf x > \"$root/one\" && printf 2 > \"$root/two\" && printf src > \"$root/source\" && : > \"$root/target\" && printf L > \"$root/locked\" &&"
    "printf h > \"$root/dots/.hidden\" && printf a > \"$root/dots/a\" && printf B > \"$root/dots/B\" && printf b > \"$root/dots/.b\" && printf c > \"$root/dots/c\" &&"
    "printf f > \"$root/removeMe/a/b/file\" && printf h > \"$root/removeMe/.h\" && printf kept > \"$root/keep/kept\" && ln -s ../keep \"$root/removeMe/ln\" &&"
    "ln -s \"$(printf '%0300d' 0)\" \"$root/longlink\" &&"
    "yes abcdefghij | head -c 3145728 > \"$root/large\" &&"
    "mkfifo \"$root/fifo\" \"$root/fifo2\" \"$root/fifo3\" &&"
    "(exec >/dev/null 2>&1 </dev/null; printf fifo > \"$root/fifo\" &) && (exec >/dev/null 2>&1 </dev/null; printf fifo > \"$root/fifo2\" &) && (exec >/dev/null 2>&1 </dev/null; printf fifo > \"$root/fifo3\" &)"
    ))

fn releaseFifos root: String -> String
  (str "for f in " root "/fifo " root "/fifo2 " root "/fifo3; do if [ -p \"$f\" ]; then (exec 3<>\"$f\") 2>/dev/null; fi; done; true")

fn ! runIn work: String env: String cmd: String -> ProcessOutput
  (let [(root (str work "/tree"))
        (made (sh (str "sh " work "/setup.sh " root)))
        (out (sh (str "env -u ASL_ROOT -u ASL_LAUNCHED " env " " cmd " " root)))
        (_ (sh (releaseFifos root)))]
    (do (assert (= made.exitCode 0) (str "fixture tree built: " made.stderr))
        out))

fn ! checkParity work: String label: String env: String -> Bool
  (let [(native (runIn work env (str work "/fsRoute")))
        (vm (runIn work env (str (host) " run " work "/fsRoute.asl")))]
    (do (assert (= native.exitCode vm.exitCode) (str label ": native exit " native.exitCode " equals asl-host run's " vm.exitCode "; native stderr " native.stderr "; vm stderr " vm.stderr))
        (assert (= native.stdout vm.stdout) (str label ": native stdout equals asl-host run's; native=" native.stdout " vm=" vm.stdout))
        (assert (= native.stderr vm.stderr) (str label ": native stderr equals asl-host run's; native=" native.stderr " vm=" vm.stderr))
        (assert (= native.exitCode 0) (str label ": native run exits 0; stderr " native.stderr))
        (assert (stringContains? native.stdout "value fileUtime (ok ())") (str label ": native run reaches its last case"))
        true))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d"))
        (work (stringReplace made.stdout "\n" ""))]
    (do (assert (= made.exitCode 0) "mktemp -d makes a work directory")
        (assert (ok? (fileWrite (str work "/setup.sh") (setupScript))) "setup.sh written")
        (checkIr (build work (fsSource)))
        (linkBin work)
        (checkParity work "HOME set" (str "-u PRELUDE_FS_UNSET HOME=" work "/home PRELUDE_FS_SET=set PRELUDE_FS_EMPTY="))
        (checkParity work "HOME empty" "-u PRELUDE_FS_UNSET HOME= PRELUDE_FS_SET=set PRELUDE_FS_EMPTY=")
        (checkParity work "HOME unset" "-u PRELUDE_FS_UNSET -u HOME PRELUDE_FS_SET=set PRELUDE_FS_EMPTY=")
        (assert (= (sh (str "chmod -R u+rwx " work " 2>/dev/null; rm -rf " work)).exitCode 0) "work directory removed")
        true))
