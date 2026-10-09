(module asl-target-llvm/parallel
  :x [ParCtx parFactNames parFacts parStrings parExterns parGlobals parFunctions wrapperName serMax helperExterns]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/libc :a libc)])

schema ParCtx
  k: (Map String Int64)
  pool: (Map String Int64)
  errno: String

fn pn name: String -> String
  (str "asl-target-llvm/parallel." name)

fn wrapperName builtin: String argc: Int64 -> String
  (pn (str builtin "/" (stringFromInt64 argc)))

fn serMax -> Int64
  67108864

fn depthMax -> Int64
  10000

fn maxFields -> Int64
  4194304

fn jmpBufBytes -> Int64
  1024

fn bufBytes -> Int64
  48

fn tagInt -> Int64
  2

fn tagList -> Int64
  6

fn objRec -> Int64
  2

fn objArr -> Int64
  6

fn appendAll lists: (List (List V)) -> (List V)
  (fold (fn [(acc (List V)) (l (List V))] -> (List V) (listAppend acc l)) (list) lists)

fn i1 -> ty/SsaTy
  (ty/tyI1)

fn i64 -> ty/SsaTy
  (ty/tyI64)

fn i32 -> ty/SsaTy
  (ty/tyI32)

fn ptr -> ty/SsaTy
  (ty/tyPtr)

fn val -> ty/SsaTy
  (ty/tyVal)

fn ins d: String t: ty/SsaTy op: ty/SsaOp -> (List ty/SsaInstr)
  (list (ty/ssaInstr d t op))

fn k d: String n: Int64 -> (List ty/SsaInstr)
  (ins d (i64) (ty/opConst (ty/constInt n)))

fn k32 d: String n: Int64 -> (List ty/SsaInstr)
  (ins d (i32) (ty/opConst (ty/constInt n)))

fn pr d: String t: ty/SsaTy name: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opPrim name args))

fn ex d: String t: ty/SsaTy callee: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opCall callee args))

fn hp d: String t: ty/SsaTy helper: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opCall (pn helper) args))

fn en d: String t: ty/SsaTy name: String args: (List String) -> (List ty/SsaInstr)
  (ins d t (ty/opEntry name args))

fn vop d: String op: ty/SsaOp -> (List ty/SsaInstr)
  (ins d (val) op)

fn i2p d: String i: String -> (List ty/SsaInstr)
  (pr d (ptr) "rawIntToPtr" (list i))

fn p2i d: String p: String -> (List ty/SsaInstr)
  (pr d (i64) "rawPtrToInt" (list p))

fn add d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawAddI64" (list a b))

fn addK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (add d a (str d ".k"))))

fn sub d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawSubI64" (list a b))

fn mul d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i64) "rawMulI64" (list a b))

fn mulK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (mul d a (str d ".k"))))

fn cmp d: String name: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) name (list a b))

fn cmpK d: String name: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (cmp d name a (str d ".k"))))

fn orB d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) "orBool" (list a b))

fn andB d: String a: String b: String -> (List ty/SsaInstr)
  (pr d (i1) "andBool" (list a b))

fn notB d: String a: String -> (List ty/SsaInstr)
  (pr d (i1) "notBool" (list a))

fn bandK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (pr d (i64) "rawAndI64" (list a (str d ".k")))))

fn shrK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (pr d (i64) "rawLshrI64" (list a (str d ".k")))))

fn shlK d: String a: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".k") n) (pr d (i64) "rawShlI64" (list a (str d ".k")))))

fn n32 d: String v: String -> (List ty/SsaInstr)
  (pr d (i32) "rawNarrowI32" (list v))

fn w64 d: String v: String -> (List ty/SsaInstr)
  (pr d (i64) "rawWidenI32" (list v))

fn ld d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (pr d (i64) "rawLoadI64" (list (str d ".p") (str d ".o")))))

fn ldS32 d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (pr (str d ".w") (i32) "rawLoadI32" (list (str d ".p") (str d ".o"))) (w64 d (str d ".w"))))

fn ldU32 d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (ldS32 (str d ".s") addr off) (bandK d (str d ".s") 4294967295)))

fn ldU8 d: String addr: String off: Int64 -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (pr (str d ".w") (i32) "rawLoadI8" (list (str d ".p") (str d ".o"))) (w64 d (str d ".w"))))

fn st d: String addr: String off: Int64 v: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (pr d (i1) "rawStoreI64" (list (str d ".p") (str d ".o") v))))

fn st32 d: String addr: String off: Int64 v: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (n32 (str d ".n") v) (pr d (i1) "rawStoreI32" (list (str d ".p") (str d ".o") (str d ".n")))))

fn st8 d: String addr: String off: Int64 v: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".p") addr) (k (str d ".o") off) (n32 (str d ".n") v) (pr d (i1) "rawStoreI8" (list (str d ".p") (str d ".o") (str d ".n")))))

fn words d: String v: String -> (List ty/SsaInstr)
  (appendAll (list (ex (str d ".a") (ptr) "aslParWord0" (list v)) (p2i (str d ".w0") (str d ".a"))
                   (ex (str d ".b") (ptr) "aslParWord1" (list v)) (p2i (str d ".w1") (str d ".b"))))

fn tagOf d: String v: String -> (List ty/SsaInstr)
  (appendAll (list (ex (str d ".a") (ptr) "aslParWord0" (list v)) (p2i (str d ".x") (str d ".a")) (bandK d (str d ".x") 4294967295)))

fn payload d: String v: String -> (List ty/SsaInstr)
  (appendAll (list (ex (str d ".b") (ptr) "aslParWord1" (list v)) (p2i d (str d ".b"))))

fn mkv d: String w0: String w1: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str d ".a") w0) (i2p (str d ".b") w1) (ex d (val) "aslParMakeVal" (list (str d ".a") (str d ".b")))))

fn mkvK d: String w0: Int64 w1: String -> (List ty/SsaInstr)
  (appendAll (list (k (str d ".t") w0) (mkv d (str d ".t") w1)))

fn ldVal d: String addr: String -> (List ty/SsaInstr)
  (appendAll (list (ld (str d ".0") addr 0) (ld (str d ".1") addr 8) (mkv d (str d ".0") (str d ".1"))))

fn stVal d: String addr: String v: String -> (List ty/SsaInstr)
  (appendAll (list (words (str d ".v") v) (st (str d ".s0") addr 0 (str d ".v.w0")) (st d addr 8 (str d ".v.w1"))))

fn unitV d: String -> (List ty/SsaInstr)
  (vop d (ty/opConst (ty/constUnit)))

fn nilV d: String -> (List ty/SsaInstr)
  (vop d (ty/opList (list)))

fn poolAt c: ParCtx text: String -> Int64
  (optionOr (mapGet c.pool text) -1)

fn cs c: ParCtx d: String text: String -> (List ty/SsaInstr)
  (appendAll (list (vop (str d ".v") (ty/opConst (ty/constStr (poolAt c text)))) (k32 (str d ".r") 0)
                   (ex d (ptr) "valToCStr" (list (str d ".v") (str d ".r")))))

fn kf c: ParCtx name: String -> Int64
  (optionOr (mapGet c.k name) 0)

fn block label: String parts: (List (List ty/SsaInstr)) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) (appendAll parts) term)

fn paramBlock label: String params: (List ty/SsaParam) parts: (List (List ty/SsaInstr)) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label params (appendAll parts) term)

fn jump label: String args: (List String) -> ty/SsaTerm
  (ty/termJump (ty/ssaEdge label args))

fn branch c: String yes: String no: String -> ty/SsaTerm
  (ty/termBranch c (ty/ssaEdge yes (list)) (ty/ssaEdge no (list)))

fn argBranch c: String yes: String yesArgs: (List String) no: String noArgs: (List String) -> ty/SsaTerm
  (ty/termBranch c (ty/ssaEdge yes yesArgs) (ty/ssaEdge no noArgs))

fn returnTerm v: String -> ty/SsaTerm
  (ty/termReturn v)

fn pI name: String -> ty/SsaParam
  (ty/ssaParam name (i64))

fn pV name: String -> ty/SsaParam
  (ty/ssaParam name (val))

fn function name: String params: (List ty/SsaParam) retTy: ty/SsaTy blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction (pn name) (list) params retTy blocks)

fn chain prefix: String var: String cases: (List (Pair Int64 String)) dflt: String -> (List ty/SsaBlock)
  (let [(n (listLength cases))]
    (map (fn [(i Int64)] -> ty/SsaBlock
           (let [(c (optionOr (listGet cases i) (pair 0 dflt)))
                 (here (str prefix (stringFromInt64 i)))
                 (next (if (= i (- n 1)) dflt (str prefix (stringFromInt64 (+ i 1)))))]
             (block here (list (cmpK (str here ".eq") "eqInt" var (pairFirst c))) (branch (str here ".eq") (pairSecond c) next))))
         (range 0 n)))

fn raiseB c: ParCtx label: String pre: (List (List ty/SsaInstr)) code: String fmt: String args: (List String) -> ty/SsaBlock
  (block label (listAppend pre (list (cs c (str label ".code") code) (cs c (str label ".fmt") fmt)
                                 (ex (str label ".r") (i64) "aslError" (listAppend (list (str label ".code") (str label ".fmt")) args))))
    (ty/termUnreachable))

fn parFactNames -> (List String)
  (list "_SC_NPROCESSORS_ONLN" "SIGPIPE" "SIGINT" "SIGTERM" "SIGKILL" "SIG_DFL" "POLLIN" "POLLHUP" "POLLERR" "EINTR" "EAGAIN"
        "pollfd.size" "pollfd.fd" "pollfd.events" "pollfd.revents")

fn factOf facts: libc/TripleFacts name: String -> (Option Int64)
  (let [(dot (stringIndexOf name "."))]
    (mt dot
      ((none) (libc/libcConst facts name))
      ((some i)
        (let [(sname (optionOr (stringSlice name 0 i) ""))
              (field (optionOr (stringSlice name (+ i 1) (stringLength name)) ""))]
          (if (= field "size")
            (libc/structSize facts sname)
            (mt (libc/pairFind facts.structs sname)
              ((some sf) (libc/structFieldOffset sf field))
              ((none) (none))))))))

fn parFacts facts: libc/TripleFacts -> (Result (Map String Int64) String)
  (let [(resolved (fold (fn [(acc (Result (Map String Int64) String)) (n String)] -> (Result (Map String Int64) String)
                          (mt acc
                            ((err e) (err e))
                            ((ok m) (mt (factOf facts n)
                                      ((some v) (ok (mapSet m n v)))
                                      ((none) (err (str "libc.asl has no " n " for " facts.triple)))))))
                        (ok (mapEmpty)) (parFactNames)))]
    (mt resolved
      ((err e) (err e))
      ((ok m)
        (cond
          ((!= (optionOr (mapGet m "pollfd.revents") 0) (+ (optionOr (mapGet m "pollfd.events") 0) 2))
            (err (str "pollfd.revents does not follow pollfd.events by 2 bytes on " facts.triple)))
          ((stringEmpty? facts.errnoAccessor) (err (str "libc.asl names no errno accessor for " facts.triple)))
          (else (ok m))))))

fn parStrings -> (List String)
  (list "ERR_ARITY" "ERR_TYPE" "ERR_ARG" "ERR_OOM" "ERR_RANGE" "ERR_WORKER_TRAP" "ERR_SERIALIZE_SIZE" "ERR_NOT_SERIALIZABLE"
        "%s" "%s expects %s, got %s" "parMap" "parFold" "parFold slots"
        "parMap expects at least 2 arguments, got %lld" "parMap expects 2 or 3 arguments, got %lld" "parFold expects 4 or 5 arguments, got %lld"
        "parMap expects (parMap fn list [slots]) or (parMap slots fn list)"
        "parMap slots must be positive, got %lld" "parFold slots must be positive, got %lld"
        "parMap process tables" "parFold process tables" "parMap poll buffers" "parFold poll buffers" "parMap sequential state" "parallel key table"
        "parMap element %lld: %s" "parMap worker result exceeds serialization size limit" "parFold worker result exceeds serialization size limit"
        "cannot serialize parMap result across worker process" "cannot serialize parFold result across worker process"
        "worker %lld response exceeds serialization size limit" "worker %lld reported error" "worker trapped"
        "worker %lld killed by signal %lld" "worker %lld exited with code %lld"
        "worker %lld sent corrupted data" "deserialization error on worker %lld item %lld"
        "worker %lld sent corrupted fold data" "deserialization error on worker %lld fold accumulator"
        "%s of %lld elements exceeds the array allocation limit" "cannot allocate %s of %lld elements" "F64Array" "I64Array" "I8Array"
        "ASL_PAR_FORCE_FALLBACK" "1")

fn helperExterns -> (List ty/SsaExtern)
  (list (ty/ssaExternTyped "aslParWord0" (list (val)) (ptr)) (ty/ssaExternTyped "aslParWord1" (list (val)) (ptr))
        (ty/ssaExternTyped "aslParMakeVal" (list (ptr) (ptr)) (val)) (ty/ssaExternTyped "aslParAlloc" (list (i32) (i64)) (ptr))
        (ty/ssaExternTyped "aslParErrorMsg" (list) (ptr)))

