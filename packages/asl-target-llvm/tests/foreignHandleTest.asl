(module asl-target-llvm/tests/foreignHandleTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/lower :a low)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a rt)
      (asl-target-llvm/main :a llvm)
      (asl-tools/fleet/run :a run)])

; (:m :ref FFI2 :do "owned C pointers end to end: a handle:F result becomes a Handle whose finaliser F runs at collection, close:F closes it once, a closed or foreign Handle is refused before C sees it, !neg and !null report strerror(errno), and :linkLibraries of an imported package reach the link")
fn unitSource -> String
  (stringJoin (list
    "(module ffiHandleUnit :x [openFile closeFile writeText closeFd] :i [])"
    ""
    "fn ! openFile path: String mode: String -> (Result Handle String)"
    "  (foreign \"c\" \"fopen\" \"cstr cstr -> handle:fclose !null\")"
    ""
    "fn ! closeFile f: Handle -> (Result Int64 String)"
    "  (foreign \"c\" \"fclose\" \"close:fclose -> i32 !neg\")"
    ""
    "fn ! writeText s: String f: Handle -> (Result Int64 String)"
    "  (foreign \"c\" \"fputs\" \"cstr handle:fclose -> i32 !neg\")"
    ""
    "fn ! closeFd fd: Int64 -> (Result Int64 String)"
    "  (foreign \"c\" \"close\" \"i32 -> i32 !neg\")"
    "") "\n")

fn finOnlySource -> String
  (stringJoin (list
    "(module ffiFinOnly :x [openDir dirFd] :i [])"
    ""
    "fn ! openDir path: String -> (Result Handle String)"
    "  (foreign \"c\" \"opendir\" \"cstr -> handle:closedir !null\")"
    ""
    "fn ! dirFd d: Handle -> Int64"
    "  (foreign \"c\" \"dirfd\" \"handle:closedir -> i32\")"
    "") "\n")

fn externNamed m: ty/SsaModule name: String -> (Option ty/SsaExtern)
  (listFind (fn [(e ty/SsaExtern)] -> Bool (= e.name name)) m.externs)

fn tyNames ts: (List ty/SsaTy) -> (List String)
  (map (fn [(t ty/SsaTy)] -> String (ty/ssaTyName t)) ts)

fn shape e: (Option ty/SsaExtern) -> String
  (match e
    ((some x) (str (stringJoin (tyNames x.params) " ") " -> " (ty/ssaTyName x.ret)))
    ((none) "absent"))

fn diagCodes ds: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.code) ds)

fn routed src: String -> (Result ty/SsaModule String)
  (match (low/lowerSource src)
    ((err ds) (err (str "lowering: " (stringJoin (diagCodes ds) " "))))
    ((ok m) (match (rt/routeModule (libc/darwinArm64Facts) m)
              ((err ds) (err (str "routing: " (stringJoin (diagCodes ds) " "))))
              ((ok r) (ok r.result)))))

fn ! testRoute -> Bool
  (do (match (routed (unitSource))
        ((err e) (assert (stringEmpty? e) (str "the handle unit routes: " e)))
        ((ok out) (do (assert (= (shape (externNamed out "fopen")) "ptr ptr -> ptr") (str "fopen takes two C strings and returns a pointer: " (shape (externNamed out "fopen"))))
                      (assert (= (shape (externNamed out "fclose")) "ptr -> i32") (str "fclose is declared once, as the close call declares it: " (shape (externNamed out "fclose"))))
                      (assert (= (shape (externNamed out "__error")) " -> ptr") (str "!neg and !null read errno through the Darwin accessor: " (shape (externNamed out "__error"))))
                      (assert (= (shape (externNamed out "strerror")) "i32 -> ptr") (str "the errno text comes from strerror: " (shape (externNamed out "strerror"))))
                      (assert (ok? (vfy/verifySsa out)) (str "the routed handle unit verifies: " (match (vfy/verifySsa out) ((err ds) (stringJoin (diagCodes ds) " ")) ((ok _) "")))))))
      (match (routed (finOnlySource))
        ((err e) (assert (stringEmpty? e) (str "the finaliser-only unit routes: " e)))
        ((ok out) (do (assert (= (shape (externNamed out "closedir")) "ptr -> i32") (str "a finaliser named only by handle:F is declared int F(void *): " (shape (externNamed out "closedir"))))
                      (assert (= (listLength (filter (fn [(e ty/SsaExtern)] -> Bool (= e.name "closedir")) out.externs)) 1) "a finaliser two foreign fns name is declared once")
                      (assert (ok? (vfy/verifySsa out)) (str "the finaliser-only unit verifies: " (match (vfy/verifySsa out) ((err ds) (stringJoin (diagCodes ds) " ")) ((ok _) "")))))))
      (match (low/lowerSource (unitSource))
        ((err ds) (assert (listEmpty? ds) (str "the handle unit lowers: " (stringJoin (diagCodes ds) " "))))
        ((ok m) (assert (listContains? (match (rt/routeModule (libc/wasm32Facts) m) ((err ds) (diagCodes ds)) ((ok _) (list))) "ERR_FOREIGN_TARGET")
                        "wasm32 rejects handles with the rest of foreign")))
      true)

