(module asl-target-llvm/sysRoute
  :x [RouteTable Routed routeTables tableBuiltins wrapperName routes? routeModule tripleOf routeFactsFor hostFactsOf routeHost! internalize routeConst signalNames errKinds tagGuardText]
  :i [(asl-ir/types :a ty)
      (asl-ir/verify :a vfy)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sys :a sys)
      (asl-target-llvm/sysNet :a sysNet)
      (asl-target-llvm/sysProc :a proc)
      (asl-target-llvm/ssa :a ssa)])

(enum RouteTable
  (:c sysNetTable [] "tcpListen, tcpConnect, sockAccept, sockLocalPort, unixListen and unixConnect over asl-target-llvm/sysNet, in place of asl/host/src/sysNet.c's table, and unixSocketPair, sockSendFd and sockRecvFd (SCM_RIGHTS descriptor passing), native only")
  (:c sysTable [] "fdRead, fdWrite, fdClose, fdPoll, fdNonBlocking, cpuCount, platformInfo, localDate, envList, procSelf, procAlive?, procKill and procExePath over asl-target-llvm/sys and libc externs, in place of those 13 rows of asl/host/src/sys.c's table")
  (:c clockTable [] "nowNs, monotonicNs and sleepMs over asl-target-llvm/sys clock_gettime and nanosleep (PRELUDEASL-A), in place of those 3 rows of asl/host/src/prelude.c's core table: a table of its own so a program that only reads a clock carries a handful of functions, not the sys table"))

schema Routed
  result: ty/SsaModule
  internal: (List String)

fn routeTables -> (List RouteTable)
  (list (sysNetTable) (sysTable) (clockTable))

fn tableBuiltins t: RouteTable -> (List String)
  (mt t
    ((sysNetTable) (list "tcpListen" "tcpConnect" "sockAccept" "sockLocalPort" "unixListen" "unixConnect" "unixSocketPair" "sockSendFd" "sockRecvFd"))
    ((sysTable) (listAppend (list "fdRead" "fdWrite" "fdClose" "fdPoll" "fdNonBlocking" "cpuCount" "platformInfo" "localDate" "envList" "procSelf" "procAlive?" "procKill" "procExePath")
                  (listAppend (sys/fileRouteBuiltins) (proc/procRouteBuiltins))))
    ((clockTable) (list "nowNs" "monotonicNs" "sleepMs")))

fn tableExterns facts: libc/TripleFacts t: RouteTable -> (List ty/SsaExtern)
  (mt t
    ((sysNetTable) (sysNet/sysNetExterns facts))
    ((sysTable) (listAppend (sys/sysExterns facts) (cons (absExtern) (listAppend (environExterns facts) (listAppend (sys/fileRouteExterns facts) (proc/procRouteExterns facts))))))
    ((clockTable) (listAppend (sys/sysExterns facts) (list (absExtern) (ty/ssaExternTyped "strerror" (list (ty/tyI32)) (ty/tyPtr))))))

fn tableStrings t: RouteTable -> (List String)
  (mt t
    ((sysNetTable) (list "io:"))
    ((sysTable) (listAppend (sysStrings) (listAppend (sys/fileRouteStrings) (proc/procRouteStrings))))
    ((clockTable) (clockStrings)))

fn tableTypes t: RouteTable -> (List ty/SsaTypeDecl)
  (mt t
    ((sysNetTable) (list (sys/resultTypeDecl) (sys/optionTypeDecl) (pairTypeDecl)))
    ((sysTable) (list (sys/resultTypeDecl) (sys/optionTypeDecl) (pairTypeDecl)))
    ((clockTable) (list (sys/resultTypeDecl))))

fn tableRecords t: RouteTable -> (List ty/SsaRecordDecl)
  (mt t
    ((sysNetTable) (list))
    ((sysTable) (cons (platformInfoDecl) (listAppend (sys/fileRouteRecords) (proc/procRouteRecords))))
    ((clockTable) (list)))

fn tableGlobals t: RouteTable -> (List ty/SsaGlobal)
  (mt t
    ((sysNetTable) (list))
    ((sysTable) (listAppend (sys/fileRouteGlobals) (proc/procPreludeGlobals)))
    ((clockTable) (list)))

fn tableFunctions facts: libc/TripleFacts t: RouteTable pool: (Map String Int64) -> (Result (List ty/SsaFunction) String)
  (mt t
    ((sysNetTable)
      (mt (sysNet/sysNetFunctions facts)
        ((err e) (err e))
        ((ok raw) (mt (netWrappers facts (poolAt pool "io:"))
                    ((err e) (err e))
                    ((ok wrappers) (ok (listAppend raw wrappers)))))))
    ((sysTable) (sysTableAll facts pool))
    ((clockTable) (clockTableFunctions facts pool)))

fn wrapperName builtin: String -> String
  (str "asl-target-llvm/sysRoute." builtin)

fn int32Max -> Int64
  2147483647

fn netWrappers facts: libc/TripleFacts ioIndex: Int64 -> (Result (List ty/SsaFunction) String)
  (mt (libc/libcConst facts "EINVAL")
    ((none) (err (str "libc.asl has no EINVAL const row for triple " facts.triple)))
    ((some einval)
      (ok (list (intWrapper "tcpListen" "sysNetTcpListen" 0 65535 einval ioIndex)
                (intWrapper "tcpConnect" "sysNetTcpConnect" 1 65535 einval ioIndex)
                (intWrapper "sockAccept" "sysNetSockAccept" 0 (int32Max) einval ioIndex)
                (intWrapper "sockLocalPort" "sysNetSockLocalPort" 0 (int32Max) einval ioIndex)
                (pathWrapper "unixListen" "sysNetUnixListen" einval ioIndex)
                (pathWrapper "unixConnect" "sysNetUnixConnect" einval ioIndex)
                (unitWrapper "unixSocketPair" "sysNetSocketPair" einval ioIndex)
                (intPairWrapper "sockSendFd" "sysNetSendFd" 0 (int32Max) einval ioIndex)
                (intWrapper "sockRecvFd" "sysNetRecvFd" 0 (int32Max) einval ioIndex)))))

fn valInstr dest: String op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) op)

fn showInstr dest: String v: String -> ty/SsaInstr
  (valInstr dest (ty/opBuiltin "str" (list v)))

fn sameReprInstrs prefix: String a: String b: String -> (List ty/SsaInstr)
  (list (valInstr (str prefix ".aList") (ty/opList (list a)))
        (valInstr (str prefix ".bList") (ty/opList (list b)))
        (showInstr (str prefix ".aRepr") (str prefix ".aList"))
        (showInstr (str prefix ".bRepr") (str prefix ".bList"))
        (sys/entryInstr (str prefix ".same") (ty/tyI1) "=" (list (str prefix ".aRepr") (str prefix ".bRepr"))))

fn resultBlocks einval: Int64 ioIndex: Int64 -> (List ty/SsaBlock)
  (list
    (sys/block "isOk" (list) (ty/termReturn "res"))
    (sys/block "isErr"
      (list (valInstr "errnoBox" (ty/opVariantField "res" 0))
            (ty/ssaInstr "errno" (ty/tyI64) (ty/opUnbox "errnoBox")))
      (ty/termJump (ty/ssaEdge "fail" (list "errno"))))
    (sys/block "bad"
      (list (sys/int64Const "einval" einval))
      (ty/termJump (ty/ssaEdge "fail" (list "einval"))))
    (ty/ssaBlock "fail" (list (ty/ssaParam "code" (ty/tyI64)))
      (list (sys/entryInstr "digits" (ty/tyVal) "stringFromInt64" (list "code"))
            (valInstr "prefix" (ty/opConst (ty/constStr ioIndex)))
            (sys/entryInstr "message" (ty/tyVal) "stringConcat" (list "prefix" "digits"))
            (valInstr "failed" (ty/opConstruct "Result" "err" (list "message"))))
      (ty/termReturn "failed")))

fn resultSwitch -> ty/SsaTerm
  (ty/termSwitch "res" "Result" (list (ty/ssaCase "ok" (sys/edgeTo "isOk")) (ty/ssaCase "err" (sys/edgeTo "isErr"))) (none))

fn intWrapper builtin: String callee: String lo: Int64 hi: Int64 einval: Int64 ioIndex: Int64 -> ty/SsaFunction
  (ty/ssaFunction (wrapperName builtin) (list) (list (ty/ssaParam "arg" (ty/tyVal))) (ty/tyVal)
    (listAppend (intCheckBlocks "arg" "arg" lo hi "call")
      (cons
        (sys/block "call"
          (list (sys/primInstr "arg.n32" (ty/tyI32) "rawNarrowI32" (list "arg.n"))
                (sys/callInstr "res" (ty/tyVal) callee (list "arg.n32")))
          (resultSwitch))
        (resultBlocks einval ioIndex))))

fn pathWrapper builtin: String callee: String einval: Int64 ioIndex: Int64 -> ty/SsaFunction
  (ty/ssaFunction (wrapperName builtin) (list) (list (ty/ssaParam "arg" (ty/tyVal))) (ty/tyVal)
    (listAppend
      (list
        (sys/block "entry"
          (cons (showInstr "shown" "arg") (sameReprInstrs "string" "arg" "shown"))
          (ty/termBranch "string.same" (sys/edgeTo "call") (sys/edgeTo "bad")))
        (sys/block "call"
          (list (sys/callInstr "res" (ty/tyVal) callee (list "arg")))
          (resultSwitch)))
      (resultBlocks einval ioIndex)))

fn intCheckBlocks prefix: String arg: String lo: Int64 hi: Int64 goodLabel: String -> (List ty/SsaBlock)
  (list
    (sys/block (str prefix ".entry")
      (list (showInstr (str prefix ".shown") arg)
            (sys/entryInstr (str prefix ".parsed") (ty/tyVal) "stringToFloat64" (list (str prefix ".shown"))))
      (ty/termSwitch (str prefix ".parsed") "Option" (list (ty/ssaCase "some" (sys/edgeTo (str prefix ".number"))) (ty/ssaCase "none" (sys/edgeTo "bad"))) (none)))
    (sys/block (str prefix ".number")
      (list (valInstr (str prefix ".fBox") (ty/opVariantField (str prefix ".parsed") 0))
            (ty/ssaInstr (str prefix ".f") (ty/tyF64) (ty/opUnbox (str prefix ".fBox")))
            (ty/ssaInstr (str prefix ".lo") (ty/tyF64) (ty/opConst (ty/constFloat (int64ToFloat64 lo))))
            (ty/ssaInstr (str prefix ".hi") (ty/tyF64) (ty/opConst (ty/constFloat (int64ToFloat64 hi))))
            (sys/primInstr (str prefix ".aboveLo") (ty/tyI1) "geFloat" (list (str prefix ".f") (str prefix ".lo")))
            (sys/primInstr (str prefix ".belowHi") (ty/tyI1) "leFloat" (list (str prefix ".f") (str prefix ".hi")))
            (sys/primInstr (str prefix ".inRange") (ty/tyI1) "andBool" (list (str prefix ".aboveLo") (str prefix ".belowHi"))))
      (ty/termBranch (str prefix ".inRange") (sys/edgeTo (str prefix ".whole")) (sys/edgeTo "bad")))
    (sys/block (str prefix ".whole")
      (listAppend
        (list (sys/primInstr (str prefix ".n") (ty/tyI64) "floatToInt" (list (str prefix ".f")))
              (sys/boxInstr (str prefix ".nBox") (str prefix ".n")))
        (sameReprInstrs (str prefix ".int") arg (str prefix ".nBox")))
      (ty/termBranch (str prefix ".int.same") (sys/edgeTo goodLabel) (sys/edgeTo "bad"))))

fn intPairWrapper builtin: String callee: String lo: Int64 hi: Int64 einval: Int64 ioIndex: Int64 -> ty/SsaFunction
  (ty/ssaFunction (wrapperName builtin) (list) (list (ty/ssaParam "arg" (ty/tyVal)) (ty/ssaParam "arg2" (ty/tyVal))) (ty/tyVal)
    (listAppend (intCheckBlocks "first" "arg" lo hi "second.entry")
      (listAppend (intCheckBlocks "second" "arg2" lo hi "call")
        (cons
          (sys/block "call"
            (list (sys/primInstr "first.n32" (ty/tyI32) "rawNarrowI32" (list "first.n"))
                  (sys/primInstr "second.n32" (ty/tyI32) "rawNarrowI32" (list "second.n"))
                  (sys/callInstr "res" (ty/tyVal) callee (list "first.n32" "second.n32")))
            (resultSwitch))
          (resultBlocks einval ioIndex)))))

fn unitWrapper builtin: String callee: String einval: Int64 ioIndex: Int64 -> ty/SsaFunction
  (ty/ssaFunction (wrapperName builtin) (list) (list) (ty/tyVal)
    (cons
      (sys/block "call" (list (sys/callInstr "res" (ty/tyVal) callee (list))) (resultSwitch))
      (resultBlocks einval ioIndex)))