fn parExterns facts: libc/TripleFacts -> (List ty/SsaExtern)
  (let [(t (fn [(name String) (params (List ty/SsaTy)) (ret ty/SsaTy)] -> ty/SsaExtern (ty/ssaExternTyped name params ret)))]
    (listAppend (helperExterns)
      (list (t "malloc" (list (i64)) (ptr)) (t "calloc" (list (i64) (i64)) (ptr)) (t "realloc" (list (ptr) (i64)) (ptr)) (t "free" (list (ptr)) (i64))
            (t "memcpy" (list (ptr) (ptr) (i64)) (ptr)) (t "memcmp" (list (ptr) (ptr) (i64)) (i32)) (t "strlen" (list (ptr)) (i64)) (t "strcmp" (list (ptr) (ptr)) (i32))
            (t "getenv" (list (ptr)) (ptr)) (t "sysconf" (list (i32)) (i64)) (t facts.errnoAccessor (list) (ptr))
            (t "pipe" (list (ptr)) (i32)) (t "fork" (list) (i32)) (t "_exit" (list (i32)) (i64)) (t "fflush" (list (ptr)) (i32))
            (t "close" (list (i32)) (i32)) (t "read" (list (i32) (ptr) (i64)) (i64)) (t "write" (list (i32) (ptr) (i64)) (i64))
            (t "poll" (list (ptr) (i64) (i32)) (i32)) (t "kill" (list (i32) (i32)) (i32)) (t "waitpid" (list (i32) (ptr) (i32)) (i32)) (t "signal" (list (i32) (ptr)) (ptr))
            (t "setjmp" (list (ptr)) (i32)) (t "aslErrorHandlerSet" (list (ptr)) (i64)) (t "aslErrorHandlerGet" (list) (ptr))
            (ty/ssaExternVariadic "aslError" (list (ptr) (ptr)) (i64)) (ty/ssaExternVariadic "snprintf" (list (ptr) (i64) (ptr)) (i32))
            (t "valToCStr" (list (val) (i32)) (ptr)) (t "symName" (list (i32)) (ptr)) (t "intern" (list (ptr) (i64)) (i32)) (t "tagName" (list (i32)) (ptr))
            (t "mkStr" (list (ptr) (i64)) (val)) (t "mkBytes" (list (ptr) (i64)) (val)) (t "mkCtor" (list (i32) (i32)) (val))
            (t "gcWillAllocate" (list (i64)) (i64)) (t "gcAccount" (list (ptr) (i64)) (i64)))))

fn parGlobals -> (List ty/SsaGlobal)
  (list (ty/ssaGlobal (pn "keyTable") (pn "keyTableInit")))


fn errnoFn c: ParCtx -> ty/SsaFunction
  (function "errno" (list) (i64)
    (list (block "entry" (list (ex "p" (ptr) c.errno (list)) (p2i "a" "p") (ldS32 "e" "a" 0)) (returnTerm "e"))))

fn cpuCountFn c: ParCtx -> ty/SsaFunction
  (function "cpuCount" (list) (i64)
    (list (block "entry" (list (k32 "name" (kf c "_SC_NPROCESSORS_ONLN")) (ex "n" (i64) "sysconf" (list "name")) (cmpK "good" "geInt" "n" 1)) (branch "good" "online" "guess"))
          (block "online" (list) (returnTerm "n"))
          (block "guess" (list (k "four" 4)) (returnTerm "four"))))

fn forcedFn c: ParCtx -> ty/SsaFunction
  (function "forced" (list) (i1)
    (list (block "entry" (list (cs c "name" "ASL_PAR_FORCE_FALLBACK") (ex "v" (ptr) "getenv" (list "name")) (ex "freed" (i64) "free" (list "name"))
                           (pr "unset" (i1) "rawPtrIsNull" (list "v")))
            (branch "unset" "no" "compare"))
          (block "no" (list (ins "f" (i1) (ty/opConst (ty/constBool false)))) (returnTerm "f"))
          (block "compare" (list (cs c "one" "1") (ex "r" (i32) "strcmp" (list "v" "one")) (ex "freed1" (i64) "free" (list "one")) (w64 "r64" "r") (cmpK "same" "eqInt" "r64" 0))
            (returnTerm "same"))))

fn countFn -> ty/SsaFunction
  (function "count" (list (pV "xs")) (i64)
    (list (block "entry" (list (k "z" 0)) (jump "loop" (list "xs" "z")))
          (paramBlock "loop" (list (pV "cur") (pI "n")) (list (en "empty" (i1) "listEmpty?" (list "cur"))) (branch "empty" "done" "step"))
          (block "step" (list (en "rest" (val) "@listRest" (list "cur")) (addK "n1" "n" 1)) (jump "loop" (list "rest" "n1")))
          (block "done" (list) (returnTerm "n"))))

fn reverseFn -> ty/SsaFunction
  (function "reverse" (list (pV "xs")) (val)
    (list (block "entry" (list (nilV "nil")) (jump "loop" (list "xs" "nil")))
          (paramBlock "loop" (list (pV "cur") (pV "out")) (list (en "empty" (i1) "listEmpty?" (list "cur"))) (branch "empty" "done" "step"))
          (block "step" (list (en "head" (val) "@listFirst" (list "cur")) (en "rest" (val) "@listRest" (list "cur")) (en "out1" (val) "cons" (list "head" "out")))
            (jump "loop" (list "rest" "out1")))
          (block "done" (list) (returnTerm "out"))))

fn dropFn -> ty/SsaFunction
  (function "drop" (list (pV "xs") (pI "n")) (val)
    (list (block "entry" (list) (jump "loop" (list "xs" "n")))
          (paramBlock "loop" (list (pV "cur") (pI "left")) (list (cmpK "done" "leInt" "left" 0)) (branch "done" "out" "step"))
          (block "step" (list (en "rest" (val) "@listRest" (list "cur")) (addK "left1" "left" -1)) (jump "loop" (list "rest" "left1")))
          (block "out" (list) (returnTerm "cur"))))

fn writeAllFn c: ParCtx -> ty/SsaFunction
  (function "writeAll" (list (pI "fd") (pI "p") (pI "n")) (i64)
    (list (block "entry" (list (n32 "fd32" "fd")) (jump "loop" (list "p" "n")))
          (paramBlock "loop" (list (pI "at") (pI "left")) (list (cmpK "finished" "leInt" "left" 0)) (branch "finished" "ok" "put"))
          (block "put" (list (i2p "atP" "at") (ex "w" (i64) "write" (list "fd32" "atP" "left")) (cmpK "failed" "ltInt" "w" 0)) (branch "failed" "failure" "advance"))
          (block "advance" (list (add "at1" "at" "w") (sub "left1" "left" "w")) (jump "loop" (list "at1" "left1")))
          (block "failure" (list (hp "e" (i64) "errno" (list)) (cmpK "again" "eqInt" "e" (kf c "EINTR"))) (argBranch "again" "loop" (list "at" "left") "bad" (list)))
          (block "bad" (list (k "m1" -1)) (returnTerm "m1"))
          (block "ok" (list (k "z" 0)) (returnTerm "z"))))

fn reapFn c: ParCtx -> ty/SsaFunction
  (function "reap" (list (pI "pid") (pI "stAt")) (i64)
    (list (block "entry" (list (n32 "pid32" "pid") (i2p "stP" "stAt") (k32 "flags" 0)) (jump "loop" (list)))
          (block "loop" (list (ex "w" (i32) "waitpid" (list "pid32" "stP" "flags")) (w64 "w64" "w") (cmpK "failed" "ltInt" "w64" 0)) (branch "failed" "check" "done"))
          (block "check" (list (hp "e" (i64) "errno" (list)) (cmpK "intr" "eqInt" "e" (kf c "EINTR"))) (branch "intr" "loop" "done"))
          (block "done" (list) (returnTerm "w64"))))

fn killAllFn c: ParCtx -> ty/SsaFunction
  (function "killAll" (list (pI "pids") (pI "rfds") (pI "n")) (i64)
    (list (block "entry" (list (k "z" 0) (k32 "sig" (kf c "SIGKILL"))) (jump "loop" (list "z")))
          (paramBlock "loop" (list (pI "j")) (list (cmp "done" "geInt" "j" "n")) (branch "done" "out" "one"))
          (block "one" (list (mulK "off" "j" 4) (add "pidAt" "pids" "off") (ldS32 "pid" "pidAt" 0) (n32 "pid32" "pid") (ex "killed" (i32) "kill" (list "pid32" "sig"))
                         (add "fdAt" "rfds" "off") (ldS32 "fd" "fdAt" 0) (n32 "fd32" "fd") (ex "closed" (i32) "close" (list "fd32"))
                         (hp "reaped" (i64) "reap" (list "pid" "z")) (addK "j1" "j" 1))
            (jump "loop" (list "j1")))
          (block "out" (list) (returnTerm "z"))))

fn killOthersFn c: ParCtx -> ty/SsaFunction
  (function "killOthers" (list (pI "pids") (pI "n") (pI "keep")) (i64)
    (list (block "entry" (list (k "z" 0) (k32 "sig" (kf c "SIGTERM"))) (jump "loop" (list "z")))
          (paramBlock "loop" (list (pI "j")) (list (cmp "done" "geInt" "j" "n")) (branch "done" "out" "pick"))
          (block "pick" (list (cmp "self" "eqInt" "j" "keep") (addK "j1" "j" 1)) (branch "self" "next" "send"))
          (block "send" (list (mulK "off" "j" 4) (add "pidAt" "pids" "off") (ldS32 "pid" "pidAt" 0) (n32 "pid32" "pid") (ex "killed" (i32) "kill" (list "pid32" "sig"))) (jump "next" (list)))
          (block "next" (list) (jump "loop" (list "j1")))
          (block "out" (list) (returnTerm "z"))))


fn serWriteFn -> ty/SsaFunction
  (function "serWrite" (list (pI "sb") (pI "src") (pI "n")) (i64)
    (list
      (block "entry" (list (k "z" 0) (ld "err" "sb" 24) (cmp "bad" "neInt" "err" "z")) (branch "bad" "done" "check"))
      (block "check" (list (ld "len" "sb" 8) (k "max" (serMax)) (sub "room" "max" "len") (cmp "big" "gtInt" "n" "room")) (branch "big" "tooBig" "fits"))
      (block "tooBig" (list (k "three" 3) (st "s3" "sb" 24 "three")) (jump "done" (list)))
      (block "fits" (list (add "needed" "len" "n") (ld "cap" "sb" 16) (cmp "grow" "gtInt" "needed" "cap")) (branch "grow" "growStart" "copy"))
      (block "growStart" (list (cmp "capZero" "eqInt" "cap" "z") (k "initial" 256)) (argBranch "capZero" "growLoop" (list "initial") "growFrom" (list)))
      (block "growFrom" (list) (jump "growLoop" (list "cap")))
      (paramBlock "growLoop" (list (pI "nc")) (list (cmp "short" "ltInt" "nc" "needed")) (branch "short" "double" "clamp"))
      (block "double" (list (mulK "nc2" "nc" 2)) (jump "growLoop" (list "nc2")))
      (block "clamp" (list (cmp "over" "gtInt" "nc" "max")) (argBranch "over" "resize" (list "max") "keep" (list)))
      (block "keep" (list) (jump "resize" (list "nc")))
      (paramBlock "resize" (list (pI "newCap"))
        (list (ld "data" "sb" 0) (i2p "dataP" "data") (ex "grown" (ptr) "realloc" (list "dataP" "newCap")) (pr "null" (i1) "rawPtrIsNull" (list "grown")))
        (branch "null" "oom" "store"))
      (block "oom" (list (k "one" 1) (st "s1" "sb" 24 "one")) (jump "done" (list)))
      (block "store" (list (p2i "grownI" "grown") (st "sd" "sb" 0 "grownI") (st "sc" "sb" 16 "newCap")) (jump "copy" (list)))
      (block "copy" (list (ld "base" "sb" 0) (add "dst" "base" "len") (i2p "dstP" "dst") (i2p "srcP" "src") (ex "copied" (ptr) "memcpy" (list "dstP" "srcP" "n"))
                      (st "sl" "sb" 8 "needed"))
        (jump "done" (list)))
      (block "done" (list) (returnTerm "z"))))

fn serNumFn -> ty/SsaFunction
  (function "serNum" (list (pI "sb") (pI "v") (pI "width")) (i64)
    (list (block "entry" (list (st "s" "sb" 32 "v") (addK "at" "sb" 32) (hp "w" (i64) "serWrite" (list "sb" "at" "width"))) (returnTerm "w"))))