fn calleeOf text: String -> String
  (match (listGet (stringSplit text "@") 1)
    ((none) "")
    ((some rest) (optionOr (listHead (stringSplit rest "(")) "")))

fn definedConventions lines: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (l String)] -> (Map String Bool)
          (if (stringStartsWith? l "define ") (mapSet acc (calleeOf l) (stringContains? l " tailcc ")) acc))
        (mapEmpty) lines)

; (:m :ref FFI2 :do "a direct call whose convention differs from its callee's define is undefined behaviour that instcombine turns into poison, so every call site of a function this program defines must match its tailcc or ccc")
fn conventionMismatches text: String -> (List String)
  (let [(lines (stringLines text))
        (defs (definedConventions lines))]
    (fold (fn [(acc (List String)) (l String)] -> (List String)
            (match (listGet (stringSplit l "call ") 1)
              ((none) acc)
              ((some rest) (let [(name (calleeOf rest))]
                             (match (mapGet defs name)
                               ((none) acc)
                               ((some tail) (if (= tail (stringStartsWith? rest "tailcc ")) acc (listAppend acc (list (stringTrim l))))))))))
          (list) lines))

fn conventionSource -> String
  (stringJoin (list
    "(module ffiConventions :x [main] :i [])"
    "fn ! openFile path: String mode: String -> (Result Handle String)"
    "  (foreign \"c\" \"fopen\" \"cstr cstr -> handle:fclose !null\")"
    "fn ! closeFile f: Handle -> (Result Int64 String)"
    "  (foreign \"c\" \"fclose\" \"close:fclose -> i32 !neg\")"
    "fn ! writeText s: String f: Handle -> (Result Int64 String)"
    "  (foreign \"c\" \"fputs\" \"cstr handle:fclose -> i32 !neg\")"
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (match (openFile \"/dev/null\" \"w\") ((ok h) (do (writeText \"a\" h) (closeFile h))) ((err e) (err e)))"
    "") "\n")

fn ! testConventions -> Bool
  (match (low/lowerSource (conventionSource))
    ((err ds) (do (assert (listEmpty? ds) (str "the handle fixture lowers: " (stringJoin (diagCodes ds) " "))) false))
    ((ok m) (match (llvm/emitLlvmProgramNativeWith! m "main" "notrace")
              ((err ds) (do (assert (listEmpty? ds) (str "the handle fixture emits: " (stringJoin (diagCodes ds) " "))) false))
              ((ok text) (let [(bad (conventionMismatches text))]
                           (do (assert (stringContains? text "@ffiHandleClear(") "the close wrapper calls ffiHandleClear")
                               (assert (listEmpty? bad) (str "every call matches its callee's calling convention: " (stringJoin (listTake bad 4) " | ")))
                               true))))))

fn fixtureSource -> String
  (stringJoin (list
    "(module ffiHandles :x [main] :i [])"
    ""
    "fn ! openFile path: String mode: String -> (Result Handle String)"
    "  (foreign \"c\" \"fopen\" \"cstr cstr -> handle:fclose !null\")"
    ""
    "fn ! closeFile f: Handle -> (Result Int64 String)"
    "  (foreign \"c\" \"fclose\" \"close:fclose -> i32 !neg\")"
    ""
    "fn ! writeText s: String f: Handle -> (Result Int64 String)"
    "  (foreign \"c\" \"fputs\" \"cstr handle:fclose -> i32 !neg\")"
    ""
    "fn ! writePlain s: String f: Handle -> Int64"
    "  (foreign \"c\" \"fputs\" \"cstr handle:fclose -> i32 !neg\")"
    ""
    "fn ! openDir path: String -> (Result Handle String)"
    "  (foreign \"c\" \"opendir\" \"cstr -> handle:closedir !null\")"
    ""
    "fn ! openFd fd: Int64 mode: String -> (Result Handle String)"
    "  (foreign \"c\" \"fdopen\" \"i32 cstr -> handle:fclose !null\")"
    ""
    "fn ! closeFd fd: Int64 -> (Result Int64 String)"
    "  (foreign \"c\" \"close\" \"i32 -> i32 !neg\")"
    ""
    "fn ! closeFdPlain fd: Int64 -> Int64"
    "  (foreign \"c\" \"close\" \"i32 -> i32 !neg\")"
    ""
    "fn ! ttyName fd: Int64 -> (Result String String)"
    "  (foreign \"c\" \"ttyname\" \"i32 -> cstr !null\")"
    ""
    "fn ! leak path: String -> Bool"
    "  (match (openFile path \"w\")"
    "    ((ok h) (>= (writePlain \"flushed by fclose\" h) 0))"
    "    ((err _) false))"
    ""
    "fn ! churn round: Int64 -> Int64"
    "  (listLength (map (fn [(i Int64)] -> String (str \"garbage \" i \" \" round)) (range 0 64)))"
    ""
    "fn ! closedLeak path: String -> Bool"
    "  (match (openFile path \"w\")"
    "    ((ok h) (ok? (closeFile h)))"
    "    ((err _) false))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (let [(dir (optionOr (listHead args) \".\")) (path (str dir \"/out.txt\")) (leaked (str dir \"/leaked.txt\"))]"
    "    (cond"
    "      ((listContains? args \"plainErrno\") (do (println (str (closeFdPlain -1))) (ok 0)))"
    "      ((listContains? args \"finaliser\")"
    "        (do (println (str \"leaked \" (leak leaked) \" closed \" (closedLeak path)))"
    "            (println (str \"churned \" (churn 1)))"
    "            (println (str \"finaliser \" (resultOr (fileReadString leaked) \"\")))"
    "            (ok 0)))"
    "      ((listContains? args \"plainClosed\")"
    "        (match (openFile path \"w\")"
    "          ((ok h) (do (closeFile h) (println (str (writePlain \"x\" h))) (ok 0)))"
    "          ((err e) (err e))))"
    "      (else"
    "        (match (openFile path \"w\")"
    "          ((err e) (err e))"
    "          ((ok h)"
    "            (do (println (str \"write \" (ok? (writeText \"hello\" h))))"
    "                (println (str \"close \" (closeFile h)))"
    "                (println (str \"after \" (writeText \"x\" h)))"
    "                (println (str \"again \" (closeFile h)))"
    "                (println (str \"content \" (resultOr (fileReadString path) \"\")))"
    "                (println (str \"kind \" (match (openDir dir) ((ok d) (writeText \"x\" d)) ((err e) (err e)))))"
    "                (println (str \"missing \" (match (openFile \"/nonexistent-ffi2/x\" \"r\") ((ok _) (ok 0)) ((err e) (err e)))))"
    "                (println (str \"badfd \" (closeFd -1)))"
    "                (println (str \"fdopen \" (match (openFd -1 \"r\") ((ok _) (ok 0)) ((err e) (err e)))))"
    "                (println (str \"tty \" (ttyName -1)))"
    "                (ok 0)))))))"
    "") "\n")

fn expectedLines -> (List String)
  (list "write true"
        "close (ok 0)"
        "after (err \"ERR_FOREIGN_CLOSED: ffiHandles.writeText (C fputs) argument 2 is a closed Handle\")"
        "again (err \"ERR_FOREIGN_CLOSED: ffiHandles.closeFile (C fclose) argument 1 is a closed Handle\")"
        "content hello"
        "kind (err \"ERR_FOREIGN_HANDLE: ffiHandles.writeText (C fputs) argument 2 is not a Handle made with fclose\")"
        "missing (err \"ERR_FOREIGN_ERRNO: ffiHandles.openFile (C fopen) failed: No such file or directory\")"
        "badfd (err \"ERR_FOREIGN_ERRNO: ffiHandles.closeFd (C close) failed: Bad file descriptor\")"
        "fdopen (err \"ERR_FOREIGN_ERRNO: ffiHandles.openFd (C fdopen) failed: Bad file descriptor\")"
        "tty (err \"ERR_FOREIGN_ERRNO: ffiHandles.ttyName (C ttyname) failed: Bad file descriptor\")")

fn ! runIn argv: (List String) cwd: String secs: Int64 -> run/Done
  (run/runOneLimited (run/job argv cwd (run/childEnv (list))) (run/limits secs 24))

fn ! build root: String dir: String exe: String -> run/Done
  (runIn (list "/bin/sh" "-c" "exec \"$0\" build \"$1\" -o \"$2\" 2>&1" (str root "/bin/asl") (str dir "/main.asl") exe) root 1500)

fn ! testHandles root: String work: String -> Bool
  (let [(dir (str work "/ffiHandles"))
        (made (dirCreate dir))
        (wrote (and (ok? (fileWrite (str dir "/manifest.asn") "(:package ffiHandles :version \"0.1.0\" :entry \"main.asl\")\n"))
                    (ok? (fileWrite (str dir "/main.asl") (fixtureSource)))))
        (exe (str dir "/handles"))
        (built (build root dir exe))
        (ran (if (= built.exit 0) (runIn (list exe dir) dir 120) built))
        (errnoTrap (if (= built.exit 0) (runIn (list "/bin/sh" "-c" "exec \"$0\" \"$1\" plainErrno 2>&1" exe dir) dir 60) built))
        (closedTrap (if (= built.exit 0) (runIn (list "/bin/sh" "-c" "exec \"$0\" \"$1\" plainClosed 2>&1" exe dir) dir 60) built))
        (swept (if (= built.exit 0) (runIn (list exe dir "finaliser") dir 120) built))
        (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines ran.out)))]
    (do (assert (and (ok? made) wrote) (str "the handle fixture was written under " dir))
        (assert (= built.exit 0) (str "bin/asl build links the handle fixture: exit " built.exit " " built.out))
        (assert (= ran.exit 0) (str "the handle fixture runs: exit " ran.exit " " ran.out))
        (assert (= (listLength lines) (listLength (expectedLines))) (str "the handle fixture prints " (listLength (expectedLines)) " lines: " ran.out))
        (fold (fn [(acc Bool) (i Int64)] -> Bool
                (do (assert (= (optionOr (listGet lines i) "") (optionOr (listGet (expectedLines) i) "")) (str "handle line " (+ i 1) ": got " (optionOr (listGet lines i) "") ", want " (optionOr (listGet (expectedLines) i) "")))
                    acc))
              true (range 0 (listLength (expectedLines))))
        (assert (!= errnoTrap.exit 0) (str "a plain foreign fn traps when !neg fails: exit " errnoTrap.exit))
        (assert (stringContains? errnoTrap.out "ERR_FOREIGN_ERRNO: ffiHandles.closeFdPlain (C close) failed: Bad file descriptor") (str "the plain errno trap carries its code and strerror: " errnoTrap.out))
        (assert (!= closedTrap.exit 0) (str "a plain foreign fn traps on a closed Handle: exit " closedTrap.exit))
        (assert (stringContains? closedTrap.out "ERR_FOREIGN_CLOSED: ffiHandles.writePlain (C fputs) argument 2 is a closed Handle") (str "the plain closed trap carries its code: " closedTrap.out))
        (assert (not (stringContains? (str errnoTrap.out closedTrap.out) "unknown error code")) "the handle trap codes are known to the runtime")
        (assert (= swept.exit 0) (str "dropping a leaked and a closed Handle does not crash: exit " swept.exit " " swept.out))
        (assert (= (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) (stringLines swept.out)) (list "leaked true closed true" "churned 64" "finaliser flushed by fclose")) (str "the leaked Handle's last reference ran fclose, flushing its buffer, and the closed one ran nothing: " swept.out))
        true))

