(module asl-ir/tests/lowerTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-ir/printer :a prn)
      (asl-ir/link :a lk)])

fn joinLines xs: (List String) -> String
  (stringJoin xs "\n")

fn codes diags: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.code) diags)

fn loci diags: (List ty/IrDiag) -> (List String)
  (map (fn [(d ty/IrDiag)] -> String d.locus) diags)

fn printed res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (mt res ((ok m) (prn/printSsa m)) ((err ds) (str "lowering failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message " " d.locus)) ds) "; "))))

fn verified? res: (Result ty/SsaModule (List ty/IrDiag)) -> Bool
  (mt res ((ok m) (ok? (vfy/verifySsa m))) ((err _) false))

fn diagsOf res: (Result ty/SsaModule (List ty/IrDiag)) -> (List ty/IrDiag)
  (mt res ((ok _) (list)) ((err ds) ds))

fn fibSource -> String
  (joinLines (list
    "(module demo/fib :x [fib])"
    ""
    "(fn fib [(n Int64)] -> Int64"
    "  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))"))

fn fibGolden -> String
  (joinLines (list
    "(ssa-module \"demo/fib\""
    "  (strings)"
    "  (fn fib (captures) (params (n i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 2))"
    "      (let %1 i1 (prim ltInt n %0))"
    "      (branch %1 (then0) (else0)))"
    "    (block then0 ()"
    "      (jump (join0 n)))"
    "    (block else0 ()"
    "      (let %2 i64 (const int 1))"
    "      (let %3 i64 (prim subIntHost n %2))"
    "      (let %4 i64 (call fib %3))"
    "      (let %5 i64 (const int 2))"
    "      (let %6 i64 (prim subIntHost n %5))"
    "      (let %7 i64 (call fib %6))"
    "      (let %8 i64 (prim addIntHost %4 %7))"
    "      (jump (join0 %8)))"
    "    (block join0 ((%9 i64))"
    "      (return %9))))"))

fn classifySource -> String
  (joinLines (list
    "(module demo/classify :x [classify])"
    ""
    "(fn classify [(x Int64)] -> Int64"
    "  (let [(a (* x 2)) (b (+ a 1))]"
    "    (do"
    "      (println b)"
    "      (cond"
    "        ((< b 0) -1)"
    "        ((= b 1) 0)"
    "        (else a)))))"))

fn classifyGolden -> String
  (joinLines (list
    "(ssa-module \"demo/classify\""
    "  (strings)"
    "  (fn classify (captures) (params (x i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 2))"
    "      (let %1 i64 (prim mulIntHost x %0))"
    "      (let %2 i64 (const int 1))"
    "      (let %3 i64 (prim addIntHost %1 %2))"
    "      (let %4 val (box %3))"
    "      (let %5 val (builtin \"println\" %4))"
    "      (let %6 i64 (const int 0))"
    "      (let %7 i1 (prim ltInt %3 %6))"
    "      (branch %7 (case0.0) (next0.0)))"
    "    (block case0.0 ()"
    "      (let %8 i64 (const int -1))"
    "      (jump (join0 %8)))"
    "    (block next0.0 ()"
    "      (let %9 i64 (const int 1))"
    "      (let %10 i1 (prim eqInt %3 %9))"
    "      (branch %10 (case0.1) (next0.1)))"
    "    (block case0.1 ()"
    "      (let %11 i64 (const int 0))"
    "      (jump (join0 %11)))"
    "    (block next0.1 ()"
    "      (jump (join0 %1)))"
    "    (block join0 ((%12 i64))"
    "      (return %12))))"))

fn stringSource -> String
  (joinLines (list
    "(module demo/strings :x [greet shout tags])"
    ""
    "(fn greet [(name String)] -> String"
    "  (str \"hello, \" name \"\\n\"))"
    ""
    "(fn shout [] -> String"
    "  (stringConcat (greet \"bob\") \"hello, \"))"
    ""
    "(fn tags [] -> Unit"
    "  (do (println :ready 2.5 false) ()))"))

fn stringGolden -> String
  (joinLines (list
    "(ssa-module \"demo/strings\""
    "  (strings \"hello, \" \"\\n\" \"bob\")"
    "  (fn greet (captures) (params (name val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (const str 0))"
    "      (let %1 val (const str 1))"
    "      (let %2 val (builtin \"str\" %0 name %1))"
    "      (return %2)))"
    "  (fn shout (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let %0 val (const str 2))"
    "      (let %1 val (call greet %0))"
    "      (let %2 val (const str 0))"
    "      (let %3 val (entry \"stringConcat\" %1 %2))"
    "      (return %3)))"
    "  (fn tags (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let %0 val (const keyword ready))"
    "      (let %1 f64 (const float 2.5))"
    "      (let %2 i1 (const bool false))"
    "      (let %3 val (box %1))"
    "      (let %4 val (box %2))"
    "      (let %5 val (builtin \"println\" %0 %3 %4))"
    "      (let %6 val (const unit))"
    "      (return %6))))"))

fn ! testFib -> Bool
  (let [(res (lk/lowerSourceLinked! (fibSource)))
        (text (printed res))]
    (do (assert (ok? res) "fib lowers")
        (assert (verified? res) "lowered fib passes verifySsa")
        (assert (= text (fibGolden)) "lowered fib prints the golden: Int64 annotations give a raw i64 signature, < - + are raw prims, recursion as direct calls, if as branch and a raw join block")
        true))

fn ! testLetDoCond -> Bool
  (let [(res (lk/lowerSourceLinked! (classifySource)))
        (text (printed res))]
    (do (assert (ok? res) "let/do/cond lowers")
        (assert (verified? res) "lowered let/do/cond passes verifySsa")
        (assert (= text (classifyGolden)) "let binds sequentially, do keeps effects in order, cond chains branches into one join")
        true))

fn ! testStrings -> Bool
  (let [(res (lk/lowerSourceLinked! (stringSource)))
        (text (printed res))]
    (do (assert (ok? res) "string, keyword, float, bool and unit literals lower")
        (assert (verified? res) "lowered string module passes verifySsa")
        (assert (= text (stringGolden)) "string literals are unescaped and interned once in the module pool")
        true))

fn badSource -> String
  (joinLines (list
    "(module demo/bad :x [pick])"
    ""
    "(fn fine [] -> Int64 1)"
    ""
    "(fn pick [(o Int64)] -> Int64"
    "  (return o))"))

fn worseSource -> String
  (joinLines (list
    "(module demo/worse :x [a])"
    "(fn a [] -> Int64 y)"
    "(fn b [(x Int64)] -> Int64 (cond ((< x 0) 1) (else 2) ((> x 0) 3)))"
    "(fn c [] -> Int64 (b 1 2))"
    "(fn d [] -> Int64 (net/fetch 1))"
    "(fn e [] -> Int64 (loop 1))"))

fn ! testUnsupported -> Bool
  (let [(bad (lk/lowerSourceLinked! (badSource)))
        (badDiags (diagsOf bad))
        (firstDiag (optionOr (listHead badDiags) (ty/makeIrDiag "" "" "")))
        (worse (lk/lowerSourceLinked! (worseSource)))
        (worseDiags (diagsOf worse))]
    (do (assert (err? bad) "a module with a return form does not lower")
        (assert (= (codes badDiags) (list "ERR_LOWER_UNSUPPORTED")) "exactly one diagnostic, for the return form; the supported function adds none")
        (assert (stringContains? firstDiag.message "'return' is outside the lowered subset") "the diagnostic names the construct")
        (assert (= firstDiag.locus "pick@5:1") "the locus is the function and its declaration line:col")
        (assert (err? worse) "a module with several unsupported constructs does not lower")
        (assert (= (codes worseDiags) (list "ERR_LOWER_UNKNOWN_SYMBOL" "ERR_LOWER_UNSUPPORTED" "ERR_LOWER_ARITY" "ERR_LOWER_UNSUPPORTED" "ERR_LOWER_UNSUPPORTED")) "every failing declaration reports, none is skipped")
        (assert (= (loci worseDiags) (list "a@2:1" "b@3:1" "c@4:1" "d@5:1" "e@6:1")) "each diagnostic carries its declaration position")
        true))

fn ! testHostVerbGone -> Bool
  (let [(bare (lk/lowerSourceLinked! (joinLines (list "(module demo/bareVerb :x [f])" "(fn f [] -> Int64 (hostVerb (list \"test\")))"))))
        (bareDiag (optionOr (listHead (diagsOf bare)) (ty/makeIrDiag "" "" "")))
        (imported (lk/lowerSourceLinked! (joinLines (list "(module demo/sysVerb :x [f] :i [(sys :a system)])" "(fn f [] -> Int64 (system/hostVerb (list \"test\")))"))))
        (importedDiag (optionOr (listHead (diagsOf imported)) (ty/makeIrDiag "" "" "")))]
    (do (assert (err? bare) "a bare hostVerb does not lower")
        (assert (stringContains? bareDiag.message "'hostVerb' is neither a module function nor a builtin") (str "the bare hostVerb diagnostic names the call: " bareDiag.message))
        (assert (err? imported) (str "hostVerb through a sys import alias does not lower: " (printed imported)))
        (assert (stringContains? importedDiag.message "system/hostVerb") (str "the sys alias diagnostic names the call: " importedDiag.message))
        true))

fn assertSource -> String
  (joinLines (list
    "(module demo/checks :x [check])"
    ""
    "(fn check [(n Int64)] -> Bool"
    "  (do (assert (> n 0))"
    "      (refute (< n 0) \"negative\")"
    "      true))"
    ""
    "(fn tooMany [(n Int64)] -> Bool (assert true \"a\" \"b\"))"))

fn assertGolden -> String
  (joinLines (list
    "(ssa-module \"demo/checks\""
    "  (strings \"negative\")"
    "  (fn check (captures) (params (n i64)) (returns i1)"
    "    (block entry ()"
    "      (let %0 i64 (const int 0))"
    "      (let %1 i1 (prim gtInt n %0))"
    "      (let %2 val (box %1))"
    "      (let %3 val (builtin \"assert\" %2))"
    "      (let %4 i64 (const int 0))"
    "      (let %5 i1 (prim ltInt n %4))"
    "      (let %6 val (const str 0))"
    "      (let %7 val (box %5))"
    "      (let %8 val (builtin \"refute\" %7 %6))"
    "      (let %9 i1 (const bool true))"
    "      (return %9))))"))

fn fallSource -> String
  (joinLines (list
    "(module demo/fall :x [pick first])"
    ""
    "(fn pick [(n Int64)] -> Int64"
    "  (cond ((= n 1) 10) ((= n 2) 20)))"
    ""
    "(fn first [(o (Option Int64))] -> Int64"
    "  (mt o (_ 1) ((some x) x) ((none) 0)))"))

fn fallGolden -> String
  (joinLines (list
    "(ssa-module \"demo/fall\""
    "  (strings)"
    "  (fn pick (captures) (params (n i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i1 (prim eqInt n %0))"
    "      (branch %1 (case0.0) (next0.0)))"
    "    (block case0.0 ()"
    "      (let %2 i64 (const int 10))"
    "      (let %7 val (box %2))"
    "      (jump (join0 %7)))"
    "    (block next0.0 ()"
    "      (let %3 i64 (const int 2))"
    "      (let %4 i1 (prim eqInt n %3))"
    "      (branch %4 (case0.1) (next0.1)))"
    "    (block case0.1 ()"
    "      (let %5 i64 (const int 20))"
    "      (let %8 val (box %5))"
    "      (jump (join0 %8)))"
    "    (block next0.1 ()"
    "      (let %6 val (const unit))"
    "      (jump (join0 %6)))"
    "    (block join0 ((%9 val))"
    "      (let %10 i64 (unbox %9))"
    "      (return %10)))"
    "  (fn first (captures) (params (o val)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (jump (join0 %0)))"
    "    (block join0 ((%1 i64))"
    "      (return %1))))"))

fn ! testFallThrough -> Bool
  (let [(res (lk/lowerSourceLinked! (fallSource)))]
    (do (assert (verified? res) (str "a cond with no else and a match with arms after its catch-all lower and verify: " (printed res)))
        (assert (= (printed res) (fallGolden)) (str "as in the host, a cond no clause of which holds gives unit and the arms after a catch-all are unreachable: " (printed res)))
        true))

fn ! testAssert -> Bool
  (let [(res (lk/lowerSourceLinked! (assertSource)))
        (ok (lk/lowerSourceLinked! (stringReplace (assertSource) "(fn tooMany [(n Int64)] -> Bool (assert true \"a\" \"b\"))" "")))]
    (do (assert (= (codes (diagsOf res)) (list "ERR_LOWER_ARITY")) (str "assert with three operands is an arity diagnostic: " (printed res)))
        (assert (verified? ok) (str "assert and refute lower and verify: " (printed ok)))
        (assert (= (printed ok) (assertGolden)) (str "assert and refute are builtin calls with one or two operands, as the host's special forms take: " (printed ok)))
        true))

fn hostBuiltinSource -> String
  (joinLines (list
    "(module demo/arrays :x [lineCount network])"
    ""
    "(fn lineCount [(xs I64Array) (key String)] -> Int64"
    "  (+ (i64ArrayLen (i64ArrayConcat (list xs (i64ArrayGenerate 2 (fn [(i Int64)] -> Int64 i)))))"
    "     (+ (i64ArrayGet xs 0) (mt (envGet key) ((some _) 1) ((none) 0)))))"
    "(fn network [(port Int64) (path String)] -> (Result Int64 String)"
    "  (do (tcpListen port) (tcpConnect port) (sockAccept port) (sockLocalPort port) (unixListen path) (unixConnect path)))"))

fn ! testHostBuiltins -> Bool
  (let [(res (lk/lowerSourceLinked! (hostBuiltinSource)))
        (text (printed res))]
    (do (assert (verified? res) (str "the host array and environment builtins lower and verify: " text))
        (map (fn [(b String)] -> Bool (do (assert (stringContains? text (str "(builtin \"" b "\"")) (str b " lowers to a builtin call")) true))
             (list "i64ArrayLen" "i64ArrayConcat" "i64ArrayGenerate" "i64ArrayGet" "envGet" "tcpListen" "tcpConnect" "sockAccept" "sockLocalPort" "unixListen" "unixConnect"))
        true))

fn arityBuiltinSource -> String
  (joinLines (list
    "(module demo/arityBuiltins :x [mapTwo foldFour files processes asValue sysInfo sysMisc shifts])"
    ""
    "(fn mapTwo [(xs (List Int64))] -> (List Int64)"
    "  (parMap (fn [(x Int64)] -> Int64 x) xs))"
    ""
    "(fn foldFour [(xs (List Int64))] -> Int64"
    "  (parFold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) (fn [(a Int64) (b Int64)] -> Int64 (+ a b)) 0 xs))"
    ""
    "(fn files [(path String) (other String) (n Int64)] -> Bool"
    "  (do (fileReadRange path 0 n) (getHomeDir) (fileCreateExclusive path other) (fileChmod path n) (fileFsync path) (fileLstat path) (pathSymlink path other) (fileUtime path n) true))"
    ""
    "(fn processes [(cmd String) (handle Int64) (timeoutMs Int64)] -> Bool"
    "  (do (processSpawn cmd) (processWait handle timeoutMs) true))"
    ""
    "(fn asValue [(cmds (List String))] -> (List (Result Int64 String))"
    "  (map processSpawn cmds))"
    ""
    "(fn sysInfo [(pid Int64)] -> Bool"
    "  (do (cpuCount) (platformInfo) (localDate) (procAlive? pid) (procRusage) true))"
    ""
    "(fn sysMisc [(fd Int64) (ms Int64) (root String) (rel String) (data String) (pids (List Int64))] -> Bool"
    "  (do (fdPoll (list) ms) (fdNonBlocking fd true) (fileLockAt root rel true) (fileReadAt root rel) (fileWriteAt root rel data) (procWaitAny pids ms) true))"
    ""
    "(fn shifts [(n Int64) (k Int64)] -> Int64"
    "  (+ (<< n k) (>> n k)))"))

fn ! testArityBuiltins -> Bool
  (let [(res (lk/lowerSourceLinked! (arityBuiltinSource)))
        (text (printed res))
        (mapWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(parMap (fn [(x Int64)] -> Int64 x) xs)" "(parMap (fn [(x Int64)] -> Int64 x) xs xs xs)")))
        (foldWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(fn [(a Int64) (b Int64)] -> Int64 (+ a b)) 0 xs)" "(fn [(a Int64) (b Int64)] -> Int64 (+ a b)))")))
        (spawnWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(processSpawn cmd)" "(processSpawn cmd cmd)")))
        (waitWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(processWait handle timeoutMs)" "(processWait handle)")))
        (pollWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(fdPoll (list) ms)" "(fdPoll (list) ms ms)")))
        (aliveWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(procAlive? pid)" "(procAlive? pid pid)")))
        (waitAnyWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(procWaitAny pids ms)" "(procWaitAny pids)")))
        (shlWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(<< n k)" "(<< n)")))
        (shrWrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) "(>> n k)" "(>> n k k)")))]
    (do (assert (verified? res) (str "parMap/2, parFold/4, the eight prelude.c file builtins, processSpawn/1, processWait/2, the eleven sys.c builtins and <</>>/2 lower and verify: " text))
        (map (fn [(b String)] -> Bool (do (assert (stringContains? text (str "(builtin \"" b "\"")) (str b " lowers to a builtin call")) true))
             (list "parMap" "parFold" "fileReadRange" "getHomeDir" "fileCreateExclusive" "fileChmod" "fileFsync" "fileLstat" "pathSymlink" "fileUtime" "processSpawn" "processWait"
                   "cpuCount" "platformInfo" "localDate" "procAlive?" "procRusage" "fdPoll" "fdNonBlocking" "fileLockAt" "fileReadAt" "fileWriteAt" "procWaitAny"))
        (assert (stringContains? text "(prim rawShlI64 n k)") (str "<< over raw Int64 operands lowers inline to rawShlI64, not a builtin call (NATIVE-INTRINSICS): " text))
        (assert (stringContains? text "(prim rawAshrI64 n k)") (str ">> over raw Int64 operands lowers inline to rawAshrI64, not a builtin call (NATIVE-INTRINSICS): " text))
        (assert (= (codes (diagsOf shlWrong)) (list "ERR_LOWER_ARITY")) (str "<< with 1 argument is an arity error: " (printed shlWrong)))
        (assert (= (codes (diagsOf shrWrong)) (list "ERR_LOWER_ARITY")) (str ">> with 3 arguments is an arity error: " (printed shrWrong)))
        (assert (= (codes (diagsOf mapWrong)) (list "ERR_LOWER_ARITY")) (str "parMap with 4 arguments is still an arity error: " (printed mapWrong)))
        (assert (= (codes (diagsOf foldWrong)) (list "ERR_LOWER_ARITY")) (str "parFold with 2 arguments is still an arity error: " (printed foldWrong)))
        (assert (= (codes (diagsOf spawnWrong)) (list "ERR_LOWER_ARITY")) (str "processSpawn with 2 arguments is an arity error: " (printed spawnWrong)))
        (assert (= (codes (diagsOf waitWrong)) (list "ERR_LOWER_ARITY")) (str "processWait with 1 argument is an arity error: " (printed waitWrong)))
        (assert (= (codes (diagsOf pollWrong)) (list "ERR_LOWER_ARITY")) (str "fdPoll with 3 arguments is an arity error: " (printed pollWrong)))
        (assert (= (codes (diagsOf aliveWrong)) (list "ERR_LOWER_ARITY")) (str "procAlive? with 2 arguments is an arity error: " (printed aliveWrong)))
        (assert (= (codes (diagsOf waitAnyWrong)) (list "ERR_LOWER_ARITY")) (str "procWaitAny with 1 argument is an arity error: " (printed waitAnyWrong)))
        (map (fn [(m (List String))] -> Bool
               (let [(wrong (lk/lowerSourceLinked! (stringReplace (arityBuiltinSource) (optionOr (listGet m 0) "") (optionOr (listGet m 1) ""))))]
                 (do (assert (= (codes (diagsOf wrong)) (list "ERR_LOWER_ARITY")) (str (optionOr (listGet m 1) "") " is an arity error: " (printed wrong))) true)))
             (list (list "(cpuCount)" "(cpuCount pid)") (list "(platformInfo)" "(platformInfo pid)") (list "(localDate)" "(localDate pid)")
                   (list "(procRusage)" "(procRusage pid)") (list "(fdNonBlocking fd true)" "(fdNonBlocking fd)")
                   (list "(fileLockAt root rel true)" "(fileLockAt root rel)") (list "(fileReadAt root rel)" "(fileReadAt root rel rel)")
                   (list "(fileWriteAt root rel data)" "(fileWriteAt root rel data data)")))
        true))

fn typedSource -> String
  (joinLines (list
    "(module demo/typed :x [mixed bump twice head rest known eqVal neg fdiv])"
    ""
    "(fn mixed [(n Int64) (s String)] -> String"
    "  (if (> n 0) s (str n)))"
    ""
    "(fn bump [(n Int64)] -> Int64"
    "  (+ n 1))"
    ""
    "(fn twice [(xs (List Int64))] -> (List Int64)"
    "  (map bump xs))"
    ""
    "(fn head [(xs (List String))] -> String"
    "  (mt (listHead xs) ((some x) x) ((none) \"\")))"
    ""
    "(fn rest [(xs (List String))] -> (List String)"
    "  (mt (listTail xs) ((some t) t)))"
    ""
    "(fn known [(n Int64) (o (Option Int64))] -> Bool"
    "  (mt o ((some v) (< n v)) ((none) false)))"
    ""
    "(fn eqVal [(n Int64) (o (Option Int64))] -> Bool"
    "  (mt o ((some v) (= v n)) ((none) false)))"
    ""
    "(fn neg [(n Int64) (x Float64)] -> Float64"
    "  (if (< (- n) 0) (- x) x))"
    ""
    "(fn fdiv [(xs (List Int64))] -> (List Int64)"
    "  (map (fn [(k Int64)] -> Int64 (* k 2)) xs))"))

fn typedGolden -> String
  (joinLines (list
    "(ssa-module \"demo/typed\""
    "  (strings \"\")"
    "  (type Option (some 1) (none 0))"
    "  (fn mixed (captures) (params (n i64) (s val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 0))"
    "      (let %1 i1 (prim gtInt n %0))"
    "      (branch %1 (then0) (else0)))"
    "    (block then0 ()"
    "      (jump (join0 s)))"
    "    (block else0 ()"
    "      (let %2 val (box n))"
    "      (let %3 val (builtin \"str\" %2))"
    "      (jump (join0 %3)))"
    "    (block join0 ((%4 val))"
    "      (return %4)))"
    "  (fn bump (captures) (params (n i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 i64 (prim addIntHost n %0))"
    "      (return %1)))"
    "  (fn twice (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (make-closure twice@lambda0))"
    "      (let %1 val (call prelude.map %0 xs))"
    "      (return %1)))"
    "  (fn twice@lambda0 (captures) (params (@0 val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox @0))"
    "      (let %1 i64 (call bump %0))"
    "      (let %2 val (box %1))"
    "      (return %2)))"
    "  (fn head (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (jump (join0 %1)))"
    "    (block arm0.1 ()"
    "      (let %2 val (const str 0))"
    "      (jump (join0 %2)))"
    "    (block join0 ((%3 val))"
    "      (return %3)))"
    "  (fn rest (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (nomatch0) (arm0.0)))"
    "    (block nomatch0 ()"
    "      (unreachable))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listRest\" xs))"
    "      (jump (join0 %1)))"
    "    (block join0 ((%2 val))"
    "      (return %2)))"
    "  (fn known (captures) (params (n i64) (o val)) (returns i1)"
    "    (block entry ()"
    "      (switch o Option (some (arm0.0)) (none (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field o 0))"
    "      (let %1 i64 (unbox %0))"
    "      (let %2 i1 (prim ltInt n %1))"
    "      (jump (join0 %2)))"
    "    (block arm0.1 ()"
    "      (let %3 i1 (const bool false))"
    "      (jump (join0 %3)))"
    "    (block join0 ((%4 i1))"
    "      (return %4)))"
    "  (fn eqVal (captures) (params (n i64) (o val)) (returns i1)"
    "    (block entry ()"
    "      (switch o Option (some (arm0.0)) (none (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field o 0))"
    "      (let %1 val (box n))"
    "      (let %2 i1 (entry \"=\" %0 %1))"
    "      (jump (join0 %2)))"
    "    (block arm0.1 ()"
    "      (let %3 i1 (const bool false))"
    "      (jump (join0 %3)))"
    "    (block join0 ((%4 i1))"
    "      (return %4)))"
    "  (fn neg (captures) (params (n i64) (x f64)) (returns f64)"
    "    (block entry ()"
    "      (let %0 i64 (prim negIntHost n))"
    "      (let %1 i64 (const int 0))"
    "      (let %2 i1 (prim ltInt %0 %1))"
    "      (branch %2 (then0) (else0)))"
    "    (block then0 ()"
    "      (let %3 f64 (prim negFloat x))"
    "      (jump (join0 %3)))"
    "    (block else0 ()"
    "      (jump (join0 x)))"
    "    (block join0 ((%4 f64))"
    "      (return %4)))"
    "  (fn fdiv (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (make-closure fdiv@lambda0))"
    "      (let %1 val (call prelude.map %0 xs))"
    "      (return %1)))"
    "  (fn fdiv@lambda0 (captures) (params (k val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox k))"
    "      (let %1 i64 (const int 2))"
    "      (let %2 i64 (prim mulIntHost %0 %1))"
    "      (let %3 val (box %2))"
    "      (return %3)))"
    "  (fn prelude.map (captures) (params (f val) (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeMapOnto f xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeMapOnto (captures) (params (f val) (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (call-closure f %1))"
    "      (let %5 val (entry \"cons\" %4 acc))"
    "      (let %6 val (call prelude.preludeMapOnto f %3 %5))"
    "      (jump (join1 %6)))"
    "    (block join1 ((%7 val))"
    "      (jump (join0 %7)))"
    "    (block arm0.1 ()"
    "      (let %8 val (call prelude.listReverse acc))"
    "      (jump (join0 %8)))"
    "    (block join0 ((%9 val))"
    "      (return %9)))"
    "  (fn prelude.listReverse (captures) (params (xs val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (list))"
    "      (let %1 val (call prelude.preludeReverseOnto xs %0))"
    "      (return %1)))"
    "  (fn prelude.preludeReverseOnto (captures) (params (xs val) (acc val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i1 (entry \"listEmpty?\" xs))"
    "      (branch %0 (arm0.1) (arm0.0)))"
    "    (block arm0.0 ()"
    "      (let %1 val (entry \"@listFirst\" xs))"
    "      (let %2 i1 (entry \"listEmpty?\" xs))"
    "      (branch %2 (nomatch1) (arm1.0)))"
    "    (block nomatch1 ()"
    "      (unreachable))"
    "    (block arm1.0 ()"
    "      (let %3 val (entry \"@listRest\" xs))"
    "      (let %4 val (entry \"cons\" %1 acc))"
    "      (let %5 val (call prelude.preludeReverseOnto %3 %4))"
    "      (jump (join1 %5)))"
    "    (block join1 ((%6 val))"
    "      (jump (join0 %6)))"
    "    (block arm0.1 ()"
    "      (jump (join0 acc)))"
    "    (block join0 ((%7 val))"
    "      (return %7))))"))

fn ! testTyped -> Bool
  (let [(res (lk/lowerSourceLinked! (typedSource)))]
    (do (assert (verified? res) (str "typed lowering verifies: " (printed res)))
        (assert (= (printed res) (typedGolden)) (str "Int64, Float64 and Bool annotations give raw signatures; arithmetic and comparison on raw operands are prims, a Val operand of an Int comparison is unboxed, = with a Val operand boxes the raw one for the = entry; a join of raw and Val arms is Val with the raw arm boxed in its block; a raw-signature function as a value is a Val wrapper; a lambda unboxes its annotated parameter; a match on listHead or listTail tests listEmpty? and reads the payload through @listFirst or @listRest, trapping when a variant has no arm: " (printed res)))
        true))

fn ! testPreludeNameClash -> Bool
  (let [(res (lk/lowerSourceLinked! (joinLines (list "(module demo/clash :x [f])"
                                                     "(fn prelude.stringJoin [(xs (List String)) (sep String)] -> String \"mine\")"
                                                     "(fn f [] -> String (stringJoin (list \"a\" \"b\") \",\"))"))))
        (ds (diagsOf res))]
    (do (assert (err? res) (str "a module function named prelude.stringJoin does not link silently: " (printed res)))
        (assert (= (codes ds) (list "ERR_LOWER_PARSE")) (str "D158 reads prelude.stringJoin as field access, so it is not a function name: " (printed res)))
        (assert (listAny? (fn [(d ty/IrDiag)] -> Bool (stringContains? d.message "stringJoin")) ds) (str "the diagnostic names stringJoin: " (printed res)))
        true))

fn arrayFamilySource -> String
  (joinLines (list
    "(module demo/arrayFamily :x [floats ints bytes])"
    ""
    "(fn floats [(xs F64Array)] -> Int64"
    "  (+ (f64ArrayFold (fn [(n Int64) (x Float64)] -> Int64 (if (> x 0.0) (+ n 1) n)) 0 (f64ArrayConcat (list xs (f64ArraySlice xs 0 1))))"
    "     (+ (f64ArrayCountEq (f64ArrayScan (fn [(a Float64) (x Float64)] -> Float64 (+ a x)) 0.0 xs) (f64ArraySum xs)) (f64ArrayLen (f64ArrayGenerate 2 (fn [(i Int64)] -> Float64 (f64ArrayGet xs i)))))))"
    "(fn ints [(xs I64Array)] -> Int64"
    "  (+ (i64ArrayFold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 (i64ArraySlice xs 0 1))"
    "     (+ (i64ArrayCountEq (i64ArrayScan (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 xs) 1) (i64ArraySum xs))))"
    "(fn bytes [(xs I8Array)] -> Int64"
    "  (+ (i8ArrayFold (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 (i8ArraySlice (i8ArrayConcat (list xs xs)) 0 1))"
    "     (+ (i8ArrayCountEq (i8ArrayScan (fn [(a Int64) (x Int64)] -> Int64 (+ a x)) 0 xs) 1)"
    "        (+ (i8ArraySum xs) (+ (i8ArrayGet xs 0) (i8ArrayLen (i8ArrayGenerate 2 (fn [(i Int64)] -> Int64 i))))))))"))

fn ! testArrayFamilyBuiltins -> Bool
  (let [(res (lk/lowerSourceLinked! (arrayFamilySource)))
        (text (printed res))
        (wrongArity (lk/lowerSourceLinked! (stringReplace (arrayFamilySource) "(i8ArraySum xs)" "(i8ArraySum xs xs)")))]
    (do (assert (verified? res) (str "the f64, i64 and i8 array families lower and verify: " text))
        (map (fn [(b String)] -> Bool (do (assert (stringContains? text (str "(builtin \"" b "\"")) (str b " lowers to a builtin call")) true))
             (list "f64ArrayFold" "f64ArrayConcat" "f64ArraySlice" "f64ArrayCountEq" "f64ArrayScan" "f64ArraySum" "f64ArrayLen" "f64ArrayGenerate" "f64ArrayGet"
                   "i64ArrayFold" "i64ArraySlice" "i64ArrayCountEq" "i64ArrayScan" "i64ArraySum"
                   "i8ArrayFold" "i8ArraySlice" "i8ArrayConcat" "i8ArrayCountEq" "i8ArrayScan" "i8ArraySum" "i8ArrayGet" "i8ArrayLen" "i8ArrayGenerate"))
        (assert (= (codes (diagsOf wrongArity)) (list "ERR_LOWER_ARITY")) (str "i8ArraySum with two arguments is an arity error: " (printed wrongArity)))
        true))

fn ! runTests -> Bool
  (do (assert (testFib) "testFib")
      (assert (testAssert) "testAssert")
      (assert (testFallThrough) "testFallThrough")
      (assert (testLetDoCond) "testLetDoCond")
      (assert (testStrings) "testStrings")
      (assert (testUnsupported) "testUnsupported")
      (assert (testHostBuiltins) "testHostBuiltins")
      (assert (testArrayFamilyBuiltins) "testArrayFamilyBuiltins")
      (assert (testArityBuiltins) "testArityBuiltins")
      (assert (testHostVerbGone) "testHostVerbGone")
      (assert (testTyped) "testTyped")
      (assert (testPreludeNameClash) "testPreludeNameClash")
      true)