fn builtinNames m: ty/SsaModule -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (f ty/SsaFunction)] -> (Map String Bool)
          (fold (fn [(acc2 (Map String Bool)) (b ty/SsaBlock)] -> (Map String Bool)
                  (fold (fn [(acc3 (Map String Bool)) (i ty/SsaInstr)] -> (Map String Bool)
                          (mt i.op
                            ((ty/opBuiltin n _) (mapSet acc3 n true))
                            (_ acc3)))
                        acc2 b.instrs))
                acc f.blocks))
        (mapEmpty) m.functions)

fn tablesUsed m: ty/SsaModule -> (List RouteTable)
  (let [(called (builtinNames m))]
    (filter (fn [(t RouteTable)] -> Bool (listAny? (fn [(b String)] -> Bool (some? (mapGet called b))) (tableBuiltins t)))
            (routeTables)))

fn routes? m: ty/SsaModule -> Bool
  (not (listEmpty? (tablesUsed m)))

fn rewriteOp names: (List String) op: ty/SsaOp -> ty/SsaOp
  (mt op
    ((ty/opBuiltin n args) (if (listContains? names n) (ty/opCall (routedCallee n (listLength args)) (routedArgs n args)) op))
    (_ op))

fn routedCallee builtin: String argc: Int64 -> String
  (if (= builtin "fileLockWait")
    (str (wrapperName builtin) "/" (if (and (>= argc 1) (<= argc 3)) (stringFromInt64 argc) "bad"))
    (wrapperName builtin))

fn routedArgs builtin: String args: (List String) -> (List String)
  (if (and (= builtin "fileLockWait") (or (< (listLength args) 1) (> (listLength args) 3))) (list) args)

fn rewriteFunction names: (List String) f: ty/SsaFunction -> ty/SsaFunction
  (ty/ssaFunction f.name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
           (ty/ssaBlock b.label b.params
             (map (fn [(i ty/SsaInstr)] -> ty/SsaInstr (ty/ssaInstr i.dest i.ty (rewriteOp names i.op))) b.instrs)
             b.term))
         f.blocks))

fn poolIndex strings: (List String) s: String -> (Option Int64)
  (listHead (filter (fn [(i Int64)] -> Bool (= (listGet strings i) (some s))) (range 0 (listLength strings))))

fn routeDiag code: String message: String locus: String -> ty/IrDiag
  (ty/makeIrDiag code message locus)

fn dedupeExterns externs: (List ty/SsaExtern) -> (List ty/SsaExtern)
  (fold (fn [(acc (List ty/SsaExtern)) (e ty/SsaExtern)] -> (List ty/SsaExtern)
          (if (listAny? (fn [(o ty/SsaExtern)] -> Bool (= o.name e.name)) acc)
            (map (fn [(o ty/SsaExtern)] -> ty/SsaExtern (if (= o.name e.name) e o)) acc)
            (listAppend acc (list e))))
        (list) externs)

fn mergeExterns own: (List ty/SsaExtern) added: (List ty/SsaExtern) locus: String -> (Result (List ty/SsaExtern) (List ty/IrDiag))
  (let [(clashes (filter (fn [(e ty/SsaExtern)] -> Bool (listAny? (fn [(o ty/SsaExtern)] -> Bool (and (= o.name e.name) (not (= o e)))) own)) added))
        (fresh (filter (fn [(e ty/SsaExtern)] -> Bool (not (listAny? (fn [(o ty/SsaExtern)] -> Bool (= o.name e.name)) own))) added))]
    (if (listEmpty? clashes)
      (ok (listAppend own fresh))
      (err (map (fn [(e ty/SsaExtern)] -> ty/IrDiag (routeDiag "ERR_LLVM_SYSROUTE_EXTERN" (str "extern '" e.name "' is declared with another signature than the routed syscall functions need") locus)) clashes))))

fn dedupeFunctions fns: (List ty/SsaFunction) -> (List ty/SsaFunction)
  (fold (fn [(acc (List ty/SsaFunction)) (f ty/SsaFunction)] -> (List ty/SsaFunction)
          (if (listAny? (fn [(g ty/SsaFunction)] -> Bool (= g.name f.name)) acc) acc (listAppend acc (list f))))
        (list) fns)

fn withTypes own: (List ty/SsaTypeDecl) added: (List ty/SsaTypeDecl) -> (List ty/SsaTypeDecl)
  (fold (fn [(acc (List ty/SsaTypeDecl)) (d ty/SsaTypeDecl)] -> (List ty/SsaTypeDecl)
          (if (listAny? (fn [(o ty/SsaTypeDecl)] -> Bool (= o.name d.name)) acc) acc (listAppend acc (list d))))
        own added)

fn mergeRecords own: (List ty/SsaRecordDecl) added: (List ty/SsaRecordDecl) locus: String -> (Result (List ty/SsaRecordDecl) (List ty/IrDiag))
  (let [(clashes (filter (fn [(d ty/SsaRecordDecl)] -> Bool (listAny? (fn [(o ty/SsaRecordDecl)] -> Bool (and (= o.name d.name) (not (= o.fields d.fields)))) own)) added))
        (fresh (filter (fn [(d ty/SsaRecordDecl)] -> Bool (not (listAny? (fn [(o ty/SsaRecordDecl)] -> Bool (= o.name d.name)) own))) added))]
    (if (listEmpty? clashes)
      (ok (listAppend own fresh))
      (err (map (fn [(d ty/SsaRecordDecl)] -> ty/IrDiag (routeDiag "ERR_LLVM_SYSROUTE_RECORD" (str "record '" d.name "' is declared with other fields than the routed " d.name " builder needs") locus)) clashes))))

fn poolAt pool: (Map String Int64) s: String -> Int64
  (optionOr (mapGet pool s) -1)

fn poolWith strings: (List String) wanted: (List String) -> (Pair (List String) (Map String Int64))
  (fold (fn [(acc (Pair (List String) (Map String Int64))) (s String)] -> (Pair (List String) (Map String Int64))
          (let [(have (pairFirst acc))]
            (mt (poolIndex have s)
              ((some i) (pair have (mapSet (pairSecond acc) s i)))
              ((none) (pair (listAppend have (list s)) (mapSet (pairSecond acc) s (listLength have)))))))
        (pair strings (mapEmpty)) wanted)

fn tablesFunctions facts: libc/TripleFacts tables: (List RouteTable) pool: (Map String Int64) -> (Result (List ty/SsaFunction) String)
  (fold (fn [(acc (Result (List ty/SsaFunction) String)) (t RouteTable)] -> (Result (List ty/SsaFunction) String)
          (mt acc
            ((err e) (err e))
            ((ok fns) (mt (tableFunctions facts t pool)
                        ((err e) (err e))
                        ((ok more) (ok (listAppend fns more)))))))
        (ok (list)) tables)

fn callNamesIn f: ty/SsaFunction -> (List String)
  (fold (fn [(acc (List String)) (b ty/SsaBlock)] -> (List String)
          (fold (fn [(acc2 (List String)) (i ty/SsaInstr)] -> (List String)
                  (mt i.op
                    ((ty/opCall n _) (cons n acc2))
                    ((ty/opMakeClosure n _) (cons n acc2))
                    (_ acc2)))
                acc b.instrs))
        (list) f.blocks)

fn moduleCallNames fs: (List ty/SsaFunction) -> (List String)
  (fold (fn [(acc (List String)) (f ty/SsaFunction)] -> (List String) (listAppend acc (callNamesIn f))) (list) fs)

fn growReachable toVisit: (List String) fnByName: (Map String ty/SsaFunction) seen: (Map String Bool) -> (Map String Bool)
  (mt (listHead toVisit)
    ((none) seen)
    ((some n)
      (let [(rest (optionOr (listTail toVisit) (list)))]
        (if (some? (mapGet seen n))
          (growReachable rest fnByName seen)
          (mt (mapGet fnByName n)
            ((none) (growReachable rest fnByName (mapSet seen n true)))
            ((some f) (growReachable (listAppend (callNamesIn f) rest) fnByName (mapSet seen n true))))))))

fn reachableFrom seed: (List String) fnByName: (Map String ty/SsaFunction) -> (Map String Bool)
  (growReachable seed fnByName (mapEmpty))

fn routeTablesInto facts: libc/TripleFacts m: ty/SsaModule tables: (List RouteTable) -> (Result Routed (List ty/IrDiag))
  (let [(pooled (poolWith m.strings (fold (fn [(acc (List String)) (t RouteTable)] -> (List String) (listAppend acc (tableStrings t))) (list) tables)))
        (names (fold (fn [(acc (List String)) (t RouteTable)] -> (List String) (listAppend acc (tableBuiltins t))) (list) tables))
        (types (fold (fn [(acc (List ty/SsaTypeDecl)) (t RouteTable)] -> (List ty/SsaTypeDecl) (listAppend acc (tableTypes t))) (list) tables))
        (records (fold (fn [(acc (List ty/SsaRecordDecl)) (t RouteTable)] -> (List ty/SsaRecordDecl) (listAppend acc (tableRecords t))) (list) tables))
        (globals (fold (fn [(acc (List ty/SsaGlobal)) (t RouteTable)] -> (List ty/SsaGlobal) (listAppend acc (tableGlobals t))) (list) tables))
        (externs (dedupeExterns (fold (fn [(acc (List ty/SsaExtern)) (t RouteTable)] -> (List ty/SsaExtern) (listAppend acc (tableExterns facts t))) (list) tables)))]
    (mt (tablesFunctions facts tables (pairSecond pooled))
      ((err e) (err (list (routeDiag "ERR_LLVM_SYSROUTE_FACTS" e m.name))))
      ((ok fns)
        (let [(available (dedupeFunctions fns))
              (rewritten (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (rewriteFunction names f)) m.functions))
              (fnByName (fold (fn [(acc (Map String ty/SsaFunction)) (f ty/SsaFunction)] -> (Map String ty/SsaFunction) (mapSet acc f.name f)) (mapEmpty) available))
              (globalInits (map (fn [(g ty/SsaGlobal)] -> String g.init) globals))
              (seed (listAppend (moduleCallNames rewritten) globalInits))
              (reached (reachableFrom seed fnByName))
              (added (filter (fn [(f ty/SsaFunction)] -> Bool (some? (mapGet reached f.name))) available))
              (clashes (filter (fn [(f ty/SsaFunction)] -> Bool (listAny? (fn [(g ty/SsaFunction)] -> Bool (= g.name f.name)) m.functions)) added))]
          (if (not (listEmpty? clashes))
            (err (map (fn [(f ty/SsaFunction)] -> ty/IrDiag (routeDiag "ERR_LLVM_SYSROUTE_NAME" (str "module function '" f.name "' has the name of a routed syscall function") f.name)) clashes))
            (mt (mergeExterns m.externs externs m.name)
              ((err diags) (err diags))
              ((ok merged)
                (mt (mergeRecords m.records records m.name)
                  ((err diags) (err diags))
                  ((ok recs)
                    (ok (Routed :result (ty/ssaModule m.name (pairFirst pooled) (withTypes m.types types) recs merged (listAppend m.globals globals)
                                          (listAppend rewritten added))
                                :internal (map (fn [(f ty/SsaFunction)] -> String f.name) added))))))))))))

fn wasmImportTable -> (List (Pair String Int64))
  (list (pair "print" 1))

fn wasmImportNames -> (List String)
  (map pairFirst (wasmImportTable))

fn wasmImportArity name: String -> (Option Int64)
  (let [(matches (filter (fn [(entry (Pair String Int64))] -> Bool (= (pairFirst entry) name)) (wasmImportTable)))]
    (optionMap pairSecond (listHead matches)))

fn wasmSystemNames -> (List String)
  (fold (fn [(acc (List String)) (t RouteTable)] -> (List String) (listAppend acc (tableBuiltins t))) (list) (routeTables))

fn wasmPrintImportInstrs dest: String args: (List String) index: Int64 spaceIndex: Int64 -> (List ty/SsaInstr)
  (if (= (listLength args) 0)
    (list)
    (let [(arg (optionOr (listHead args) ""))
          (tail (optionOr (listTail args) (list)))
          (lastArg (= (listLength args) 1))
          (callDest (if lastArg dest (str dest "$printArg" (stringFromInt64 index))))
          (argCall (ty/ssaInstr callDest (ty/tyVal) (ty/opCall "print" (list arg))))
          (rest (wasmPrintImportInstrs dest tail (+ index 1) spaceIndex))]
      (if (= index 0)
        (cons argCall rest)
        (let [(spaceDest (str dest "$space" (stringFromInt64 index)))
              (spaceCallDest (str dest "$printSpace" (stringFromInt64 index)))]
          (cons (ty/ssaInstr spaceDest (ty/tyVal) (ty/opConst (ty/constStr spaceIndex)))
                (cons (ty/ssaInstr spaceCallDest (ty/tyVal) (ty/opCall "print" (list spaceDest)))
                      (cons argCall rest)))))))