fn serNameBlocks label: String sb: String name: String next: String -> (List ty/SsaBlock)
  (list (block label (list (i2p (str label ".p") name) (ex (str label ".len") (i64) "strlen" (list (str label ".p"))) (cmpK (str label ".long") "gtInt" (str label ".len") 4294967295))
          (branch (str label ".long") (str label "Long") (str label "Put")))
        (block (str label "Long") (list (k (str label ".three") 3) (st (str label ".s3") sb 24 (str label ".three"))) (jump next (list)))
        (block (str label "Put") (list (k (str label ".four") 4) (hp (str label ".w1") (i64) "serNum" (list sb (str label ".len") (str label ".four")))
                                   (hp (str label ".w2") (i64) "serWrite" (list sb name (str label ".len"))))
          (jump next (list))))

fn serTag label: String sb: String n: Int64 -> (List ty/SsaInstr)
  (appendAll (list (k (str label ".tag") n) (k (str label ".one") 1) (hp (str label ".tw") (i64) "serNum" (list sb (str label ".tag") (str label ".one")))))

fn serValFn -> ty/SsaFunction
  (function "serVal" (list (pI "sb") (pV "v") (pI "depth")) (i64)
    (appendAll
      (list
        (list
          (block "entry" (list (k "z" 0) (ld "err" "sb" 24) (cmp "bad" "neInt" "err" "z")) (branch "bad" "done" "depthCheck"))
          (block "depthCheck" (list (cmpK "deep" "gtInt" "depth" (depthMax))) (branch "deep" "tooDeep" "split"))
          (block "tooDeep" (list (k "two" 2) (st "s2" "sb" 24 "two")) (jump "done" (list)))
          (block "split" (list (words "v" "v") (bandK "tag" "v.w0" 4294967295) (shrK "aux" "v.w0" 32) (addK "next" "depth" 1) (k "eight" 8) (k "four" 4)) (jump "t0" (list))))
        (chain "t" "tag" (list (pair 0 "unit") (pair 1 "bool") (pair 2 "int") (pair 3 "float") (pair 4 "kw") (pair 5 "str") (pair 6 "list") (pair 7 "rec") (pair 8 "ctor")
                               (pair 11 "bytes") (pair 12 "f64") (pair 13 "i64") (pair 14 "i8"))
               "other")
        (list
          (block "unit" (list (serTag "unit" "sb" 1)) (jump "done" (list)))
          (block "bool" (list (serTag "bool" "sb" 2) (cmp "truth" "neInt" "v.w1" "z")) (argBranch "truth" "boolPut" (list "bool.one") "boolPut" (list "z")))
          (paramBlock "boolPut" (list (pI "bit")) (list (hp "bw" (i64) "serNum" (list "sb" "bit" "bool.one"))) (jump "done" (list)))
          (block "int" (list (serTag "int" "sb" 3) (hp "iw" (i64) "serNum" (list "sb" "v.w1" "eight"))) (jump "done" (list)))
          (block "float" (list (serTag "float" "sb" 4) (hp "fw" (i64) "serNum" (list "sb" "v.w1" "eight"))) (jump "done" (list)))
          (block "kw" (list (serTag "kw" "sb" 5) (n32 "aux32" "aux") (ex "kwName" (ptr) "symName" (list "aux32")) (p2i "kwAt" "kwName")) (jump "kwName0" (list)))
          (block "str" (list (serTag "str" "sb" 6) (ld "slen" "v.w1" 8) (hp "sw1" (i64) "serNum" (list "sb" "slen" "eight")) (addK "sAt" "v.w1" 16)
                         (hp "sw2" (i64) "serWrite" (list "sb" "sAt" "slen")))
            (jump "done" (list)))
          (block "bytes" (list (serTag "bytes" "sb" 7) (ld "blen" "v.w1" 8) (ld "bdata" "v.w1" 24) (hp "bw1" (i64) "serNum" (list "sb" "blen" "eight"))
                           (cmp "bhas" "neInt" "blen" "z") (cmp "bptr" "neInt" "bdata" "z") (andB "bput" "bhas" "bptr"))
            (branch "bput" "bytesPut" "done"))
          (block "bytesPut" (list (hp "bw2" (i64) "serWrite" (list "sb" "bdata" "blen"))) (jump "done" (list)))
          (block "list" (list (serTag "list" "sb" 8)) (jump "lcount" (list "v.w1" "z")))
          (paramBlock "lcount" (list (pI "lp") (pI "lc")) (list (cmp "lend" "eqInt" "lp" "z")) (branch "lend" "lcounted" "lcstep"))
          (block "lcstep" (list (addK "lc1" "lc" 1) (ld "lnext" "lp" 32)) (jump "lcount" (list "lnext" "lc1")))
          (block "lcounted" (list (hp "lw" (i64) "serNum" (list "sb" "lc" "eight"))) (jump "lwalk" (list "v.w1")))
          (paramBlock "lwalk" (list (pI "wp")) (list (cmp "wend" "eqInt" "wp" "z")) (branch "wend" "done" "lelem"))
          (block "lelem" (list (addK "carAt" "wp" 8) (ldVal "car" "carAt") (hp "lsw" (i64) "serVal" (list "sb" "car" "next")) (ld "lerr" "sb" 24) (cmp "lbad" "neInt" "lerr" "z")
                           (ld "wnext" "wp" 32))
            (argBranch "lbad" "done" (list) "lwalk" (list "wnext")))
          (block "ctor" (list (serTag "ctor" "sb" 9) (ldS32 "cid" "v.w1" 8) (n32 "cid32" "cid") (ex "cName" (ptr) "symName" (list "cid32")) (p2i "cAt" "cName")) (jump "cName0" (list)))
          (block "cfields" (list (ldS32 "cn" "v.w1" 12) (hp "cnw" (i64) "serNum" (list "sb" "cn" "four"))) (jump "cloop" (list "z")))
          (paramBlock "cloop" (list (pI "ci")) (list (cmp "cend" "geInt" "ci" "cn")) (branch "cend" "done" "cfield"))
          (block "cfield" (list (mulK "cOff" "ci" 16) (add "cBase" "v.w1" "cOff") (addK "cfAt" "cBase" 16) (ldVal "cf" "cfAt") (hp "csw" (i64) "serVal" (list "sb" "cf" "next"))
                            (ld "cerr" "sb" 24) (cmp "cbad" "neInt" "cerr" "z") (addK "ci1" "ci" 1))
            (argBranch "cbad" "done" (list) "cloop" (list "ci1")))
          (block "rec" (list (serTag "rec" "sb" 10) (ldS32 "schema" "v.w1" 8) (cmp "anon" "ltInt" "schema" "z")) (branch "anon" "recAnon" "recNamed"))
          (block "recAnon" (list (hp "raw" (i64) "serNum" (list "sb" "z" "four"))) (jump "rfields" (list)))
          (block "recNamed" (list (n32 "schema32" "schema") (ex "rName" (ptr) "symName" (list "schema32")) (p2i "rAt" "rName")) (jump "rName0" (list)))
          (block "rfields" (list (ldS32 "rn" "v.w1" 12) (hp "rnw" (i64) "serNum" (list "sb" "rn" "four")) (ld "keys" "v.w1" 16)) (jump "rloop" (list "z")))
          (paramBlock "rloop" (list (pI "ri")) (list (cmp "rend" "geInt" "ri" "rn")) (branch "rend" "done" "rkey"))
          (block "rkey" (list (mulK "kOff" "ri" 4) (add "kAt" "keys" "kOff") (ldS32 "kid" "kAt" 0) (n32 "kid32" "kid") (ex "kName" (ptr) "symName" (list "kid32")) (p2i "kNameAt" "kName"))
            (jump "kName0" (list)))
          (block "rvalue" (list (mulK "rOff" "ri" 16) (add "rBase" "v.w1" "rOff") (addK "rfAt" "rBase" 24) (ldVal "rf" "rfAt") (hp "rsw" (i64) "serVal" (list "sb" "rf" "next"))
                            (ld "rerr" "sb" 24) (cmp "rbad" "neInt" "rerr" "z") (addK "ri1" "ri" 1))
            (argBranch "rbad" "done" (list) "rloop" (list "ri1")))
          (block "f64" (list (k "f64tag" 11)) (jump "arr" (list "f64tag")))
          (block "i64" (list (k "i64tag" 12)) (jump "arr" (list "i64tag")))
          (block "i8" (list (k "i8tag" 13)) (jump "arr" (list "i8tag")))
          (paramBlock "arr" (list (pI "atag")) (list (k "aone" 1) (hp "aw0" (i64) "serNum" (list "sb" "atag" "aone")) (ld "alen" "v.w1" 8) (ld "aelem" "v.w1" 16) (ld "adata" "v.w1" 24)
                                             (hp "aw1" (i64) "serNum" (list "sb" "alen" "eight")) (cmp "aunit" "eqInt" "aelem" "z"))
            (branch "aunit" "done" "asize"))
          (block "asize" (list (k "imax" 9223372036854775807) (pr "alimit" (i64) "quotInt" (list "imax" "aelem")) (cmp "awide" "gtInt" "alen" "alimit")) (branch "awide" "arrWide" "abytes"))
          (block "arrWide" (list (k "athree" 3) (st "as3" "sb" 24 "athree")) (jump "done" (list)))
          (block "abytes" (list (mul "ablen" "alen" "aelem") (cmp "ahas" "neInt" "ablen" "z") (cmp "aptr" "neInt" "adata" "z") (andB "aput" "ahas" "aptr")) (branch "aput" "arrPut" "done"))
          (block "arrPut" (list (hp "aw2" (i64) "serWrite" (list "sb" "adata" "ablen"))) (jump "done" (list)))
          (block "other" (list (k "oone" 1) (st "os1" "sb" 24 "oone")) (jump "done" (list)))
          (block "done" (list) (returnTerm "z")))
        (serNameBlocks "kwName0" "sb" "kwAt" "done")
        (serNameBlocks "cName0" "sb" "cAt" "cfields")
        (serNameBlocks "rName0" "sb" "rAt" "rfields")
        (serNameBlocks "kName0" "sb" "kNameAt" "rvalue"))))

fn deserHasFn -> ty/SsaFunction
  (function "deserHas" (list (pI "d") (pI "n")) (i1)
    (list (block "entry" (list (ld "pos" "d" 8) (ld "len" "d" 16) (k "z" 0) (cmp "past" "gtInt" "pos" "len") (cmp "neg" "ltInt" "n" "z") (cmpK "big" "gtInt" "n" (serMax))
                           (sub "left" "len" "pos") (cmp "short" "gtInt" "n" "left") (orB "o1" "past" "neg") (orB "o2" "o1" "big") (orB "bad" "o2" "short"))
            (branch "bad" "fail" "ok"))
          (block "fail" (list (k "one" 1) (st "s" "d" 24 "one") (ins "f" (i1) (ty/opConst (ty/constBool false)))) (returnTerm "f"))
          (block "ok" (list (ins "t" (i1) (ty/opConst (ty/constBool true)))) (returnTerm "t"))))

fn deserNumFn -> ty/SsaFunction
  (function "deserNum" (list (pI "d") (pI "width")) (i64)
    (list (block "entry" (list (k "z" 0) (ld "err" "d" 24) (ld "pos" "d" 8) (ld "len" "d" 16) (cmp "bad0" "neInt" "err" "z") (cmp "past" "gtInt" "pos" "len")
                           (sub "left" "len" "pos") (cmp "short" "gtInt" "width" "left") (orB "o1" "bad0" "past") (orB "bad" "o1" "short"))
            (branch "bad" "fail" "read"))
          (block "fail" (list (k "one" 1) (st "s" "d" 24 "one")) (returnTerm "z"))
          (block "read" (list (ld "data" "d" 0) (add "at" "data" "pos") (add "pos1" "pos" "width") (st "sp" "d" 8 "pos1") (cmpK "is1" "eqInt" "width" 1)) (branch "is1" "u8" "not1"))
          (block "not1" (list (cmpK "is4" "eqInt" "width" 4)) (branch "is4" "u32" "u64"))
          (block "u8" (list (ldU8 "b" "at" 0)) (returnTerm "b"))
          (block "u32" (list (ldU32 "w" "at" 0)) (returnTerm "w"))
          (block "u64" (list (ld "q" "at" 0)) (returnTerm "q"))))