fn depSource -> String
  (stringJoin (list
    "(module ffiApp/ffiDep/crcs :x [crcOf] :i [])"
    ""
    "fn ! crc seed: Int64 data: Bytes -> Int64"
    "  (foreign \"z\" \"crc32\" \"u64 bytes32 -> u64\")"
    ""
    "fn ! crcOf text: String -> Int64"
    "  (crc 0 (stringToBytes text))"
    "") "\n")

fn ! testTransitive root: String work: String -> Bool
  (let [(dir (str work "/ffiApp"))
        (dep (str dir "/ffiDep"))
        (made (and (ok? (dirCreate dir)) (ok? (dirCreate dep))))
        (wrote (and (and (ok? (fileWrite (str dir "/.asl.config.asn") "(:asl-config :workspace \"ffiApp\" :root true)\n"))
                         (ok? (fileWrite (str dir "/manifest.asn") "(:package ffiApp :version \"0.1.0\" :entry \"main.asl\")\n")))
                    (and (ok? (fileWrite (str dir "/main.asl") "(module ffiApp/main :x [main] :i [(ffiApp/ffiDep/crcs :a d)])\n\nfn ! main args: (List String) -> (Result Int64 String)\n  (do (println (str \"crc32 \" (d/crcOf \"hello\"))) (ok (listLength args)))\n"))
                         (and (ok? (fileWrite (str dep "/manifest.asn") "(:package ffiDep :version \"0.1.0\" :entry \"crcs.asl\" :linkLibraries [\"z\"])\n"))
                              (ok? (fileWrite (str dep "/crcs.asl") (depSource)))))))
        (exe (str dir "/app"))
        (built (build root dir exe))
        (ran (if (= built.exit 0) (runIn (list exe) dir 60) built))]
    (do (assert (and made wrote) (str "the two-package fixture was written under " dir))
        (assert (= built.exit 0) (str "bin/asl build links -lz named only by the imported package's manifest: exit " built.exit " " built.out))
        (assert (= ran.exit 0) (str "the two-package fixture runs: exit " ran.exit " " ran.out))
        (assert (= (stringTrim ran.out) "crc32 907060870") (str "the imported package's crc32 is libz's: " ran.out))
        true))