fn rewriteImportInstr names: (List String) i: ty/SsaInstr spaceIndex: Int64 -> (List ty/SsaInstr)
  (let [(op i.op)]
    (mt op
      ((ty/opBuiltin n args)
        (if (and (= n "print") (listContains? names n))
          (if (listEmpty? args)
            (list (ty/ssaInstr i.dest (ty/tyVal) (ty/opConst (ty/constUnit))))
            (wasmPrintImportInstrs i.dest args 0 spaceIndex))
          (if (listContains? names n)
            (list (ty/ssaInstr i.dest i.ty (ty/opCall n args)))
            (list i))))
      (_ (list i))))

fn rewriteImports names: (List String) f: ty/SsaFunction spaceIndex: Int64 -> ty/SsaFunction
  (ty/ssaFunction f.name f.captures f.params f.retTy
    (map (fn [(b ty/SsaBlock)] -> ty/SsaBlock
           (ty/ssaBlock b.label b.params
             (fold (fn [(out (List ty/SsaInstr)) (i ty/SsaInstr)] -> (List ty/SsaInstr)
                     (listAppend out (rewriteImportInstr names i spaceIndex)))
                   (list) b.instrs)
             b.term))
         f.blocks))

fn wasmImportExterns names: (List String) -> (List ty/SsaExtern)
  (fold (fn [(externs (List ty/SsaExtern)) (entry (Pair String Int64))] -> (List ty/SsaExtern)
          (let [(name (pairFirst entry))]
            (if (listContains? names name)
              (cons (ty/ssaExternTyped name (wasmValParams (pairSecond entry)) (ty/tyVal)) externs)
              externs)))
        (list) (wasmImportTable))

fn wasmValParams arity: Int64 -> (List ty/SsaTy)
  (if (<= arity 0) (list) (cons (ty/tyVal) (wasmValParams (- arity 1))))

fn wasmPrintStrings strings: (List String) names: (List String) -> (Pair (List String) Int64)
  (if (not (listContains? names "print"))
    (pair strings -1)
    (mt (poolIndex strings " ")
      ((some index) (pair strings index))
      ((none) (pair (listAppend strings (list " ")) (listLength strings)))))

fn wasmImportInstrDiags m: ty/SsaModule i: ty/SsaInstr -> (List ty/IrDiag)
  (mt i.op
    ((ty/opBuiltin name args)
      (mt (wasmImportArity name)
        ((none) (list))
        ((some expected)
          (if (or (= name "print") (= (listLength args) expected))
            (list)
            (list (routeDiag "ERR_LLVM_WASM_IMPORT" (str "wasm import " name " expects " expected " arguments, got " (listLength args)) m.name))))))
    (_ (list)))

fn wasmImportCallDiags m: ty/SsaModule -> (List ty/IrDiag)
  (fold (fn [(all (List ty/IrDiag)) (f ty/SsaFunction)] -> (List ty/IrDiag)
          (fold (fn [(functionDiags (List ty/IrDiag)) (b ty/SsaBlock)] -> (List ty/IrDiag)
                  (fold (fn [(blockDiags (List ty/IrDiag)) (i ty/SsaInstr)] -> (List ty/IrDiag)
                          (listAppend blockDiags (wasmImportInstrDiags m i)))
                        functionDiags b.instrs))
                all f.blocks))
        (list) m.functions)

fn wasmRouteModule facts: libc/TripleFacts m: ty/SsaModule -> (Result Routed (List ty/IrDiag))
  (let [(called (builtinNames m))
        (absent (filter (fn [(name String)] -> Bool (and (some? (mapGet called name)) (not (listContains? (wasmImportNames) name)))) (wasmSystemNames)))
        (imports (filter (fn [(name String)] -> Bool (some? (mapGet called name))) (wasmImportNames)))
        (printStrings (wasmPrintStrings m.strings imports))
        (spaceIndex (pairSecond printStrings))
        (arityDiags (wasmImportCallDiags m))]
    (if (not (listEmpty? absent))
      (err (map (fn [(name String)] -> ty/IrDiag (routeDiag "ERR_CAPABILITY_ABSENT" (str "builtin " name " is absent on target " facts.triple) m.name)) absent))
      (if (not (listEmpty? arityDiags))
        (err arityDiags)
        (mt (vfy/verifySsa m)
          ((err diags) (err diags))
          ((ok _) (mt (mergeExterns m.externs (wasmImportExterns imports) m.name)
            ((err diags) (err diags))
            ((ok externs)
              (ok (Routed :result (ty/ssaModule m.name (pairFirst printStrings) m.types m.records externs m.globals (map (fn [(f ty/SsaFunction)] -> ty/SsaFunction (rewriteImports imports f spaceIndex)) m.functions)) :internal (list))))))))))

fn routeModule facts: libc/TripleFacts m: ty/SsaModule -> (Result Routed (List ty/IrDiag))
  (if (stringStartsWith? facts.triple "wasm32")
    (wasmRouteModule facts m)
    (let [(tables (tablesUsed m))]
      (if (listEmpty? tables)
        (ok (Routed :result m :internal (list)))
        (mt (vfy/verifySsa m)
          ((err diags) (err diags))
          ((ok _) (routeTablesInto facts m tables))))))

fn tripleOf os: String machine: String -> String
  (cond
    ((and (= os "Darwin") (= machine "arm64")) "darwin-arm64")
    ((and (= os "Linux") (= machine "x86_64")) "linux-x86_64")
    ((and (= os "Linux") (or (= machine "aarch64") (= machine "arm64"))) "linux-aarch64")
    (else ""))

fn routeFactsFor triple: String -> (Option libc/TripleFacts)
  (if (libc/libcVerified triple) (libc/libcFacts triple) (none))

fn unamePair text: String -> (Option (Pair String String))
  (let [(words (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit (stringReplace text "\n" " ") " ")))]
    (if (= (listLength words) 2)
      (mt (listHead words)
        ((none) (none))
        ((some os) (optionMap (fn [(machine String)] -> (Pair String String) (pair os machine)) (listGet words 1))))
      (none)))

fn hostFactsOf text: String -> (Result (Option libc/TripleFacts) String)
  (mt (unamePair text)
    ((none) (err (str "uname -s -m printed '" text "', not a sysname and a machine")))
    ((some p) (ok (routeFactsFor (tripleOf (pairFirst p) (pairSecond p))))))

fn ! routeHost! m: ty/SsaModule -> (Result Routed (List ty/IrDiag))
  (if (routes? m)
    (let [(out (processRun "uname -s -m"))
          (host (if (= out.exitCode 0) (unamePair out.stdout) (none)))]
      (mt host
        ((none) (err (list (routeDiag "ERR_LLVM_SYSROUTE_HOST" (str "uname -s -m exited " out.exitCode " printing '" out.stdout "' " out.stderr) m.name))))
        ((some p) (mt (routeFactsFor (tripleOf (pairFirst p) (pairSecond p)))
                    ((none) (ok (Routed :result m :internal (list))))
                    ((some facts) (routeModule facts m))))))
    (ok (Routed :result m :internal (list))))

fn internalizeDefinePrefix -> String
  "define tailcc "

fn internalizeNames names: (List String) -> (Map String Bool)
  (fold (fn [(acc (Map String Bool)) (n String)] -> (Map String Bool) (mapSet acc (ssa/llvmName n) true)) (mapEmpty) names)

fn defineLineSymbol line: String -> String
  (mt (listGet (stringSplit line "@") 1)
    ((none) "")
    ((some rest) (optionOr (listHead (stringSplit rest "(")) "")))

fn internalizeLine wanted: (Map String Bool) line: String -> String
  (if (stringStartsWith? line (internalizeDefinePrefix))
    (if (some? (mapGet wanted (defineLineSymbol line)))
      (stringReplace line (internalizeDefinePrefix) "define internal tailcc ")
      line)
    line)

fn internalize res: (Result String (List ty/IrDiag)) names: (List String) -> (Result String (List ty/IrDiag))
  (if (listEmpty? names)
    res
    (mt res
      ((err diags) (err diags))
      ((ok text)
        (let [(wanted (internalizeNames names))]
          (ok (stringJoin (map (fn [(line String)] -> String (internalizeLine wanted line)) (stringSplit text "\n")) "\n"))))))

fn signalNames -> (List String)
  (list "SIGHUP" "SIGINT" "SIGQUIT" "SIGKILL" "SIGUSR1" "SIGUSR2" "SIGTERM" "SIGCONT" "SIGSTOP" "SIGWINCH")

fn errKinds -> (List (Pair String String))
  (list (pair "EAGAIN" "wouldBlock") (pair "ENOENT" "notFound") (pair "EACCES" "permission") (pair "EPERM" "permission") (pair "EROFS" "permission")
        (pair "EBADF" "badFd") (pair "EBUSY" "busy") (pair "EINTR" "interrupted") (pair "ESRCH" "noProcess") (pair "ECHILD" "noChild"))

fn sysStrings -> (List String)
  (listAppend (list "io:" "" "badFd" "io:22" "io:12" "io:38" "((pair " "((some " "-" "0" (tagGuardText) "ERR_IO" "nowNs: ")
    (listAppend (map (fn [(k (Pair String String))] -> String (pairSecond k)) (errKinds)) (signalNames)))

fn routeConst facts: libc/TripleFacts name: String -> (Option Int64)
  (libc/libcConst facts name)

fn structFact facts: libc/TripleFacts structName: String field: String -> (Option Int64)
  (if (= field "size")
    (libc/structSize facts structName)
    (mt (libc/pairFind facts.structs structName)
      ((none) (none))
      ((some sf) (libc/structFieldOffset sf field))))

fn sysFactNames -> (List String)
  (listAppend (list "F_GETFL" "F_SETFL" "O_NONBLOCK" "_SC_NPROCESSORS_ONLN" "POLLIN" "POLLOUT" "POLLNVAL" "POLLPRI" "POLLERR" "POLLHUP" "EOVERFLOW"
                    "pollfd.size" "pollfd.fd" "pollfd.events" "pollfd.revents" "utsname.size" "utsname.sysname" "utsname.release" "utsname.machine"
                    "CLOCK_REALTIME" "CLOCK_MONOTONIC" "timespec.size" "timespec.tv_sec" "timespec.tv_nsec" "EINTR")
    (listAppend (map (fn [(k (Pair String String))] -> String (pairFirst k)) (errKinds)) (signalNames)))

fn sysFacts facts: libc/TripleFacts -> (Result (Map String Int64) String)
  (let [(resolved (fold (fn [(acc (Result (Map String Int64) String)) (n String)] -> (Result (Map String Int64) String)
                          (mt acc
                            ((err e) (err e))
                            ((ok m)
                              (let [(parts (stringSplit n "."))
                                    (v (if (= (listLength parts) 2)
                                         (structFact facts (optionOr (listGet parts 0) "") (optionOr (listGet parts 1) ""))
                                         (routeConst facts n)))]
                                (mt v
                                  ((none) (err (str "no " n " fact for triple " facts.triple)))
                                  ((some x) (ok (mapSet m n x))))))))
                        (ok (mapEmpty)) (sysFactNames)))]
    (mt resolved
      ((err e) (err e))
      ((ok m) (if (= (fact m "pollfd.revents") (+ (fact m "pollfd.events") 2))
                (ok m)
                (err (str "pollfd revents is not 2 bytes after events on " facts.triple))))))

fn fact k: (Map String Int64) name: String -> Int64
  (optionOr (mapGet k name) 0)

fn pairTypeDecl -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Pair" (list (ty/ssaVariant "pair" 2)))

fn platformInfoDecl -> ty/SsaRecordDecl
  (ty/ssaRecordDecl "PlatformInfo" (list "os" "release" "machine"))

fn nsGetEnvironExtern -> ty/SsaExtern
  (ty/ssaExternTyped "_NSGetEnviron" (list) (ty/tyPtr))

fn environExterns facts: libc/TripleFacts -> (List ty/SsaExtern)
  (if (stringStartsWith? facts.triple "darwin") (list (nsGetEnvironExtern)) (list))

fn int64Min -> Int64
  (- -9223372036854775807 1)

fn i64 dest: String n: Int64 -> ty/SsaInstr
  (sys/int64Const dest n)

fn prim dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (sys/primInstr dest t name args)

fn rawBool dest: String b: Bool -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI1) (ty/opConst (ty/constBool b)))

fn valBool dest: String b: Bool -> ty/SsaInstr
  (valInstr dest (ty/opConst (ty/constBool b)))

fn poolStr pool: (Map String Int64) dest: String text: String -> ty/SsaInstr
  (valInstr dest (ty/opConst (ty/constStr (poolAt pool text))))

fn unboxI64 dest: String v: String -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI64) (ty/opUnbox v))

fn fieldOf dest: String v: String i: Int64 -> ty/SsaInstr
  (valInstr dest (ty/opVariantField v i))