fn internKeysFn -> ty/SsaFunction
  (function "internKeys" (list (pI "kbuf") (pI "n")) (i64)
    (list (block "entry" (list (k "z" 0) (vop "cellV" (ty/opGlobal (pn "keyTable"))) (ins "cell" (i64) (ty/opUnbox "cellV")) (cmp "noCell" "eqInt" "cell" "z") (mulK "bytes" "n" 4))
            (branch "noCell" "fail" "start"))
          (block "start" (list (ld "head" "cell" 0)) (jump "scan" (list "head")))
          (paramBlock "scan" (list (pI "e")) (list (cmp "end" "eqInt" "e" "z")) (branch "end" "add" "probe"))
          (block "probe" (list (ld "en" "e" 8) (ld "enext" "e" 0) (cmp "sameN" "eqInt" "en" "n")) (branch "sameN" "compare" "skip"))
          (block "skip" (list) (jump "scan" (list "enext")))
          (block "compare" (list (addK "eKeys" "e" 16) (i2p "eKeysP" "eKeys") (i2p "kbufP" "kbuf") (ex "c" (i32) "memcmp" (list "eKeysP" "kbufP" "bytes")) (w64 "c64" "c")
                             (cmp "same" "eqInt" "c64" "z"))
            (branch "same" "found" "skip"))
          (block "found" (list) (returnTerm "eKeys"))
          (block "add" (list (addK "size" "bytes" 16) (ex "ent" (ptr) "malloc" (list "size")) (pr "entNull" (i1) "rawPtrIsNull" (list "ent"))) (branch "entNull" "fail" "fill"))
          (block "fill" (list (p2i "entI" "ent") (st "sn" "entI" 8 "n") (addK "keysAt" "entI" 16) (cmp "any" "gtInt" "n" "z")) (branch "any" "copy" "link"))
          (block "copy" (list (i2p "keysP" "keysAt") (i2p "srcP" "kbuf") (ex "copied" (ptr) "memcpy" (list "keysP" "srcP" "bytes"))) (jump "link" (list)))
          (block "link" (list (ld "old" "cell" 0) (st "sl" "entI" 0 "old") (st "sh" "cell" 0 "entI")) (returnTerm "keysAt"))
          (block "fail" (list) (returnTerm "z"))))

fn keyTableInitFn c: ParCtx -> ty/SsaFunction
  (function "keyTableInit" (list) (val)
    (list (block "entry" (list (k "one" 1) (k "eight" 8) (ex "cell" (ptr) "calloc" (list "one" "eight")) (pr "null" (i1) "rawPtrIsNull" (list "cell"))) (branch "null" "oom" "ok"))
          (raiseB c "oom" (list) "ERR_OOM" "parallel key table" (list))
          (block "ok" (list (p2i "cellI" "cell") (vop "boxed" (ty/opBox "cellI"))) (returnTerm "boxed"))))

fn newArrayFn c: ParCtx -> ty/SsaFunction
  (function "newArray" (list (pI "tag") (pI "n")) (val)
    (list (block "entry" (list (k "one" 1) (k "eight" 8) (cmpK "isI8" "eqInt" "tag" 14)) (argBranch "isI8" "sized" (list "one") "wide" (list)))
          (block "wide" (list) (jump "sized" (list "eight")))
          (paramBlock "sized" (list (pI "elem"))
            (list (cmpK "isF" "eqInt" "tag" 12) (cmpK "huge" "gtInt" "n" 16777216)
                  (k "imax" 9223372036854775807) (pr "limit" (i64) "quotInt" (list "imax" "elem")) (cmp "wrap" "gtInt" "n" "limit") (orB "bad" "huge" "wrap"))
            (branch "bad" "range" "alloc"))
          (block "range" (list) (jump "named" (list)))
          (block "named" (list) (branch "isF" "rangeF" "rangeNotF"))
          (block "rangeNotF" (list (cmpK "isI64" "eqInt" "tag" 13)) (branch "isI64" "rangeI" "rangeB"))
          (raiseB c "rangeF" (list (cs c "rangeF.t" "F64Array")) "ERR_RANGE" "%s of %lld elements exceeds the array allocation limit" (list "rangeF.t" "n"))
          (raiseB c "rangeI" (list (cs c "rangeI.t" "I64Array")) "ERR_RANGE" "%s of %lld elements exceeds the array allocation limit" (list "rangeI.t" "n"))
          (raiseB c "rangeB" (list (cs c "rangeB.t" "I8Array")) "ERR_RANGE" "%s of %lld elements exceeds the array allocation limit" (list "rangeB.t" "n"))
          (block "alloc" (list (mul "bytes" "n" "elem") (ex "will" (i64) "gcWillAllocate" (list "bytes")) (k32 "otype" (objArr)) (k "arrSize" 32)
                           (ex "obj" (ptr) "aslParAlloc" (list "otype" "arrSize")) (p2i "objI" "obj") (st "se" "objI" 16 "elem") (st "sn" "objI" 8 "n")
                           (addK "dataBytes" "bytes" 1) (ex "data" (ptr) "malloc" (list "dataBytes")) (pr "null" (i1) "rawPtrIsNull" (list "data")))
            (branch "null" "oom" "ready"))
          (block "oom" (list) (branch "isF" "oomF" "oomNotF"))
          (block "oomNotF" (list (cmpK "isI64b" "eqInt" "tag" 13)) (branch "isI64b" "oomI" "oomB"))
          (raiseB c "oomF" (list (cs c "oomF.t" "F64Array")) "ERR_OOM" "cannot allocate %s of %lld elements" (list "oomF.t" "n"))
          (raiseB c "oomI" (list (cs c "oomI.t" "I64Array")) "ERR_OOM" "cannot allocate %s of %lld elements" (list "oomI.t" "n"))
          (raiseB c "oomB" (list (cs c "oomB.t" "I8Array")) "ERR_OOM" "cannot allocate %s of %lld elements" (list "oomB.t" "n"))
          (block "ready" (list (p2i "dataI" "data") (st "sd" "objI" 24 "dataI") (ex "accounted" (i64) "gcAccount" (list "obj" "bytes")) (mkv "arr" "tag" "objI")) (returnTerm "arr"))))

fn deserStrBlocks label: String d: String maker: String fail: String -> (List ty/SsaBlock)
  (list (block label (list (k (str label ".w") 8) (hp (str label ".len") (i64) "deserNum" (list d (str label ".w"))) (ld (str label ".err") d 24) (k (str label ".z") 0)
                       (cmp (str label ".bad") "neInt" (str label ".err") (str label ".z")))
          (branch (str label ".bad") fail (str label "Has")))
        (block (str label "Has") (list (hp (str label ".has") (i1) "deserHas" (list d (str label ".len")))) (branch (str label ".has") (str label "Make") fail))
        (block (str label "Make") (list (ld (str label ".data") d 0) (ld (str label ".pos") d 8) (add (str label ".at") (str label ".data") (str label ".pos")) (i2p (str label ".atP") (str label ".at"))
                                    (ex (str label ".v") (val) maker (list (str label ".atP") (str label ".len"))) (add (str label ".pos1") (str label ".pos") (str label ".len"))
                                    (st (str label ".sp") d 8 (str label ".pos1")))
          (returnTerm (str label ".v"))))

fn deserNameBlocks label: String d: String next: String fail: String -> (List ty/SsaBlock)
  (list (block label (list (k (str label ".w") 4) (hp (str label ".len") (i64) "deserNum" (list d (str label ".w"))) (ld (str label ".err") d 24) (k (str label ".z") 0)
                       (cmp (str label ".bad") "neInt" (str label ".err") (str label ".z")))
          (branch (str label ".bad") fail (str label "Has")))
        (block (str label "Has") (list (hp (str label ".has") (i1) "deserHas" (list d (str label ".len")))) (branch (str label ".has") (str label "Intern") fail))
        (block (str label "Intern") (list (ld (str label ".data") d 0) (ld (str label ".pos") d 8) (add (str label ".at") (str label ".data") (str label ".pos")) (i2p (str label ".atP") (str label ".at"))
                                      (ex (str label ".id32") (i32) "intern" (list (str label ".atP") (str label ".len"))) (w64 (str label ".id") (str label ".id32"))
                                      (add (str label ".pos1") (str label ".pos") (str label ".len")) (st (str label ".sp") d 8 (str label ".pos1")))
          (jump next (list (str label ".id")))))

fn errSet label: String d: String -> (List ty/SsaInstr)
  (appendAll (list (k (str label ".one") 1) (st (str label ".s") d 24 (str label ".one"))))

