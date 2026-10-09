(module asl-target-llvm/sysNet
  :x [sysNetExterns sysNetFunctions tcpListenFn tcpConnectFn sockAcceptFn sockLocalPortFn unixListenFn unixConnectFn socketPairFn sendFdFn recvFdFn]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sys :a sys)])


fn structOffset facts: libc/TripleFacts structName: String field: String -> (Result Int64 String)
  (mt (libc/pairFind facts.structs structName)
    ((none) (err (str "libc.asl has no " structName " struct row for triple " facts.triple)))
    ((some sf) (mt (libc/structFieldOffset sf field)
                  ((none) (err (str "libc.asl's " structName " row for triple " facts.triple " has no field " field)))
                  ((some off) (ok off)))))

fn structByteSize facts: libc/TripleFacts structName: String -> (Result Int64 String)
  (mt (libc/structSize facts structName)
    ((none) (err (str "libc.asl has no sizeof for " structName " on triple " facts.triple)))
    ((some sz) (ok sz)))

fn constOrErr facts: libc/TripleFacts name: String -> (Result Int64 String)
  (mt (libc/libcConst facts name)
    ((none) (err (str "libc.asl has no " name " const row for triple " facts.triple)))
    ((some v) (ok v)))

fn constructResult dest: String variant: String field: String -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opConstruct "Result" variant (list field)))

fn freeInstr dest: String ptrName: String -> ty/SsaInstr
  (sys/callInstr dest (ty/tyI64) "free" (list ptrName))

fn stringToPtrInstrs dest: String v: String -> (List ty/SsaInstr)
  (list (sys/int32Const (str dest ".repr") 0)
        (sys/callInstr dest (ty/tyPtr) "valToCStr" (list v (str dest ".repr"))))

fn zeroByteInstrs destPtr: String i: Int64 prefix: String zeroVar: String -> (List ty/SsaInstr)
  (let [(offName (str prefix ".zo" (stringFromInt64 i))) (stName (str prefix ".zs" (stringFromInt64 i)))]
    (list (sys/int64Const offName i)
          (sys/primInstr stName (ty/tyI1) "rawStoreI8" (list destPtr offName zeroVar))))

fn zeroBytesLoop destPtr: String i: Int64 n: Int64 prefix: String zeroVar: String -> (List ty/SsaInstr)
  (if (>= i n) (list) (listAppend (zeroByteInstrs destPtr i prefix zeroVar) (zeroBytesLoop destPtr (+ i 1) n prefix zeroVar)))

fn zeroBytesInstrs destPtr: String n: Int64 prefix: String -> (List ty/SsaInstr)
  (let [(zeroVar (str prefix ".zb"))]
    (cons (sys/int32Const zeroVar 0) (zeroBytesLoop destPtr 0 n prefix zeroVar)))

fn fdCloexecBlocks facts: libc/TripleFacts prefix: String fdName: String okEdge: ty/SsaEdge errLabel: String -> (Result (List ty/SsaBlock) String)
  (mt (constOrErr facts "F_GETFD")
    ((err e) (err e))
    ((ok getfdCmd)
     (mt (constOrErr facts "F_SETFD")
       ((err e) (err e))
       ((ok setfdCmd)
        (mt (constOrErr facts "FD_CLOEXEC")
          ((err e) (err e))
          ((ok fdCloexec)
           (ok (list
             (sys/block (str prefix ".cloGet")
               (list (sys/int32Const (str prefix ".getfdCmd") getfdCmd)
                     (sys/callInstr (str prefix ".flags") (ty/tyI32) "fcntl" (list fdName (str prefix ".getfdCmd")))
                     (sys/int32Const (str prefix ".z1") 0)
                     (sys/primInstr (str prefix ".flagsErr") (ty/tyI1) "rawLtI32" (list (str prefix ".flags") (str prefix ".z1"))))
               (ty/termBranch (str prefix ".flagsErr") (sys/edgeTo (str prefix ".cloGetErr")) (sys/edgeTo (str prefix ".cloSet"))))
             (sys/block (str prefix ".cloGetErr")
               (list (sys/callInstr (str prefix ".errno1") (ty/tyI64) "sysErrnoValue" (list))
                     (sys/callInstr (str prefix ".closeAfterGet") (ty/tyI32) "close" (list fdName)))
               (ty/termJump (ty/ssaEdge errLabel (list (str prefix ".errno1")))))
             (sys/block (str prefix ".cloSet")
               (list (sys/int32Const (str prefix ".fdcloexecC") fdCloexec)
                     (sys/primInstr (str prefix ".newFlags") (ty/tyI32) "rawOrI32" (list (str prefix ".flags") (str prefix ".fdcloexecC")))
                     (sys/int32Const (str prefix ".setfdCmd") setfdCmd)
                     (sys/callInstr (str prefix ".setr") (ty/tyI32) "fcntl" (list fdName (str prefix ".setfdCmd") (str prefix ".newFlags")))
                     (sys/int32Const (str prefix ".z2") 0)
                     (sys/primInstr (str prefix ".setErr") (ty/tyI1) "rawLtI32" (list (str prefix ".setr") (str prefix ".z2"))))
               (ty/termBranch (str prefix ".setErr") (sys/edgeTo (str prefix ".cloSetErr")) okEdge))
             (sys/block (str prefix ".cloSetErr")
               (list (sys/callInstr (str prefix ".errno2") (ty/tyI64) "sysErrnoValue" (list))
                     (sys/callInstr (str prefix ".closeAfterSet") (ty/tyI32) "close" (list fdName)))
               (ty/termJump (ty/ssaEdge errLabel (list (str prefix ".errno2")))))))))))))

fn socketCloexecBlocks facts: libc/TripleFacts prefix: String domainConst: Int64 typeConst: Int64 okLabel: String errLabel: String -> (Result (List ty/SsaBlock) String)
  (mt (fdCloexecBlocks facts prefix (str prefix ".fd") (ty/ssaEdge okLabel (list (str prefix ".fd"))) errLabel)
    ((err e) (err e))
    ((ok cloexecBlocks)
     (ok (cons
           (sys/block (str prefix ".sock")
             (list (sys/int32Const (str prefix ".dom") domainConst)
                   (sys/int32Const (str prefix ".ty") typeConst)
                   (sys/int32Const (str prefix ".proto") 0)
                   (sys/callInstr (str prefix ".fd") (ty/tyI32) "socket" (list (str prefix ".dom") (str prefix ".ty") (str prefix ".proto")))
                   (sys/int32Const (str prefix ".z0") 0)
                   (sys/primInstr (str prefix ".fdErr") (ty/tyI1) "rawLtI32" (list (str prefix ".fd") (str prefix ".z0"))))
             (ty/termBranch (str prefix ".fdErr") (sys/edgeTo (str prefix ".sockErr")) (sys/edgeTo (str prefix ".cloGet"))))
           (cons
             (sys/block (str prefix ".sockErr")
               (list (sys/callInstr (str prefix ".errno0") (ty/tyI64) "sysErrnoValue" (list)))
               (ty/termJump (ty/ssaEdge errLabel (list (str prefix ".errno0")))))
             cloexecBlocks)))))


fn socketExtern -> ty/SsaExtern
  (ty/ssaExternTyped "socket" (list (ty/tyI32) (ty/tyI32) (ty/tyI32)) (ty/tyI32))

fn bindExtern -> ty/SsaExtern
  (ty/ssaExternTyped "bind" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))

fn listenExtern -> ty/SsaExtern
  (ty/ssaExternTyped "listen" (list (ty/tyI32) (ty/tyI32)) (ty/tyI32))

fn connectExtern -> ty/SsaExtern
  (ty/ssaExternTyped "connect" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))