fn callHelper dest: String t: ty/SsaTy helper: String args: (List String) -> ty/SsaInstr
  (sys/callInstr dest t (wrapperName helper) args)

fn edgeArgs label: String args: (List String) -> ty/SsaEdge
  (ty/ssaEdge label args)

fn branch c: String yes: String no: String -> ty/SsaTerm
  (ty/termBranch c (sys/edgeTo yes) (sys/edgeTo no))

fn optionSwitch v: String someLabel: String noneLabel: String -> ty/SsaTerm
  (ty/termSwitch v "Option" (list (ty/ssaCase "some" (sys/edgeTo someLabel)) (ty/ssaCase "none" (sys/edgeTo noneLabel))) (none))

fn resultSwitchTo v: String okLabel: String errLabel: String -> ty/SsaTerm
  (ty/termSwitch v "Result" (list (ty/ssaCase "ok" (sys/edgeTo okLabel)) (ty/ssaCase "err" (sys/edgeTo errLabel))) (none))

fn errTextBlock pool: (Map String Int64) label: String text: String -> ty/SsaBlock
  (sys/block label (list (poolStr pool (str label ".text") text) (valInstr (str label ".v") (ty/opConstruct "Result" "err" (list (str label ".text")))))
    (ty/termReturn (str label ".v")))

fn okBlock label: String pre: (List ty/SsaInstr) value: String -> ty/SsaBlock
  (sys/block label (listAppend pre (list (valInstr (str label ".v") (ty/opConstruct "Result" "ok" (list value)))))
    (ty/termReturn (str label ".v")))

fn okUnitBlock label: String -> ty/SsaBlock
  (okBlock label (list (valInstr (str label ".unit") (ty/opConst (ty/constUnit)))) (str label ".unit"))

fn mapErrnoBlock label: String code: String -> ty/SsaBlock
  (sys/block label (list (callHelper (str label ".v") (ty/tyVal) "errnoErr" (list code))) (ty/termReturn (str label ".v")))

fn errnoBlock label: String cleanup: (List ty/SsaInstr) -> ty/SsaBlock
  (sys/block label
    (listAppend (list (sys/callInstr (str label ".errno") (ty/tyI64) "sysErrnoValue" (list)))
      (listAppend cleanup (list (callHelper (str label ".v") (ty/tyVal) "errnoErr" (list (str label ".errno"))))))
    (ty/termReturn (str label ".v")))

fn resultErrBlock label: String res: String -> ty/SsaBlock
  (sys/block label
    (list (fieldOf (str label ".box") res 0) (unboxI64 (str label ".code") (str label ".box"))
          (callHelper (str label ".v") (ty/tyVal) "errnoErr" (list (str label ".code"))))
    (ty/termReturn (str label ".v")))

fn outsideInstrs prefix: String v: String lo: Int64 hi: Int64 -> (List ty/SsaInstr)
  (list (i64 (str prefix ".lo") lo) (i64 (str prefix ".hi") hi)
        (prim (str prefix ".below") (ty/tyI1) "ltInt" (list v (str prefix ".lo")))
        (prim (str prefix ".above") (ty/tyI1) "gtInt" (list v (str prefix ".hi")))
        (prim (str prefix ".out") (ty/tyI1) "orBool" (list (str prefix ".below") (str prefix ".above"))))

fn helperFn name: String params: (List ty/SsaParam) retTy: ty/SsaTy blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction (wrapperName name) (list) params retTy blocks)

fn valParams names: (List String) -> (List ty/SsaParam)
  (map (fn [(n String)] -> ty/SsaParam (ty/ssaParam n (ty/tyVal))) names)

fn intOfFn -> ty/SsaFunction
  (helperFn "intOf" (valParams (list "v")) (ty/tyVal)
    (list
      (sys/block "entry"
        (list (showInstr "shown" "v")
              (sys/entryInstr "bytes" (ty/tyVal) "stringToBytes" (list "shown"))
              (sys/entryInstr "len" (ty/tyI64) "bytesLength" (list "bytes"))
              (i64 "zero" 0) (i64 "one" 1)
              (prim "empty" (ty/tyI1) "eqInt" (list "len" "zero")))
        (branch "empty" "none" "first"))
      (sys/block "first"
        (list (sys/entryInstr "b0" (ty/tyI64) "bytesGet" (list "bytes" "zero"))
              (i64 "minus" 45)
              (prim "neg" (ty/tyI1) "eqInt" (list "b0" "minus")))
        (ty/termBranch "neg" (edgeArgs "start" (list "one")) (edgeArgs "start" (list "zero"))))
      (ty/ssaBlock "start" (list (ty/ssaParam "from" (ty/tyI64)))
        (list (prim "noDigits" (ty/tyI1) "geInt" (list "from" "len")))
        (ty/termBranch "noDigits" (sys/edgeTo "none") (edgeArgs "loop" (list "from" "zero"))))
      (ty/ssaBlock "loop" (list (ty/ssaParam "i" (ty/tyI64)) (ty/ssaParam "acc" (ty/tyI64)))
        (list (prim "done" (ty/tyI1) "geInt" (list "i" "len")))
        (ty/termBranch "done" (edgeArgs "finish" (list "acc")) (sys/edgeTo "digit")))
      (sys/block "digit"
        (list (sys/entryInstr "b" (ty/tyI64) "bytesGet" (list "bytes" "i"))
              (i64 "c48" 48) (i64 "c57" 57)
              (prim "lowByte" (ty/tyI1) "ltInt" (list "b" "c48"))
              (prim "highByte" (ty/tyI1) "gtInt" (list "b" "c57"))
              (prim "notDigit" (ty/tyI1) "orBool" (list "lowByte" "highByte")))
        (branch "notDigit" "none" "accum"))
      (sys/block "accum"
        (list (prim "d" (ty/tyI64) "subInt" (list "b" "c48"))
              (i64 "min" (int64Min)) (i64 "ten" 10)
              (prim "limBase" (ty/tyI64) "addInt" (list "min" "d"))
              (prim "lim" (ty/tyI64) "quotInt" (list "limBase" "ten"))
              (prim "over" (ty/tyI1) "ltInt" (list "acc" "lim")))
        (branch "over" "none" "step"))
      (sys/block "step"
        (list (prim "acc10" (ty/tyI64) "mulInt" (list "acc" "ten"))
              (prim "accNext" (ty/tyI64) "subInt" (list "acc10" "d"))
              (prim "iNext" (ty/tyI64) "addInt" (list "i" "one")))
        (ty/termJump (edgeArgs "loop" (list "iNext" "accNext"))))
      (ty/ssaBlock "finish" (list (ty/ssaParam "total" (ty/tyI64)))
        (list)
        (ty/termBranch "neg" (edgeArgs "confirm" (list "total")) (sys/edgeTo "positive")))
      (sys/block "positive"
        (list (i64 "min2" (int64Min)) (prim "isMin" (ty/tyI1) "eqInt" (list "total" "min2")))
        (branch "isMin" "none" "flip"))
      (sys/block "flip"
        (list (prim "flipped" (ty/tyI64) "subInt" (list "zero" "total")))
        (ty/termJump (edgeArgs "confirm" (list "flipped"))))
      (ty/ssaBlock "confirm" (list (ty/ssaParam "n" (ty/tyI64)))
        (cons (sys/boxInstr "nBox" "n") (sameReprInstrs "rep" "v" "nBox"))
        (branch "rep.same" "some" "none"))
      (sys/block "some" (list (valInstr "someV" (ty/opConstruct "Option" "some" (list "nBox")))) (ty/termReturn "someV"))
      (sys/block "none" (list (valInstr "noneV" (ty/opConstruct "Option" "none" (list)))) (ty/termReturn "noneV"))))

fn isStringFn -> ty/SsaFunction
  (helperFn "isString" (valParams (list "v")) (ty/tyI1)
    (list (sys/block "entry" (cons (showInstr "shown" "v") (sameReprInstrs "s" "v" "shown")) (ty/termReturn "s.same"))))

fn boolOfFn -> ty/SsaFunction
  (helperFn "boolOf" (valParams (list "v")) (ty/tyI64)
    (list
      (sys/block "entry" (cons (valBool "t" true) (sameReprInstrs "isTrue" "v" "t")) (branch "isTrue.same" "yes" "notTrue"))
      (sys/block "yes" (list (i64 "one" 1)) (ty/termReturn "one"))
      (sys/block "notTrue" (cons (valBool "f" false) (sameReprInstrs "isFalse" "v" "f")) (branch "isFalse.same" "no" "neither"))
      (sys/block "no" (list (i64 "zero" 0)) (ty/termReturn "zero"))
      (sys/block "neither" (list (i64 "minusOne" -1)) (ty/termReturn "minusOne"))))

fn letterInstrs prefix: String b: String -> (List ty/SsaInstr)
  (list (i64 (str prefix ".a") 97) (i64 (str prefix ".z") 122) (i64 (str prefix ".A") 65) (i64 (str prefix ".Z") 90)
        (prim (str prefix ".geA") (ty/tyI1) "geInt" (list b (str prefix ".a"))) (prim (str prefix ".leZ") (ty/tyI1) "leInt" (list b (str prefix ".z")))
        (prim (str prefix ".lower") (ty/tyI1) "andBool" (list (str prefix ".geA") (str prefix ".leZ")))
        (prim (str prefix ".geUA") (ty/tyI1) "geInt" (list b (str prefix ".A"))) (prim (str prefix ".leUZ") (ty/tyI1) "leInt" (list b (str prefix ".Z")))
        (prim (str prefix ".upper") (ty/tyI1) "andBool" (list (str prefix ".geUA") (str prefix ".leUZ")))
        (prim (str prefix ".letter") (ty/tyI1) "orBool" (list (str prefix ".lower") (str prefix ".upper"))))

fn reprBytesInstrs v: String -> (List ty/SsaInstr)
  (list (valInstr "wrapped" (ty/opList (list v))) (showInstr "repr" "wrapped")
        (sys/entryInstr "bytes" (ty/tyVal) "stringToBytes" (list "repr"))
        (i64 "one" 1) (i64 "two" 2)
        (sys/entryInstr "b1" (ty/tyI64) "bytesGet" (list "bytes" "one"))
        (sys/entryInstr "b2" (ty/tyI64) "bytesGet" (list "bytes" "two"))
        (i64 "open" 40) (prim "nested" (ty/tyI1) "eqInt" (list "b1" "open")))

fn absExtern -> ty/SsaExtern
  (ty/ssaExternTyped "abs" (list (ty/tyVal)) (ty/tyI32))

fn tagOfFn -> ty/SsaFunction
  (helperFn "tagOf" (valParams (list "v")) (ty/tyI64)
    (list (sys/block "entry"
            (list (sys/callInstr "t32" (ty/tyI32) "abs" (list "v")) (prim "t" (ty/tyI64) "rawWidenI32" (list "t32"))
                  (callHelper "checked" (ty/tyI64) "tagCheck" (list "t")))
            (ty/termReturn "checked"))))

fn tagGuardText -> String
  "ERR_LLVM_SYSROUTE_TAG: libc abs of a %Val passed by value gave no Tag (outside 0..255); this target does not pass %Val {i64, i64} in two integer registers"

fn tagCheckFn pool: (Map String Int64) -> ty/SsaFunction
  (helperFn "tagCheck" (list (ty/ssaParam "t" (ty/tyI64))) (ty/tyI64)
    (list (sys/block "entry" (outsideInstrs "range" "t" 0 255) (branch "range.out" "bad" "good"))
          (sys/block "good" (list) (ty/termReturn "t"))
          (sys/block "bad" (list (poolStr pool "msg" (tagGuardText)) (valInstr "shown" (ty/opBuiltin "eprintln" (list "msg")))) (ty/termUnreachable))))

fn tagTestFn name: String exemplar: (List ty/SsaInstr) -> ty/SsaFunction
  (helperFn name (valParams (list "v")) (ty/tyI1)
    (list (sys/block "entry"
            (listAppend exemplar
              (list (callHelper "vt" (ty/tyI64) "tagOf" (list "v")) (callHelper "et" (ty/tyI64) "tagOf" (list "ex"))
                    (prim "same" (ty/tyI1) "eqInt" (list "vt" "et"))))
            (ty/termReturn "same"))))

fn isListFn -> ty/SsaFunction
  (tagTestFn "isList" (list (valInstr "ex" (ty/opList (list)))))

fn isStrFn pool: (Map String Int64) -> ty/SsaFunction
  (tagTestFn "isStr" (list (poolStr pool "ex" "")))

fn isBytesFn pool: (Map String Int64) -> ty/SsaFunction
  (tagTestFn "isBytes" (list (poolStr pool "empty" "") (sys/entryInstr "ex" (ty/tyVal) "stringToBytes" (list "empty"))))