fn deserValFn -> ty/SsaFunction
  (function "deserVal" (list (pI "d") (pI "depth")) (val)
    (appendAll
      (list
        (list
          (block "entry" (list (k "z" 0) (ld "err" "d" 24) (cmp "bad" "neInt" "err" "z")) (branch "bad" "unit" "depthCheck"))
          (block "depthCheck" (list (cmpK "deep" "gtInt" "depth" (depthMax))) (branch "deep" "tooDeep" "readTag"))
          (block "tooDeep" (list (k "two" 2) (st "s2" "d" 24 "two")) (jump "unit" (list)))
          (block "readTag" (list (k "one" 1) (k "four" 4) (k "eight" 8) (addK "next" "depth" 1) (hp "tag" (i64) "deserNum" (list "d" "one")) (ld "terr" "d" 24) (cmp "tbad" "neInt" "terr" "z"))
            (branch "tbad" "unit" "t0")))
        (chain "t" "tag" (list (pair 1 "unit") (pair 2 "bool") (pair 3 "int") (pair 4 "float") (pair 5 "kw") (pair 6 "str") (pair 7 "bytes") (pair 8 "list") (pair 9 "ctor")
                               (pair 10 "rec") (pair 11 "f64") (pair 12 "i64") (pair 13 "i8"))
               "corrupt")
        (list
          (block "unit" (list (unitV "u")) (returnTerm "u"))
          (block "corrupt" (list (errSet "cor" "d")) (jump "unit" (list)))
          (block "bool" (list (hp "b" (i64) "deserNum" (list "d" "one")) (cmp "truth" "neInt" "b" "z")) (argBranch "truth" "boolMake" (list "one") "boolMake" (list "z")))
          (paramBlock "boolMake" (list (pI "bit")) (list (mkvK "bv" 1 "bit")) (returnTerm "bv"))
          (block "int" (list (hp "iv" (i64) "deserNum" (list "d" "eight")) (mkvK "ivv" (tagInt) "iv")) (returnTerm "ivv"))
          (block "float" (list (hp "fv" (i64) "deserNum" (list "d" "eight")) (mkvK "fvv" 3 "fv")) (returnTerm "fvv"))
          (paramBlock "kwMake" (list (pI "kid")) (list (shlK "kw0a" "kid" 32) (k "kwTag" 4) (pr "kw0" (i64) "rawOrI64" (list "kw0a" "kwTag")) (mkv "kwv" "kw0" "z")) (returnTerm "kwv"))
          (block "list" (list (hp "count" (i64) "deserNum" (list "d" "eight")) (ld "lerr" "d" 24) (cmp "lbad" "neInt" "lerr" "z")) (branch "lbad" "unit" "lcheck"))
          (block "lcheck" (list (ld "lpos" "d" 8) (ld "llen" "d" 16) (sub "lleft" "llen" "lpos") (cmp "lneg" "ltInt" "count" "z") (cmp "lshort" "gtInt" "count" "lleft")
                            (cmpK "lbig" "gtInt" "count" (serMax)) (orB "l1" "lneg" "lshort") (orB "lout" "l1" "lbig"))
            (branch "lout" "corrupt" "lstart"))
          (block "lstart" (list (nilV "nil")) (jump "lloop" (list "z" "nil")))
          (paramBlock "lloop" (list (pI "li") (pV "rev")) (list (cmp "ldone" "geInt" "li" "count")) (branch "ldone" "lreverse" "lelem"))
          (block "lelem" (list (hp "elem" (val) "deserVal" (list "d" "next")) (ld "eerr" "d" 24) (cmp "ebad" "neInt" "eerr" "z")) (branch "ebad" "unit" "lpush"))
          (block "lpush" (list (en "rev1" (val) "cons" (list "elem" "rev")) (addK "li1" "li" 1)) (jump "lloop" (list "li1" "rev1")))
          (block "lreverse" (list (hp "lout2" (val) "reverse" (list "rev"))) (returnTerm "lout2"))
          (paramBlock "ctorMake" (list (pI "cid"))
            (list (hp "cn" (i64) "deserNum" (list "d" "four")) (ld "cerr" "d" 24) (cmp "cbad0" "neInt" "cerr" "z")
                  (ld "cpos" "d" 8) (ld "clen" "d" 16) (sub "cleft" "clen" "cpos") (cmpK "cbig" "gtInt" "cn" 2147483647) (cmpK "cwide" "gtInt" "cn" (maxFields))
                  (cmp "cshort" "gtInt" "cn" "cleft") (orB "c1" "cbad0" "cbig") (orB "c2" "c1" "cwide") (orB "cbad" "c2" "cshort"))
            (branch "cbad" "ctorBad" "ctorAlloc"))
          (block "ctorBad" (list) (branch "cbad0" "unit" "corrupt"))
          (block "ctorAlloc" (list (n32 "cid32" "cid") (n32 "cn32" "cn") (ex "cv" (val) "mkCtor" (list "cid32" "cn32")) (payload "cobj" "cv")) (jump "cloop" (list "z")))
          (paramBlock "cloop" (list (pI "ci")) (list (cmp "cdone" "geInt" "ci" "cn")) (branch "cdone" "ctorDone" "cfield"))
          (block "cfield" (list (hp "cf" (val) "deserVal" (list "d" "next")) (ld "cferr" "d" 24) (cmp "cfbad" "neInt" "cferr" "z")) (branch "cfbad" "unit" "cstore"))
          (block "cstore" (list (mulK "cOff" "ci" 16) (add "cBase" "cobj" "cOff") (addK "cAt" "cBase" 16) (stVal "cset" "cAt" "cf") (addK "ci1" "ci" 1)) (jump "cloop" (list "ci1")))
          (block "ctorDone" (list) (returnTerm "cv"))
          (block "rec" (list (hp "slen" (i64) "deserNum" (list "d" "four")) (ld "rerr0" "d" 24) (cmp "rbad0" "neInt" "rerr0" "z")) (branch "rbad0" "unit" "rschema"))
          (block "rschema" (list (cmp "anon" "eqInt" "slen" "z") (k "minus1" -1)) (argBranch "anon" "recBody" (list "minus1") "rhas" (list)))
          (block "rhas" (list (hp "shas" (i1) "deserHas" (list "d" "slen"))) (branch "shas" "rintern" "unit"))
          (block "rintern" (list (ld "sdata" "d" 0) (ld "spos" "d" 8) (add "sat" "sdata" "spos") (i2p "satP" "sat") (ex "sid32" (i32) "intern" (list "satP" "slen")) (w64 "sid" "sid32")
                             (add "spos1" "spos" "slen") (st "ssp" "d" 8 "spos1"))
            (jump "recBody" (list "sid")))
          (paramBlock "recBody" (list (pI "schema"))
            (list (hp "rn" (i64) "deserNum" (list "d" "four")) (ld "rerr1" "d" 24) (cmp "rbad1" "neInt" "rerr1" "z")
                  (ld "rpos" "d" 8) (ld "rlen" "d" 16) (sub "rleft" "rlen" "rpos") (k "five" 5) (pr "rfit" (i64) "quotInt" (list "rleft" "five"))
                  (cmpK "rwide" "gtInt" "rn" (maxFields)) (cmp "rshort" "gtInt" "rn" "rfit") (cmpK "rbig" "gtInt" "rn" 2147483647)
                  (orB "r1" "rwide" "rshort") (orB "rout" "r1" "rbig"))
            (branch "rbad1" "unit" "rsize"))
          (block "rsize" (list) (branch "rout" "corrupt" "rkeys"))
          (block "rkeys" (list (mulK "kbytes" "rn" 4) (cmp "rany" "gtInt" "rn" "z")) (branch "rany" "rkbuf" "rnokeys"))
          (block "rnokeys" (list) (jump "ralloc" (list "z")))
          (block "rkbuf" (list (ex "kb" (ptr) "malloc" (list "kbytes")) (pr "kbNull" (i1) "rawPtrIsNull" (list "kb")) (p2i "kbI" "kb")) (argBranch "kbNull" "corrupt" (list) "ralloc" (list "kbI")))
          (paramBlock "ralloc" (list (pI "kbuf"))
            (list (mulK "vbytes" "rn" 16) (addK "rbytes" "vbytes" 24) (k32 "otype" (objRec)) (ex "robj" (ptr) "aslParAlloc" (list "otype" "rbytes")) (p2i "robjI" "robj")
                  (st32 "ss" "robjI" 8 "schema") (st32 "sn" "robjI" 12 "rn") (st "sk" "robjI" 16 "z") (mkvK "rv" 7 "robjI"))
            (jump "rloop" (list "z")))
          (paramBlock "rloop" (list (pI "ri")) (list (cmp "rdone" "geInt" "ri" "rn")) (branch "rdone" "rfinish" "kName0"))
          (paramBlock "rvalue" (list (pI "ksym"))
            (list (mulK "kOff" "ri" 4) (add "kAt" "kbuf" "kOff") (st32 "kset" "kAt" 0 "ksym") (hp "rf" (val) "deserVal" (list "d" "next")) (ld "rferr" "d" 24) (cmp "rfbad" "neInt" "rferr" "z"))
            (branch "rfbad" "rfail" "rstore"))
          (block "rstore" (list (mulK "vOff" "ri" 16) (add "vBase" "robjI" "vOff") (addK "vAt" "vBase" 24) (stVal "vset" "vAt" "rf") (addK "ri1" "ri" 1)) (jump "rloop" (list "ri1")))
          (block "rfail" (list (i2p "kbP" "kbuf") (ex "freed" (i64) "free" (list "kbP"))) (jump "unit" (list)))
          (block "rfinish" (list (hp "keys" (i64) "internKeys" (list "kbuf" "rn")) (i2p "kbP2" "kbuf") (ex "freed2" (i64) "free" (list "kbP2")) (cmp "nokeys" "eqInt" "keys" "z"))
            (branch "nokeys" "corrupt" "rdone2"))
          (block "rdone2" (list (st "skeys" "robjI" 16 "keys")) (returnTerm "rv"))
          (block "f64" (list (k "f64tag" 12)) (jump "arr" (list "f64tag" "eight")))
          (block "i64" (list (k "i64tag" 13)) (jump "arr" (list "i64tag" "eight")))
          (block "i8" (list (k "i8tag" 14)) (jump "arr" (list "i8tag" "one")))
          (paramBlock "arr" (list (pI "atag") (pI "aelem"))
            (list (hp "alen" (i64) "deserNum" (list "d" "eight")) (ld "aerr" "d" 24) (cmp "abad0" "neInt" "aerr" "z") (cmp "aneg" "ltInt" "alen" "z") (cmpK "abig" "gtInt" "alen" (serMax))
                  (orB "a1" "abad0" "aneg") (orB "abad" "a1" "abig"))
            (branch "abad" "corrupt" "asize"))
          (block "asize" (list (mul "ablen" "alen" "aelem") (cmpK "awide" "gtInt" "ablen" (serMax))) (branch "awide" "corrupt" "ahas"))
          (block "ahas" (list (hp "has" (i1) "deserHas" (list "d" "ablen"))) (branch "has" "amake" "unit"))
          (block "amake" (list (hp "av" (val) "newArray" (list "atag" "alen")) (cmp "aany" "gtInt" "ablen" "z")) (branch "aany" "acopy" "adone"))
          (block "acopy" (list (payload "aobj" "av") (ld "adst" "aobj" 24) (i2p "adstP" "adst") (ld "adata" "d" 0) (ld "apos" "d" 8) (add "asrc" "adata" "apos") (i2p "asrcP" "asrc")
                           (ex "acopied" (ptr) "memcpy" (list "adstP" "asrcP" "ablen")) (add "apos1" "apos" "ablen") (st "asp" "d" 8 "apos1"))
            (jump "adone" (list)))
          (block "adone" (list) (returnTerm "av")))
        (deserNameBlocks "kw" "d" "kwMake" "unit")
        (deserStrBlocks "str" "d" "mkStr" "unit")
        (deserStrBlocks "bytes" "d" "mkBytes" "unit")
        (deserNameBlocks "ctor" "d" "ctorMake" "unit")
        (deserNameBlocks "kName0" "d" "rvalue" "rfail"))))


fn childStateBytes -> Int64
  (+ (jmpBufBytes) (+ 8 (+ (bufBytes) 1024)))

fn childFn c: ParCtx fold: Bool -> ty/SsaFunction
  (let [(who (if fold "parFold" "parMap"))
        (name (if fold "childFold" "childMap"))
        (jb (jmpBufBytes))]
    (function name (list (pV "fn") (pV "init") (pV "xs") (pI "start") (pI "end") (pI "wfd")) (i64)
      (appendAll
        (list
          (list
            (block "entry" (list (k "z" 0) (k "one" 1) (k "total" (childStateBytes)) (ex "mem" (ptr) "calloc" (list "one" "total")) (pr "memNull" (i1) "rawPtrIsNull" (list "mem")))
              (branch "memNull" "noMemory" "setup"))
            (block "noMemory" (list (i2p "nullp0" "z") (ex "flushed0" (i32) "fflush" (list "nullp0")) (k32 "exitOne0" 1) (ex "gone0" (i64) "_exit" (list "exitOne0"))) (ty/termUnreachable))
            (block "setup" (list (p2i "memI" "mem") (addK "failAt" "memI" jb) (addK "sb" "memI" (+ jb 8)) (addK "pkt" "memI" (+ jb (+ 8 (bufBytes))))
                             (st "fs" "failAt" 0 "start") (hp "items" (val) "drop" (list "xs" "start")) (n32 "wfd32" "wfd")
                             (ex "handled" (i64) "aslErrorHandlerSet" (list "mem")) (ex "jumped" (i32) "setjmp" (list "mem")) (w64 "jumped64" "jumped") (cmp "caught" "neInt" "jumped64" "z"))
              (branch "caught" "trapped" "begin"))
            (block "begin" (list) (jump "loop" (list "start" "items" "init")))
            (paramBlock "loop" (list (pI "i") (pV "cur") (pV "acc")) (list (cmp "finished" "geInt" "i" "end")) (branch "finished" (if fold "fold" "frame") "call"))
            (block "call"
              (if fold
                (list (en "item" (val) "@listFirst" (list "cur")) (vop "res" (ty/opCallClosure "fn" (list "acc" "item"))) (en "rest" (val) "@listRest" (list "cur")) (addK "i1" "i" 1))
                (list (st "fi" "failAt" 0 "i") (en "item" (val) "@listFirst" (list "cur")) (vop "res" (ty/opCallClosure "fn" (list "item")))
                      (hp "sw" (i64) "serVal" (list "sb" "res" "z")) (ld "serr" "sb" 24) (en "rest" (val) "@listRest" (list "cur")) (addK "i1" "i" 1) (cmp "sfail" "neInt" "serr" "z")))
              (if fold (jump "loop" (list "i1" "rest" "res")) (argBranch "sfail" "serFail" (list) "loop" (list "i1" "rest" "acc")))))
          (if fold
            (list (block "fold" (list (hp "fw" (i64) "serVal" (list "sb" "acc" "z")) (ld "serr" "sb" 24) (cmp "sfail" "neInt" "serr" "z")) (branch "sfail" "serFail" "frame")))
            (list))
          (list
            (block "serFail" (list (cmpK "size" "eqInt" "serr" 3)) (branch "size" "serSize" "serKind"))
            (raiseB c "serSize" (list) "ERR_SERIALIZE_SIZE" (str who " worker result exceeds serialization size limit") (list))
            (raiseB c "serKind" (list) "ERR_NOT_SERIALIZABLE" (str "cannot serialize " who " result across worker process") (list))
            (block "frame"
              (list (st8 "status" "pkt" 0 "z") (k "hdr" (if fold 1 9))
                               (if fold (list) (appendAll (list (sub "cnt" "end" "start") (st "sc" "pkt" 1 "cnt"))))
                               (hp "wh" (i64) "writeAll" (list "wfd" "pkt" "hdr")) (ld "slen" "sb" 8) (ld "sdata" "sb" 0) (hp "wd" (i64) "writeAll" (list "wfd" "sdata" "slen"))
                               (i2p "sdataP" "sdata") (ex "freed" (i64) "free" (list "sdataP")) (ex "closed" (i32) "close" (list "wfd32")) (i2p "nullp" "z")
                               (ex "flushed" (i32) "fflush" (list "nullp")) (k32 "exitZero" 0) (ex "gone" (i64) "_exit" (list "exitZero")))
              (ty/termUnreachable))
            (block "trapped"
              (list (ex "msg" (ptr) "aslParErrorMsg" (list)) (addK "textAt" "pkt" 5) (i2p "textP" "textAt")
                               (if fold
                                 (appendAll (list (ex "mlen" (i64) "strlen" (list "msg")) (cmpK "mlong" "gtInt" "mlen" 1019)))
                                 (appendAll (list (ld "idx" "failAt" 0) (k "room" 1019) (cs c "fmtP" "parMap element %lld: %s")
                                                  (ex "written" (i32) "snprintf" (list "textP" "room" "fmtP" "idx" "msg")) (w64 "mlen" "written") (cmpK "mlong" "gtInt" "mlen" 1018)))))
              (argBranch "mlong" "cut" (list) "send" (list "mlen")))
            (block "cut" (list (k "cutLen" (if fold 1019 1018))) (jump "send" (list "cutLen")))
            (paramBlock "send" (list (pI "len0")) (list (cmpK "neg" "ltInt" "len0" 0)) (argBranch "neg" "packet" (list "z") "packet" (list "len0")))
            (paramBlock "packet" (list (pI "plen"))
              (list (st8 "tag1" "pkt" 0 "one") (st32 "plen32" "pkt" 1 "plen")
                               (if fold (appendAll (list (ex "copied" (ptr) "memcpy" (list "textP" "msg" "plen")))) (list))
                               (addK "total5" "plen" 5) (hp "wt" (i64) "writeAll" (list "wfd" "pkt" "total5")) (ex "tclosed" (i32) "close" (list "wfd32")) (i2p "tnullp" "z")
                               (ex "tflushed" (i32) "fflush" (list "tnullp")) (k32 "exitOne" 1) (ex "tgone" (i64) "_exit" (list "exitOne")))
              (ty/termUnreachable)))))))