fn acceptExtern -> ty/SsaExtern
  (ty/ssaExternTyped "accept" (list (ty/tyI32) (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn accept4Extern -> ty/SsaExtern
  (ty/ssaExternTyped "accept4" (list (ty/tyI32) (ty/tyPtr) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))

fn getsocknameExtern -> ty/SsaExtern
  (ty/ssaExternTyped "getsockname" (list (ty/tyI32) (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn fcntlExtern -> ty/SsaExtern
  (ty/ssaExternVariadic "fcntl" (list (ty/tyI32) (ty/tyI32)) (ty/tyI32))

fn closeExtern -> ty/SsaExtern
  (ty/ssaExternTyped "close" (list (ty/tyI32)) (ty/tyI32))


fn somaxconnRows -> (List (Pair String Int64))
  (list (pair "darwin-arm64" 128) (pair "linux-x86_64" 4096) (pair "linux-aarch64" 4096))

fn listenBacklog facts: libc/TripleFacts -> (Result Int64 String)
  (mt (libc/libcConst facts "SOMAXCONN")
    ((some v) (ok v))
    ((none) (mt (libc/pairFind (somaxconnRows) facts.triple)
              ((some v) (ok v))
              ((none) (err (str "no SOMAXCONN row for triple " facts.triple))))))

fn tcpListenFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (listenBacklog facts)
    ((err e) (err e))
    ((ok backlog) (tcpListenWith facts backlog)))

fn tcpListenWith facts: libc/TripleFacts backlog: Int64 -> (Result ty/SsaFunction String)
  (mt (constOrErr facts "AF_INET")
    ((err e) (err e))
    ((ok afInet)
     (mt (constOrErr facts "SOCK_STREAM")
       ((err e) (err e))
       ((ok sockStream)
        (mt (structOffset facts "sockaddr_in" "sin_family")
          ((err e) (err e))
          ((ok famOff)
           (mt (structOffset facts "sockaddr_in" "sin_port")
             ((err e) (err e))
             ((ok portOff)
              (mt (structOffset facts "sockaddr_in" "sin_addr")
                ((err e) (err e))
                ((ok addrOff)
                 (mt (structByteSize facts "sockaddr_in")
                   ((err e) (err e))
                   ((ok saSize)
                    (mt (constOrErr facts "EINVAL")
                      ((err e) (err e))
                      ((ok einval)
                       (mt (socketCloexecBlocks facts "tl.sock" afInet sockStream "tl.afterSock" "tl.err")
                         ((err e) (err e))
                         ((ok sockBlocks)
                          (ok (ty/ssaFunction "sysNetTcpListen" (list) (list (ty/ssaParam "port" (ty/tyI32))) (ty/tyVal)
                            (listAppend
                              (list
                               (sys/block "tl.validate"
                                 (list (sys/int32Const "tl.z0" 0) (sys/int32Const "tl.max" 65535)
                                       (sys/primInstr "tl.tooSmall" (ty/tyI1) "rawLtI32" (list "port" "tl.z0"))
                                       (sys/primInstr "tl.tooBig" (ty/tyI1) "rawGtI32" (list "port" "tl.max"))
                                       (sys/primInstr "tl.bad" (ty/tyI1) "orBool" (list "tl.tooSmall" "tl.tooBig")))
                                 (ty/termBranch "tl.bad" (sys/edgeTo "tl.badB") (sys/edgeTo "tl.sock.sock")))
                               (sys/block "tl.badB"
                                 (list (sys/int64Const "tl.einvalC" einval))
                                 (ty/termJump (ty/ssaEdge "tl.err" (list "tl.einvalC")))))
                              (listAppend sockBlocks
                                (list
                                 (ty/ssaBlock "tl.afterSock" (list (ty/ssaParam "fd" (ty/tyI32)))
                              (list (sys/int64Const "tl.saSizeC" saSize)
                                    (sys/callInstr "tl.sa" (ty/tyPtr) "malloc" (list "tl.saSizeC"))
                                    (sys/primInstr "tl.saNull" (ty/tyI1) "rawPtrIsNull" (list "tl.sa")))
                              (ty/termBranch "tl.saNull" (sys/edgeTo "tl.allocErr") (sys/edgeTo "tl.setup")))
                            (sys/block "tl.allocErr"
                              (list (sys/callInstr "tl.errnoAlloc" (ty/tyI64) "sysErrnoValue" (list))
                                    (sys/callInstr "tl.closeAlloc" (ty/tyI32) "close" (list "fd")))
                              (ty/termJump (ty/ssaEdge "tl.err" (list "tl.errnoAlloc"))))
                            (sys/block "tl.setup"
                              (listAppend (zeroBytesInstrs "tl.sa" saSize "tl.z")
                                (list
                                  (sys/int64Const "tl.famOffC" famOff)
                                  (sys/int32Const "tl.afInetByte" afInet)
                                  (sys/primInstr "tl.famStored" (ty/tyI1) "rawStoreI8" (list "tl.sa" "tl.famOffC" "tl.afInetByte"))
                                  (sys/int32Const "tl.shift8" 8)
                                  (sys/primInstr "tl.hiShifted" (ty/tyI32) "rawLshrI32" (list "port" "tl.shift8"))
                                  (sys/int32Const "tl.mask255" 255)
                                  (sys/primInstr "tl.hi" (ty/tyI32) "rawAndI32" (list "tl.hiShifted" "tl.mask255"))
                                  (sys/primInstr "tl.lo" (ty/tyI32) "rawAndI32" (list "port" "tl.mask255"))
                                  (sys/int64Const "tl.portOffC" portOff)
                                  (sys/int64Const "tl.portOff1C" (+ portOff 1))
                                  (sys/primInstr "tl.portHiStored" (ty/tyI1) "rawStoreI8" (list "tl.sa" "tl.portOffC" "tl.hi"))
                                  (sys/primInstr "tl.portLoStored" (ty/tyI1) "rawStoreI8" (list "tl.sa" "tl.portOff1C" "tl.lo"))
                                  (sys/int64Const "tl.addrOffC" addrOff)
                                  (sys/int32Const "tl.loopback" 16777343)
                                  (sys/primInstr "tl.addrStored" (ty/tyI1) "rawStoreI32" (list "tl.sa" "tl.addrOffC" "tl.loopback"))
                                  (sys/int32Const "tl.saSize32" saSize)
                                  (sys/callInstr "tl.bindR" (ty/tyI32) "bind" (list "fd" "tl.sa" "tl.saSize32"))
                                  (sys/int32Const "tl.z3" 0)
                                  (sys/primInstr "tl.bindErr" (ty/tyI1) "rawLtI32" (list "tl.bindR" "tl.z3"))))
                              (ty/termBranch "tl.bindErr" (sys/edgeTo "tl.bindErrB") (sys/edgeTo "tl.listen")))
                            (sys/block "tl.bindErrB"
                              (list (sys/callInstr "tl.errnoBind" (ty/tyI64) "sysErrnoValue" (list))
                                    (freeInstr "tl.freeBind" "tl.sa")
                                    (sys/callInstr "tl.closeBind" (ty/tyI32) "close" (list "fd")))
                              (ty/termJump (ty/ssaEdge "tl.err" (list "tl.errnoBind"))))
                            (sys/block "tl.listen"
                              (list (sys/int32Const "tl.backlog" backlog)
                                    (sys/callInstr "tl.listenR" (ty/tyI32) "listen" (list "fd" "tl.backlog"))
                                    (sys/int32Const "tl.z4" 0)
                                    (sys/primInstr "tl.listenErr" (ty/tyI1) "rawLtI32" (list "tl.listenR" "tl.z4")))
                              (ty/termBranch "tl.listenErr" (sys/edgeTo "tl.listenErrB") (sys/edgeTo "tl.ok")))
                            (sys/block "tl.listenErrB"
                              (list (sys/callInstr "tl.errnoListen" (ty/tyI64) "sysErrnoValue" (list))
                                    (freeInstr "tl.freeListen" "tl.sa")
                                    (sys/callInstr "tl.closeListen" (ty/tyI32) "close" (list "fd")))
                              (ty/termJump (ty/ssaEdge "tl.err" (list "tl.errnoListen"))))
                            (sys/block "tl.ok"
                              (list (freeInstr "tl.freeOk" "tl.sa")
                                    (sys/primInstr "tl.fdWide" (ty/tyI64) "rawWidenI32" (list "fd"))
                                    (sys/boxInstr "tl.fdBox" "tl.fdWide")
                                    (constructResult "tl.okv" "ok" "tl.fdBox"))
                              (ty/termReturn "tl.okv"))
                            (ty/ssaBlock "tl.err" (list (ty/ssaParam "tl.errnoVal" (ty/tyI64)))
                              (list (sys/boxInstr "tl.errBox" "tl.errnoVal") (constructResult "tl.errv" "err" "tl.errBox"))
                              (ty/termReturn "tl.errv")))))))))))))))))))))))


fn tcpConnectFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (constOrErr facts "AF_INET")
    ((err e) (err e))
    ((ok afInet)
     (mt (constOrErr facts "SOCK_STREAM")
       ((err e) (err e))
       ((ok sockStream)
        (mt (structOffset facts "sockaddr_in" "sin_family")
          ((err e) (err e))
          ((ok famOff)
           (mt (structOffset facts "sockaddr_in" "sin_port")
             ((err e) (err e))
             ((ok portOff)
              (mt (structOffset facts "sockaddr_in" "sin_addr")
                ((err e) (err e))
                ((ok addrOff)
                 (mt (structByteSize facts "sockaddr_in")
                   ((err e) (err e))
                   ((ok saSize)
                    (mt (constOrErr facts "EINVAL")
                      ((err e) (err e))
                      ((ok einval)
                       (mt (socketCloexecBlocks facts "tc.sock" afInet sockStream "tc.afterSock" "tc.err")
                         ((err e) (err e))
                         ((ok sockBlocks)
                          (ok (ty/ssaFunction "sysNetTcpConnect" (list) (list (ty/ssaParam "port" (ty/tyI32))) (ty/tyVal)
                            (listAppend
                              (list
                               (sys/block "tc.entry"
                                 (list (sys/int32Const "tc.z0" 0) (sys/int32Const "tc.max" 65535)
                                       (sys/primInstr "tc.isZero" (ty/tyI1) "rawEqI32" (list "port" "tc.z0"))
                                       (sys/primInstr "tc.tooSmall" (ty/tyI1) "rawLtI32" (list "port" "tc.z0"))
                                       (sys/primInstr "tc.tooBig" (ty/tyI1) "rawGtI32" (list "port" "tc.max"))
                                       (sys/primInstr "tc.badLo" (ty/tyI1) "orBool" (list "tc.isZero" "tc.tooSmall"))
                                       (sys/primInstr "tc.portBad" (ty/tyI1) "orBool" (list "tc.badLo" "tc.tooBig")))
                                 (ty/termBranch "tc.portBad" (sys/edgeTo "tc.bad") (sys/edgeTo "tc.sock.sock")))
                               (sys/block "tc.bad"
                                 (list (sys/int64Const "tc.einvalC" einval))
                                 (ty/termJump (ty/ssaEdge "tc.err" (list "tc.einvalC")))))
                              (listAppend sockBlocks
                                (list
                                 (ty/ssaBlock "tc.afterSock" (list (ty/ssaParam "fd" (ty/tyI32)))
                                   (list (sys/int64Const "tc.saSizeC" saSize)
                                         (sys/callInstr "tc.sa" (ty/tyPtr) "malloc" (list "tc.saSizeC"))
                                         (sys/primInstr "tc.saNull" (ty/tyI1) "rawPtrIsNull" (list "tc.sa")))
                                   (ty/termBranch "tc.saNull" (sys/edgeTo "tc.allocErr") (sys/edgeTo "tc.setup")))
                                 (sys/block "tc.allocErr"
                                   (list (sys/callInstr "tc.errnoAlloc" (ty/tyI64) "sysErrnoValue" (list))
                                         (sys/callInstr "tc.closeAlloc" (ty/tyI32) "close" (list "fd")))
                                   (ty/termJump (ty/ssaEdge "tc.err" (list "tc.errnoAlloc"))))
                                 (sys/block "tc.setup"
                                   (listAppend (zeroBytesInstrs "tc.sa" saSize "tc.z")
                                     (list
                                       (sys/int64Const "tc.famOffC" famOff)
                                       (sys/int32Const "tc.afInetByte" afInet)
                                       (sys/primInstr "tc.famStored" (ty/tyI1) "rawStoreI8" (list "tc.sa" "tc.famOffC" "tc.afInetByte"))
                                       (sys/int32Const "tc.shift8" 8)
                                       (sys/primInstr "tc.hiShifted" (ty/tyI32) "rawLshrI32" (list "port" "tc.shift8"))
                                       (sys/int32Const "tc.mask255" 255)
                                       (sys/primInstr "tc.hi" (ty/tyI32) "rawAndI32" (list "tc.hiShifted" "tc.mask255"))
                                       (sys/primInstr "tc.lo" (ty/tyI32) "rawAndI32" (list "port" "tc.mask255"))
                                       (sys/int64Const "tc.portOffC" portOff)
                                       (sys/int64Const "tc.portOff1C" (+ portOff 1))
                                       (sys/primInstr "tc.portHiStored" (ty/tyI1) "rawStoreI8" (list "tc.sa" "tc.portOffC" "tc.hi"))
                                       (sys/primInstr "tc.portLoStored" (ty/tyI1) "rawStoreI8" (list "tc.sa" "tc.portOff1C" "tc.lo"))
                                       (sys/int64Const "tc.addrOffC" addrOff)
                                       (sys/int32Const "tc.loopback" 16777343)
                                       (sys/primInstr "tc.addrStored" (ty/tyI1) "rawStoreI32" (list "tc.sa" "tc.addrOffC" "tc.loopback"))
                                       (sys/int32Const "tc.saSize32" saSize)
                                       (sys/callInstr "tc.connR" (ty/tyI32) "connect" (list "fd" "tc.sa" "tc.saSize32"))
                                       (sys/int32Const "tc.z3" 0)
                                       (sys/primInstr "tc.connErr" (ty/tyI1) "rawLtI32" (list "tc.connR" "tc.z3"))))
                                   (ty/termBranch "tc.connErr" (sys/edgeTo "tc.connErrB") (sys/edgeTo "tc.ok")))
                                 (sys/block "tc.connErrB"
                                   (list (sys/callInstr "tc.errnoConn" (ty/tyI64) "sysErrnoValue" (list))
                                         (freeInstr "tc.freeConn" "tc.sa")
                                         (sys/callInstr "tc.closeConn" (ty/tyI32) "close" (list "fd")))
                                   (ty/termJump (ty/ssaEdge "tc.err" (list "tc.errnoConn"))))
                                 (sys/block "tc.ok"
                                   (list (freeInstr "tc.freeOk" "tc.sa")
                                         (sys/primInstr "tc.fdWide" (ty/tyI64) "rawWidenI32" (list "fd"))
                                         (sys/boxInstr "tc.fdBox" "tc.fdWide")
                                         (constructResult "tc.okv" "ok" "tc.fdBox"))
                                   (ty/termReturn "tc.okv"))
                                 (ty/ssaBlock "tc.err" (list (ty/ssaParam "tc.errnoVal" (ty/tyI64)))
                                   (list (sys/boxInstr "tc.errBox" "tc.errnoVal") (constructResult "tc.errv" "err" "tc.errBox"))
                                   (ty/termReturn "tc.errv")))))))))))))))))))))))


fn sockAcceptFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (let [(entryBlk
          (sys/block "sa.entry"
            (list (sys/int64Const "sa.scratchSizeC" 128)
                  (sys/callInstr "sa.scratch" (ty/tyPtr) "malloc" (list "sa.scratchSizeC"))
                  (sys/primInstr "sa.scratchNull" (ty/tyI1) "rawPtrIsNull" (list "sa.scratch")))
            (ty/termBranch "sa.scratchNull" (sys/edgeTo "sa.allocErr") (sys/edgeTo "sa.lenAlloc"))))
        (allocErrBlk
          (sys/block "sa.allocErr"
            (list (sys/callInstr "sa.errnoAlloc" (ty/tyI64) "sysErrnoValue" (list)))
            (ty/termJump (ty/ssaEdge "sa.err" (list "sa.errnoAlloc")))))
        (lenAllocBlk
          (sys/block "sa.lenAlloc"
            (list (sys/int64Const "sa.lenSizeC" 4)
                  (sys/callInstr "sa.lenBuf" (ty/tyPtr) "malloc" (list "sa.lenSizeC"))
                  (sys/primInstr "sa.lenNull" (ty/tyI1) "rawPtrIsNull" (list "sa.lenBuf")))
            (ty/termBranch "sa.lenNull" (sys/edgeTo "sa.lenAllocErr") (sys/edgeTo "sa.setLen"))))
        (lenAllocErrBlk
          (sys/block "sa.lenAllocErr"
            (list (sys/callInstr "sa.errnoLenAlloc" (ty/tyI64) "sysErrnoValue" (list))
                  (freeInstr "sa.freeScratchLenErr" "sa.scratch"))
            (ty/termJump (ty/ssaEdge "sa.err" (list "sa.errnoLenAlloc")))))
        (errBlk
          (ty/ssaBlock "sa.err" (list (ty/ssaParam "sa.errnoVal" (ty/tyI64)))
            (list (sys/boxInstr "sa.errBox" "sa.errnoVal") (constructResult "sa.errv" "err" "sa.errBox"))
            (ty/termReturn "sa.errv")))]
    (if (= facts.triple "darwin-arm64")
      (mt (constOrErr facts "F_GETFD")
        ((err e) (err e))
        ((ok getfdCmd)
         (mt (constOrErr facts "F_SETFD")
           ((err e) (err e))
           ((ok setfdCmd)
            (mt (constOrErr facts "FD_CLOEXEC")
              ((err e) (err e))
              ((ok fdCloexec)
               (ok (ty/ssaFunction "sysNetSockAccept" (list) (list (ty/ssaParam "fd" (ty/tyI32))) (ty/tyVal)
                 (list entryBlk allocErrBlk lenAllocBlk lenAllocErrBlk
                   (sys/block "sa.setLen"
                     (list (sys/int64Const "sa.zeroOff" 0) (sys/int32Const "sa.initLen" 128)
                           (sys/primInstr "sa.lenStored" (ty/tyI1) "rawStoreI32" (list "sa.lenBuf" "sa.zeroOff" "sa.initLen")))
                     (ty/termJump (sys/edgeTo "sa.call")))
                   (sys/block "sa.call"
                     (list (sys/callInstr "sa.fd2" (ty/tyI32) "accept" (list "fd" "sa.scratch" "sa.lenBuf"))
                           (sys/int32Const "sa.z1" 0)
                           (sys/primInstr "sa.fd2Err" (ty/tyI1) "rawLtI32" (list "sa.fd2" "sa.z1")))
                     (ty/termBranch "sa.fd2Err" (sys/edgeTo "sa.acceptErrB") (sys/edgeTo "sa.cloGet")))
                   (sys/block "sa.acceptErrB"
                     (list (sys/callInstr "sa.errnoAccept" (ty/tyI64) "sysErrnoValue" (list))
                           (freeInstr "sa.freeScratchAE" "sa.scratch") (freeInstr "sa.freeLenAE" "sa.lenBuf"))
                     (ty/termJump (ty/ssaEdge "sa.err" (list "sa.errnoAccept"))))
                   (sys/block "sa.cloGet"
                     (list (sys/int32Const "sa.getfdCmd" getfdCmd)
                           (sys/callInstr "sa.flags" (ty/tyI32) "fcntl" (list "sa.fd2" "sa.getfdCmd"))
                           (sys/int32Const "sa.z2" 0)
                           (sys/primInstr "sa.flagsErr" (ty/tyI1) "rawLtI32" (list "sa.flags" "sa.z2")))
                     (ty/termBranch "sa.flagsErr" (sys/edgeTo "sa.cloGetErr") (sys/edgeTo "sa.cloSet")))
                   (sys/block "sa.cloGetErr"
                     (list (sys/callInstr "sa.errnoCloGet" (ty/tyI64) "sysErrnoValue" (list))
                           (freeInstr "sa.freeScratchCG" "sa.scratch") (freeInstr "sa.freeLenCG" "sa.lenBuf")
                           (sys/callInstr "sa.closeCG" (ty/tyI32) "close" (list "sa.fd2")))
                     (ty/termJump (ty/ssaEdge "sa.err" (list "sa.errnoCloGet"))))
                   (sys/block "sa.cloSet"
                     (list (sys/int32Const "sa.fdcloexecC" fdCloexec)
                           (sys/primInstr "sa.newFlags" (ty/tyI32) "rawOrI32" (list "sa.flags" "sa.fdcloexecC"))
                           (sys/int32Const "sa.setfdCmd" setfdCmd)
                           (sys/callInstr "sa.setr" (ty/tyI32) "fcntl" (list "sa.fd2" "sa.setfdCmd" "sa.newFlags"))
                           (sys/int32Const "sa.z3" 0)
                           (sys/primInstr "sa.setErr" (ty/tyI1) "rawLtI32" (list "sa.setr" "sa.z3")))
                     (ty/termBranch "sa.setErr" (sys/edgeTo "sa.cloSetErr") (sys/edgeTo "sa.ok")))
                   (sys/block "sa.cloSetErr"
                     (list (sys/callInstr "sa.errnoCloSet" (ty/tyI64) "sysErrnoValue" (list))
                           (freeInstr "sa.freeScratchCS" "sa.scratch") (freeInstr "sa.freeLenCS" "sa.lenBuf")
                           (sys/callInstr "sa.closeCS" (ty/tyI32) "close" (list "sa.fd2")))
                     (ty/termJump (ty/ssaEdge "sa.err" (list "sa.errnoCloSet"))))
                   (sys/block "sa.ok"
                     (list (freeInstr "sa.freeScratchOK" "sa.scratch") (freeInstr "sa.freeLenOK" "sa.lenBuf")
                           (sys/primInstr "sa.fd2Wide" (ty/tyI64) "rawWidenI32" (list "sa.fd2"))
                           (sys/boxInstr "sa.fd2Box" "sa.fd2Wide")
                           (constructResult "sa.okv" "ok" "sa.fd2Box"))
                     (ty/termReturn "sa.okv"))
                   errBlk)))))))))
      (mt (constOrErr facts "SOCK_CLOEXEC")
        ((err e) (err e))
        ((ok sockCloexec)
         (ok (ty/ssaFunction "sysNetSockAccept" (list) (list (ty/ssaParam "fd" (ty/tyI32))) (ty/tyVal)
           (list entryBlk allocErrBlk lenAllocBlk lenAllocErrBlk
             (sys/block "sa.setLen"
               (list (sys/int64Const "sa.zeroOff" 0) (sys/int32Const "sa.initLen" 128)
                     (sys/primInstr "sa.lenStored" (ty/tyI1) "rawStoreI32" (list "sa.lenBuf" "sa.zeroOff" "sa.initLen")))
               (ty/termJump (sys/edgeTo "sa.call4")))
             (sys/block "sa.call4"
               (list (sys/int32Const "sa.cloexecFlag" sockCloexec)
                     (sys/callInstr "sa.fd2" (ty/tyI32) "accept4" (list "fd" "sa.scratch" "sa.lenBuf" "sa.cloexecFlag"))
                     (sys/int32Const "sa.z1" 0)
                     (sys/primInstr "sa.fd2Err" (ty/tyI1) "rawLtI32" (list "sa.fd2" "sa.z1")))
               (ty/termBranch "sa.fd2Err" (sys/edgeTo "sa.accept4ErrB") (sys/edgeTo "sa.ok4")))
             (sys/block "sa.accept4ErrB"
               (list (sys/callInstr "sa.errnoAccept4" (ty/tyI64) "sysErrnoValue" (list))
                     (freeInstr "sa.freeScratchA4" "sa.scratch") (freeInstr "sa.freeLenA4" "sa.lenBuf"))
               (ty/termJump (ty/ssaEdge "sa.err" (list "sa.errnoAccept4"))))
             (sys/block "sa.ok4"
               (list (freeInstr "sa.freeScratchOK4" "sa.scratch") (freeInstr "sa.freeLenOK4" "sa.lenBuf")
                     (sys/primInstr "sa.fd2Wide" (ty/tyI64) "rawWidenI32" (list "sa.fd2"))
                     (sys/boxInstr "sa.fd2Box" "sa.fd2Wide")
                     (constructResult "sa.okv" "ok" "sa.fd2Box"))
               (ty/termReturn "sa.okv"))
             errBlk)))))))


fn sockLocalPortFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (constOrErr facts "AF_INET")
    ((err e) (err e))
    ((ok afInet)
     (mt (structOffset facts "sockaddr_in" "sin_family")
       ((err e) (err e))
       ((ok famOff)
        (mt (structOffset facts "sockaddr_in" "sin_port")
          ((err e) (err e))
          ((ok portOff)
           (mt (structByteSize facts "sockaddr_in")
             ((err e) (err e))
             ((ok saSize)
              (mt (constOrErr facts "EINVAL")
                ((err e) (err e))
                ((ok einval)
                 (ok (ty/ssaFunction "sysNetSockLocalPort" (list) (list (ty/ssaParam "fd" (ty/tyI32))) (ty/tyVal)
                   (list
                    (sys/block "sl.entry"
                      (list (sys/int64Const "sl.saSizeC" saSize)
                            (sys/callInstr "sl.sa" (ty/tyPtr) "malloc" (list "sl.saSizeC"))
                            (sys/primInstr "sl.saNull" (ty/tyI1) "rawPtrIsNull" (list "sl.sa")))
                      (ty/termBranch "sl.saNull" (sys/edgeTo "sl.allocErr") (sys/edgeTo "sl.lenAlloc")))
                    (sys/block "sl.allocErr"
                      (list (sys/callInstr "sl.errnoAlloc" (ty/tyI64) "sysErrnoValue" (list)))
                      (ty/termJump (ty/ssaEdge "sl.err" (list "sl.errnoAlloc"))))
                    (sys/block "sl.lenAlloc"
                      (list (sys/int64Const "sl.lenSizeC" 4)
                            (sys/callInstr "sl.lenBuf" (ty/tyPtr) "malloc" (list "sl.lenSizeC"))
                            (sys/primInstr "sl.lenNull" (ty/tyI1) "rawPtrIsNull" (list "sl.lenBuf")))
                      (ty/termBranch "sl.lenNull" (sys/edgeTo "sl.lenAllocErr") (sys/edgeTo "sl.setup")))
                    (sys/block "sl.lenAllocErr"
                      (list (sys/callInstr "sl.errnoLenAlloc" (ty/tyI64) "sysErrnoValue" (list))
                            (freeInstr "sl.freeSaLE" "sl.sa"))
                      (ty/termJump (ty/ssaEdge "sl.err" (list "sl.errnoLenAlloc"))))
                    (sys/block "sl.setup"
                      (listAppend (zeroBytesInstrs "sl.sa" saSize "sl.z")
                        (list
                         (sys/int64Const "sl.zeroOff" 0)
                         (sys/int32Const "sl.saSizeConst" saSize)
                         (sys/primInstr "sl.lenStored" (ty/tyI1) "rawStoreI32" (list "sl.lenBuf" "sl.zeroOff" "sl.saSizeConst"))
                         (sys/callInstr "sl.gsnR" (ty/tyI32) "getsockname" (list "fd" "sl.sa" "sl.lenBuf"))
                         (sys/int32Const "sl.z1" 0)
                         (sys/primInstr "sl.gsnErr" (ty/tyI1) "rawLtI32" (list "sl.gsnR" "sl.z1"))))
                      (ty/termBranch "sl.gsnErr" (sys/edgeTo "sl.gsnErrB") (sys/edgeTo "sl.checkFam")))
                    (sys/block "sl.gsnErrB"
                      (list (sys/callInstr "sl.errnoGsn" (ty/tyI64) "sysErrnoValue" (list))
                            (freeInstr "sl.freeSaGE" "sl.sa") (freeInstr "sl.freeLenGE" "sl.lenBuf"))
                      (ty/termJump (ty/ssaEdge "sl.err" (list "sl.errnoGsn"))))
                    (sys/block "sl.checkFam"
                      (list (sys/int64Const "sl.famOffC" famOff)
                            (sys/primInstr "sl.famByte" (ty/tyI32) "rawLoadI8" (list "sl.sa" "sl.famOffC"))
                            (sys/int32Const "sl.afInetByte" afInet)
                            (sys/primInstr "sl.famBad" (ty/tyI1) "rawNeI32" (list "sl.famByte" "sl.afInetByte")))
                      (ty/termBranch "sl.famBad" (sys/edgeTo "sl.bad") (sys/edgeTo "sl.readPort")))
                    (sys/block "sl.bad"
                      (list (freeInstr "sl.freeSaBad" "sl.sa") (freeInstr "sl.freeLenBad" "sl.lenBuf")
                            (sys/int64Const "sl.einvalC" einval))
                      (ty/termJump (ty/ssaEdge "sl.err" (list "sl.einvalC"))))
                    (sys/block "sl.readPort"
                      (list (sys/int64Const "sl.portOffC" portOff)
                            (sys/int64Const "sl.portOff1C" (+ portOff 1))
                            (sys/primInstr "sl.hiByte" (ty/tyI32) "rawLoadI8" (list "sl.sa" "sl.portOffC"))
                            (sys/primInstr "sl.loByte" (ty/tyI32) "rawLoadI8" (list "sl.sa" "sl.portOff1C"))
                            (sys/int32Const "sl.256" 256)
                            (sys/primInstr "sl.hi256" (ty/tyI32) "rawMulI32" (list "sl.hiByte" "sl.256"))
                            (sys/primInstr "sl.portI32" (ty/tyI32) "rawAddI32" (list "sl.hi256" "sl.loByte"))
                            (sys/primInstr "sl.portI64" (ty/tyI64) "rawWidenI32" (list "sl.portI32"))
                            (freeInstr "sl.freeSaOK" "sl.sa") (freeInstr "sl.freeLenOK" "sl.lenBuf")
                            (sys/boxInstr "sl.portBox" "sl.portI64")
                            (constructResult "sl.okv" "ok" "sl.portBox"))
                      (ty/termReturn "sl.okv"))
                    (ty/ssaBlock "sl.err" (list (ty/ssaParam "sl.errnoVal" (ty/tyI64)))
                      (list (sys/boxInstr "sl.errBox" "sl.errnoVal") (constructResult "sl.errv" "err" "sl.errBox"))
                      (ty/termReturn "sl.errv")))))))))))))))


fn unixListenFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (listenBacklog facts)
    ((err e) (err e))
    ((ok backlog) (unixListenWith facts backlog)))

fn unixListenWith facts: libc/TripleFacts backlog: Int64 -> (Result ty/SsaFunction String)
  (mt (constOrErr facts "AF_UNIX")
    ((err e) (err e))
    ((ok afUnix)
     (mt (constOrErr facts "SOCK_STREAM")
       ((err e) (err e))
       ((ok sockStream)
        (mt (structOffset facts "sockaddr_un" "sun_family")
          ((err e) (err e))
          ((ok famOff)
           (mt (structOffset facts "sockaddr_un" "sun_path")
             ((err e) (err e))
             ((ok pathOff)
              (mt (structByteSize facts "sockaddr_un")
                ((err e) (err e))
                ((ok saSize)
                 (mt (constOrErr facts "EINVAL")
                   ((err e) (err e))
                   ((ok einval)
                    (mt (socketCloexecBlocks facts "ul.sock" afUnix sockStream "ul.afterSock" "ul.err")
                      ((err e) (err e))
                      ((ok sockBlocks)
                       (let [(capacity (- saSize pathOff))]
                         (ok (ty/ssaFunction "sysNetUnixListen" (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
                           (listAppend
                             (list
                              (sys/block "ul.entry"
                                (listAppend (stringToPtrInstrs "ul.p" "path")
                                  (list
                                   (sys/entryInstr "ul.pathLen" (ty/tyI64) "stringLength" (list "path"))
                                   (sys/int64Const "ul.zero" 0)
                                   (sys/primInstr "ul.tooSmall" (ty/tyI1) "leInt" (list "ul.pathLen" "ul.zero"))
                                   (sys/int64Const "ul.capC" capacity)
                                   (sys/primInstr "ul.tooBig" (ty/tyI1) "geInt" (list "ul.pathLen" "ul.capC"))
                                   (sys/primInstr "ul.bad" (ty/tyI1) "orBool" (list "ul.tooSmall" "ul.tooBig"))))
                                (ty/termBranch "ul.bad" (sys/edgeTo "ul.badB") (ty/ssaEdge "ul.nulScan" (list "ul.zero"))))
                              (ty/ssaBlock "ul.nulScan" (list (ty/ssaParam "ul.nIdx" (ty/tyI64)))
                                (list (sys/primInstr "ul.nDone" (ty/tyI1) "geInt" (list "ul.nIdx" "ul.pathLen")))
                                (ty/termBranch "ul.nDone" (sys/edgeTo "ul.sock.sock") (sys/edgeTo "ul.nulCheck")))
                              (sys/block "ul.nulCheck"
                                (list (sys/primInstr "ul.nByte" (ty/tyI32) "rawLoadI8" (list "ul.p" "ul.nIdx"))
                                      (sys/int32Const "ul.nZero32" 0)
                                      (sys/primInstr "ul.nIsZero" (ty/tyI1) "rawEqI32" (list "ul.nByte" "ul.nZero32"))
                                      (sys/int64Const "ul.nOne" 1)
                                      (sys/primInstr "ul.nIdx1" (ty/tyI64) "addInt" (list "ul.nIdx" "ul.nOne")))
                                (ty/termBranch "ul.nIsZero" (sys/edgeTo "ul.badB") (ty/ssaEdge "ul.nulScan" (list "ul.nIdx1"))))
                              (sys/block "ul.badB"
                                (list (freeInstr "ul.freeBadP" "ul.p") (sys/int64Const "ul.einvalC" einval))
                                (ty/termJump (ty/ssaEdge "ul.err" (list "ul.einvalC")))))
                             (listAppend sockBlocks
                               (list
                                (ty/ssaBlock "ul.afterSock" (list (ty/ssaParam "fd" (ty/tyI32)))
                                  (list (sys/int64Const "ul.saSizeC" saSize)
                                        (sys/callInstr "ul.sa" (ty/tyPtr) "malloc" (list "ul.saSizeC"))
                                        (sys/primInstr "ul.saNull" (ty/tyI1) "rawPtrIsNull" (list "ul.sa")))
                                  (ty/termBranch "ul.saNull" (sys/edgeTo "ul.allocErr") (sys/edgeTo "ul.setup")))
                                (sys/block "ul.allocErr"
                                  (list (sys/callInstr "ul.errnoAlloc" (ty/tyI64) "sysErrnoValue" (list))
                                        (freeInstr "ul.freeAllocErrP" "ul.p")
                                        (sys/callInstr "ul.closeAlloc" (ty/tyI32) "close" (list "fd")))
                                  (ty/termJump (ty/ssaEdge "ul.err" (list "ul.errnoAlloc"))))
                                (sys/block "ul.setup"
                                  (listAppend (zeroBytesInstrs "ul.sa" saSize "ul.z")
                                    (list
                                     (sys/int64Const "ul.famOffC" famOff)
                                     (sys/int32Const "ul.afUnixByte" afUnix)
                                     (sys/primInstr "ul.famStored" (ty/tyI1) "rawStoreI8" (list "ul.sa" "ul.famOffC" "ul.afUnixByte"))
                                     (sys/int64Const "ul.zeroIdx" 0)))
                                  (ty/termJump (ty/ssaEdge "ul.copy" (list "ul.zeroIdx"))))
                                (ty/ssaBlock "ul.copy" (list (ty/ssaParam "ul.idx" (ty/tyI64)))
                                  (list (sys/primInstr "ul.idxDone" (ty/tyI1) "geInt" (list "ul.idx" "ul.pathLen")))
                                  (ty/termBranch "ul.idxDone" (sys/edgeTo "ul.copyDone") (sys/edgeTo "ul.copyStep")))
                                (sys/block "ul.copyStep"
                                  (list (sys/primInstr "ul.srcByte" (ty/tyI32) "rawLoadI8" (list "ul.p" "ul.idx"))
                                        (sys/int64Const "ul.pathOffC" pathOff)
                                        (sys/primInstr "ul.destOff" (ty/tyI64) "addInt" (list "ul.pathOffC" "ul.idx"))
                                        (sys/primInstr "ul.stored" (ty/tyI1) "rawStoreI8" (list "ul.sa" "ul.destOff" "ul.srcByte"))
                                        (sys/int64Const "ul.one" 1)
                                        (sys/primInstr "ul.idx1" (ty/tyI64) "addInt" (list "ul.idx" "ul.one")))
                                  (ty/termJump (ty/ssaEdge "ul.copy" (list "ul.idx1"))))
                                (sys/block "ul.copyDone"
                                  (list (freeInstr "ul.freeP" "ul.p")
                                        (sys/int32Const "ul.saSizeConst" saSize)
                                        (sys/callInstr "ul.bindR" (ty/tyI32) "bind" (list "fd" "ul.sa" "ul.saSizeConst"))
                                        (sys/int32Const "ul.z1" 0)
                                        (sys/primInstr "ul.bindErr" (ty/tyI1) "rawLtI32" (list "ul.bindR" "ul.z1")))
                                  (ty/termBranch "ul.bindErr" (sys/edgeTo "ul.bindErrB") (sys/edgeTo "ul.listen")))
                                (sys/block "ul.bindErrB"
                                  (list (sys/callInstr "ul.errnoBind" (ty/tyI64) "sysErrnoValue" (list))
                                        (freeInstr "ul.freeBind" "ul.sa")
                                        (sys/callInstr "ul.closeBind" (ty/tyI32) "close" (list "fd")))
                                  (ty/termJump (ty/ssaEdge "ul.err" (list "ul.errnoBind"))))
                                (sys/block "ul.listen"
                                  (list (sys/int32Const "ul.backlog" backlog)
                                        (sys/callInstr "ul.listenR" (ty/tyI32) "listen" (list "fd" "ul.backlog"))
                                        (sys/int32Const "ul.z2" 0)
                                        (sys/primInstr "ul.listenErr" (ty/tyI1) "rawLtI32" (list "ul.listenR" "ul.z2")))
                                  (ty/termBranch "ul.listenErr" (sys/edgeTo "ul.listenErrB") (sys/edgeTo "ul.ok")))
                                (sys/block "ul.listenErrB"
                                  (list (sys/callInstr "ul.errnoListen" (ty/tyI64) "sysErrnoValue" (list))
                                        (freeInstr "ul.freeListen" "ul.sa")
                                        (sys/callInstr "ul.closeListen" (ty/tyI32) "close" (list "fd")))
                                  (ty/termJump (ty/ssaEdge "ul.err" (list "ul.errnoListen"))))
                                (sys/block "ul.ok"
                                  (list (freeInstr "ul.freeOk" "ul.sa")
                                        (sys/primInstr "ul.fdWide" (ty/tyI64) "rawWidenI32" (list "fd"))
                                        (sys/boxInstr "ul.fdBox" "ul.fdWide")
                                        (constructResult "ul.okv" "ok" "ul.fdBox"))
                                  (ty/termReturn "ul.okv"))
                                (ty/ssaBlock "ul.err" (list (ty/ssaParam "ul.errnoVal" (ty/tyI64)))
                                  (list (sys/boxInstr "ul.errBox" "ul.errnoVal") (constructResult "ul.errv" "err" "ul.errBox"))
                                  (ty/termReturn "ul.errv"))))))))))))))))))))))


fn unixConnectFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (constOrErr facts "AF_UNIX")
    ((err e) (err e))
    ((ok afUnix)
     (mt (constOrErr facts "SOCK_STREAM")
       ((err e) (err e))
       ((ok sockStream)
        (mt (structOffset facts "sockaddr_un" "sun_family")
          ((err e) (err e))
          ((ok famOff)
           (mt (structOffset facts "sockaddr_un" "sun_path")
             ((err e) (err e))
             ((ok pathOff)
              (mt (structByteSize facts "sockaddr_un")
                ((err e) (err e))
                ((ok saSize)
                 (mt (constOrErr facts "EINVAL")
                   ((err e) (err e))
                   ((ok einval)
                    (mt (socketCloexecBlocks facts "uc.sock" afUnix sockStream "uc.afterSock" "uc.err")
                      ((err e) (err e))
                      ((ok sockBlocks)
                       (let [(capacity (- saSize pathOff))]
                         (ok (ty/ssaFunction "sysNetUnixConnect" (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
                           (listAppend
                             (list
                              (sys/block "uc.entry"
                                (listAppend (stringToPtrInstrs "uc.p" "path")
                                  (list
                                   (sys/entryInstr "uc.pathLen" (ty/tyI64) "stringLength" (list "path"))
                                   (sys/int64Const "uc.zero" 0)
                                   (sys/primInstr "uc.tooSmall" (ty/tyI1) "leInt" (list "uc.pathLen" "uc.zero"))
                                   (sys/int64Const "uc.capC" capacity)
                                   (sys/primInstr "uc.tooBig" (ty/tyI1) "geInt" (list "uc.pathLen" "uc.capC"))
                                   (sys/primInstr "uc.bad" (ty/tyI1) "orBool" (list "uc.tooSmall" "uc.tooBig"))))
                                (ty/termBranch "uc.bad" (sys/edgeTo "uc.badB") (ty/ssaEdge "uc.nulScan" (list "uc.zero"))))
                              (ty/ssaBlock "uc.nulScan" (list (ty/ssaParam "uc.nIdx" (ty/tyI64)))
                                (list (sys/primInstr "uc.nDone" (ty/tyI1) "geInt" (list "uc.nIdx" "uc.pathLen")))
                                (ty/termBranch "uc.nDone" (sys/edgeTo "uc.sock.sock") (sys/edgeTo "uc.nulCheck")))
                              (sys/block "uc.nulCheck"
                                (list (sys/primInstr "uc.nByte" (ty/tyI32) "rawLoadI8" (list "uc.p" "uc.nIdx"))
                                      (sys/int32Const "uc.nZero32" 0)
                                      (sys/primInstr "uc.nIsZero" (ty/tyI1) "rawEqI32" (list "uc.nByte" "uc.nZero32"))
                                      (sys/int64Const "uc.nOne" 1)
                                      (sys/primInstr "uc.nIdx1" (ty/tyI64) "addInt" (list "uc.nIdx" "uc.nOne")))
                                (ty/termBranch "uc.nIsZero" (sys/edgeTo "uc.badB") (ty/ssaEdge "uc.nulScan" (list "uc.nIdx1"))))
                              (sys/block "uc.badB"
                                (list (freeInstr "uc.freeBadP" "uc.p") (sys/int64Const "uc.einvalC" einval))
                                (ty/termJump (ty/ssaEdge "uc.err" (list "uc.einvalC")))))
                             (listAppend sockBlocks
                               (list
                                (ty/ssaBlock "uc.afterSock" (list (ty/ssaParam "fd" (ty/tyI32)))
                                  (list (sys/int64Const "uc.saSizeC" saSize)
                                        (sys/callInstr "uc.sa" (ty/tyPtr) "malloc" (list "uc.saSizeC"))
                                        (sys/primInstr "uc.saNull" (ty/tyI1) "rawPtrIsNull" (list "uc.sa")))
                                  (ty/termBranch "uc.saNull" (sys/edgeTo "uc.allocErr") (sys/edgeTo "uc.setup")))
                                (sys/block "uc.allocErr"
                                  (list (sys/callInstr "uc.errnoAlloc" (ty/tyI64) "sysErrnoValue" (list))
                                        (freeInstr "uc.freeAllocErrP" "uc.p")
                                        (sys/callInstr "uc.closeAlloc" (ty/tyI32) "close" (list "fd")))
                                  (ty/termJump (ty/ssaEdge "uc.err" (list "uc.errnoAlloc"))))
                                (sys/block "uc.setup"
                                  (listAppend (zeroBytesInstrs "uc.sa" saSize "uc.z")
                                    (list
                                     (sys/int64Const "uc.famOffC" famOff)
                                     (sys/int32Const "uc.afUnixByte" afUnix)
                                     (sys/primInstr "uc.famStored" (ty/tyI1) "rawStoreI8" (list "uc.sa" "uc.famOffC" "uc.afUnixByte"))
                                     (sys/int64Const "uc.zeroIdx" 0)))
                                  (ty/termJump (ty/ssaEdge "uc.copy" (list "uc.zeroIdx"))))
                                (ty/ssaBlock "uc.copy" (list (ty/ssaParam "uc.idx" (ty/tyI64)))
                                  (list (sys/primInstr "uc.idxDone" (ty/tyI1) "geInt" (list "uc.idx" "uc.pathLen")))
                                  (ty/termBranch "uc.idxDone" (sys/edgeTo "uc.copyDone") (sys/edgeTo "uc.copyStep")))
                                (sys/block "uc.copyStep"
                                  (list (sys/primInstr "uc.srcByte" (ty/tyI32) "rawLoadI8" (list "uc.p" "uc.idx"))
                                        (sys/int64Const "uc.pathOffC" pathOff)
                                        (sys/primInstr "uc.destOff" (ty/tyI64) "addInt" (list "uc.pathOffC" "uc.idx"))
                                        (sys/primInstr "uc.stored" (ty/tyI1) "rawStoreI8" (list "uc.sa" "uc.destOff" "uc.srcByte"))
                                        (sys/int64Const "uc.one" 1)
                                        (sys/primInstr "uc.idx1" (ty/tyI64) "addInt" (list "uc.idx" "uc.one")))
                                  (ty/termJump (ty/ssaEdge "uc.copy" (list "uc.idx1"))))
                                (sys/block "uc.copyDone"
                                  (list (freeInstr "uc.freeP" "uc.p")
                                        (sys/int32Const "uc.saSizeConst" saSize)
                                        (sys/callInstr "uc.connR" (ty/tyI32) "connect" (list "fd" "uc.sa" "uc.saSizeConst"))
                                        (sys/int32Const "uc.z1" 0)
                                        (sys/primInstr "uc.connErr" (ty/tyI1) "rawLtI32" (list "uc.connR" "uc.z1")))
                                  (ty/termBranch "uc.connErr" (sys/edgeTo "uc.connErrB") (sys/edgeTo "uc.ok")))
                                (sys/block "uc.connErrB"
                                  (list (sys/callInstr "uc.errnoConn" (ty/tyI64) "sysErrnoValue" (list))
                                        (freeInstr "uc.freeConn" "uc.sa")
                                        (sys/callInstr "uc.closeConn" (ty/tyI32) "close" (list "fd")))
                                  (ty/termJump (ty/ssaEdge "uc.err" (list "uc.errnoConn"))))
                                (sys/block "uc.ok"
                                  (list (freeInstr "uc.freeOk" "uc.sa")
                                        (sys/primInstr "uc.fdWide" (ty/tyI64) "rawWidenI32" (list "fd"))
                                        (sys/boxInstr "uc.fdBox" "uc.fdWide")
                                        (constructResult "uc.okv" "ok" "uc.fdBox"))
                                  (ty/termReturn "uc.okv"))
                                (ty/ssaBlock "uc.err" (list (ty/ssaParam "uc.errnoVal" (ty/tyI64)))
                                  (list (sys/boxInstr "uc.errBox" "uc.errnoVal") (constructResult "uc.errv" "err" "uc.errBox"))
                                  (ty/termReturn "uc.errv"))))))))))))))))))))))


fn socketpairExtern -> ty/SsaExtern
  (ty/ssaExternTyped "socketpair" (list (ty/tyI32) (ty/tyI32) (ty/tyI32) (ty/tyPtr)) (ty/tyI32))

fn sendmsgExtern -> ty/SsaExtern
  (ty/ssaExternTyped "sendmsg" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI64))

fn recvmsgExtern -> ty/SsaExtern
  (ty/ssaExternTyped "recvmsg" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI64))

fn fdPassFactNames -> (List String)
  (list "sizeof.msghdr" "msghdr.msg_iov" "msghdr.msg_iovlen" "msghdr.msg_control" "msghdr.msg_controllen" "msghdr.msg_flags"
        "sizeof.iovec" "iovec.iov_base" "iovec.iov_len" "cmsghdr.cmsg_len" "cmsghdr.cmsg_level" "cmsghdr.cmsg_type"
        "SOL_SOCKET" "SCM_RIGHTS" "CMSG_LEN_INT" "CMSG_SPACE_INT" "CMSG_DATA_OFFSET" "MSG_CTRUNC" "EBADMSG" "EMSGSIZE" "EIO")

fn fdPassFact facts: libc/TripleFacts name: String -> (Result Int64 String)
  (let [(parts (stringSplit name "."))]
    (mt (listGet parts 1)
      ((none) (constOrErr facts name))
      ((some field)
        (let [(structName (optionOr (listHead parts) ""))]
          (if (= structName "sizeof") (structByteSize facts field) (structOffset facts structName field))))))

fn fdPassFacts facts: libc/TripleFacts -> (Result (Map String Int64) String)
  (mt (fold (fn [(acc (Result (Map String Int64) String)) (name String)] -> (Result (Map String Int64) String)
              (mt acc
                ((err e) (err e))
                ((ok m) (mt (fdPassFact facts name) ((err e) (err e)) ((ok v) (ok (mapSet m name v)))))))
            (ok (mapEmpty)) (fdPassFactNames))
    ((err e) (err e))
    ((ok m)
      (let [(dataOff (fdPassOf m "CMSG_DATA_OFFSET"))]
        (cond
          ((< (fdPassOf m "CMSG_SPACE_INT") (+ dataOff 4)) (err (str "libc.asl's CMSG_SPACE_INT has no room for an int at CMSG_DATA_OFFSET on triple " facts.triple)))
          ((not (= (fdPassOf m "CMSG_LEN_INT") (+ dataOff 4))) (err (str "libc.asl's CMSG_LEN_INT is not CMSG_DATA_OFFSET + 4 on triple " facts.triple)))
          (else (ok m))))))

fn fdPassOf k: (Map String Int64) name: String -> Int64
  (optionOr (mapGet k name) 0)

fn fdPassIov k: (Map String Int64) -> Int64
  (fdPassOf k "sizeof.msghdr")

fn fdPassControl k: (Map String Int64) -> Int64
  (+ (fdPassIov k) (fdPassOf k "sizeof.iovec"))

fn fdPassData k: (Map String Int64) -> Int64
  (+ (fdPassControl k) (fdPassOf k "CMSG_SPACE_INT"))

fn fdPassTotal k: (Map String Int64) -> Int64
  (+ (fdPassData k) 1)

fn zeroLoopBlocks prefix: String ptrName: String n: Int64 nextLabel: String -> (List ty/SsaBlock)
  (list
    (ty/ssaBlock (str prefix ".zl") (list (ty/ssaParam (str prefix ".zi") (ty/tyI64)))
      (list (sys/int64Const (str prefix ".zn") n)
            (sys/primInstr (str prefix ".zdone") (ty/tyI1) "geInt" (list (str prefix ".zi") (str prefix ".zn"))))
      (ty/termBranch (str prefix ".zdone") (sys/edgeTo nextLabel) (sys/edgeTo (str prefix ".zs"))))
    (sys/block (str prefix ".zs")
      (list (sys/int32Const (str prefix ".zb") 0)
            (sys/primInstr (str prefix ".zst") (ty/tyI1) "rawStoreI8" (list ptrName (str prefix ".zi") (str prefix ".zb")))
            (sys/int64Const (str prefix ".zone") 1)
            (sys/primInstr (str prefix ".zi1") (ty/tyI64) "addInt" (list (str prefix ".zi") (str prefix ".zone"))))
      (ty/termJump (ty/ssaEdge (str prefix ".zl") (list (str prefix ".zi1"))))))

fn storeAtInstrs prefix: String name: String ptrName: String off: Int64 storePrim: String valueName: String -> (List ty/SsaInstr)
  (list (sys/int64Const (str prefix "." name "Off") off)
        (sys/primInstr (str prefix "." name "St") (ty/tyI1) storePrim (list ptrName (str prefix "." name "Off") valueName)))

fn msgFillInstrs prefix: String buf: String k: (Map String Int64) -> (List ty/SsaInstr)
  (let [(iov (fdPassIov k)) (ctl (fdPassControl k))]
    (listAppend
      (list (sys/primInstr (str prefix ".base") (ty/tyI64) "rawPtrToInt" (list buf))
            (sys/int64Const (str prefix ".dataOff") (fdPassData k))
            (sys/primInstr (str prefix ".dataAddr") (ty/tyI64) "addInt" (list (str prefix ".base") (str prefix ".dataOff")))
            (sys/int64Const (str prefix ".iovOff") iov)
            (sys/primInstr (str prefix ".iovAddr") (ty/tyI64) "addInt" (list (str prefix ".base") (str prefix ".iovOff")))
            (sys/int64Const (str prefix ".ctlOff") ctl)
            (sys/primInstr (str prefix ".ctlAddr") (ty/tyI64) "addInt" (list (str prefix ".base") (str prefix ".ctlOff")))
            (sys/int64Const (str prefix ".one64") 1)
            (sys/int32Const (str prefix ".one32") 1)
            (sys/int32Const (str prefix ".space32") (fdPassOf k "CMSG_SPACE_INT")))
      (listAppend (storeAtInstrs prefix "iovBase" buf (+ iov (fdPassOf k "iovec.iov_base")) "rawStoreI64" (str prefix ".dataAddr"))
        (listAppend (storeAtInstrs prefix "iovLen" buf (+ iov (fdPassOf k "iovec.iov_len")) "rawStoreI64" (str prefix ".one64"))
          (listAppend (storeAtInstrs prefix "msgIov" buf (fdPassOf k "msghdr.msg_iov") "rawStoreI64" (str prefix ".iovAddr"))
            (listAppend (storeAtInstrs prefix "msgIovlen" buf (fdPassOf k "msghdr.msg_iovlen") "rawStoreI32" (str prefix ".one32"))
              (listAppend (storeAtInstrs prefix "msgControl" buf (fdPassOf k "msghdr.msg_control") "rawStoreI64" (str prefix ".ctlAddr"))
                (storeAtInstrs prefix "msgControllen" buf (fdPassOf k "msghdr.msg_controllen") "rawStoreI32" (str prefix ".space32")))))))))

fn fdPassAllocBlocks prefix: String k: (Map String Int64) nextLabel: String errLabel: String -> (List ty/SsaBlock)
  (listAppend
    (list
      (sys/block (str prefix ".entry")
        (list (sys/int64Const (str prefix ".total") (fdPassTotal k))
              (sys/callInstr (str prefix ".buf") (ty/tyPtr) "malloc" (list (str prefix ".total")))
              (sys/primInstr (str prefix ".bufNull") (ty/tyI1) "rawPtrIsNull" (list (str prefix ".buf")))
              (sys/int64Const (str prefix ".z64") 0))
        (ty/termBranch (str prefix ".bufNull") (sys/edgeTo (str prefix ".allocErr")) (ty/ssaEdge (str prefix ".zl") (list (str prefix ".z64")))))
      (sys/block (str prefix ".allocErr")
        (list (sys/callInstr (str prefix ".errnoAlloc") (ty/tyI64) "sysErrnoValue" (list)))
        (ty/termJump (ty/ssaEdge errLabel (list (str prefix ".errnoAlloc"))))))
    (zeroLoopBlocks prefix (str prefix ".buf") (fdPassTotal k) nextLabel))

fn fdResultBlocks prefix: String -> (List ty/SsaBlock)
  (list
    (ty/ssaBlock (str prefix ".err") (list (ty/ssaParam (str prefix ".errnoVal") (ty/tyI64)))
      (list (sys/boxInstr (str prefix ".errBox") (str prefix ".errnoVal")) (constructResult (str prefix ".errv") "err" (str prefix ".errBox")))
      (ty/termReturn (str prefix ".errv"))))

fn errnoConstBlock label: String dest: String value: Int64 frees: (List ty/SsaInstr) errLabel: String -> ty/SsaBlock
  (sys/block label (listAppend frees (list (sys/int64Const dest value))) (ty/termJump (ty/ssaEdge errLabel (list dest))))

fn socketPairFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (constOrErr facts "AF_UNIX")
    ((err e) (err e))
    ((ok afUnix)
     (mt (constOrErr facts "SOCK_STREAM")
       ((err e) (err e))
       ((ok sockStream)
        (mt (fdCloexecBlocks facts "sp.a" "sp.fdA" (sys/edgeTo "sp.b.cloGet") "sp.aFail")
          ((err e) (err e))
          ((ok cloA)
           (mt (fdCloexecBlocks facts "sp.b" "sp.fdB" (sys/edgeTo "sp.ok") "sp.bFail")
             ((err e) (err e))
             ((ok cloB)
              (ok (ty/ssaFunction "sysNetSocketPair" (list) (list) (ty/tyVal)
                (listAppend
                  (list
                    (sys/block "sp.entry"
                      (list (sys/int64Const "sp.svSize" 8)
                            (sys/callInstr "sp.sv" (ty/tyPtr) "malloc" (list "sp.svSize"))
                            (sys/primInstr "sp.svNull" (ty/tyI1) "rawPtrIsNull" (list "sp.sv")))
                      (ty/termBranch "sp.svNull" (sys/edgeTo "sp.allocErr") (sys/edgeTo "sp.call")))
                    (sys/block "sp.allocErr"
                      (list (sys/callInstr "sp.errnoAlloc" (ty/tyI64) "sysErrnoValue" (list)))
                      (ty/termJump (ty/ssaEdge "sp.err" (list "sp.errnoAlloc"))))
                    (sys/block "sp.call"
                      (list (sys/int32Const "sp.dom" afUnix)
                            (sys/int32Const "sp.ty" sockStream)
                            (sys/int32Const "sp.proto" 0)
                            (sys/callInstr "sp.r" (ty/tyI32) "socketpair" (list "sp.dom" "sp.ty" "sp.proto" "sp.sv"))
                            (sys/primInstr "sp.failed" (ty/tyI1) "rawLtI32" (list "sp.r" "sp.proto")))
                      (ty/termBranch "sp.failed" (sys/edgeTo "sp.callErr") (sys/edgeTo "sp.loaded")))
                    (sys/block "sp.callErr"
                      (list (sys/callInstr "sp.errnoCall" (ty/tyI64) "sysErrnoValue" (list))
                            (freeInstr "sp.freeCall" "sp.sv"))
                      (ty/termJump (ty/ssaEdge "sp.err" (list "sp.errnoCall"))))
                    (sys/block "sp.loaded"
                      (list (sys/int64Const "sp.offA" 0)
                            (sys/primInstr "sp.fdA" (ty/tyI32) "rawLoadI32" (list "sp.sv" "sp.offA"))
                            (sys/int64Const "sp.offB" 4)
                            (sys/primInstr "sp.fdB" (ty/tyI32) "rawLoadI32" (list "sp.sv" "sp.offB"))
                            (freeInstr "sp.freeSv" "sp.sv"))
                      (ty/termJump (sys/edgeTo "sp.a.cloGet")))
                    (ty/ssaBlock "sp.aFail" (list (ty/ssaParam "sp.aErrno" (ty/tyI64)))
                      (list (sys/callInstr "sp.closeBAfterA" (ty/tyI32) "close" (list "sp.fdB")))
                      (ty/termJump (ty/ssaEdge "sp.err" (list "sp.aErrno"))))
                    (ty/ssaBlock "sp.bFail" (list (ty/ssaParam "sp.bErrno" (ty/tyI64)))
                      (list (sys/callInstr "sp.closeAAfterB" (ty/tyI32) "close" (list "sp.fdA")))
                      (ty/termJump (ty/ssaEdge "sp.err" (list "sp.bErrno"))))
                    (sys/block "sp.ok"
                      (list (sys/primInstr "sp.aWide" (ty/tyI64) "rawWidenI32" (list "sp.fdA"))
                            (sys/boxInstr "sp.aBox" "sp.aWide")
                            (sys/primInstr "sp.bWide" (ty/tyI64) "rawWidenI32" (list "sp.fdB"))
                            (sys/boxInstr "sp.bBox" "sp.bWide")
                            (ty/ssaInstr "sp.pair" (ty/tyVal) (ty/opConstruct "Pair" "pair" (list "sp.aBox" "sp.bBox")))
                            (constructResult "sp.okv" "ok" "sp.pair"))
                      (ty/termReturn "sp.okv")))
                  (listAppend cloA (listAppend cloB (fdResultBlocks "sp"))))))))))))))