fn optionArgFn pool: (Map String Int64) -> ty/SsaFunction
  (helperFn "optionArg" (valParams (list "v")) (ty/tyI64)
    (list
      (sys/block "entry"
        (list (valInstr "noneV" (ty/opConstruct "Option" "none" (list)))
              (callHelper "vt" (ty/tyI64) "tagOf" (list "v")) (callHelper "ct" (ty/tyI64) "tagOf" (list "noneV"))
              (prim "isCtor" (ty/tyI1) "eqInt" (list "vt" "ct")))
        (branch "isCtor" "ctor" "bad"))
      (sys/block "ctor" (sameReprInstrs "n" "v" "noneV") (branch "n.same" "isNone" "trySome"))
      (sys/block "trySome"
        (list (poolStr pool "somePrefix" "((some ") (sys/entryInstr "someShape" (ty/tyI1) "stringStartsWith?" (list "n.aRepr" "somePrefix")))
        (branch "someShape" "rebuild" "bad"))
      (sys/block "rebuild"
        (cons (fieldOf "f0" "v" 0) (cons (valInstr "again" (ty/opConstruct "Option" "some" (list "f0"))) (sameReprInstrs "s" "v" "again")))
        (branch "s.same" "isSome" "bad"))
      (sys/block "isNone" (list (i64 "zero" 0)) (ty/termReturn "zero"))
      (sys/block "isSome" (list (i64 "one" 1)) (ty/termReturn "one"))
      (sys/block "bad" (list (i64 "minusOne" -1)) (ty/termReturn "minusOne"))))

fn errnoErrFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (let [(kinds (errKinds))
        (count (listLength kinds))
        (labelAt (fn [(i Int64)] -> String (cond ((= i 0) "entry") ((>= i count) "other") (else (str "kind" i)))))]
    (helperFn "errnoErr" (list (ty/ssaParam "code" (ty/tyI64))) (ty/tyVal)
      (listAppend
        (fold (fn [(acc (List ty/SsaBlock)) (i Int64)] -> (List ty/SsaBlock)
                (let [(row (optionOr (listGet kinds i) (pair "" "")))]
                  (listAppend acc
                    (list (sys/block (labelAt i)
                            (list (i64 (str "c" i) (fact k (pairFirst row))) (prim (str "is" i) (ty/tyI1) "eqInt" (list "code" (str "c" i))))
                            (branch (str "is" i) (str "hit" i) (labelAt (+ i 1))))
                          (errTextBlock pool (str "hit" i) (pairSecond row))))))
              (list) (range 0 count))
        (list (sys/block "other"
                (list (sys/entryInstr "digits" (ty/tyVal) "stringFromInt64" (list "code"))
                      (poolStr pool "prefix" "io:")
                      (sys/entryInstr "message" (ty/tyVal) "stringConcat" (list "prefix" "digits"))
                      (valInstr "failed" (ty/opConstruct "Result" "err" (list "message"))))
                (ty/termReturn "failed"))))))

fn pollItemFn pool: (Map String Int64) -> ty/SsaFunction
  (helperFn "pollItem" (valParams (list "v")) (ty/tyVal)
    (list
      (sys/block "entry" (reprBytesInstrs "v") (branch "nested" "third" "bad1"))
      (sys/block "third" (letterInstrs "c" "b2") (branch "c.letter" "ctor" "listy"))
      (sys/block "ctor"
        (list (poolStr pool "pairPrefix" "((pair ") (sys/entryInstr "isPair" (ty/tyI1) "stringStartsWith?" (list "repr" "pairPrefix")))
        (branch "isPair" "fromPair" "bad1"))
      (sys/block "fromPair" (list (fieldOf "f0" "v" 0) (fieldOf "f1" "v" 1)) (ty/termJump (edgeArgs "check" (list "f0" "f1"))))
      (sys/block "listy" (list (i64 "close" 41) (prim "isEmpty" (ty/tyI1) "eqInt" (list "b2" "close"))) (branch "isEmpty" "bad1" "fromList"))
      (sys/block "fromList"
        (list (sys/entryInstr "g0" (ty/tyVal) "@listFirst" (list "v")) (sys/entryInstr "rest" (ty/tyVal) "@listRest" (list "v"))
              (sys/entryInstr "short" (ty/tyI1) "listEmpty?" (list "rest")))
        (branch "short" "bad1" "second"))
      (sys/block "second" (list (sys/entryInstr "g1" (ty/tyVal) "@listFirst" (list "rest"))) (ty/termJump (edgeArgs "check" (list "g0" "g1"))))
      (ty/ssaBlock "check" (valParams (list "x" "y"))
        (list (callHelper "ox" (ty/tyVal) "intOf" (list "x")))
        (optionSwitch "ox" "checkY" "bad1"))
      (sys/block "checkY" (list (callHelper "oy" (ty/tyVal) "intOf" (list "y"))) (optionSwitch "oy" "range" "bad1"))
      (sys/block "range"
        (listAppend (list (fieldOf "fdBox" "ox" 0) (unboxI64 "fd" "fdBox")) (outsideInstrs "fd" "fd" 0 (int32Max)))
        (branch "fd.out" "bad2" "good"))
      (sys/block "good"
        (list (fieldOf "maskBox" "oy" 0) (valInstr "item" (ty/opConstruct "Pair" "pair" (list "fdBox" "maskBox"))))
        (ty/termJump (edgeArgs "okItem" (list "item"))))
      (ty/ssaBlock "okItem" (valParams (list "p")) (list (valInstr "okV" (ty/opConstruct "Result" "ok" (list "p")))) (ty/termReturn "okV"))
      (sys/block "bad1" (list (valInstr "one1" (ty/opConst (ty/constInt 1))) (valInstr "bad1V" (ty/opConstruct "Result" "err" (list "one1")))) (ty/termReturn "bad1V"))
      (sys/block "bad2" (list (valInstr "two2" (ty/opConst (ty/constInt 2))) (valInstr "bad2V" (ty/opConstruct "Result" "err" (list "two2")))) (ty/termReturn "bad2V"))))

fn wrapperFn builtin: String params: (List String) blocks: (List ty/SsaBlock) -> ty/SsaFunction
  (ty/ssaFunction (wrapperName builtin) (list) (valParams params) (ty/tyVal) blocks)

fn intArgBlocks label: String arg: String next: String fail: String -> ty/SsaBlock
  (sys/block label (list (callHelper (str label ".opt") (ty/tyVal) "intOf" (list arg))) (optionSwitch (str label ".opt") next fail))

fn fdRangeBlock label: String opt: String next: String -> ty/SsaBlock
  (sys/block label
    (listAppend (list (fieldOf "fdBox" opt 0) (unboxI64 "fd" "fdBox")) (outsideInstrs "fd" "fd" 0 (int32Max)))
    (branch "fd.out" "badFd" next))

fn fdReadFn pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn "fdRead" (list "a" "b")
    (list
      (intArgBlocks "entry" "a" "aInt" "badFd")
      (intArgBlocks "aInt" "b" "ints" "badFd")
      (sys/block "ints"
        (listAppend (list (fieldOf "fdBox" "entry.opt" 0) (unboxI64 "fd" "fdBox") (fieldOf "maxBox" "aInt.opt" 0) (unboxI64 "max" "maxBox"))
          (outsideInstrs "fd" "fd" 0 (int32Max)))
        (branch "fd.out" "badFd" "maxCheck"))
      (sys/block "maxCheck" (outsideInstrs "max" "max" 0 16777216) (branch "max.out" "inval" "sizeCheck"))
      (sys/block "sizeCheck" (list (i64 "zero" 0) (prim "isZero" (ty/tyI1) "eqInt" (list "max" "zero"))) (branch "isZero" "empty" "alloc"))
      (okBlock "empty" (list (poolStr pool "nothing" "")) "nothing")
      (sys/block "alloc"
        (list (sys/callInstr "buf" (ty/tyPtr) "malloc" (list "max")) (prim "bufNull" (ty/tyI1) "rawPtrIsNull" (list "buf")))
        (branch "bufNull" "nomem" "doRead"))
      (sys/block "doRead"
        (list (prim "fd32" (ty/tyI32) "rawNarrowI32" (list "fd")) (sys/callInstr "n" (ty/tyI64) "read" (list "fd32" "buf" "max"))
              (prim "readFailed" (ty/tyI1) "ltInt" (list "n" "zero")))
        (branch "readFailed" "readErr" "readOk"))
      (errnoBlock "readErr" (list (sys/callInstr "readErr.free" (ty/tyI64) "free" (list "buf"))))
      (okBlock "readOk" (list (sys/callInstr "text" (ty/tyVal) "mkStr" (list "buf" "n")) (sys/callInstr "readOk.free" (ty/tyI64) "free" (list "buf"))) "text")
      (errTextBlock pool "badFd" "badFd")
      (errTextBlock pool "inval" "io:22")
      (errTextBlock pool "nomem" "io:12")))

fn fdWriteFn pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn "fdWrite" (list "a" "b")
    (list
      (intArgBlocks "entry" "a" "aInt" "badFd")
      (sys/block "aInt" (list (callHelper "isText" (ty/tyI1) "isString" (list "b"))) (branch "isText" "typed" "inval"))
      (fdRangeBlock "typed" "entry.opt" "write")
      (sys/block "write"
        (list (prim "fd32" (ty/tyI32) "rawNarrowI32" (list "fd")) (sys/callInstr "res" (ty/tyVal) "sysWrite" (list "fd32" "b")))
        (resultSwitchTo "res" "written" "failed"))
      (sys/block "written" (list) (ty/termReturn "res"))
      (resultErrBlock "failed" "res")
      (errTextBlock pool "badFd" "badFd")
      (errTextBlock pool "inval" "io:22")))

fn fdCloseFn pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn "fdClose" (list "a")
    (list
      (intArgBlocks "entry" "a" "aInt" "badFd")
      (fdRangeBlock "aInt" "entry.opt" "close")
      (sys/block "close"
        (list (prim "fd32" (ty/tyI32) "rawNarrowI32" (list "fd")) (sys/callInstr "res" (ty/tyVal) "sysClose" (list "fd32")))
        (resultSwitchTo "res" "closed" "failed"))
      (okUnitBlock "closed")
      (resultErrBlock "failed" "res")
      (errTextBlock pool "badFd" "badFd")))

fn fdNonBlockingFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn "fdNonBlocking" (list "a" "b")
    (list
      (intArgBlocks "entry" "a" "aInt" "badFd")
      (sys/block "aInt" (list (callHelper "flag" (ty/tyI64) "boolOf" (list "b")) (i64 "minusOne" -1) (prim "notBool" (ty/tyI1) "eqInt" (list "flag" "minusOne")))
        (branch "notBool" "inval" "range"))
      (fdRangeBlock "range" "entry.opt" "get")
      (sys/block "get"
        (list (prim "fd32" (ty/tyI32) "rawNarrowI32" (list "fd")) (sys/int32Const "getCmd" (fact k "F_GETFL"))
              (sys/callInstr "got" (ty/tyVal) "sysFcntlGet" (list "fd32" "getCmd")))
        (resultSwitchTo "got" "haveFlags" "getFailed"))
      (sys/block "haveFlags"
        (list (fieldOf "flagsBox" "got" 0) (unboxI64 "flags" "flagsBox") (i64 "nb" (fact k "O_NONBLOCK")) (i64 "one" 1)
              (prim "turnOn" (ty/tyI1) "eqInt" (list "flag" "one")))
        (branch "turnOn" "setOn" "setOff"))
      (sys/block "setOn" (list (prim "withNb" (ty/tyI64) "rawOrI64" (list "flags" "nb"))) (ty/termJump (edgeArgs "apply" (list "withNb"))))
      (sys/block "setOff"
        (list (prim "keep" (ty/tyI64) "rawXorI64" (list "nb" "minusOne")) (prim "withoutNb" (ty/tyI64) "rawAndI64" (list "flags" "keep")))
        (ty/termJump (edgeArgs "apply" (list "withoutNb"))))
      (ty/ssaBlock "apply" (list (ty/ssaParam "next" (ty/tyI64)))
        (list (prim "next32" (ty/tyI32) "rawNarrowI32" (list "next")) (sys/int32Const "setCmd" (fact k "F_SETFL"))
              (sys/callInstr "set" (ty/tyVal) "sysFcntlSet" (list "fd32" "setCmd" "next32")))
        (resultSwitchTo "set" "applied" "setFailed"))
      (okUnitBlock "applied")
      (resultErrBlock "getFailed" "got")
      (resultErrBlock "setFailed" "set")
      (errTextBlock pool "badFd" "badFd")
      (errTextBlock pool "inval" "io:22")))