fn seqMapFn c: ParCtx -> ty/SsaFunction
  (let [(jb (jmpBufBytes))]
    (function "seqMap" (list (pV "fn") (pV "xs")) (val)
      (list
        (block "entry" (list (k "z" 0) (k "one" 1) (k "total" (+ jb 4104)) (ex "prev" (ptr) "aslErrorHandlerGet" (list)) (ex "mem" (ptr) "calloc" (list "one" "total"))
                         (pr "memNull" (i1) "rawPtrIsNull" (list "mem")))
          (branch "memNull" "oom" "setup"))
        (raiseB c "oom" (list) "ERR_OOM" "parMap sequential state" (list))
        (block "setup" (list (p2i "memI" "mem") (addK "idxAt" "memI" jb) (addK "causeAt" "memI" (+ jb 8)) (ex "handled" (i64) "aslErrorHandlerSet" (list "mem"))
                         (ex "jumped" (i32) "setjmp" (list "mem")) (w64 "jumped64" "jumped") (cmp "caught" "neInt" "jumped64" "z"))
          (branch "caught" "failed" "begin"))
        (block "begin" (list (nilV "nil")) (jump "loop" (list "xs" "nil" "z")))
        (paramBlock "loop" (list (pV "cur") (pV "out") (pI "i")) (list (en "empty" (i1) "listEmpty?" (list "cur"))) (branch "empty" "finish" "step"))
        (block "step" (list (st "si" "idxAt" 0 "i") (en "head" (val) "@listFirst" (list "cur")) (vop "v" (ty/opCallClosure "fn" (list "head"))) (en "out1" (val) "cons" (list "v" "out"))
                        (en "rest" (val) "@listRest" (list "cur")) (addK "i1" "i" 1))
          (jump "loop" (list "rest" "out1" "i1")))
        (block "finish" (list (ex "restored" (i64) "aslErrorHandlerSet" (list "prev")) (ex "freed" (i64) "free" (list "mem")) (hp "r" (val) "reverse" (list "out"))) (returnTerm "r"))
        (raiseB c "failed"
          (list (ex "msg" (ptr) "aslParErrorMsg" (list)) (i2p "causeP" "causeAt") (k "causeSize" 4096) (cs c "pct" "%s")
                (ex "copied" (i32) "snprintf" (list "causeP" "causeSize" "pct" "msg")) (ld "idx" "idxAt" 0) (ex "restored2" (i64) "aslErrorHandlerSet" (list "prev")))
          "ERR_WORKER_TRAP" "parMap element %lld: %s" (list "idx" "causeP")))))

fn seqFoldFn -> ty/SsaFunction
  (function "seqFold" (list (pV "fn") (pV "init") (pV "xs")) (val)
    (list (block "entry" (list) (jump "loop" (list "xs" "init")))
          (paramBlock "loop" (list (pV "cur") (pV "acc")) (list (en "empty" (i1) "listEmpty?" (list "cur"))) (branch "empty" "done" "step"))
          (block "step" (list (en "head" (val) "@listFirst" (list "cur")) (vop "acc1" (ty/opCallClosure "fn" (list "acc" "head"))) (en "rest" (val) "@listRest" (list "cur")))
            (jump "loop" (list "rest" "acc1")))
          (block "done" (list) (returnTerm "acc"))))

fn freeFn name: String -> (List ty/SsaInstr)
  (appendAll (list (i2p (str "free." name ".p") name) (ex (str "free." name) (i64) "free" (list (str "free." name ".p")))))

fn freeBufsFn -> ty/SsaFunction
  (function "freeBufs" (list (pI "bufs") (pI "n")) (i64)
    (list (block "entry" (list (k "z" 0)) (jump "loop" (list "z")))
          (paramBlock "loop" (list (pI "j")) (list (cmp "done" "geInt" "j" "n")) (branch "done" "out" "one"))
          (block "one" (list (mulK "off" "j" (bufBytes)) (add "at" "bufs" "off") (ld "data" "at" 0) (freeFn "data") (addK "j1" "j" 1)) (jump "loop" (list "j1")))
          (block "out" (list (freeFn "bufs")) (returnTerm "z"))))

fn freeCtlFn -> ty/SsaFunction
  (function "freeCtl" (list (pI "ctl")) (i64)
    (list (block "entry" (list (k "z" 0) (ld "pids" "ctl" 8) (ld "rfds" "ctl" 16) (freeFn "pids") (freeFn "rfds") (freeFn "ctl")) (returnTerm "z"))))

fn workersFn c: ParCtx -> ty/SsaFunction
  (function "workers" (list (pI "mode") (pV "fn") (pV "init") (pV "xs") (pI "m") (pI "kn")) (i64)
    (list
      (block "entry" (list (k "z" 0) (cmp "isMap" "eqInt" "mode" "z") (mulK "tbytes" "kn" 4) (ex "pids" (ptr) "malloc" (list "tbytes")) (ex "rfds" (ptr) "malloc" (list "tbytes"))
                       (k "ctlBytes" 24) (ex "ctl" (ptr) "malloc" (list "ctlBytes")) (k "pairBytes" 8) (ex "fds" (ptr) "malloc" (list "pairBytes"))
                       (pr "n1" (i1) "rawPtrIsNull" (list "pids")) (pr "n2" (i1) "rawPtrIsNull" (list "rfds")) (pr "n3" (i1) "rawPtrIsNull" (list "ctl")) (pr "n4" (i1) "rawPtrIsNull" (list "fds"))
                       (orB "o1" "n1" "n2") (orB "o2" "o1" "n3") (orB "anyNull" "o2" "n4"))
        (branch "anyNull" "oom" "start"))
      (block "oom" (list (ex "f1" (i64) "free" (list "pids")) (ex "f2" (i64) "free" (list "rfds")) (ex "f3" (i64) "free" (list "ctl")) (ex "f4" (i64) "free" (list "fds")))
        (branch "isMap" "oomMap" "oomFold"))
      (raiseB c "oomMap" (list) "ERR_OOM" "parMap process tables" (list))
      (raiseB c "oomFold" (list) "ERR_OOM" "parFold process tables" (list))
      (block "start" (list (p2i "pidsI" "pids") (p2i "rfdsI" "rfds") (p2i "ctlI" "ctl") (p2i "fdsI" "fds") (st "s0" "ctlI" 0 "kn") (st "s8" "ctlI" 8 "pidsI") (st "s16" "ctlI" 16 "rfdsI")
                       (i2p "nullp" "z"))
        (jump "loop" (list "z")))
      (paramBlock "loop" (list (pI "kk")) (list (cmp "done" "geInt" "kk" "kn")) (branch "done" "finished" "pipeB"))
      (block "pipeB" (list (ex "pr" (i32) "pipe" (list "fds")) (w64 "pr64" "pr") (cmp "pfail" "neInt" "pr64" "z")) (argBranch "pfail" "fallback" (list "kk") "forkB" (list)))
      (block "forkB" (list (ldS32 "rd" "fdsI" 0) (ldS32 "wr" "fdsI" 4) (n32 "rd32" "rd") (n32 "wr32" "wr") (mul "km" "kk" "m") (pr "from" (i64) "quotInt" (list "km" "kn"))
                       (addK "kk1" "kk" 1) (mul "k1m" "kk1" "m") (pr "to" (i64) "quotInt" (list "k1m" "kn")) (ex "flushed" (i32) "fflush" (list "nullp"))
                       (hp "forced" (i1) "forced" (list)))
        (branch "forced" "forkFailed" "doFork"))
      (block "doFork" (list (ex "pid" (i32) "fork" (list)) (w64 "pid64" "pid") (cmp "forkNeg" "ltInt" "pid64" "z")) (branch "forkNeg" "forkFailed" "which"))
      (block "forkFailed" (list (ex "c1" (i32) "close" (list "rd32")) (ex "c2" (i32) "close" (list "wr32"))) (jump "fallback" (list "kk")))
      (block "which" (list (cmp "isChild" "eqInt" "pid64" "z")) (branch "isChild" "child" "parent"))
      (block "child" (list (ex "cr" (i32) "close" (list "rd32"))) (jump "cclose" (list "z")))
      (paramBlock "cclose" (list (pI "j")) (list (cmp "cdone" "geInt" "j" "kk")) (branch "cdone" "csig" "cstep"))
      (block "cstep" (list (mulK "joff" "j" 4) (add "jat" "rfdsI" "joff") (ldS32 "jfd" "jat" 0) (n32 "jfd32" "jfd") (ex "jc" (i32) "close" (list "jfd32")) (addK "j1" "j" 1)) (jump "cclose" (list "j1")))
      (block "csig" (list (k "dfl" (kf c "SIG_DFL")) (i2p "dflP" "dfl") (k32 "sPipe" (kf c "SIGPIPE")) (k32 "sInt" (kf c "SIGINT")) (k32 "sTerm" (kf c "SIGTERM"))
                      (ex "o1s" (ptr) "signal" (list "sPipe" "dflP")) (ex "o2s" (ptr) "signal" (list "sInt" "dflP")) (ex "o3s" (ptr) "signal" (list "sTerm" "dflP")))
        (branch "isMap" "runMap" "runFold"))
      (block "runMap" (list (hp "rm" (i64) "childMap" (list "fn" "init" "xs" "from" "to" "wr"))) (ty/termUnreachable))
      (block "runFold" (list (hp "rf" (i64) "childFold" (list "fn" "init" "xs" "from" "to" "wr"))) (ty/termUnreachable))
      (block "parent" (list (mulK "poff" "kk" 4) (add "pidAt" "pidsI" "poff") (st32 "sp" "pidAt" 0 "pid64") (add "rdAt" "rfdsI" "poff") (st32 "sr" "rdAt" 0 "rd")
                        (ex "pc" (i32) "close" (list "wr32")))
        (jump "loop" (list "kk1")))
      (paramBlock "fallback" (list (pI "started"))
        (list (hp "killed" (i64) "killAll" (list "pidsI" "rfdsI" "started")) (ex "f5" (i64) "free" (list "pids")) (ex "f6" (i64) "free" (list "rfds")) (ex "f7" (i64) "free" (list "ctl"))
              (ex "f8" (i64) "free" (list "fds")))
        (returnTerm "z"))
      (block "finished" (list (ex "f9" (i64) "free" (list "fds"))) (returnTerm "ctlI"))))