fn sendFdFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (fdPassFacts facts)
    ((err e) (err e))
    ((ok k)
      (let [(ctl (fdPassControl k))]
        (ok (ty/ssaFunction "sysNetSendFd" (list) (list (ty/ssaParam "sock" (ty/tyI32)) (ty/ssaParam "fd" (ty/tyI32))) (ty/tyVal)
          (listAppend (fdPassAllocBlocks "sf" k "sf.fill" "sf.err")
            (listAppend
              (list
                (sys/block "sf.fill"
                  (listAppend (msgFillInstrs "sf" "sf.buf" k)
                    (listAppend
                      (list (sys/int32Const "sf.cmsgLen" (fdPassOf k "CMSG_LEN_INT"))
                            (sys/int32Const "sf.level" (fdPassOf k "SOL_SOCKET"))
                            (sys/int32Const "sf.type" (fdPassOf k "SCM_RIGHTS")))
                      (listAppend (storeAtInstrs "sf" "cmsgLen" "sf.buf" (+ ctl (fdPassOf k "cmsghdr.cmsg_len")) "rawStoreI32" "sf.cmsgLen")
                        (listAppend (storeAtInstrs "sf" "cmsgLevel" "sf.buf" (+ ctl (fdPassOf k "cmsghdr.cmsg_level")) "rawStoreI32" "sf.level")
                          (listAppend (storeAtInstrs "sf" "cmsgType" "sf.buf" (+ ctl (fdPassOf k "cmsghdr.cmsg_type")) "rawStoreI32" "sf.type")
                            (listAppend (storeAtInstrs "sf" "cmsgFd" "sf.buf" (+ ctl (fdPassOf k "CMSG_DATA_OFFSET")) "rawStoreI32" "fd")
                              (list (sys/int32Const "sf.flags" 0)
                                    (sys/callInstr "sf.n" (ty/tyI64) "sendmsg" (list "sock" "sf.buf" "sf.flags"))
                                    (sys/int64Const "sf.zero" 0)
                                    (sys/primInstr "sf.failed" (ty/tyI1) "ltInt" (list "sf.n" "sf.zero")))))))))
                  (ty/termBranch "sf.failed" (sys/edgeTo "sf.sendErr") (sys/edgeTo "sf.sent")))
                (sys/block "sf.sendErr"
                  (list (sys/callInstr "sf.errnoSend" (ty/tyI64) "sysErrnoValue" (list))
                        (freeInstr "sf.freeErr" "sf.buf"))
                  (ty/termJump (ty/ssaEdge "sf.err" (list "sf.errnoSend"))))
                (sys/block "sf.sent"
                  (list (freeInstr "sf.freeSent" "sf.buf")
                        (sys/primInstr "sf.none" (ty/tyI1) "leInt" (list "sf.n" "sf.zero")))
                  (ty/termBranch "sf.none" (sys/edgeTo "sf.short") (sys/edgeTo "sf.ok")))
                (errnoConstBlock "sf.short" "sf.eio" (fdPassOf k "EIO") (list) "sf.err")
                (sys/block "sf.ok"
                  (list (sys/primInstr "sf.fdWide" (ty/tyI64) "rawWidenI32" (list "fd"))
                        (sys/boxInstr "sf.fdBox" "sf.fdWide")
                        (constructResult "sf.okv" "ok" "sf.fdBox"))
                  (ty/termReturn "sf.okv")))
              (fdResultBlocks "sf"))))))))