fn fdPollFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (let [(size (fact k "pollfd.size")) (fdOff (fact k "pollfd.fd")) (evOff (fact k "pollfd.events"))]
    (wrapperFn "fdPoll" (list "a" "b")
      (list
        (sys/block "entry" (list (callHelper "isItems" (ty/tyI1) "isList" (list "a"))) (branch "isItems" "listOk" "inval"))
        (intArgBlocks "listOk" "b" "timeoutInt" "inval")
        (sys/block "timeoutInt"
          (list (fieldOf "msBox" "listOk.opt" 0) (unboxI64 "ms" "msBox") (i64 "minusOne" -1) (prim "tooLow" (ty/tyI1) "ltInt" (list "ms" "minusOne")))
          (branch "tooLow" "inval" "clamp"))
        (sys/block "clamp"
          (list (i64 "intMax" (int32Max)) (prim "tooHigh" (ty/tyI1) "gtInt" (list "ms" "intMax")))
          (ty/termBranch "tooHigh" (edgeArgs "ready" (list "intMax")) (edgeArgs "ready" (list "ms"))))
        (ty/ssaBlock "ready" (list (ty/ssaParam "wait" (ty/tyI64)))
          (list (prim "wait32" (ty/tyI32) "rawNarrowI32" (list "wait")) (i64 "zero" 0) (i64 "one" 1))
          (ty/termJump (edgeArgs "count" (list "zero" "a"))))
        (ty/ssaBlock "count" (list (ty/ssaParam "n" (ty/tyI64)) (ty/ssaParam "xs" (ty/tyVal)))
          (list (sys/entryInstr "counted" (ty/tyI1) "listEmpty?" (list "xs")))
          (branch "counted" "sized" "countNext"))
        (sys/block "countNext"
          (list (sys/entryInstr "xsRest" (ty/tyVal) "@listRest" (list "xs")) (prim "nNext" (ty/tyI64) "addInt" (list "n" "one")))
          (ty/termJump (edgeArgs "count" (list "nNext" "xsRest"))))
        (sys/block "sized" (list (prim "noItems" (ty/tyI1) "eqInt" (list "n" "zero"))) (branch "noItems" "pollNothing" "alloc"))
        (sys/block "pollNothing"
          (list (prim "nullp" (ty/tyPtr) "rawIntToPtr" (list "zero")) (sys/callInstr "rc0" (ty/tyI32) "poll" (list "nullp" "zero" "wait32"))
                (sys/int32Const "zero32" 0) (prim "failed0" (ty/tyI1) "rawLtI32" (list "rc0" "zero32")))
          (branch "failed0" "nothingErr" "nothingOk"))
        (errnoBlock "nothingErr" (list))
        (okBlock "nothingOk" (list (valInstr "noneReady" (ty/opList (list)))) "noneReady")
        (sys/block "alloc"
          (list (i64 "size" size) (prim "bytes" (ty/tyI64) "mulInt" (list "n" "size"))
                (sys/callInstr "pfd" (ty/tyPtr) "malloc" (list "bytes")) (prim "pfdNull" (ty/tyI1) "rawPtrIsNull" (list "pfd"))
                (i64 "fdOff" fdOff) (i64 "evOff" evOff) (i64 "pollIn" (fact k "POLLIN")) (i64 "pollOut" (fact k "POLLOUT")))
          (ty/termBranch "pfdNull" (sys/edgeTo "nomem") (edgeArgs "fill" (list "zero" "a"))))
        (ty/ssaBlock "fill" (list (ty/ssaParam "i" (ty/tyI64)) (ty/ssaParam "ys" (ty/tyVal)))
          (list (sys/entryInstr "filled" (ty/tyI1) "listEmpty?" (list "ys")))
          (branch "filled" "doPoll" "item"))
        (sys/block "item"
          (list (sys/entryInstr "it" (ty/tyVal) "@listFirst" (list "ys")) (callHelper "parsed" (ty/tyVal) "pollItem" (list "it")))
          (resultSwitchTo "parsed" "store" "itemBad"))
        (sys/block "itemBad"
          (list (fieldOf "codeBox" "parsed" 0) (unboxI64 "code" "codeBox") (sys/callInstr "itemBad.free" (ty/tyI64) "free" (list "pfd"))
                (i64 "two" 2) (prim "isFd" (ty/tyI1) "eqInt" (list "code" "two")))
          (branch "isFd" "badFd" "inval"))
        (sys/block "store"
          (list (fieldOf "pr" "parsed" 0) (fieldOf "fdBox" "pr" 0) (unboxI64 "fd" "fdBox") (fieldOf "maskBox" "pr" 1) (unboxI64 "mask" "maskBox")
                (prim "base" (ty/tyI64) "mulInt" (list "i" "size"))
                (prim "atFd" (ty/tyI64) "addInt" (list "base" "fdOff")) (prim "fd32" (ty/tyI32) "rawNarrowI32" (list "fd"))
                (prim "storedFd" (ty/tyI1) "rawStoreI32" (list "pfd" "atFd" "fd32"))
                (prim "inBit" (ty/tyI64) "rawAndI64" (list "mask" "one")) (prim "inEv" (ty/tyI64) "rawMulI64" (list "inBit" "pollIn"))
                (i64 "twoBit" 2) (prim "outMasked" (ty/tyI64) "rawAndI64" (list "mask" "twoBit")) (prim "outBit" (ty/tyI64) "rawLshrI64" (list "outMasked" "one"))
                (prim "outEv" (ty/tyI64) "rawMulI64" (list "outBit" "pollOut"))
                (prim "events" (ty/tyI64) "rawOrI64" (list "inEv" "outEv")) (prim "events32" (ty/tyI32) "rawNarrowI32" (list "events"))
                (prim "atEv" (ty/tyI64) "addInt" (list "base" "evOff"))
                (prim "storedEv" (ty/tyI1) "rawStoreI32" (list "pfd" "atEv" "events32"))
                (sys/entryInstr "ysRest" (ty/tyVal) "@listRest" (list "ys")) (prim "iNext" (ty/tyI64) "addInt" (list "i" "one")))
          (ty/termJump (edgeArgs "fill" (list "iNext" "ysRest"))))
        (sys/block "doPoll"
          (list (sys/callInstr "rc" (ty/tyI32) "poll" (list "pfd" "n" "wait32")) (sys/int32Const "zero32b" 0)
                (prim "pollFailed" (ty/tyI1) "rawLtI32" (list "rc" "zero32b")) (valInstr "noReady" (ty/opList (list))))
          (ty/termBranch "pollFailed" (sys/edgeTo "pollErr") (edgeArgs "collect" (list "n" "noReady"))))
        (errnoBlock "pollErr" (list (sys/callInstr "pollErr.free" (ty/tyI64) "free" (list "pfd"))))
        (ty/ssaBlock "collect" (list (ty/ssaParam "j" (ty/tyI64)) (ty/ssaParam "acc" (ty/tyVal)))
          (list (prim "collected" (ty/tyI1) "leInt" (list "j" "zero")))
          (branch "collected" "finished" "take"))
        (sys/block "take"
          (list (prim "jm" (ty/tyI64) "subInt" (list "j" "one")) (prim "base2" (ty/tyI64) "mulInt" (list "jm" "size"))
                (prim "atEv2" (ty/tyI64) "addInt" (list "base2" "evOff")) (prim "word" (ty/tyI32) "rawLoadI32" (list "pfd" "atEv2"))
                (sys/int32Const "sixteen" 16) (prim "high" (ty/tyI32) "rawLshrI32" (list "word" "sixteen")) (prim "highWide" (ty/tyI64) "rawWidenI32" (list "high"))
                (i64 "low16" 65535) (prim "revents" (ty/tyI64) "rawAndI64" (list "highWide" "low16"))
                (i64 "pollPri" (fact k "POLLPRI")) (prim "inMask" (ty/tyI64) "rawOrI64" (list "pollIn" "pollPri"))
                (prim "inHit" (ty/tyI64) "rawAndI64" (list "revents" "inMask")) (prim "isIn" (ty/tyI1) "neInt" (list "inHit" "zero"))
                (prim "outHit" (ty/tyI64) "rawAndI64" (list "revents" "pollOut")) (prim "isOut" (ty/tyI1) "neInt" (list "outHit" "zero"))
                (i64 "pollHup" (fact k "POLLHUP")) (i64 "pollErrBit" (fact k "POLLERR")) (i64 "pollNval" (fact k "POLLNVAL"))
                (prim "hupErr" (ty/tyI64) "rawOrI64" (list "pollHup" "pollErrBit")) (prim "errMask" (ty/tyI64) "rawOrI64" (list "hupErr" "pollNval"))
                (prim "errHit" (ty/tyI64) "rawAndI64" (list "revents" "errMask")) (prim "isErr" (ty/tyI1) "neInt" (list "errHit" "zero")))
          (ty/termBranch "isIn" (edgeArgs "bitOut" (list "one")) (edgeArgs "bitOut" (list "zero"))))
        (ty/ssaBlock "bitOut" (list (ty/ssaParam "m1" (ty/tyI64)))
          (list (i64 "two3" 2) (prim "with2" (ty/tyI64) "rawOrI64" (list "m1" "two3")))
          (ty/termBranch "isOut" (edgeArgs "bitErr" (list "with2")) (edgeArgs "bitErr" (list "m1"))))
        (ty/ssaBlock "bitErr" (list (ty/ssaParam "m2" (ty/tyI64)))
          (list (i64 "four" 4) (prim "with4" (ty/tyI64) "rawOrI64" (list "m2" "four")))
          (ty/termBranch "isErr" (edgeArgs "classified" (list "with4")) (edgeArgs "classified" (list "m2"))))
        (ty/ssaBlock "classified" (list (ty/ssaParam "rm" (ty/tyI64)))
          (list (prim "quiet" (ty/tyI1) "eqInt" (list "rm" "zero")))
          (ty/termBranch "quiet" (edgeArgs "collect" (list "jm" "acc")) (sys/edgeTo "readyAdd")))
        (sys/block "readyAdd"
          (list (prim "atFd2" (ty/tyI64) "addInt" (list "base2" "fdOff")) (prim "fdWord" (ty/tyI32) "rawLoadI32" (list "pfd" "atFd2"))
                (prim "fdWide" (ty/tyI64) "rawWidenI32" (list "fdWord")) (sys/boxInstr "fdOut" "fdWide") (sys/boxInstr "rmOut" "rm")
                (valInstr "readyPair" (ty/opConstruct "Pair" "pair" (list "fdOut" "rmOut")))
                (sys/entryInstr "accNext" (ty/tyVal) "cons" (list "readyPair" "acc")))
          (ty/termJump (edgeArgs "collect" (list "jm" "accNext"))))
        (okBlock "finished" (list (sys/callInstr "finished.free" (ty/tyI64) "free" (list "pfd"))) "acc")
        (errTextBlock pool "badFd" "badFd")
        (errTextBlock pool "inval" "io:22")
        (errTextBlock pool "nomem" "io:12"))))

fn cpuCountFn facts: libc/TripleFacts k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn "cpuCount" (list)
    (list
      (sys/block "entry"
        (list (sys/callInstr "errp" (ty/tyPtr) facts.errnoAccessor (list)) (i64 "zero" 0) (sys/int32Const "zero32" 0)
              (prim "cleared" (ty/tyI1) "rawStoreI32" (list "errp" "zero" "zero32"))
              (sys/int32Const "name" (fact k "_SC_NPROCESSORS_ONLN")) (sys/callInstr "c" (ty/tyI64) "sysconf" (list "name"))
              (i64 "one" 1) (prim "none" (ty/tyI1) "ltInt" (list "c" "one")))
        (branch "none" "failed" "counted"))
      (okBlock "counted" (list (sys/boxInstr "cBox" "c")) "cBox")
      (sys/block "failed"
        (list (sys/callInstr "e" (ty/tyI64) "sysErrnoValue" (list)) (prim "unset" (ty/tyI1) "eqInt" (list "e" "zero")))
        (branch "unset" "noErrno" "mapped"))
      (errTextBlock pool "noErrno" "io:38")
      (mapErrnoBlock "mapped" "e")))

fn platformInfoFn k: (Map String Int64) -> ty/SsaFunction
  (let [(size (fact k "utsname.size")) (sysnameOff (fact k "utsname.sysname")) (releaseOff (fact k "utsname.release")) (machineOff (fact k "utsname.machine"))]
    (wrapperFn "platformInfo" (list)
      (listAppend
        (list
          (sys/block "entry"
            (list (i64 "size" size) (sys/callInstr "un" (ty/tyPtr) "malloc" (list "size")) (prim "unNull" (ty/tyI1) "rawPtrIsNull" (list "un")))
            (branch "unNull" "allocErr" "call"))
          (errnoBlock "allocErr" (list))
          (sys/block "call"
            (list (sys/callInstr "rc" (ty/tyI32) "uname" (list "un")) (sys/int32Const "zero32" 0) (prim "failed" (ty/tyI1) "rawNeI32" (list "rc" "zero32")))
            (branch "failed" "fieldErr" "cstr.os.alloc"))
          (errnoBlock "fieldErr" (list (sys/callInstr "fieldErr.free" (ty/tyI64) "free" (list "un")))))
        (listAppend (sys/cstrFieldBlocks "os" "un" sysnameOff (- size sysnameOff) "fieldErr" "gotOs")
          (listAppend (list (ty/ssaBlock "gotOs" (valParams (list "osText")) (list) (ty/termJump (sys/edgeTo "cstr.release.alloc"))))
            (listAppend (sys/cstrFieldBlocks "release" "un" releaseOff (- size releaseOff) "fieldErr" "gotRelease")
              (listAppend (list (ty/ssaBlock "gotRelease" (valParams (list "releaseText")) (list) (ty/termJump (sys/edgeTo "cstr.machine.alloc"))))
                (listAppend (sys/cstrFieldBlocks "machine" "un" machineOff (- size machineOff) "fieldErr" "gotMachine")
                  (list (ty/ssaBlock "gotMachine" (valParams (list "machineText"))
                          (list (sys/callInstr "un.free" (ty/tyI64) "free" (list "un"))
                                (valInstr "info" (ty/opRecord "PlatformInfo" (list "os" "release" "machine") (list "osText" "releaseText" "machineText")))
                                (valInstr "okInfo" (ty/opConstruct "Result" "ok" (list "info"))))
                          (ty/termReturn "okInfo")))))))))))