fn collectFn c: ParCtx -> ty/SsaFunction
  (let [(psz (kf c "pollfd.size")) (fdOff (kf c "pollfd.fd")) (evOff (kf c "pollfd.events"))]
    (function "collect" (list (pI "ctl") (pI "mode")) (i64)
      (list
        (block "entry" (list (k "z" 0) (k "m1" -1) (cmp "isMap" "eqInt" "mode" "z") (ld "kn" "ctl" 0) (ld "pids" "ctl" 8) (ld "rfds" "ctl" 16)
                         (mulK "pbytes" "kn" psz) (ex "pfds" (ptr) "malloc" (list "pbytes")) (addK "slots" "kn" 1) (k "bsize" (bufBytes)) (ex "bufs" (ptr) "calloc" (list "slots" "bsize"))
                         (k "rsize" 8200) (ex "rbuf" (ptr) "malloc" (list "rsize"))
                         (pr "n1" (i1) "rawPtrIsNull" (list "pfds")) (pr "n2" (i1) "rawPtrIsNull" (list "bufs")) (pr "n3" (i1) "rawPtrIsNull" (list "rbuf"))
                         (orB "o1" "n1" "n2") (orB "anyNull" "o1" "n3"))
          (branch "anyNull" "oom" "init0"))
        (block "oom" (list (hp "killed" (i64) "killAll" (list "pids" "rfds" "kn")) (ex "f1" (i64) "free" (list "pfds")) (ex "f2" (i64) "free" (list "bufs")) (ex "f3" (i64) "free" (list "rbuf"))
                       (hp "fc" (i64) "freeCtl" (list "ctl")))
          (branch "isMap" "oomMap" "oomFold"))
        (raiseB c "oomMap" (list) "ERR_OOM" "parMap poll buffers" (list))
        (raiseB c "oomFold" (list) "ERR_OOM" "parFold poll buffers" (list))
        (block "init0" (list (p2i "pfdsI" "pfds") (p2i "bufsI" "bufs") (p2i "rbufI" "rbuf") (addK "stAt" "rbufI" 8192)) (jump "init" (list "z")))
        (paramBlock "init" (list (pI "j")) (list (cmp "idone" "geInt" "j" "kn")) (branch "idone" "poll0" "initStep"))
        (block "initStep" (list (mulK "ioff" "j" psz) (add "iat" "pfdsI" "ioff") (mulK "foff" "j" 4) (add "fat" "rfds" "foff") (ldS32 "ifd" "fat" 0)
                            (st32 "sfd" "iat" fdOff "ifd") (k "pollin" (kf c "POLLIN")) (st32 "sev" "iat" evOff "pollin") (addK "j1" "j" 1))
          (jump "init" (list "j1")))
        (block "poll0" (list (k32 "forever" -1)) (jump "pollLoop" (list "kn" "m1" "m1")))
        (paramBlock "pollLoop" (list (pI "open") (pI "failed") (pI "over")) (list (cmp "noneOpen" "leInt" "open" "z")) (branch "noneOpen" "afterPoll" "doPoll"))
        (block "afterPoll" (list) (jump "after" (list "failed" "over")))
        (block "doPoll" (list (ex "pr" (i32) "poll" (list "pfds" "kn" "forever")) (w64 "pr64" "pr") (cmp "pneg" "ltInt" "pr64" "z")) (branch "pneg" "pollErr" "scan0"))
        (block "pollErr" (list (hp "pe" (i64) "errno" (list)) (cmpK "pintr" "eqInt" "pe" (kf c "EINTR"))) (argBranch "pintr" "pollLoop" (list "open" "failed" "over") "after" (list "failed" "over")))
        (block "scan0" (list) (jump "scan" (list "z" "open" "failed" "over")))
        (paramBlock "scan" (list (pI "kk") (pI "o") (pI "f") (pI "v")) (list (cmp "send" "geInt" "kk" "kn")) (argBranch "send" "pollLoop" (list "o" "f" "v") "look" (list)))
        (block "look" (list (addK "kk1" "kk" 1) (mulK "loff" "kk" psz) (add "at" "pfdsI" "loff") (ldS32 "fd" "at" fdOff) (cmp "fdNeg" "ltInt" "fd" "z"))
          (argBranch "fdNeg" "scan" (list "kk1" "o" "f" "v") "check" (list)))
        (block "check" (list (ldU32 "ev" "at" evOff) (shrK "rev" "ev" 16) (k "mask" (+ (kf c "POLLIN") (+ (kf c "POLLHUP") (kf c "POLLERR"))))
                         (pr "hitBits" (i64) "rawAndI64" (list "rev" "mask")) (cmp "hit" "neInt" "hitBits" "z"))
          (argBranch "hit" "readB" (list) "scan" (list "kk1" "o" "f" "v")))
        (block "readB" (list (n32 "fd32" "fd") (k "chunk" 8192) (ex "r" (i64) "read" (list "fd32" "rbuf" "chunk")) (cmp "gotSome" "gtInt" "r" "z")) (branch "gotSome" "got" "noData"))
        (block "got" (list (mulK "boff" "kk" (bufBytes)) (add "buf" "bufsI" "boff") (hp "sw" (i64) "serWrite" (list "buf" "rbufI" "r")) (ld "berr" "buf" 24) (cmp "bbad" "neInt" "berr" "z"))
          (argBranch "bbad" "overB" (list) "failCheck" (list "v")))
        (block "overB" (list (cmp "vneg" "ltInt" "v" "z")) (argBranch "vneg" "overSet" (list "kk") "overKeep" (list)))
        (block "overKeep" (list) (jump "overSet" (list "v")))
        (paramBlock "overSet" (list (pI "nv")) (list (hp "ko" (i64) "killOthers" (list "pids" "kn" "kk"))) (jump "failCheck" (list "nv")))
        (paramBlock "failCheck" (list (pI "v2")) (list (ld "blen" "buf" 8) (cmpK "long" "geInt" "blen" 5)) (argBranch "long" "firstByte" (list) "scan" (list "kk1" "o" "f" "v2")))
        (block "firstByte" (list (ld "bdata" "buf" 0) (ldU8 "b0" "bdata" 0) (cmpK "is1" "eqInt" "b0" 1)) (argBranch "is1" "failSet" (list) "scan" (list "kk1" "o" "f" "v2")))
        (block "failSet" (list (cmp "fneg" "ltInt" "f" "z")) (argBranch "fneg" "failKill" (list "kk") "failKeep" (list)))
        (block "failKeep" (list) (jump "failKill" (list "f")))
        (paramBlock "failKill" (list (pI "nf")) (list (hp "kf" (i64) "killOthers" (list "pids" "kn" "kk"))) (jump "scan" (list "kk1" "o" "nf" "v2")))
        (block "noData" (list (cmp "eof" "eqInt" "r" "z")) (branch "eof" "closeFd" "readErr"))
        (block "readErr" (list (hp "re" (i64) "errno" (list)) (cmpK "rintr" "eqInt" "re" (kf c "EINTR")) (cmpK "ragain" "eqInt" "re" (kf c "EAGAIN")) (orB "retry" "rintr" "ragain"))
          (argBranch "retry" "scan" (list "kk1" "o" "f" "v") "closeFd" (list)))
        (block "closeFd" (list (ex "cl" (i32) "close" (list "fd32")) (st32 "sneg" "at" fdOff "m1") (addK "o1c" "o" -1)) (jump "scan" (list "kk1" "o1c" "f" "v")))
        (paramBlock "after" (list (pI "af") (pI "av")) (list (cmp "afneg" "ltInt" "af" "z")) (argBranch "afneg" "findFail" (list "z") "reap0" (list "af")))
        (paramBlock "findFail" (list (pI "fj")) (list (cmp "fdone" "geInt" "fj" "kn")) (argBranch "fdone" "reap0" (list "m1") "findOne" (list)))
        (block "findOne" (list (addK "fj1" "fj" 1) (mulK "fboff" "fj" (bufBytes)) (add "fbuf" "bufsI" "fboff") (ld "fblen" "fbuf" 8) (cmpK "flong" "geInt" "fblen" 5))
          (argBranch "flong" "findByte" (list) "findFail" (list "fj1")))
        (block "findByte" (list (ld "fbdata" "fbuf" 0) (ldU8 "fb0" "fbdata" 0) (cmpK "fis1" "eqInt" "fb0" 1)) (argBranch "fis1" "reap0" (list "fj") "findFail" (list "fj1")))
        (paramBlock "reap0" (list (pI "ff")) (list) (jump "reapLoop" (list "z" "m1" "z" "z")))
        (paramBlock "reapLoop" (list (pI "rj") (pI "oth") (pI "osig") (pI "oexit")) (list (cmp "rdone" "geInt" "rj" "kn")) (branch "rdone" "decide" "reapOne"))
        (block "reapOne" (list (addK "rj1" "rj" 1) (mulK "roff" "rj" psz) (add "rat" "pfdsI" "roff") (ldS32 "rfd" "rat" fdOff) (cmp "ropen" "geInt" "rfd" "z")) (branch "ropen" "closeIt" "waitIt"))
        (block "closeIt" (list (n32 "rfd32" "rfd") (ex "rcl" (i32) "close" (list "rfd32"))) (jump "waitIt" (list)))
        (block "waitIt" (list (mulK "rpoff" "rj" 4) (add "rpidAt" "pids" "rpoff") (ldS32 "rpid" "rpidAt" 0) (st32 "st0" "stAt" 0 "z") (hp "reaped" (i64) "reap" (list "rpid" "stAt"))
                          (ldS32 "status" "stAt" 0) (cmp "noFail" "ltInt" "ff" "z") (cmp "noOther" "ltInt" "oth" "z") (andB "consider" "noFail" "noOther"))
          (argBranch "consider" "classify" (list) "reapLoop" (list "rj1" "oth" "osig" "oexit")))
        (block "classify" (list (bandK "sig" "status" 127) (cmp "sigNz" "neInt" "sig" "z") (cmpK "not7f" "neInt" "sig" 127) (andB "signaled" "sigNz" "not7f"))
          (argBranch "signaled" "reapLoop" (list "rj1" "rj" "sig" "oexit") "exitCheck" (list)))
        (block "exitCheck" (list (cmp "exited" "eqInt" "sig" "z") (shrK "hi" "status" 8) (bandK "code" "hi" 255) (cmp "codeNz" "neInt" "code" "z") (andB "badExit" "exited" "codeNz"))
          (argBranch "badExit" "reapLoop" (list "rj1" "rj" "osig" "code") "reapLoop" (list "rj1" "oth" "osig" "oexit")))
        (block "decide" (list (cmp "overflowed" "geInt" "av" "z")) (branch "overflowed" "overRaise" "checkFailed"))
        (raiseB c "overRaise" (list (hp "fb1" (i64) "freeBufs" (list "bufsI" "kn")) (hp "fc1" (i64) "freeCtl" (list "ctl")) (ex "fp1" (i64) "free" (list "pfds")) (ex "fr1" (i64) "free" (list "rbuf")))
          "ERR_SERIALIZE_SIZE" "worker %lld response exceeds serialization size limit" (list "av"))
        (block "checkFailed" (list (cmp "hasFailed" "geInt" "ff" "z")) (branch "hasFailed" "failMsg" "checkOther"))
        (block "failMsg" (list (mulK "mboff" "ff" (bufBytes)) (add "mbuf" "bufsI" "mboff") (ld "mdata" "mbuf" 0) (ld "mlen" "mbuf" 8) (ldU32 "mraw" "mdata" 1) (cmpK "mbig" "gtInt" "mraw" 1023) (k "cap1023" 1023))
          (argBranch "mbig" "msgLen" (list "cap1023") "msgLen" (list "mraw")))
        (paramBlock "msgLen" (list (pI "ml")) (list (cmp "mnz" "neInt" "ml" "z") (addK "mlenLess" "mlen" -5) (cmp "mfits" "leInt" "ml" "mlenLess") (andB "mok" "mnz" "mfits"))
          (branch "mok" "copyMsg" "reported"))
        (block "copyMsg" (list (addK "msrc" "mdata" 5) (i2p "msrcP" "msrc") (ex "mcopied" (ptr) "memcpy" (list "rbuf" "msrcP" "ml")) (add "mend" "rbufI" "ml") (st8 "mnul" "mend" 0 "z")
                           (ldU8 "mfirst" "rbufI" 0) (cmp "mempty" "eqInt" "mfirst" "z")
                           (hp "fb2" (i64) "freeBufs" (list "bufsI" "kn")) (hp "fc2" (i64) "freeCtl" (list "ctl")) (ex "fp2" (i64) "free" (list "pfds")))
          (branch "mempty" "trappedRaise" "msgRaise"))
        (raiseB c "msgRaise" (list (ex "mstr" (val) "mkStr" (list "rbuf" "ml")) (ex "frm" (i64) "free" (list "rbuf")) (payload "mso" "mstr") (addK "msi" "mso" 16) (i2p "msp" "msi"))
          "ERR_WORKER_TRAP" "%s" (list "msp"))
        (raiseB c "trappedRaise" (list (ex "frt" (i64) "free" (list "rbuf"))) "ERR_WORKER_TRAP" "worker trapped" (list))
        (raiseB c "reported" (list (hp "fb3" (i64) "freeBufs" (list "bufsI" "kn")) (hp "fc3" (i64) "freeCtl" (list "ctl")) (ex "fp3" (i64) "free" (list "pfds")) (ex "fr3" (i64) "free" (list "rbuf")))
          "ERR_WORKER_TRAP" "worker %lld reported error" (list "ff"))
        (block "checkOther" (list (cmp "hasOther" "geInt" "oth" "z")) (branch "hasOther" "otherB" "ok"))
        (block "otherB" (list (hp "fb4" (i64) "freeBufs" (list "bufsI" "kn")) (hp "fc4" (i64) "freeCtl" (list "ctl")) (ex "fp4" (i64) "free" (list "pfds")) (ex "fr4" (i64) "free" (list "rbuf"))
                          (cmp "bySig" "neInt" "osig" "z"))
          (branch "bySig" "sigRaise" "exitRaise"))
        (raiseB c "sigRaise" (list) "ERR_WORKER_TRAP" "worker %lld killed by signal %lld" (list "oth" "osig"))
        (raiseB c "exitRaise" (list) "ERR_WORKER_TRAP" "worker %lld exited with code %lld" (list "oth" "oexit"))
        (block "ok" (list (ex "fp5" (i64) "free" (list "pfds")) (ex "fr5" (i64) "free" (list "rbuf"))) (returnTerm "bufsI")))))

fn kSlotsBlocks next: String -> (List ty/SsaBlock)
  (list (block "workersK" (list (cmp "fewer" "ltInt" "slots" "m")) (argBranch "fewer" "cap1" (list "slots") "cap1m" (list)))
        (block "cap1m" (list) (jump "cap1" (list "m")))
        (paramBlock "cap1" (list (pI "k0")) (list (k "most" 256) (cmp "big" "gtInt" "k0" "most")) (argBranch "big" next (list "most") "cap2keep" (list)))
        (block "cap2keep" (list) (jump next (list "k0"))))

fn listGuardBlocks c: ParCtx who: String next: String -> (List ty/SsaBlock)
  (list (block "listCheck" (list (tagOf "tag" "xs") (cmpK "isList" "eqInt" "tag" (tagList))) (branch "isList" next "typeErr"))
        (raiseB c "typeErr" (list (cs c "whoP" who) (k32 "listTag" (tagList)) (ex "lt" (ptr) "tagName" (list "listTag")) (n32 "tag32" "tag") (ex "tt" (ptr) "tagName" (list "tag32")))
          "ERR_TYPE" "%s expects %s, got %s" (list "whoP" "lt" "tt")))