fn recvFdFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (fdPassFacts facts)
    ((err e) (err e))
    ((ok k)
      (mt (fdCloexecBlocks facts "rf.clo" "rf.fd" (sys/edgeTo "rf.ok") "rf.err")
        ((err e) (err e))
        ((ok cloBlocks)
          (let [(ctl (fdPassControl k))
                (atomic (libc/libcConst facts "MSG_CMSG_CLOEXEC"))
                (flags (optionOr atomic 0))]
            (ok (ty/ssaFunction "sysNetRecvFd" (list) (list (ty/ssaParam "sock" (ty/tyI32))) (ty/tyVal)
              (listAppend (fdPassAllocBlocks "rf" k "rf.fill" "rf.err")
                (listAppend
                  (list
                    (sys/block "rf.fill"
                      (listAppend (msgFillInstrs "rf" "rf.buf" k)
                        (list (sys/int32Const "rf.flags" flags)
                              (sys/callInstr "rf.n" (ty/tyI64) "recvmsg" (list "sock" "rf.buf" "rf.flags"))
                              (sys/int64Const "rf.zero" 0)
                              (sys/primInstr "rf.failed" (ty/tyI1) "ltInt" (list "rf.n" "rf.zero"))))
                      (ty/termBranch "rf.failed" (sys/edgeTo "rf.recvErr") (sys/edgeTo "rf.got")))
                    (sys/block "rf.recvErr"
                      (list (sys/callInstr "rf.errnoRecv" (ty/tyI64) "sysErrnoValue" (list))
                            (freeInstr "rf.freeErr" "rf.buf"))
                      (ty/termJump (ty/ssaEdge "rf.err" (list "rf.errnoRecv"))))
                    (sys/block "rf.got"
                      (list (sys/int64Const "rf.ctlLenOff" (fdPassOf k "msghdr.msg_controllen"))
                            (sys/primInstr "rf.ctlLen" (ty/tyI32) "rawLoadI32" (list "rf.buf" "rf.ctlLenOff"))
                            (sys/int32Const "rf.wantLen" (fdPassOf k "CMSG_LEN_INT"))
                            (sys/primInstr "rf.ctlRoom" (ty/tyI1) "rawGeI32" (list "rf.ctlLen" "rf.wantLen"))
                            (sys/int64Const "rf.cmsgLenOff" (+ ctl (fdPassOf k "cmsghdr.cmsg_len")))
                            (sys/primInstr "rf.cmsgLen" (ty/tyI32) "rawLoadI32" (list "rf.buf" "rf.cmsgLenOff"))
                            (sys/primInstr "rf.cmsgRoom" (ty/tyI1) "rawGeI32" (list "rf.cmsgLen" "rf.wantLen"))
                            (sys/int64Const "rf.levelOff" (+ ctl (fdPassOf k "cmsghdr.cmsg_level")))
                            (sys/primInstr "rf.level" (ty/tyI32) "rawLoadI32" (list "rf.buf" "rf.levelOff"))
                            (sys/int32Const "rf.solSocket" (fdPassOf k "SOL_SOCKET"))
                            (sys/primInstr "rf.levelOk" (ty/tyI1) "rawEqI32" (list "rf.level" "rf.solSocket"))
                            (sys/int64Const "rf.typeOff" (+ ctl (fdPassOf k "cmsghdr.cmsg_type")))
                            (sys/primInstr "rf.type" (ty/tyI32) "rawLoadI32" (list "rf.buf" "rf.typeOff"))
                            (sys/int32Const "rf.scmRights" (fdPassOf k "SCM_RIGHTS"))
                            (sys/primInstr "rf.typeOk" (ty/tyI1) "rawEqI32" (list "rf.type" "rf.scmRights"))
                            (sys/primInstr "rf.room" (ty/tyI1) "andBool" (list "rf.ctlRoom" "rf.cmsgRoom"))
                            (sys/primInstr "rf.kind" (ty/tyI1) "andBool" (list "rf.levelOk" "rf.typeOk"))
                            (sys/primInstr "rf.hasFd" (ty/tyI1) "andBool" (list "rf.room" "rf.kind")))
                      (ty/termBranch "rf.hasFd" (sys/edgeTo "rf.take") (sys/edgeTo "rf.noFd")))
                    (errnoConstBlock "rf.noFd" "rf.badmsg" (fdPassOf k "EBADMSG") (list (freeInstr "rf.freeNoFd" "rf.buf")) "rf.err")
                    (sys/block "rf.take"
                      (list (sys/int64Const "rf.fdOff" (+ ctl (fdPassOf k "CMSG_DATA_OFFSET")))
                            (sys/primInstr "rf.fd" (ty/tyI32) "rawLoadI32" (list "rf.buf" "rf.fdOff"))
                            (sys/int64Const "rf.msgFlagsOff" (fdPassOf k "msghdr.msg_flags"))
                            (sys/primInstr "rf.msgFlags" (ty/tyI32) "rawLoadI32" (list "rf.buf" "rf.msgFlagsOff"))
                            (sys/int32Const "rf.ctrunc" (fdPassOf k "MSG_CTRUNC"))
                            (sys/primInstr "rf.cut" (ty/tyI32) "rawAndI32" (list "rf.msgFlags" "rf.ctrunc"))
                            (sys/int32Const "rf.z32" 0)
                            (sys/primInstr "rf.truncated" (ty/tyI1) "rawNeI32" (list "rf.cut" "rf.z32"))
                            (freeInstr "rf.freeTake" "rf.buf"))
                      (ty/termBranch "rf.truncated" (sys/edgeTo "rf.trunc") (sys/edgeTo "rf.check")))
                    (errnoConstBlock "rf.trunc" "rf.emsgsize" (fdPassOf k "EMSGSIZE") (list (sys/callInstr "rf.closeTrunc" (ty/tyI32) "close" (list "rf.fd"))) "rf.err")
                    (sys/block "rf.check"
                      (list (sys/primInstr "rf.negative" (ty/tyI1) "rawLtI32" (list "rf.fd" "rf.z32")))
                      (ty/termBranch "rf.negative" (sys/edgeTo "rf.negFd") (sys/edgeTo (if (some? atomic) "rf.ok" "rf.clo.cloGet"))))
                    (errnoConstBlock "rf.negFd" "rf.badmsgNeg" (fdPassOf k "EBADMSG") (list) "rf.err")
                    (sys/block "rf.ok"
                      (list (sys/primInstr "rf.fdWide" (ty/tyI64) "rawWidenI32" (list "rf.fd"))
                            (sys/boxInstr "rf.fdBox" "rf.fdWide")
                            (constructResult "rf.okv" "ok" "rf.fdBox"))
                      (ty/termReturn "rf.okv")))
                  (listAppend (if (some? atomic) (list) cloBlocks) (fdResultBlocks "rf")))))))))))