fn padBlocks prefix: String n: String pool: (Map String Int64) join: String -> (List ty/SsaBlock)
  (list
    (sys/block (str prefix ".check") (list (i64 (str prefix ".ten") 10) (prim (str prefix ".small") (ty/tyI1) "ltInt" (list n (str prefix ".ten"))))
      (branch (str prefix ".small") (str prefix ".pad") (str prefix ".plain")))
    (sys/block (str prefix ".pad")
      (list (poolStr pool (str prefix ".zeroText") "0") (sys/entryInstr (str prefix ".digits") (ty/tyVal) "stringFromInt64" (list n))
            (sys/entryInstr (str prefix ".padded") (ty/tyVal) "stringConcat" (list (str prefix ".zeroText") (str prefix ".digits"))))
      (ty/termJump (edgeArgs join (list (str prefix ".padded")))))
    (sys/block (str prefix ".plain") (list (sys/entryInstr (str prefix ".text") (ty/tyVal) "stringFromInt64" (list n)))
      (ty/termJump (edgeArgs join (list (str prefix ".text"))))))

fn localDateFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn "localDate" (list)
    (listAppend
      (list
        (sys/block "entry"
          (list (callHelper "nsBox" (ty/tyVal) "nowNs" (list)) (unboxI64 "ns" "nsBox") (i64 "billion" 1000000000) (prim "secs" (ty/tyI64) "quotInt" (list "ns" "billion"))
                (sys/callInstr "tm" (ty/tyVal) "sysLocaltime" (list "secs")))
          (resultSwitchTo "tm" "format" "failed"))
        (sys/block "failed"
          (list (fieldOf "eBox" "tm" 0) (unboxI64 "e" "eBox") (i64 "zero" 0) (prim "unset" (ty/tyI1) "eqInt" (list "e" "zero")))
          (branch "unset" "overflow" "mapped"))
        (sys/block "overflow" (list (i64 "eoverflow" (fact k "EOVERFLOW"))) (ty/termJump (edgeArgs "mappedCode" (list "eoverflow"))))
        (sys/block "mapped" (list) (ty/termJump (edgeArgs "mappedCode" (list "e"))))
        (ty/ssaBlock "mappedCode" (list (ty/ssaParam "code" (ty/tyI64)))
          (list (callHelper "mappedV" (ty/tyVal) "errnoErr" (list "code")))
          (ty/termReturn "mappedV"))
        (sys/block "format"
          (list (fieldOf "fields" "tm" 0)
                (sys/entryInstr "afterSec" (ty/tyVal) "@listRest" (list "fields")) (sys/entryInstr "afterMin" (ty/tyVal) "@listRest" (list "afterSec"))
                (sys/entryInstr "afterHour" (ty/tyVal) "@listRest" (list "afterMin")) (sys/entryInstr "mdayBox" (ty/tyVal) "@listFirst" (list "afterHour"))
                (sys/entryInstr "afterMday" (ty/tyVal) "@listRest" (list "afterHour")) (sys/entryInstr "monBox" (ty/tyVal) "@listFirst" (list "afterMday"))
                (sys/entryInstr "afterMon" (ty/tyVal) "@listRest" (list "afterMday")) (sys/entryInstr "yearBox" (ty/tyVal) "@listFirst" (list "afterMon"))
                (unboxI64 "mday" "mdayBox") (unboxI64 "mon0" "monBox") (unboxI64 "year0" "yearBox")
                (i64 "one" 1) (prim "mon" (ty/tyI64) "addInt" (list "mon0" "one"))
                (i64 "base" 1900) (prim "year" (ty/tyI64) "addInt" (list "year0" "base"))
                (sys/entryInstr "yearText" (ty/tyVal) "stringFromInt64" (list "year")) (poolStr pool "dash" "-"))
          (ty/termJump (sys/edgeTo "mon.check"))))
      (listAppend (padBlocks "mon" "mon" pool "monDone")
        (listAppend (list (ty/ssaBlock "monDone" (valParams (list "monText")) (list) (ty/termJump (sys/edgeTo "day.check"))))
          (listAppend (padBlocks "day" "mday" pool "dayDone")
            (list (ty/ssaBlock "dayDone" (valParams (list "dayText"))
                    (list (sys/entryInstr "s1" (ty/tyVal) "stringConcat" (list "yearText" "dash"))
                          (sys/entryInstr "s2" (ty/tyVal) "stringConcat" (list "s1" "monText"))
                          (sys/entryInstr "s3" (ty/tyVal) "stringConcat" (list "s2" "dash"))
                          (sys/entryInstr "date" (ty/tyVal) "stringConcat" (list "s3" "dayText"))
                          (valInstr "okDate" (ty/opConstruct "Result" "ok" (list "date"))))
                    (ty/termReturn "okDate"))))))))

fn environInstrs facts: libc/TripleFacts -> (List ty/SsaInstr)
  (if (stringStartsWith? facts.triple "darwin")
    (list (sys/callInstr "envpp" (ty/tyPtr) "_NSGetEnviron" (list)) (i64 "off0" 0)
          (prim "envRaw" (ty/tyI64) "rawLoadI64" (list "envpp" "off0")) (prim "envp" (ty/tyPtr) "rawIntToPtr" (list "envRaw")))
    (list (ty/ssaInstr "envp" (ty/tyPtr) (ty/opLoadGlobal "environ"))))

fn envListFn facts: libc/TripleFacts -> ty/SsaFunction
  (wrapperFn "envList" (list)
    (list
      (sys/block "entry" (listAppend (environInstrs facts) (list (i64 "zero" 0) (i64 "one" 1) (i64 "eight" 8) (valInstr "nil" (ty/opList (list)))))
        (ty/termJump (edgeArgs "count" (list "zero"))))
      (ty/ssaBlock "count" (list (ty/ssaParam "i" (ty/tyI64)))
        (list (prim "off" (ty/tyI64) "mulInt" (list "i" "eight")) (prim "slot" (ty/tyI64) "rawLoadI64" (list "envp" "off"))
              (prim "atEnd" (ty/tyI1) "eqInt" (list "slot" "zero")))
        (ty/termBranch "atEnd" (edgeArgs "build" (list "i" "nil")) (sys/edgeTo "countNext")))
      (sys/block "countNext" (list (prim "iNext" (ty/tyI64) "addInt" (list "i" "one"))) (ty/termJump (edgeArgs "count" (list "iNext"))))
      (ty/ssaBlock "build" (list (ty/ssaParam "j" (ty/tyI64)) (ty/ssaParam "acc" (ty/tyVal)))
        (list (prim "done" (ty/tyI1) "leInt" (list "j" "zero")))
        (branch "done" "finished" "take"))
      (sys/block "take"
        (list (prim "jm" (ty/tyI64) "subInt" (list "j" "one")) (prim "off2" (ty/tyI64) "mulInt" (list "jm" "eight"))
              (prim "raw" (ty/tyI64) "rawLoadI64" (list "envp" "off2")) (prim "entryPtr" (ty/tyPtr) "rawIntToPtr" (list "raw"))
              (sys/callInstr "len" (ty/tyI64) "strlen" (list "entryPtr")) (sys/callInstr "text" (ty/tyVal) "mkStr" (list "entryPtr" "len"))
              (sys/entryInstr "accNext" (ty/tyVal) "cons" (list "text" "acc")))
        (ty/termJump (edgeArgs "build" (list "jm" "accNext"))))
      (sys/block "finished" (list) (ty/termReturn "acc"))))

fn procSelfFn -> ty/SsaFunction
  (wrapperFn "procSelf" (list)
    (list (sys/block "entry"
            (list (sys/callInstr "pid32" (ty/tyI32) "getpid" (list)) (prim "pid" (ty/tyI64) "rawWidenI32" (list "pid32")) (sys/boxInstr "pidBox" "pid"))
            (ty/termReturn "pidBox"))))

fn procAliveFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn "procAlive?" (list "a")
    (list
      (intArgBlocks "entry" "a" "num" "inval")
      (sys/block "num"
        (listAppend (list (fieldOf "pidBox" "entry.opt" 0) (unboxI64 "pid" "pidBox")) (outsideInstrs "pid" "pid" 1 (int32Max)))
        (branch "pid.out" "inval" "probe"))
      (sys/block "probe"
        (list (prim "pid32" (ty/tyI32) "rawNarrowI32" (list "pid")) (sys/int32Const "sig0" 0)
              (sys/callInstr "rc" (ty/tyI32) "kill" (list "pid32" "sig0")) (prim "sent" (ty/tyI1) "rawEqI32" (list "rc" "sig0")))
        (branch "sent" "alive" "failed"))
      (okBlock "alive" (list (valBool "yes" true)) "yes")
      (sys/block "failed"
        (list (sys/callInstr "e" (ty/tyI64) "sysErrnoValue" (list)) (i64 "eperm" (fact k "EPERM")) (prim "isPerm" (ty/tyI1) "eqInt" (list "e" "eperm")))
        (branch "isPerm" "alive" "notPerm"))
      (sys/block "notPerm" (list (i64 "esrch" (fact k "ESRCH")) (prim "isGone" (ty/tyI1) "eqInt" (list "e" "esrch"))) (branch "isGone" "dead" "mapped"))
      (okBlock "dead" (list (valBool "no" false)) "no")
      (mapErrnoBlock "mapped" "e")
      (errTextBlock pool "inval" "io:22")))

fn procKillFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (let [(names (signalNames))
        (count (listLength names))
        (sigLabel (fn [(i Int64)] -> String (if (>= i count) "inval" (str "sig" i))))]
    (wrapperFn "procKill" (list "a" "b")
      (listAppend
        (list
          (intArgBlocks "entry" "a" "aInt" "inval")
          (sys/block "aInt" (list (callHelper "isText" (ty/tyI1) "isString" (list "b"))) (branch "isText" "range" "inval"))
          (sys/block "range"
            (list (fieldOf "pidBox" "entry.opt" 0) (unboxI64 "pid" "pidBox")
                  (i64 "intMax" (int32Max)) (i64 "negMax" (- 0 (int32Max))) (i64 "minusOne" -1) (i64 "one" 1)
                  (prim "above" (ty/tyI1) "gtInt" (list "pid" "intMax")) (prim "below" (ty/tyI1) "ltInt" (list "pid" "negMax"))
                  (prim "geMinusOne" (ty/tyI1) "geInt" (list "pid" "minusOne")) (prim "leOne" (ty/tyI1) "leInt" (list "pid" "one"))
                  (prim "near" (ty/tyI1) "andBool" (list "geMinusOne" "leOne")) (prim "outer" (ty/tyI1) "orBool" (list "above" "below"))
                  (prim "bad" (ty/tyI1) "orBool" (list "outer" "near")))
            (branch "bad" "inval" (sigLabel 0))))
        (listAppend
          (map (fn [(i Int64)] -> ty/SsaBlock
                 (let [(name (optionOr (listGet names i) ""))]
                   (sys/block (sigLabel i)
                     (list (poolStr pool (str "name" i) name) (sys/entryInstr (str "is" i) (ty/tyI1) "=" (list "b" (str "name" i)))
                           (i64 (str "num" i) (fact k name)))
                     (ty/termBranch (str "is" i) (edgeArgs "send" (list (str "num" i))) (sys/edgeTo (sigLabel (+ i 1)))))))
               (range 0 count))
          (list
            (ty/ssaBlock "send" (list (ty/ssaParam "sig" (ty/tyI64)))
              (list (prim "pid32" (ty/tyI32) "rawNarrowI32" (list "pid")) (prim "sig32" (ty/tyI32) "rawNarrowI32" (list "sig"))
                    (sys/callInstr "rc" (ty/tyI32) "kill" (list "pid32" "sig32")) (sys/int32Const "zero32" 0) (prim "sent" (ty/tyI1) "rawEqI32" (list "rc" "zero32")))
              (branch "sent" "done" "killErr"))
            (okUnitBlock "done")
            (errnoBlock "killErr" (list))
            (errTextBlock pool "inval" "io:22"))))))