fn churnSource -> String
  (stringJoin (list
    "(module ffiChurn :x [main] :i [])"
    ""
    "fn ! openFile path: String mode: String -> (Result Handle String)"
    "  (foreign \"c\" \"fopen\" \"cstr cstr -> handle:fclose !null\")"
    ""
    "fn ! writePlain s: String f: Handle -> Int64"
    "  (foreign \"c\" \"fputs\" \"cstr handle:fclose -> i32 !neg\")"
    ""
    "fn ! opened path: String k: Int64 -> Int64"
    "  (fold (fn [(acc Int64) (i Int64)] -> Int64 (match (openFile path \"w\") ((ok h) (do (writePlain \"x\" h) (+ acc 1))) ((err _) acc))) 0 (range 0 k))"
    ""
    "fn ! main args: (List String) -> (Result Int64 String)"
    "  (do (println (str \"files \" (opened (str (optionOr (listHead args) \".\") \"/churn.txt\") 2000)))"
    "      (ok 0))"
    "") "\n")

; (:m :ref FFI2 :do "a Handle whose count reaches zero runs its finaliser at once in every RC mode: 2000 fopen results dropped without fclose stay under a 64-descriptor limit only if each drop closes its FILE")
fn ! churnIn root: String work: String mode: String -> Bool
  (let [(dir (str work "/churn-" mode))
        (made (dirCreate dir))
        (wrote (and (ok? (fileWrite (str dir "/manifest.asn") "(:package ffiChurn :version \"0.1.0\" :entry \"main.asl\")\n"))
                    (and (ok? (fileWrite (str dir "/.asl.config.asn") (str "(:asl-config :native (:rc :" mode "))\n")))
                         (ok? (fileWrite (str dir "/main.asl") (churnSource))))))
        (exe (str dir "/churn"))
        (built (build root dir exe))
        (ran (if (= built.exit 0) (runIn (list "/bin/sh" "-c" "ulimit -n 64 && exec \"$0\" \"$1\" 2>&1" exe dir) dir 120) built))]
    (do (assert (and (ok? made) wrote) (str "the " mode " churn fixture was written under " dir))
        (assert (= built.exit 0) (str "bin/asl build links the " mode " churn fixture: exit " built.exit " " built.out))
        (assert (= ran.exit 0) (str "the " mode " churn fixture runs: exit " ran.exit " " ran.out))
        (assert (= (stringTrim ran.out) "files 2000") (str "under :rc :" mode " every dropped FILE is closed by its finaliser, 2000 of 2000 opens under ulimit -n 64: " ran.out))
        true))

fn ! testRcModes root: String work: String -> Bool
  (fold (fn [(acc Bool) (mode String)] -> Bool (and (churnIn root work mode) acc)) true (list "counted" "asan" "notrace"))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/foreignHandleTest." (stringFromInt64 (procSelf))))
        (_ (dirCreate (str root "/.asl/cache")))
        (made (dirCreate work))
        (routedOk (testRoute))
        (conventions (testConventions))
        (handles (if (ok? made) (testHandles root work) false))
        (transitive (if (ok? made) (testTransitive root work) false))
        (modes (if (ok? made) (testRcModes root work) false))
        (cleaned (run/runOneLimited (run/job (list "/bin/rm" "-rf" work) root (run/childEnv (list))) (run/limits 60 4)))]
    (do (assert routedOk "ffiRoute declares the handle and errno externs")
        (assert handles "the native handle fixture prints the C results")
        (assert transitive "an imported package's :linkLibraries reach the link")
        (assert conventions "foreign wrappers call the ffi helpers with their own calling convention")
        (assert modes "every RC mode finalises a dropped Handle at once")
        (assert (= cleaned.exit 0) "the work directory was removed")
        true))