fn sysNetExterns facts: libc/TripleFacts -> (List ty/SsaExtern)
  (listAppend (sys/sysCommonExterns facts)
    (list (socketExtern) (bindExtern) (listenExtern) (connectExtern) (acceptExtern) (accept4Extern) (getsocknameExtern) (fcntlExtern) (closeExtern)
          (socketpairExtern) (sendmsgExtern) (recvmsgExtern)))

fn sysNetFunctions facts: libc/TripleFacts -> (Result (List ty/SsaFunction) String)
  (mt (tcpListenFn facts)
    ((err e) (err e))
    ((ok tcpListen)
     (mt (tcpConnectFn facts)
       ((err e) (err e))
       ((ok tcpConnect)
        (mt (sockAcceptFn facts)
          ((err e) (err e))
          ((ok sockAccept)
           (mt (sockLocalPortFn facts)
             ((err e) (err e))
             ((ok sockLocalPort)
              (mt (unixListenFn facts)
                ((err e) (err e))
                ((ok unixListen)
                 (mt (unixConnectFn facts)
                   ((err e) (err e))
                   ((ok unixConnect)
                    (mt (socketPairFn facts)
                      ((err e) (err e))
                      ((ok socketPair)
                       (mt (sendFdFn facts)
                         ((err e) (err e))
                         ((ok sendFd)
                          (mt (recvFdFn facts)
                            ((err e) (err e))
                            ((ok recvFd)
                             (ok (list (sys/sysErrnoValueFn facts) tcpListen tcpConnect sockAccept sockLocalPort unixListen unixConnect socketPair sendFd recvFd))))))))))))))))))))