fn procExePathFn -> ty/SsaFunction
  (wrapperFn "procExePath" (list)
    (list
      (sys/block "entry" (list (sys/callInstr "res" (ty/tyVal) "sysExePath" (list))) (resultSwitchTo "res" "found" "failed"))
      (sys/block "found" (list) (ty/termReturn "res"))
      (resultErrBlock "failed" "res")))

fn ioTrapInstrs pool: (Map String Int64) label: String prefix: String code: String -> (List ty/SsaInstr)
  (list (prim (str label ".code32") (ty/tyI32) "rawNarrowI32" (list code))
        (sys/callInstr (str label ".reasonPtr") (ty/tyPtr) "strerror" (list (str label ".code32")))
        (sys/callInstr (str label ".reasonLen") (ty/tyI64) "strlen" (list (str label ".reasonPtr")))
        (sys/callInstr (str label ".reason") (ty/tyVal) "mkStr" (list (str label ".reasonPtr") (str label ".reasonLen")))
        (poolStr pool (str label ".prefix") prefix)
        (sys/entryInstr (str label ".message") (ty/tyVal) "stringConcat" (list (str label ".prefix") (str label ".reason")))
        (poolStr pool (str label ".kind") "ERR_IO")
        (valInstr (str label ".trapped") (ty/opBuiltin "trap" (list (str label ".kind") (str label ".message")))))

fn clockFn builtin: String clockId: Int64 pool: (Map String Int64) -> ty/SsaFunction
  (wrapperFn builtin (list)
    (list
      (sys/block "entry" (list (sys/int32Const "clock" clockId) (sys/callInstr "res" (ty/tyVal) "sysClockGettime" (list "clock")))
        (resultSwitchTo "res" "read" "failed"))
      (sys/block "read"
        (list (fieldOf "parts" "res" 0)
              (sys/entryInstr "secBox" (ty/tyVal) "@listFirst" (list "parts"))
              (sys/entryInstr "rest" (ty/tyVal) "@listRest" (list "parts"))
              (sys/entryInstr "nsecBox" (ty/tyVal) "@listFirst" (list "rest"))
              (unboxI64 "sec" "secBox") (unboxI64 "nsec" "nsecBox")
              (i64 "billion" 1000000000)
              (prim "secNs" (ty/tyI64) "mulInt" (list "sec" "billion"))
              (prim "ns" (ty/tyI64) "addInt" (list "secNs" "nsec"))
              (sys/boxInstr "nsBox" "ns"))
        (ty/termReturn "nsBox"))
      (sys/block "failed" (listAppend (list (fieldOf "codeBox" "res" 0) (unboxI64 "code" "codeBox")) (ioTrapInstrs pool "failed" (str builtin ": ") "code"))
        (ty/termUnreachable))))

fn sleepMsFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (let [(size (fact k "timespec.size")) (secOff (fact k "timespec.tv_sec")) (nsecOff (fact k "timespec.tv_nsec"))]
    (wrapperFn "sleepMs" (list "ms")
      (list
        (sys/block "entry" (list (callHelper "tag" (ty/tyI64) "tagOf" (list "ms")) (i64 "intTag" 2) (prim "isInt" (ty/tyI1) "eqInt" (list "tag" "intTag")))
          (branch "isInt" "checked" "badType"))
        (sys/block "badType" (list (poolStr pool "badType.prefix" "sleepMs expects Int, got ")
                                   (callHelper "badType.name" (ty/tyVal) "clockTagName" (list "tag"))
                                   (sys/entryInstr "badType.message" (ty/tyVal) "stringConcat" (list "badType.prefix" "badType.name"))
                                   (poolStr pool "badType.kind" "ERR_TYPE")
                                   (valInstr "badType.trapped" (ty/opBuiltin "trap" (list "badType.kind" "badType.message"))))
          (ty/termUnreachable))
        (sys/block "checked" (list (unboxI64 "n" "ms") (i64 "zero" 0) (prim "negative" (ty/tyI1) "ltInt" (list "n" "zero")))
          (branch "negative" "range" "split"))
        (sys/block "range" (list (poolStr pool "range.head" "sleepMs: ")
                                 (sys/entryInstr "range.number" (ty/tyVal) "stringFromInt64" (list "n"))
                                 (sys/entryInstr "range.part" (ty/tyVal) "stringConcat" (list "range.head" "range.number"))
                                 (poolStr pool "range.tail" " is negative")
                                 (sys/entryInstr "range.message" (ty/tyVal) "stringConcat" (list "range.part" "range.tail"))
                                 (poolStr pool "range.kind" "ERR_RANGE")
                                 (valInstr "range.trapped" (ty/opBuiltin "trap" (list "range.kind" "range.message"))))
          (ty/termUnreachable))
        (sys/block "split" (list (i64 "thousand" 1000) (prim "sec" (ty/tyI64) "quotInt" (list "n" "thousand"))
                                 (prim "msRest" (ty/tyI64) "remInt" (list "n" "thousand")) (i64 "million" 1000000)
                                 (prim "nsec" (ty/tyI64) "mulInt" (list "msRest" "million"))
                                 (i64 "size" size) (sys/callInstr "req" (ty/tyPtr) "malloc" (list "size"))
                                 (prim "reqNull" (ty/tyI1) "rawPtrIsNull" (list "req")))
          (branch "reqNull" "reqFailed" "remAlloc"))
        (sys/block "reqFailed" (list (sys/callInstr "reqFailed.errno" (ty/tyI64) "sysErrnoValue" (list)))
          (ty/termJump (edgeArgs "raise" (list "reqFailed.errno"))))
        (sys/block "remAlloc" (list (sys/callInstr "rem" (ty/tyPtr) "malloc" (list "size")) (prim "remNull" (ty/tyI1) "rawPtrIsNull" (list "rem")))
          (branch "remNull" "remFailed" "store"))
        (sys/block "remFailed" (list (sys/callInstr "remFailed.errno" (ty/tyI64) "sysErrnoValue" (list)) (sys/callInstr "remFailed.free" (ty/tyI64) "free" (list "req")))
          (ty/termJump (edgeArgs "raise" (list "remFailed.errno"))))
        (sys/block "store" (list (i64 "secOff" secOff) (prim "store.sec" (ty/tyI1) "rawStoreI64" (list "req" "secOff" "sec"))
                                 (i64 "nsecOff" nsecOff) (prim "store.nsec" (ty/tyI1) "rawStoreI64" (list "req" "nsecOff" "nsec")))
          (ty/termJump (sys/edgeTo "sleep")))
        (sys/block "sleep" (list (sys/callInstr "call.raw" (ty/tyI32) "nanosleep" (list "req" "rem")) (prim "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))
                                 (prim "call.failed" (ty/tyI1) "neInt" (list "call.n" "zero")))
          (branch "call.failed" "failed" "done"))
        (sys/block "failed" (list (sys/callInstr "failed.errno" (ty/tyI64) "sysErrnoValue" (list)) (i64 "eintr" (fact k "EINTR"))
                                  (prim "interrupted" (ty/tyI1) "eqInt" (list "failed.errno" "eintr")))
          (branch "interrupted" "resume" "sleepFailed"))
        (sys/block "resume" (list (prim "left.sec" (ty/tyI64) "rawLoadI64" (list "rem" "secOff")) (prim "left.nsec" (ty/tyI64) "rawLoadI64" (list "rem" "nsecOff"))
                                  (prim "resume.sec" (ty/tyI1) "rawStoreI64" (list "req" "secOff" "left.sec"))
                                  (prim "resume.nsec" (ty/tyI1) "rawStoreI64" (list "req" "nsecOff" "left.nsec")))
          (ty/termJump (sys/edgeTo "sleep")))
        (sys/block "sleepFailed" (list (sys/callInstr "sleepFailed.req" (ty/tyI64) "free" (list "req")) (sys/callInstr "sleepFailed.rem" (ty/tyI64) "free" (list "rem")))
          (ty/termJump (edgeArgs "raise" (list "failed.errno"))))
        (sys/block "done" (list (sys/callInstr "done.req" (ty/tyI64) "free" (list "req")) (sys/callInstr "done.rem" (ty/tyI64) "free" (list "rem"))
                                (valInstr "unit" (ty/opConst (ty/constUnit))))
          (ty/termReturn "unit"))
        (ty/ssaBlock "raise" (list (ty/ssaParam "code" (ty/tyI64))) (ioTrapInstrs pool "raise" "sleepMs: nanosleep: " "code") (ty/termUnreachable)))))

fn clockTagNames -> (List String)
  (list "Unit" "Bool" "Int" "Float" "Keyword" "String" "List" "Record" "Variant" "Fn" "Builtin" "Bytes" "F64Array" "I64Array" "I8Array" "Handle")

fn clockStrings -> (List String)
  (listAppend (list "ERR_IO" "ERR_RANGE" "ERR_TYPE" "nowNs: " "monotonicNs: " "sleepMs: nanosleep: " "sleepMs expects Int, got " "sleepMs: " " is negative" (tagGuardText) "?")
    (clockTagNames))

fn clockTagNameFn pool: (Map String Int64) -> ty/SsaFunction
  (let [(names (clockTagNames))
        (n (listLength names))
        (label (fn [(i Int64)] -> String (if (= i 0) "entry" (str "check" i))))]
    (helperFn "clockTagName" (list (ty/ssaParam "tag" (ty/tyI64))) (ty/tyVal)
      (listAppend
        (map (fn [(i Int64)] -> ty/SsaBlock
               (sys/block (label i) (list (i64 (str "k" i) i) (prim (str "is" i) (ty/tyI1) "eqInt" (list "tag" (str "k" i))))
                 (branch (str "is" i) (str "name" i) (if (= i (- n 1)) "unknown" (label (+ i 1))))))
             (range 0 n))
        (listAppend
          (map (fn [(i Int64)] -> ty/SsaBlock
                 (sys/block (str "name" i) (list (poolStr pool (str "text" i) (optionOr (listGet names i) "?"))) (ty/termReturn (str "text" i))))
               (range 0 n))
          (list (sys/block "unknown" (list (poolStr pool "text.unknown" "?")) (ty/termReturn "text.unknown")))))))

fn clockTableFunctions facts: libc/TripleFacts pool: (Map String Int64) -> (Result (List ty/SsaFunction) String)
  (mt (sysFacts facts)
    ((err e) (err e))
    ((ok k)
      (mt (sys/sysClockGettimeFn facts)
        ((err e) (err e))
        ((ok clockGettime)
          (ok (list (sys/sysErrnoValueFn facts) clockGettime (tagOfFn) (tagCheckFn pool) (clockTagNameFn pool)
                    (clockFn "nowNs" (fact k "CLOCK_REALTIME") pool) (clockFn "monotonicNs" (fact k "CLOCK_MONOTONIC") pool) (sleepMsFn k pool)))))))

fn sysTableFunctions facts: libc/TripleFacts pool: (Map String Int64) -> (Result (List ty/SsaFunction) String)
  (mt (sysFacts facts)
    ((err e) (err e))
    ((ok k)
      (mt (sys/sysLocaltimeFn facts)
        ((err e) (err e))
        ((ok localtime)
          (mt (sys/sysExePathFn facts)
            ((err e) (err e))
            ((ok exePath)
              (mt (sys/sysClockGettimeFn facts)
                ((err e) (err e))
                ((ok clockGettime)
              (ok (list (sys/sysErrnoValueFn facts) (sys/sysWriteFn) (sys/sysCloseFn) (sys/sysFcntlGetFn) (sys/sysFcntlSetFn) localtime exePath
                        (intOfFn) (isStringFn) (boolOfFn) (tagOfFn) (tagCheckFn pool) (isListFn) (isStrFn pool) (isBytesFn pool) (optionArgFn pool) (errnoErrFn k pool) (pollItemFn pool)
                        (fdReadFn pool) (fdWriteFn pool) (fdCloseFn pool) (fdPollFn k pool) (fdNonBlockingFn k pool)
                        (cpuCountFn facts k pool) (platformInfoFn k) (localDateFn k pool) (envListFn facts)
                        (procSelfFn) (procAliveFn k pool) (procKillFn k pool) (procExePathFn)
                        clockGettime (clockFn "nowNs" (fact k "CLOCK_REALTIME") pool)))))))))))

fn sysTableAll facts: libc/TripleFacts pool: (Map String Int64) -> (Result (List ty/SsaFunction) String)
  (mt (sysTableFunctions facts pool)
    ((err e) (err e))
    ((ok base)
      (mt (sys/fileRouteFunctions facts pool)
        ((err e) (err e))
        ((ok files)
          (mt (proc/procRouteFunctions facts pool)
            ((err e) (err e))
            ((ok procs) (ok (listAppend base (listAppend files procs)))))))))