fn ctxBlock label: String bufs: String kn: String kk: String next: String -> ty/SsaBlock
  (block label (list (mulK "boff" kk (bufBytes)) (add "buf" bufs "boff") (mulK "dctxOff" kn (bufBytes)) (add "d" bufs "dctxOff") (ld "bdata" "buf" 0) (ld "blen" "buf" 8)
                 (st "sd0" "d" 0 "bdata") (st "sd8" "d" 8 "z") (st "sd16" "d" 16 "blen") (st "sd24" "d" 24 "z") (addK "kk1" kk 1))
    (jump next (list)))

fn mapRunFn c: ParCtx -> ty/SsaFunction
  (function "mapRun" (list (pV "fn") (pV "xs") (pI "slots")) (val)
    (appendAll
      (list
        (list (block "entry" (list (k "z" 0) (k "one" 1) (k "eight" 8) (cmp "nonPos" "leInt" "slots" "z")) (branch "nonPos" "argErr" "listCheck"))
              (raiseB c "argErr" (list) "ERR_ARG" "parMap slots must be positive, got %lld" (list "slots")))
        (listGuardBlocks c "parMap" "counted")
        (list (block "counted" (list (hp "m" (i64) "count" (list "xs")) (cmp "none" "eqInt" "m" "z")) (branch "none" "nilRet" "workersK"))
              (block "nilRet" (list (nilV "nil0")) (returnTerm "nil0")))
        (kSlotsBlocks "decideK")
        (list (paramBlock "decideK" (list (pI "kn")) (list (cmpK "single" "leInt" "kn" 1)) (branch "single" "seqB" "par"))
              (block "seqB" (list (hp "sr" (val) "seqMap" (list "fn" "xs"))) (returnTerm "sr"))
              (block "par" (list (unitV "noInit") (hp "ctl" (i64) "workers" (list "z" "fn" "noInit" "xs" "m" "kn")) (cmp "fell" "eqInt" "ctl" "z")) (branch "fell" "seqB" "gather"))
              (block "gather" (list (hp "bufs" (i64) "collect" (list "ctl" "z")) (nilV "nil")) (jump "chunk" (list "z" "nil")))
              (paramBlock "chunk" (list (pI "kk") (pV "out")) (list (cmp "cdone" "geInt" "kk" "kn")) (branch "cdone" "finish" "chunkStart"))
              (ctxBlock "chunkStart" "bufs" "kn" "kk" "header")
              (block "header" (list (mul "km" "kk" "m") (pr "from" (i64) "quotInt" (list "km" "kn")) (mul "k1m" "kk1" "m") (pr "to" (i64) "quotInt" (list "k1m" "kn")) (sub "cnt" "to" "from")
                                (hp "status" (i64) "deserNum" (list "d" "one")) (hp "ck" (i64) "deserNum" (list "d" "eight")) (ld "herr" "d" 24)
                                (cmp "b1" "neInt" "status" "z") (cmp "b2" "neInt" "ck" "cnt") (cmp "b3" "neInt" "herr" "z") (orB "b12" "b1" "b2") (orB "hbad" "b12" "b3"))
                (argBranch "hbad" "corrupt" (list) "items" (list "z" "out")))
              (raiseB c "corrupt" (list (hp "fb1" (i64) "freeBufs" (list "bufs" "kn")) (hp "fc1" (i64) "freeCtl" (list "ctl"))) "ERR_WORKER_TRAP" "worker %lld sent corrupted data" (list "kk"))
              (paramBlock "items" (list (pI "i") (pV "acc")) (list (cmp "idone" "geInt" "i" "cnt")) (argBranch "idone" "chunk" (list "kk1" "acc") "item" (list)))
              (block "item" (list (hp "v" (val) "deserVal" (list "d" "z")) (ld "verr" "d" 24) (cmp "vbad" "neInt" "verr" "z")) (branch "vbad" "itemErr" "push"))
              (raiseB c "itemErr" (list (hp "fb2" (i64) "freeBufs" (list "bufs" "kn")) (hp "fc2" (i64) "freeCtl" (list "ctl")))
                "ERR_WORKER_TRAP" "deserialization error on worker %lld item %lld" (list "kk" "i"))
              (block "push" (list (en "acc1" (val) "cons" (list "v" "acc")) (addK "i1" "i" 1)) (jump "items" (list "i1" "acc1")))
              (block "finish" (list (hp "fb3" (i64) "freeBufs" (list "bufs" "kn")) (hp "fc3" (i64) "freeCtl" (list "ctl")) (hp "r" (val) "reverse" (list "out"))) (returnTerm "r"))))))

fn foldRunFn c: ParCtx -> ty/SsaFunction
  (function "foldRun" (list (pV "step") (pV "combine") (pV "init") (pV "xs") (pI "slots")) (val)
    (appendAll
      (list
        (list (block "entry" (list (k "z" 0) (k "one" 1) (cmp "nonPos" "leInt" "slots" "z")) (branch "nonPos" "argErr" "listCheck"))
              (raiseB c "argErr" (list) "ERR_ARG" "parFold slots must be positive, got %lld" (list "slots")))
        (listGuardBlocks c "parFold" "counted")
        (list (block "counted" (list (hp "m" (i64) "count" (list "xs")) (cmp "none" "eqInt" "m" "z")) (branch "none" "initRet" "workersK"))
              (block "initRet" (list) (returnTerm "init")))
        (kSlotsBlocks "decideK")
        (list (paramBlock "decideK" (list (pI "kn")) (list (cmpK "single" "leInt" "kn" 1)) (branch "single" "seqB" "par"))
              (block "seqB" (list (hp "sr" (val) "seqFold" (list "step" "init" "xs"))) (returnTerm "sr"))
              (block "par" (list (hp "ctl" (i64) "workers" (list "one" "step" "init" "xs" "m" "kn")) (cmp "fell" "eqInt" "ctl" "z")) (branch "fell" "seqB" "gather"))
              (block "gather" (list (hp "bufs" (i64) "collect" (list "ctl" "one")) (nilV "nil")) (jump "chunk" (list "z" "nil")))
              (paramBlock "chunk" (list (pI "kk") (pV "accs")) (list (cmp "cdone" "geInt" "kk" "kn")) (branch "cdone" "combine0" "chunkStart"))
              (ctxBlock "chunkStart" "bufs" "kn" "kk" "header")
              (block "header" (list (hp "status" (i64) "deserNum" (list "d" "one")) (ld "herr" "d" 24) (cmp "b1" "neInt" "status" "z") (cmp "b2" "neInt" "herr" "z") (orB "hbad" "b1" "b2"))
                (branch "hbad" "corrupt" "value"))
              (raiseB c "corrupt" (list (hp "fb1" (i64) "freeBufs" (list "bufs" "kn")) (hp "fc1" (i64) "freeCtl" (list "ctl"))) "ERR_WORKER_TRAP" "worker %lld sent corrupted fold data" (list "kk"))
              (block "value" (list (hp "a" (val) "deserVal" (list "d" "z")) (ld "verr" "d" 24) (cmp "vbad" "neInt" "verr" "z")) (branch "vbad" "valueErr" "push"))
              (raiseB c "valueErr" (list (hp "fb2" (i64) "freeBufs" (list "bufs" "kn")) (hp "fc2" (i64) "freeCtl" (list "ctl")))
                "ERR_WORKER_TRAP" "deserialization error on worker %lld fold accumulator" (list "kk"))
              (block "push" (list (en "accs1" (val) "cons" (list "a" "accs"))) (jump "chunk" (list "kk1" "accs1")))
              (block "combine0" (list (hp "fb3" (i64) "freeBufs" (list "bufs" "kn")) (hp "fc3" (i64) "freeCtl" (list "ctl")) (hp "ordered" (val) "reverse" (list "accs"))
                                  (en "first" (val) "@listFirst" (list "ordered")) (en "others" (val) "@listRest" (list "ordered")))
                (jump "comb" (list "others" "first")))
              (paramBlock "comb" (list (pV "cur") (pV "res")) (list (en "empty" (i1) "listEmpty?" (list "cur"))) (branch "empty" "done" "combStep"))
              (block "combStep" (list (en "x" (val) "@listFirst" (list "cur")) (vop "res1" (ty/opCallClosure "combine" (list "res" "x"))) (en "rest" (val) "@listRest" (list "cur")))
                (jump "comb" (list "rest" "res1")))
              (block "done" (list) (returnTerm "res"))))))

fn valParams n: Int64 -> (List ty/SsaParam)
  (map (fn [(i Int64)] -> ty/SsaParam (pV (str "a" (stringFromInt64 i)))) (range 0 n))

fn arityFn c: ParCtx builtin: String argc: Int64 -> ty/SsaFunction
  (let [(fmt (cond ((= builtin "parFold") "parFold expects 4 or 5 arguments, got %lld")
                   ((< argc 2) "parMap expects at least 2 arguments, got %lld")
                   (else "parMap expects 2 or 3 arguments, got %lld")))]
    (ty/ssaFunction (wrapperName builtin argc) (list) (valParams argc) (val)
      (list (block "entry" (list (k "n" argc)) (jump "raise" (list)))
            (raiseB c "raise" (list) "ERR_ARITY" fmt (list "n")))))

fn wrapperFn c: ParCtx builtin: String argc: Int64 -> ty/SsaFunction
  (cond
    ((and (= builtin "parMap") (= argc 2))
      (ty/ssaFunction (wrapperName builtin argc) (list) (valParams 2) (val)
        (list (block "entry" (list (hp "slots" (i64) "cpuCount" (list)) (hp "r" (val) "mapRun" (list "a0" "a1" "slots"))) (returnTerm "r")))))
    ((and (= builtin "parMap") (= argc 3))
      (ty/ssaFunction (wrapperName builtin argc) (list) (valParams 3) (val)
        (list (block "entry" (list (tagOf "t0" "a0") (cmpK "first" "eqInt" "t0" (tagInt))) (branch "first" "slotsFirst" "tryLast"))
              (block "slotsFirst" (list (payload "s0" "a0") (hp "r0" (val) "mapRun" (list "a1" "a2" "s0"))) (returnTerm "r0"))
              (block "tryLast" (list (tagOf "t2" "a2") (cmpK "last" "eqInt" "t2" (tagInt))) (branch "last" "slotsLast" "shape"))
              (block "slotsLast" (list (payload "s2" "a2") (hp "r2" (val) "mapRun" (list "a0" "a1" "s2"))) (returnTerm "r2"))
              (raiseB c "shape" (list) "ERR_TYPE" "parMap expects (parMap fn list [slots]) or (parMap slots fn list)" (list)))))
    ((and (= builtin "parFold") (= argc 4))
      (ty/ssaFunction (wrapperName builtin argc) (list) (valParams 4) (val)
        (list (block "entry" (list (hp "slots" (i64) "cpuCount" (list)) (hp "r" (val) "foldRun" (list "a0" "a1" "a2" "a3" "slots"))) (returnTerm "r")))))
    ((and (= builtin "parFold") (= argc 5))
      (ty/ssaFunction (wrapperName builtin argc) (list) (valParams 5) (val)
        (list (block "entry" (list (tagOf "t4" "a4") (cmpK "isInt" "eqInt" "t4" (tagInt))) (branch "isInt" "run" "typeErr"))
              (block "run" (list (payload "s4" "a4") (hp "r" (val) "foldRun" (list "a0" "a1" "a2" "a3" "s4"))) (returnTerm "r"))
              (raiseB c "typeErr" (list (cs c "whoP" "parFold slots") (k32 "intTag" (tagInt)) (ex "it" (ptr) "tagName" (list "intTag")) (n32 "t32" "t4") (ex "tt" (ptr) "tagName" (list "t32")))
                "ERR_TYPE" "%s expects %s, got %s" (list "whoP" "it" "tt")))))
    (else (arityFn c builtin argc)))

fn parFunctions facts: libc/TripleFacts pool: (Map String Int64) calls: (List (Pair String Int64)) -> (Result (List ty/SsaFunction) String)
  (mt (parFacts facts)
    ((err e) (err e))
    ((ok kmap)
      (let [(c (ParCtx :k kmap :pool pool :errno facts.errnoAccessor))]
        (ok (listAppend
              (list (errnoFn c) (cpuCountFn c) (forcedFn c) (countFn) (reverseFn) (dropFn) (writeAllFn c) (reapFn c) (killAllFn c) (killOthersFn c)
                    (serWriteFn) (serNumFn) (serValFn) (deserHasFn) (deserNumFn) (internKeysFn) (keyTableInitFn c) (newArrayFn c) (deserValFn)
                    (childFn c false) (childFn c true) (seqMapFn c) (seqFoldFn) (freeBufsFn) (freeCtlFn) (workersFn c) (collectFn c) (mapRunFn c) (foldRunFn c))
              (map (fn [(p (Pair String Int64))] -> ty/SsaFunction (wrapperFn c (pairFirst p) (pairSecond p))) calls))))))
