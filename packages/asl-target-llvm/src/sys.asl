(module asl-target-llvm/sys
  :x [resultTypeDecl optionTypeDecl sysCommonExterns sysExterns sysFunctions
      sysErrnoValueFn sysGetpidFn sysReadFn sysWriteFn sysCloseFn sysPreadFn sysPwriteFn
      sysKillFn sysFsyncFn sysFlockFn sysRenameFn sysChmodFn sysMkdirFn sysUnlinkFn sysRmdirFn
      sysSymlinkFn sysReadlinkFn sysSysconfFn sysClockGettimeFn sysUsleepFn
      sysGetenvFn sysFcntlGetFn sysFcntlSetFn sysPollFn sysNanosleepFn
      sysStatFn sysLstatFn sysUtimesFn sysLocaltimeFn sysGetrusageFn sysUnameFn sysDirListFn sysRealpathFn sysExePathFn exePathExterns
      int64Const int32Const callInstr entryInstr primInstr boxInstr listInstr block edgeTo cstrFieldBlocks
      fileRouteBuiltins fileRouteExterns fileRouteStrings fileRouteGlobals fileRouteRecords fileRouteFunctions]
  :i [(asl-ir/types :a ty)
      (asl-target-llvm/libc :a libc)])

fn int64Const dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI64) (ty/opConst (ty/constInt n)))

fn int32Const dest: String n: Int64 -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyI32) (ty/opConst (ty/constInt n)))

fn callInstr dest: String t: ty/SsaTy callee: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opCall callee args))

fn entryInstr dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opEntry name args))

fn primInstr dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest t (ty/opPrim name args))

fn boxInstr dest: String v: String -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opBox v))

fn listInstr dest: String items: (List String) -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opList items))

fn constructResult dest: String variant: String field: String -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) (ty/opConstruct "Result" variant (list field)))

fn block label: String instrs: (List ty/SsaInstr) term: ty/SsaTerm -> ty/SsaBlock
  (ty/ssaBlock label (list) instrs term)

fn edgeTo label: String -> ty/SsaEdge
  (ty/ssaEdge label (list))

fn resultTypeDecl -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Result" (list (ty/ssaVariant "ok" 1) (ty/ssaVariant "err" 1)))

fn optionTypeDecl -> ty/SsaTypeDecl
  (ty/ssaTypeDecl "Option" (list (ty/ssaVariant "some" 1) (ty/ssaVariant "none" 0)))

fn mallocExtern -> ty/SsaExtern
  (ty/ssaExternTyped "malloc" (list (ty/tyI64)) (ty/tyPtr))

fn freeExtern -> ty/SsaExtern
  (ty/ssaExternTyped "free" (list (ty/tyPtr)) (ty/tyI64))

fn valToCStrExtern -> ty/SsaExtern
  (ty/ssaExternTyped "valToCStr" (list (ty/tyVal) (ty/tyI32)) (ty/tyPtr))

fn mkBytesExtern -> ty/SsaExtern
  (ty/ssaExternTyped "mkBytes" (list (ty/tyPtr) (ty/tyI64)) (ty/tyVal))

fn mkStrExtern -> ty/SsaExtern
  (ty/ssaExternTyped "mkStr" (list (ty/tyPtr) (ty/tyI64)) (ty/tyVal))

fn errnoAccessorExtern facts: libc/TripleFacts -> ty/SsaExtern
  (ty/ssaExternTyped facts.errnoAccessor (list) (ty/tyPtr))

fn sysCommonExterns facts: libc/TripleFacts -> (List ty/SsaExtern)
  (list (mallocExtern) (freeExtern) (valToCStrExtern) (mkBytesExtern) (mkStrExtern) (errnoAccessorExtern facts))

fn pow256 i: Int64 -> Int64
  (if (<= i 0) 1 (* 256 (pow256 (- i 1))))

fn decodeLittleEndianBytes bytesVal: String offset: Int64 n: Int64 prefix: String -> (Pair (List ty/SsaInstr) String)
  (fold
    (fn [(acc (Pair (List ty/SsaInstr) String)) (i Int64)] -> (Pair (List ty/SsaInstr) String)
      (let [(doneSoFar (pairFirst acc)) (accName (pairSecond acc))
            (idxName (str prefix ".i" i)) (byteName (str prefix ".b" i))
            (idxInstr (int64Const idxName (+ offset i)))
            (getInstr (entryInstr byteName (ty/tyI64) "bytesGet" (list bytesVal idxName)))]
        (if (= i 0)
          (pair (listAppend doneSoFar (list idxInstr getInstr)) byteName)
          (let [(scaleName (str prefix ".k" i)) (scaledName (str prefix ".s" i)) (sumName (str prefix ".n" i))
                (scaleInstr (int64Const scaleName (pow256 i)))
                (mulInstr (primInstr scaledName (ty/tyI64) "mulInt" (list byteName scaleName)))
                (addInstr (primInstr sumName (ty/tyI64) "addInt" (list accName scaledName)))]
            (pair (listAppend doneSoFar (list idxInstr getInstr scaleInstr mulInstr addInstr)) sumName)))))
    (pair (list) "") (range 0 n))

fn sysErrnoValueFn facts: libc/TripleFacts -> ty/SsaFunction
  (let [(decoded (decodeLittleEndianBytes "bs" 0 4 "errno"))
        (pre (list (int64Const "four" 4)
                    (callInstr "errp" (ty/tyPtr) facts.errnoAccessor (list))
                    (callInstr "bs" (ty/tyVal) "mkBytes" (list "errp" "four"))))]
    (ty/ssaFunction "sysErrnoValue" (list) (list) (ty/tyI64)
      (list (block "entry" (listAppend pre (pairFirst decoded)) (ty/termReturn (pairSecond decoded))))))

fn errnoResultFn name: String params: (List ty/SsaParam) preInstrs: (List ty/SsaInstr) callee: String callArgs: (List String) checkPrim: String errPre: (List ty/SsaInstr) okPre: (List ty/SsaInstr) okValue: String nativeRetTy: ty/SsaTy allocCheck: (Option String) -> ty/SsaFunction
  (let [(native32? (= (ty/ssaTyName nativeRetTy) "i32"))
        (callDest (if native32? "call.raw" "call.n"))
        (widen (if native32? (list (primInstr "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))) (list)))
        (callInstrs (listAppend (list (callInstr callDest nativeRetTy callee callArgs))
                      (listAppend widen
                        (list (int64Const "call.zero" 0)
                              (primInstr "call.isErr" (ty/tyI1) checkPrim (list "call.n" "call.zero"))))))
        (callBranch (ty/termBranch "call.isErr" (edgeTo "err") (edgeTo "ok")))
        (entryBlk (mt allocCheck
                    ((none) (block "entry" (listAppend preInstrs callInstrs) callBranch))
                    ((some ptrName)
                      (block "entry"
                        (listAppend preInstrs (list (primInstr "alloc.isNull" (ty/tyI1) "rawPtrIsNull" (list ptrName))))
                        (ty/termBranch "alloc.isNull" (edgeTo "err") (edgeTo "call"))))))
        (restBlocks (mt allocCheck ((none) (list)) ((some _) (list (block "call" callInstrs callBranch)))))
        (errBlk (block "err"
                  (listAppend (list (callInstr "call.errno" (ty/tyI64) "sysErrnoValue" (list)))
                    (listAppend errPre
                      (list (boxInstr "call.errnoBox" "call.errno")
                            (constructResult "call.errv" "err" "call.errnoBox"))))
                  (ty/termReturn "call.errv")))
        (okBlk (block "ok"
                 (listAppend okPre (list (constructResult "call.okv" "ok" okValue)))
                 (ty/termReturn "call.okv")))]
    (ty/ssaFunction name (list) params (ty/tyVal) (listAppend (list entryBlk) (listAppend restBlocks (list errBlk okBlk)))))

fn boxCallResult -> (List ty/SsaInstr)
  (list (boxInstr "call.nb" "call.n"))

fn stringToPtrInstrs dest: String v: String -> (List ty/SsaInstr)
  (list (int32Const (str dest ".repr") 0)
        (callInstr dest (ty/tyPtr) "valToCStr" (list v (str dest ".repr"))))

fn freeInstr dest: String ptrName: String -> ty/SsaInstr
  (callInstr dest (ty/tyI64) "free" (list ptrName))

fn atLeastOneBlocks sizeParam: String joinLabel: String pre: (List ty/SsaInstr) -> (List ty/SsaBlock)
  (list
    (block "size"
      (listAppend pre (list (int64Const "size.zeroC" 0) (primInstr "size.isZero" (ty/tyI1) "eqInt" (list sizeParam "size.zeroC"))))
      (ty/termBranch "size.isZero" (edgeTo "size.z") (edgeTo "size.nz")))
    (block "size.z" (list (int64Const "size.one" 1)) (ty/termJump (ty/ssaEdge joinLabel (list "size.one"))))
    (block "size.nz" (list) (ty/termJump (ty/ssaEdge joinLabel (list sizeParam)))))


fn getpidExtern -> ty/SsaExtern
  (ty/ssaExternTyped "getpid" (list) (ty/tyI32))

fn sysGetpidFn -> ty/SsaFunction
  (ty/ssaFunction "sysGetpid" (list) (list) (ty/tyI32)
    (list (block "entry" (list (callInstr "pid" (ty/tyI32) "getpid" (list))) (ty/termReturn "pid"))))

fn readExtern -> ty/SsaExtern
  (ty/ssaExternTyped "read" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64)) (ty/tyI64))

fn sysReadFn -> ty/SsaFunction
  (ty/ssaFunction "sysRead" (list) (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "max" (ty/tyI64))) (ty/tyVal)
    (listAppend (atLeastOneBlocks "max" "entry" (list))
      (list
        (ty/ssaBlock "entry" (list (ty/ssaParam "allocSize" (ty/tyI64)))
          (list (callInstr "buf" (ty/tyPtr) "malloc" (list "allocSize"))
                (primInstr "alloc.isNull" (ty/tyI1) "rawPtrIsNull" (list "buf")))
          (ty/termBranch "alloc.isNull" (edgeTo "err") (edgeTo "call")))
        (block "call"
          (list (callInstr "call.n" (ty/tyI64) "read" (list "fd" "buf" "max"))
                (int64Const "call.zero" 0)
                (primInstr "call.isErr" (ty/tyI1) "ltInt" (list "call.n" "call.zero")))
          (ty/termBranch "call.isErr" (edgeTo "err") (edgeTo "ok")))
        (block "err"
          (listAppend (list (callInstr "call.errno" (ty/tyI64) "sysErrnoValue" (list)))
            (list (freeInstr "free.err" "buf")
                  (boxInstr "call.errnoBox" "call.errno")
                  (constructResult "call.errv" "err" "call.errnoBox")))
          (ty/termReturn "call.errv"))
        (block "ok"
          (list (callInstr "bytes" (ty/tyVal) "mkBytes" (list "buf" "call.n"))
                (freeInstr "free.ok" "buf")
                (constructResult "call.okv" "ok" "bytes"))
          (ty/termReturn "call.okv")))))

fn writeExtern -> ty/SsaExtern
  (ty/ssaExternTyped "write" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64)) (ty/tyI64))

fn sysWriteFn -> ty/SsaFunction
  (errnoResultFn "sysWrite" (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "data" (ty/tyVal)))
    (listAppend (stringToPtrInstrs "p" "data") (list (entryInstr "len" (ty/tyI64) "stringLength" (list "data"))))
    "write" (list "fd" "p" "len") "ltInt"
    (list (freeInstr "free.err" "p"))
    (listAppend (list (freeInstr "free.ok" "p")) (boxCallResult))
    "call.nb" (ty/tyI64) (none))

fn closeExtern -> ty/SsaExtern
  (ty/ssaExternTyped "close" (list (ty/tyI32)) (ty/tyI32))

fn sysCloseFn -> ty/SsaFunction
  (errnoResultFn "sysClose" (list (ty/ssaParam "fd" (ty/tyI32))) (list) "close" (list "fd") "neInt"
    (list) (boxCallResult) "call.nb" (ty/tyI32) (none))

fn preadExtern -> ty/SsaExtern
  (ty/ssaExternTyped "pread" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64) (ty/tyI64)) (ty/tyI64))

fn sysPreadFn -> ty/SsaFunction
  (ty/ssaFunction "sysPread" (list)
    (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "max" (ty/tyI64)) (ty/ssaParam "offset" (ty/tyI64))) (ty/tyVal)
    (listAppend (atLeastOneBlocks "max" "entry" (list))
      (list
        (ty/ssaBlock "entry" (list (ty/ssaParam "allocSize" (ty/tyI64)))
          (list (callInstr "buf" (ty/tyPtr) "malloc" (list "allocSize"))
                (primInstr "alloc.isNull" (ty/tyI1) "rawPtrIsNull" (list "buf")))
          (ty/termBranch "alloc.isNull" (edgeTo "err") (edgeTo "call")))
        (block "call"
          (list (callInstr "call.n" (ty/tyI64) "pread" (list "fd" "buf" "max" "offset"))
                (int64Const "call.zero" 0)
                (primInstr "call.isErr" (ty/tyI1) "ltInt" (list "call.n" "call.zero")))
          (ty/termBranch "call.isErr" (edgeTo "err") (edgeTo "ok")))
        (block "err"
          (listAppend (list (callInstr "call.errno" (ty/tyI64) "sysErrnoValue" (list)))
            (list (freeInstr "free.err" "buf")
                  (boxInstr "call.errnoBox" "call.errno")
                  (constructResult "call.errv" "err" "call.errnoBox")))
          (ty/termReturn "call.errv"))
        (block "ok"
          (list (callInstr "bytes" (ty/tyVal) "mkBytes" (list "buf" "call.n"))
                (freeInstr "free.ok" "buf")
                (constructResult "call.okv" "ok" "bytes"))
          (ty/termReturn "call.okv")))))

fn pwriteExtern -> ty/SsaExtern
  (ty/ssaExternTyped "pwrite" (list (ty/tyI32) (ty/tyPtr) (ty/tyI64) (ty/tyI64)) (ty/tyI64))

fn sysPwriteFn -> ty/SsaFunction
  (errnoResultFn "sysPwrite" (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "data" (ty/tyVal)) (ty/ssaParam "offset" (ty/tyI64)))
    (listAppend (stringToPtrInstrs "p" "data") (list (entryInstr "len" (ty/tyI64) "stringLength" (list "data"))))
    "pwrite" (list "fd" "p" "len" "offset") "ltInt"
    (list (freeInstr "free.err" "p"))
    (listAppend (list (freeInstr "free.ok" "p")) (boxCallResult))
    "call.nb" (ty/tyI64) (none))

fn killExtern -> ty/SsaExtern
  (ty/ssaExternTyped "kill" (list (ty/tyI32) (ty/tyI32)) (ty/tyI32))

fn sysKillFn -> ty/SsaFunction
  (errnoResultFn "sysKill" (list (ty/ssaParam "pid" (ty/tyI32)) (ty/ssaParam "sig" (ty/tyI32)))
    (list) "kill" (list "pid" "sig") "neInt" (list) (boxCallResult) "call.nb" (ty/tyI32) (none))

fn fsyncExtern -> ty/SsaExtern
  (ty/ssaExternTyped "fsync" (list (ty/tyI32)) (ty/tyI32))

fn sysFsyncFn -> ty/SsaFunction
  (errnoResultFn "sysFsync" (list (ty/ssaParam "fd" (ty/tyI32))) (list) "fsync" (list "fd") "neInt"
    (list) (boxCallResult) "call.nb" (ty/tyI32) (none))

fn flockExtern -> ty/SsaExtern
  (ty/ssaExternTyped "flock" (list (ty/tyI32) (ty/tyI32)) (ty/tyI32))

fn sysFlockFn -> ty/SsaFunction
  (errnoResultFn "sysFlock" (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "op" (ty/tyI32)))
    (list) "flock" (list "fd" "op") "neInt" (list) (boxCallResult) "call.nb" (ty/tyI32) (none))

fn renameExtern -> ty/SsaExtern
  (ty/ssaExternTyped "rename" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn sysRenameFn -> ty/SsaFunction
  (errnoResultFn "sysRename" (list (ty/ssaParam "oldPath" (ty/tyVal)) (ty/ssaParam "newPath" (ty/tyVal)))
    (listAppend (stringToPtrInstrs "p1" "oldPath") (stringToPtrInstrs "p2" "newPath"))
    "rename" (list "p1" "p2") "neInt"
    (list (freeInstr "free1.err" "p1") (freeInstr "free2.err" "p2"))
    (listAppend (list (freeInstr "free1.ok" "p1") (freeInstr "free2.ok" "p2")) (boxCallResult))
    "call.nb" (ty/tyI32) (none))

fn chmodExtern -> ty/SsaExtern
  (ty/ssaExternTyped "chmod" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32))

fn sysChmodFn -> ty/SsaFunction
  (errnoResultFn "sysChmod" (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "mode" (ty/tyI32)))
    (stringToPtrInstrs "p" "path")
    "chmod" (list "p" "mode") "neInt"
    (list (freeInstr "free.err" "p"))
    (listAppend (list (freeInstr "free.ok" "p")) (boxCallResult))
    "call.nb" (ty/tyI32) (none))

fn mkdirExtern -> ty/SsaExtern
  (ty/ssaExternTyped "mkdir" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32))

fn sysMkdirFn -> ty/SsaFunction
  (errnoResultFn "sysMkdir" (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "mode" (ty/tyI32)))
    (stringToPtrInstrs "p" "path")
    "mkdir" (list "p" "mode") "neInt"
    (list (freeInstr "free.err" "p"))
    (listAppend (list (freeInstr "free.ok" "p")) (boxCallResult))
    "call.nb" (ty/tyI32) (none))

fn unlinkExtern -> ty/SsaExtern
  (ty/ssaExternTyped "unlink" (list (ty/tyPtr)) (ty/tyI32))

fn sysUnlinkFn -> ty/SsaFunction
  (errnoResultFn "sysUnlink" (list (ty/ssaParam "path" (ty/tyVal)))
    (stringToPtrInstrs "p" "path")
    "unlink" (list "p") "neInt"
    (list (freeInstr "free.err" "p"))
    (listAppend (list (freeInstr "free.ok" "p")) (boxCallResult))
    "call.nb" (ty/tyI32) (none))

fn rmdirExtern -> ty/SsaExtern
  (ty/ssaExternTyped "rmdir" (list (ty/tyPtr)) (ty/tyI32))

fn sysRmdirFn -> ty/SsaFunction
  (errnoResultFn "sysRmdir" (list (ty/ssaParam "path" (ty/tyVal)))
    (stringToPtrInstrs "p" "path")
    "rmdir" (list "p") "neInt"
    (list (freeInstr "free.err" "p"))
    (listAppend (list (freeInstr "free.ok" "p")) (boxCallResult))
    "call.nb" (ty/tyI32) (none))

fn symlinkExtern -> ty/SsaExtern
  (ty/ssaExternTyped "symlink" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn sysSymlinkFn -> ty/SsaFunction
  (errnoResultFn "sysSymlink" (list (ty/ssaParam "target" (ty/tyVal)) (ty/ssaParam "linkPath" (ty/tyVal)))
    (listAppend (stringToPtrInstrs "p1" "target") (stringToPtrInstrs "p2" "linkPath"))
    "symlink" (list "p1" "p2") "neInt"
    (list (freeInstr "free1.err" "p1") (freeInstr "free2.err" "p2"))
    (listAppend (list (freeInstr "free1.ok" "p1") (freeInstr "free2.ok" "p2")) (boxCallResult))
    "call.nb" (ty/tyI32) (none))

fn readlinkExtern -> ty/SsaExtern
  (ty/ssaExternTyped "readlink" (list (ty/tyPtr) (ty/tyPtr) (ty/tyI64)) (ty/tyI64))

fn sysReadlinkFn -> ty/SsaFunction
  (ty/ssaFunction "sysReadlink" (list) (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "max" (ty/tyI64))) (ty/tyVal)
    (listAppend (atLeastOneBlocks "max" "entry" (stringToPtrInstrs "p" "path"))
      (list
        (ty/ssaBlock "entry" (list (ty/ssaParam "allocSize" (ty/tyI64)))
          (list (callInstr "buf" (ty/tyPtr) "malloc" (list "allocSize"))
                (primInstr "alloc.isNull" (ty/tyI1) "rawPtrIsNull" (list "buf")))
          (ty/termBranch "alloc.isNull" (edgeTo "err") (edgeTo "call")))
        (block "call"
          (list (callInstr "call.n" (ty/tyI64) "readlink" (list "p" "buf" "max"))
                (int64Const "call.zero" 0)
                (primInstr "call.isErr" (ty/tyI1) "ltInt" (list "call.n" "call.zero")))
          (ty/termBranch "call.isErr" (edgeTo "err") (edgeTo "ok")))
        (block "err"
          (listAppend (list (callInstr "call.errno" (ty/tyI64) "sysErrnoValue" (list)))
            (list (freeInstr "freep.err" "p") (freeInstr "freebuf.err" "buf")
                  (boxInstr "call.errnoBox" "call.errno")
                  (constructResult "call.errv" "err" "call.errnoBox")))
          (ty/termReturn "call.errv"))
        (block "ok"
          (list (callInstr "s" (ty/tyVal) "mkBytes" (list "buf" "call.n"))
                (freeInstr "freep.ok" "p") (freeInstr "freebuf.ok" "buf")
                (constructResult "call.okv" "ok" "s"))
          (ty/termReturn "call.okv")))))

fn realpathExtern -> ty/SsaExtern
  (ty/ssaExternTyped "realpath" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyPtr))

fn sysRealpathFn -> ty/SsaFunction
  (ty/ssaFunction "sysRealpath" (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry"
        (listAppend (stringToPtrInstrs "p" "path")
          (list (int64Const "null.zero" 0) (primInstr "nullp" (ty/tyPtr) "rawIntToPtr" (list "null.zero"))
                (callInstr "resolved" (ty/tyPtr) "realpath" (list "p" "nullp"))
                (primInstr "resolved.isNull" (ty/tyI1) "rawPtrIsNull" (list "resolved"))))
        (ty/termBranch "resolved.isNull" (edgeTo "err") (edgeTo "ok")))
      (block "err"
        (listAppend (list (callInstr "call.errno" (ty/tyI64) "sysErrnoValue" (list)))
          (list (freeInstr "freep.err" "p")
                (boxInstr "call.errnoBox" "call.errno")
                (constructResult "call.errv" "err" "call.errnoBox")))
        (ty/termReturn "call.errv"))
      (block "ok"
        (list (callInstr "resolved.len" (ty/tyI64) "strlen" (list "resolved"))
              (callInstr "s" (ty/tyVal) "mkStr" (list "resolved" "resolved.len"))
              (freeInstr "freep.ok" "p") (freeInstr "freeresolved.ok" "resolved")
              (constructResult "call.okv" "ok" "s"))
        (ty/termReturn "call.okv"))))

fn nsGetExecutablePathExtern -> ty/SsaExtern
  (ty/ssaExternTyped "_NSGetExecutablePath" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn exePathExterns facts: libc/TripleFacts -> (List ty/SsaExtern)
  (if (= (libc/exePathSource facts.triple) "nsGetExecutablePath") (list (nsGetExecutablePathExtern)) (list))

fn cStringStoreInstrs ptrName: String text: String -> (List ty/SsaInstr)
  (let [(bs (stringToBytes text))
        (n (bytesLength bs))]
    (fold (fn [(acc (List ty/SsaInstr)) (i Int64)] -> (List ty/SsaInstr)
            (let [(b (if (< i n) (bytesGet bs i) 0))
                  (tag (str "lit." i))]
              (listAppend acc (list (int64Const (str tag ".off") i)
                                    (int32Const (str tag ".b") b)
                                    (primInstr (str tag ".st") (ty/tyI1) "rawStoreI8" (list ptrName (str tag ".off") (str tag ".b")))))))
          (list) (range 0 (+ n 1))))

fn errnoReturnBlock label: String pre: (List ty/SsaInstr) -> ty/SsaBlock
  (block label
    (listAppend (list (callInstr (str label ".errno") (ty/tyI64) "sysErrnoValue" (list)))
      (listAppend pre
        (list (boxInstr (str label ".box") (str label ".errno"))
              (constructResult (str label ".v") "err" (str label ".box")))))
    (ty/termReturn (str label ".v")))

fn exePathFillBlocks method: String pathMax: Int64 erange: Int64 -> (List ty/SsaBlock)
  (if (= method "nsGetExecutablePath")
    (list
      (block "fill"
        (list (int64Const "sz.bytes" 4)
              (callInstr "sz" (ty/tyPtr) "malloc" (list "sz.bytes"))
              (primInstr "sz.isNull" (ty/tyI1) "rawPtrIsNull" (list "sz")))
        (ty/termBranch "sz.isNull" (edgeTo "szErr") (edgeTo "nsCall")))
      (errnoReturnBlock "szErr" (list (freeInstr "szErr.freebuf" "buf")))
      (block "nsCall"
        (list (int64Const "sz.off" 0)
              (int32Const "sz.max" pathMax)
              (primInstr "sz.st" (ty/tyI1) "rawStoreI32" (list "sz" "sz.off" "sz.max"))
              (callInstr "ns.rc" (ty/tyI32) "_NSGetExecutablePath" (list "buf" "sz"))
              (freeInstr "ns.freesz" "sz")
              (int32Const "ns.zero" 0)
              (primInstr "ns.ok" (ty/tyI1) "rawEqI32" (list "ns.rc" "ns.zero")))
        (ty/termBranch "ns.ok" (edgeTo "resolve") (edgeTo "rangeErr")))
      (block "rangeErr"
        (list (freeInstr "rangeErr.freebuf" "buf")
              (int64Const "rangeErr.code" erange)
              (boxInstr "rangeErr.box" "rangeErr.code")
              (constructResult "rangeErr.v" "err" "rangeErr.box"))
        (ty/termReturn "rangeErr.v")))
    (list (block "fill" (cStringStoreInstrs "buf" "/proc/self/exe") (ty/termJump (edgeTo "resolve")))))

fn sysExePathFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (let [(method (libc/exePathSource facts.triple))]
    (mt (libc/libcConst facts "PATH_MAX")
      ((none) (err (str "libc.asl has no PATH_MAX for " facts.triple)))
      ((some pathMax)
        (mt (libc/libcConst facts "ERANGE")
          ((none) (err (str "libc.asl has no ERANGE for " facts.triple)))
          ((some erange)
            (if (stringEmpty? method)
              (err (str "libc.asl names no exe path source for " facts.triple))
              (ok (ty/ssaFunction "sysExePath" (list) (list) (ty/tyVal)
                    (listAppend
                      (list
                        (block "entry"
                          (list (int64Const "size" pathMax)
                                (callInstr "buf" (ty/tyPtr) "malloc" (list "size"))
                                (primInstr "buf.isNull" (ty/tyI1) "rawPtrIsNull" (list "buf")))
                          (ty/termBranch "buf.isNull" (edgeTo "allocErr") (edgeTo "fill")))
                        (errnoReturnBlock "allocErr" (list)))
                      (listAppend (exePathFillBlocks method pathMax erange)
                        (list
                          (block "resolve"
                            (list (int64Const "null.zero" 0)
                                  (primInstr "nullp" (ty/tyPtr) "rawIntToPtr" (list "null.zero"))
                                  (callInstr "resolved" (ty/tyPtr) "realpath" (list "buf" "nullp"))
                                  (primInstr "resolved.isNull" (ty/tyI1) "rawPtrIsNull" (list "resolved")))
                            (ty/termBranch "resolved.isNull" (edgeTo "resolveErr") (edgeTo "ok")))
                          (errnoReturnBlock "resolveErr" (list (freeInstr "resolveErr.freebuf" "buf")))
                          (block "ok"
                            (list (callInstr "resolved.len" (ty/tyI64) "strlen" (list "resolved"))
                                  (callInstr "s" (ty/tyVal) "mkStr" (list "resolved" "resolved.len"))
                                  (freeInstr "ok.freebuf" "buf") (freeInstr "ok.freeresolved" "resolved")
                                  (constructResult "ok.v" "ok" "s"))
                            (ty/termReturn "ok.v")))))))))))))

fn sysconfExtern -> ty/SsaExtern
  (ty/ssaExternTyped "sysconf" (list (ty/tyI32)) (ty/tyI64))

fn sysSysconfFn -> ty/SsaFunction
  (errnoResultFn "sysSysconf" (list (ty/ssaParam "name" (ty/tyI32))) (list) "sysconf" (list "name") "ltInt"
    (list) (boxCallResult) "call.nb" (ty/tyI64) (none))

fn clockGettimeExtern -> ty/SsaExtern
  (ty/ssaExternTyped "clock_gettime" (list (ty/tyI32) (ty/tyPtr)) (ty/tyI32))

fn sysClockGettimeFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (timespecSize facts)
    ((err e) (err e))
    ((ok tsSize)
     (mt (timespecOffset facts "tv_sec")
       ((err e) (err e))
       ((ok secOff)
        (mt (timespecOffset facts "tv_nsec")
          ((err e) (err e))
          ((ok nsecOff)
           (let [(secDecoded (decodeLittleEndianBytes "bs" secOff 8 "sec"))
                 (nsecDecoded (decodeLittleEndianBytes "bs" nsecOff 8 "nsec"))
                 (secInstrs (pairFirst secDecoded)) (secName (pairSecond secDecoded))
                 (nsecInstrs (pairFirst nsecDecoded)) (nsecName (pairSecond nsecDecoded))
                 (readBack (list (callInstr "bs" (ty/tyVal) "mkBytes" (list "buf" "tsSize"))))
                 (boxBoth (list (boxInstr "secBox" secName) (boxInstr "nsecBox" nsecName)
                                (listInstr "pair" (list "secBox" "nsecBox"))))
                 (okPre (listAppend (listAppend (listAppend readBack secInstrs) (listAppend nsecInstrs boxBoth)) (list (freeInstr "free.ok" "buf"))))]
             (ok (errnoResultFn "sysClockGettime" (list (ty/ssaParam "clockId" (ty/tyI32)))
               (list (int64Const "tsSize" tsSize) (callInstr "buf" (ty/tyPtr) "malloc" (list "tsSize")))
               "clock_gettime" (list "clockId" "buf") "neInt"
               (list (freeInstr "free.err" "buf"))
               okPre "pair" (ty/tyI32) (some "buf"))))))))))

fn usleepExtern -> ty/SsaExtern
  (ty/ssaExternTyped "usleep" (list (ty/tyI32)) (ty/tyI32))

fn sysUsleepFn -> ty/SsaFunction
  (errnoResultFn "sysUsleep" (list (ty/ssaParam "micros" (ty/tyI32))) (list) "usleep" (list "micros") "neInt"
    (list) (boxCallResult) "call.nb" (ty/tyI32) (none))

fn strlenExtern -> ty/SsaExtern
  (ty/ssaExternTyped "strlen" (list (ty/tyPtr)) (ty/tyI64))

fn getenvExtern -> ty/SsaExtern
  (ty/ssaExternTyped "getenv" (list (ty/tyPtr)) (ty/tyPtr))

fn sysGetenvFn -> ty/SsaFunction
  (ty/ssaFunction "sysGetenv" (list) (list (ty/ssaParam "name" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry"
        (listAppend (stringToPtrInstrs "p" "name")
          (list (callInstr "envp" (ty/tyPtr) "getenv" (list "p"))
                (freeInstr "free.p" "p")
                (primInstr "envp.isNull" (ty/tyI1) "rawPtrIsNull" (list "envp"))))
        (ty/termBranch "envp.isNull" (edgeTo "none") (edgeTo "some")))
      (block "none"
        (list (ty/ssaInstr "r.none" (ty/tyVal) (ty/opConstruct "Option" "none" (list))))
        (ty/termReturn "r.none"))
      (block "some"
        (list (callInstr "envLen" (ty/tyI64) "strlen" (list "envp"))
              (callInstr "envBytes" (ty/tyVal) "mkBytes" (list "envp" "envLen"))
              (ty/ssaInstr "r.some" (ty/tyVal) (ty/opConstruct "Option" "some" (list "envBytes"))))
        (ty/termReturn "r.some"))))

fn fcntlExtern -> ty/SsaExtern
  (ty/ssaExternVariadic "fcntl" (list (ty/tyI32) (ty/tyI32)) (ty/tyI32))

fn sysFcntlGetFn -> ty/SsaFunction
  (errnoResultFn "sysFcntlGet" (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "cmd" (ty/tyI32)))
    (list) "fcntl" (list "fd" "cmd") "ltInt" (list) (boxCallResult) "call.nb" (ty/tyI32) (none))

fn sysFcntlSetFn -> ty/SsaFunction
  (errnoResultFn "sysFcntlSet" (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "cmd" (ty/tyI32)) (ty/ssaParam "arg" (ty/tyI32)))
    (list) "fcntl" (list "fd" "cmd" "arg") "ltInt" (list) (boxCallResult) "call.nb" (ty/tyI32) (none))

fn pollExtern -> ty/SsaExtern
  (ty/ssaExternTyped "poll" (list (ty/tyPtr) (ty/tyI64) (ty/tyI32)) (ty/tyI32))

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

fn pollfdOffset facts: libc/TripleFacts field: String -> (Result Int64 String)
  (structOffset facts "pollfd" field)

fn timespecOffset facts: libc/TripleFacts field: String -> (Result Int64 String)
  (structOffset facts "timespec" field)

fn timespecSize facts: libc/TripleFacts -> (Result Int64 String)
  (structByteSize facts "timespec")

fn timevalOffset facts: libc/TripleFacts field: String -> (Result Int64 String)
  (structOffset facts "timeval" field)

fn timevalSize facts: libc/TripleFacts -> (Result Int64 String)
  (structByteSize facts "timeval")

fn constOrErr facts: libc/TripleFacts name: String -> (Result Int64 String)
  (mt (libc/libcConst facts name)
    ((none) (err (str "libc.asl has no " name " const row for triple " facts.triple)))
    ((some v) (ok v)))

fn sysPollFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (pollfdOffset facts "fd")
    ((err e) (err e))
    ((ok fdOff)
     (mt (pollfdOffset facts "events")
       ((err e) (err e))
       ((ok evOff)
        (mt (pollfdOffset facts "revents")
          ((err e) (err e))
          ((ok revOff)
           (mt (structByteSize facts "pollfd")
             ((err e) (err e))
             ((ok pfdSize)
              (let [(shiftBits (* (- revOff evOff) 8))]
                (ok (ty/ssaFunction "sysPoll" (list)
                  (list (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "events" (ty/tyI32)) (ty/ssaParam "timeoutMs" (ty/tyI32)))
                  (ty/tyVal)
                  (list
                    (block "entry"
                      (list (int64Const "pfd.size" pfdSize) (callInstr "pfd" (ty/tyPtr) "malloc" (list "pfd.size"))
                            (primInstr "pfd.isNull" (ty/tyI1) "rawPtrIsNull" (list "pfd")))
                      (ty/termBranch "pfd.isNull" (edgeTo "err0") (edgeTo "store")))
                    (block "store"
                      (list (int64Const "pfd.fdOff" fdOff) (primInstr "st.fd" (ty/tyI1) "rawStoreI32" (list "pfd" "pfd.fdOff" "fd"))
                            (int64Const "pfd.evOff" evOff) (primInstr "st.ev" (ty/tyI1) "rawStoreI32" (list "pfd" "pfd.evOff" "events"))
                            (int64Const "pfd.nfds" 1)
                            (callInstr "call.raw" (ty/tyI32) "poll" (list "pfd" "pfd.nfds" "timeoutMs"))
                            (primInstr "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))
                            (int64Const "call.zero" 0)
                            (primInstr "call.isErr" (ty/tyI1) "ltInt" (list "call.n" "call.zero")))
                      (ty/termBranch "call.isErr" (edgeTo "err1") (edgeTo "ok")))
                    (block "err0"
                      (list (callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list))
                            (boxInstr "errnoBox0" "errno0")
                            (constructResult "errv0" "err" "errnoBox0"))
                      (ty/termReturn "errv0"))
                    (block "err1"
                      (listAppend (list (callInstr "errno1" (ty/tyI64) "sysErrnoValue" (list)))
                        (list (freeInstr "free.err1" "pfd")
                              (boxInstr "errnoBox1" "errno1")
                              (constructResult "errv1" "err" "errnoBox1")))
                      (ty/termReturn "errv1"))
                    (block "ok"
                      (list (primInstr "rev.word" (ty/tyI32) "rawLoadI32" (list "pfd" "pfd.evOff"))
                            (int32Const "rev.shiftN" shiftBits)
                            (primInstr "rev.shifted" (ty/tyI32) "rawLshrI32" (list "rev.word" "rev.shiftN"))
                            (primInstr "rev.n" (ty/tyI64) "rawWidenI32" (list "rev.shifted"))
                            (freeInstr "free.ok" "pfd")
                            (boxInstr "call.nb" "call.n") (boxInstr "rev.box" "rev.n")
                            (listInstr "pollRes" (list "call.nb" "rev.box"))
                            (constructResult "okv" "ok" "pollRes"))
                      (ty/termReturn "okv"))))))))))))))

fn nanosleepExtern -> ty/SsaExtern
  (ty/ssaExternTyped "nanosleep" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn sysNanosleepFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (timespecSize facts)
    ((err e) (err e))
    ((ok tsSize)
     (mt (timespecOffset facts "tv_sec")
       ((err e) (err e))
       ((ok secOff)
        (mt (timespecOffset facts "tv_nsec")
          ((err e) (err e))
          ((ok nsecOff)
           (ok (ty/ssaFunction "sysNanosleep" (list) (list (ty/ssaParam "sec" (ty/tyI64)) (ty/ssaParam "nanos" (ty/tyI64))) (ty/tyVal)
             (list
               (block "entry"
                 (list (int64Const "ts.size" tsSize) (callInstr "req" (ty/tyPtr) "malloc" (list "ts.size"))
                       (primInstr "req.isNull" (ty/tyI1) "rawPtrIsNull" (list "req")))
                 (ty/termBranch "req.isNull" (edgeTo "err0") (edgeTo "store")))
               (block "store"
                 (list (int64Const "ts.off0" secOff) (primInstr "st.sec" (ty/tyI1) "rawStoreI64" (list "req" "ts.off0" "sec"))
                       (int64Const "ts.off8" nsecOff) (primInstr "st.nsec" (ty/tyI1) "rawStoreI64" (list "req" "ts.off8" "nanos"))
                       (int64Const "rem.zero" 0) (primInstr "rem" (ty/tyPtr) "rawIntToPtr" (list "rem.zero"))
                       (callInstr "call.raw" (ty/tyI32) "nanosleep" (list "req" "rem"))
                       (primInstr "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))
                       (int64Const "call.zero" 0)
                       (primInstr "call.isErr" (ty/tyI1) "neInt" (list "call.n" "call.zero")))
                 (ty/termBranch "call.isErr" (edgeTo "err2") (edgeTo "ok")))
               (block "err0"
                 (list (callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list))
                       (boxInstr "errnoBox0" "errno0")
                       (constructResult "errv0" "err" "errnoBox0"))
                 (ty/termReturn "errv0"))
               (block "err2"
                 (listAppend (list (callInstr "errno2" (ty/tyI64) "sysErrnoValue" (list)))
                   (list (freeInstr "free.req2" "req")
                         (boxInstr "errnoBox2" "errno2")
                         (constructResult "errv2" "err" "errnoBox2")))
                 (ty/termReturn "errv2"))
               (block "ok"
                 (list (freeInstr "free.req3" "req")
                       (boxInstr "call.nb" "call.n")
                       (constructResult "okv" "ok" "call.nb"))
                 (ty/termReturn "okv")))))))))))

fn cstrFieldBlocks prefix: String basePtr: String fieldOffset: Int64 maxScan: Int64 errLabel: String okLabel: String -> (List ty/SsaBlock)
  (let [(allocLbl (str "cstr." prefix ".alloc")) (scanLbl (str "cstr." prefix ".scan")) (storeLbl (str "cstr." prefix ".store")) (doneLbl (str "cstr." prefix ".done"))
        (maxName (str "cstr." prefix ".max")) (bufName (str "cstr." prefix ".buf")) (bufNullName (str "cstr." prefix ".bufNull"))
        (zeroIdxName (str "cstr." prefix ".zeroIdx")) (oneName (str "cstr." prefix ".one")) (fieldOffName (str "cstr." prefix ".fieldOff"))
        (idxName (str "cstr." prefix ".idx")) (offName (str "cstr." prefix ".off")) (byteName (str "cstr." prefix ".byte"))
        (zeroByteName (str "cstr." prefix ".zeroByte")) (isZeroName (str "cstr." prefix ".isZero"))
        (storedName (str "cstr." prefix ".stored")) (idx1Name (str "cstr." prefix ".idx1")) (isMaxName (str "cstr." prefix ".isMax"))
        (lenName (str "cstr." prefix ".len")) (strName (str "cstr." prefix ".str")) (freedName (str "cstr." prefix ".freed"))]
    (list
      (block allocLbl
        (list (int64Const maxName maxScan) (callInstr bufName (ty/tyPtr) "malloc" (list maxName))
              (primInstr bufNullName (ty/tyI1) "rawPtrIsNull" (list bufName))
              (int64Const zeroIdxName 0) (int64Const oneName 1) (int64Const fieldOffName fieldOffset))
        (ty/termBranch bufNullName (edgeTo errLabel) (ty/ssaEdge scanLbl (list zeroIdxName))))
      (ty/ssaBlock scanLbl (list (ty/ssaParam idxName (ty/tyI64)))
        (list (primInstr offName (ty/tyI64) "addInt" (list fieldOffName idxName))
              (primInstr byteName (ty/tyI32) "rawLoadI8" (list basePtr offName))
              (int32Const zeroByteName 0)
              (primInstr isZeroName (ty/tyI1) "rawEqI32" (list byteName zeroByteName)))
        (ty/termBranch isZeroName (ty/ssaEdge doneLbl (list idxName)) (edgeTo storeLbl)))
      (block storeLbl
        (list (primInstr storedName (ty/tyI1) "rawStoreI8" (list bufName idxName byteName))
              (primInstr idx1Name (ty/tyI64) "addInt" (list idxName oneName))
              (primInstr isMaxName (ty/tyI1) "geInt" (list idx1Name maxName)))
        (ty/termBranch isMaxName (ty/ssaEdge doneLbl (list idx1Name)) (ty/ssaEdge scanLbl (list idx1Name))))
      (ty/ssaBlock doneLbl (list (ty/ssaParam lenName (ty/tyI64)))
        (list (callInstr strName (ty/tyVal) "mkStr" (list bufName lenName)) (freeInstr freedName bufName))
        (ty/termJump (ty/ssaEdge okLabel (list strName))))))

fn statExtern -> ty/SsaExtern
  (ty/ssaExternTyped "stat" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn lstatExtern -> ty/SsaExtern
  (ty/ssaExternTyped "lstat" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn statFamilyFn name: String externName: String facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (structOffset facts "stat" "st_mode")
    ((err e) (err e))
    ((ok modeOff)
     (mt (structOffset facts "stat" "st_size")
       ((err e) (err e))
       ((ok sizeOff)
        (mt (structOffset facts "stat" "st_mtimespec")
          ((err e) (err e))
          ((ok mtimespecOff)
           (mt (structOffset facts "timespec" "tv_sec")
             ((err e) (err e))
             ((ok tvSecOff)
           (mt (structOffset facts "timespec" "tv_nsec")
             ((err e) (err e))
             ((ok tvNsecOff)
           (mt (structByteSize facts "stat")
             ((err e) (err e))
             ((ok statSize)
              (mt (constOrErr facts "S_IFMT")
                ((err e) (err e))
                ((ok ifmt)
                 (ok (ty/ssaFunction name (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
                   (list
                     (block "entry"
                       (listAppend (stringToPtrInstrs "p" "path")
                         (list (int64Const "st.size" statSize) (callInstr "st" (ty/tyPtr) "malloc" (list "st.size"))
                               (primInstr "st.isNull" (ty/tyI1) "rawPtrIsNull" (list "st"))))
                       (ty/termBranch "st.isNull" (edgeTo "err0") (edgeTo "call")))
                     (block "call"
                       (list (callInstr "call.raw" (ty/tyI32) externName (list "p" "st"))
                             (primInstr "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))
                             (int64Const "call.zero" 0)
                             (primInstr "call.isErr" (ty/tyI1) "neInt" (list "call.n" "call.zero")))
                       (ty/termBranch "call.isErr" (edgeTo "err1") (edgeTo "ok")))
                     (block "err0"
                       (list (callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list))
                             (freeInstr "free.p0" "p")
                             (boxInstr "errnoBox0" "errno0")
                             (constructResult "errv0" "err" "errnoBox0"))
                       (ty/termReturn "errv0"))
                     (block "err1"
                       (listAppend (list (callInstr "errno1" (ty/tyI64) "sysErrnoValue" (list)))
                         (list (freeInstr "free.p1" "p") (freeInstr "free.st1" "st")
                               (boxInstr "errnoBox1" "errno1")
                               (constructResult "errv1" "err" "errnoBox1")))
                       (ty/termReturn "errv1"))
                     (block "ok"
                       (list
                         (int64Const "modeOffC" modeOff)
                         (primInstr "mode32" (ty/tyI32) "rawLoadI32" (list "st" "modeOffC"))
                         (int32Const "modeMask" 65535)
                         (primInstr "modeMasked" (ty/tyI32) "rawAndI32" (list "mode32" "modeMask"))
                         (primInstr "modeW" (ty/tyI64) "rawWidenI32" (list "modeMasked"))
                         (int32Const "ifmtMask" ifmt)
                         (primInstr "kind32" (ty/tyI32) "rawAndI32" (list "modeMasked" "ifmtMask"))
                         (primInstr "kindW" (ty/tyI64) "rawWidenI32" (list "kind32"))
                         (int64Const "sizeOffC" sizeOff)
                         (primInstr "sizeW" (ty/tyI64) "rawLoadI64" (list "st" "sizeOffC"))
                         (int64Const "mtimeSecOffC" (+ mtimespecOff tvSecOff))
                         (int64Const "mtimeNsecOffC" (+ mtimespecOff tvNsecOff))
                         (primInstr "mtimeW" (ty/tyI64) "rawLoadI64" (list "st" "mtimeSecOffC"))
                         (primInstr "nsecW" (ty/tyI64) "rawLoadI64" (list "st" "mtimeNsecOffC"))
                         (int64Const "billion" 1000000000)
                         (primInstr "mtimeNsSec" (ty/tyI64) "mulInt" (list "mtimeW" "billion"))
                         (primInstr "mtimeNs" (ty/tyI64) "addInt" (list "mtimeNsSec" "nsecW"))
                         (freeInstr "free.p2" "p") (freeInstr "free.st2" "st")
                         (boxInstr "sizeBox" "sizeW") (boxInstr "modeBox" "modeW")
                         (boxInstr "mtimeBox" "mtimeW") (boxInstr "kindBox" "kindW") (boxInstr "mtimeNsBox" "mtimeNs")
                         (listInstr "statRes" (list "sizeBox" "modeBox" "mtimeBox" "kindBox" "mtimeNsBox"))
                         (constructResult "okv" "ok" "statRes"))
                       (ty/termReturn "okv")))))))))))))))))))

fn sysStatFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (statFamilyFn "sysStat" "stat" facts)

fn sysLstatFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (statFamilyFn "sysLstat" "lstat" facts)

fn utimesExtern -> ty/SsaExtern
  (ty/ssaExternTyped "utimes" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))

fn sysUtimesFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (timevalSize facts)
    ((err e) (err e))
    ((ok tvSize)
     (mt (timevalOffset facts "tv_sec")
       ((err e) (err e))
       ((ok tvSecOff)
        (mt (timevalOffset facts "tv_usec")
          ((err e) (err e))
          ((ok tvUsecOff)
           (let [(mSecOff (+ tvSize tvSecOff)) (mUsecOff (+ tvSize tvUsecOff)) (bufSize (* 2 tvSize))]
             (ok (ty/ssaFunction "sysUtimes" (list)
               (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "aSec" (ty/tyI64)) (ty/ssaParam "aUsec" (ty/tyI64))
                     (ty/ssaParam "mSec" (ty/tyI64)) (ty/ssaParam "mUsec" (ty/tyI64)))
               (ty/tyVal)
               (list
                 (block "entry"
                   (listAppend (stringToPtrInstrs "p" "path")
                     (list (int64Const "buf.size" bufSize) (callInstr "buf" (ty/tyPtr) "malloc" (list "buf.size"))
                           (primInstr "buf.isNull" (ty/tyI1) "rawPtrIsNull" (list "buf"))))
                   (ty/termBranch "buf.isNull" (edgeTo "err0") (edgeTo "store")))
                 (block "store"
                   (list (int64Const "aSecOffC" tvSecOff) (primInstr "st.aSec" (ty/tyI1) "rawStoreI64" (list "buf" "aSecOffC" "aSec"))
                         (int64Const "aUsecOffC" tvUsecOff) (primInstr "st.aUsec" (ty/tyI1) "rawStoreI64" (list "buf" "aUsecOffC" "aUsec"))
                         (int64Const "mSecOffC" mSecOff) (primInstr "st.mSec" (ty/tyI1) "rawStoreI64" (list "buf" "mSecOffC" "mSec"))
                         (int64Const "mUsecOffC" mUsecOff) (primInstr "st.mUsec" (ty/tyI1) "rawStoreI64" (list "buf" "mUsecOffC" "mUsec"))
                         (callInstr "call.raw" (ty/tyI32) "utimes" (list "p" "buf"))
                         (primInstr "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))
                         (int64Const "call.zero" 0)
                         (primInstr "call.isErr" (ty/tyI1) "neInt" (list "call.n" "call.zero")))
                   (ty/termBranch "call.isErr" (edgeTo "err1") (edgeTo "ok")))
                 (block "err0"
                   (list (callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list))
                         (freeInstr "free.p0" "p")
                         (boxInstr "errnoBox0" "errno0")
                         (constructResult "errv0" "err" "errnoBox0"))
                   (ty/termReturn "errv0"))
                 (block "err1"
                   (listAppend (list (callInstr "errno1" (ty/tyI64) "sysErrnoValue" (list)))
                     (list (freeInstr "free.p1" "p") (freeInstr "free.buf1" "buf")
                           (boxInstr "errnoBox1" "errno1")
                           (constructResult "errv1" "err" "errnoBox1")))
                   (ty/termReturn "errv1"))
                 (block "ok"
                   (listAppend (list (freeInstr "free.p2" "p") (freeInstr "free.buf2" "buf"))
                     (listAppend (boxCallResult) (list (constructResult "okv" "ok" "call.nb"))))
                   (ty/termReturn "okv"))))))))))))

fn localtimeRExtern -> ty/SsaExtern
  (ty/ssaExternTyped "localtime_r" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyPtr))

fn sysLocaltimeFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (structByteSize facts "tm")
    ((err e) (err e))
    ((ok tmSize)
     (mt (structOffset facts "tm" "tm_sec")
       ((err e) (err e))
       ((ok secOff)
        (mt (structOffset facts "tm" "tm_min")
          ((err e) (err e))
          ((ok minOff)
           (mt (structOffset facts "tm" "tm_hour")
             ((err e) (err e))
             ((ok hourOff)
              (mt (structOffset facts "tm" "tm_mday")
                ((err e) (err e))
                ((ok mdayOff)
                 (mt (structOffset facts "tm" "tm_mon")
                   ((err e) (err e))
                   ((ok monOff)
                    (mt (structOffset facts "tm" "tm_year")
                      ((err e) (err e))
                      ((ok yearOff)
                       (mt (structOffset facts "tm" "tm_wday")
                         ((err e) (err e))
                         ((ok wdayOff)
                          (mt (structOffset facts "tm" "tm_yday")
                            ((err e) (err e))
                            ((ok ydayOff)
                             (mt (structOffset facts "tm" "tm_isdst")
                               ((err e) (err e))
                               ((ok isdstOff)
                                (ok (ty/ssaFunction "sysLocaltime" (list) (list (ty/ssaParam "epochSec" (ty/tyI64))) (ty/tyVal)
                                  (list
                                    (block "entry"
                                      (list (int64Const "time.size" 8) (callInstr "timeBuf" (ty/tyPtr) "malloc" (list "time.size"))
                                            (primInstr "timeBuf.isNull" (ty/tyI1) "rawPtrIsNull" (list "timeBuf")))
                                      (ty/termBranch "timeBuf.isNull" (edgeTo "err0") (edgeTo "storeTime")))
                                    (block "storeTime"
                                      (list (int64Const "time.off" 0) (primInstr "st.time" (ty/tyI1) "rawStoreI64" (list "timeBuf" "time.off" "epochSec"))
                                            (int64Const "tm.size" tmSize) (callInstr "tmBuf" (ty/tyPtr) "malloc" (list "tm.size"))
                                            (primInstr "tmBuf.isNull" (ty/tyI1) "rawPtrIsNull" (list "tmBuf")))
                                      (ty/termBranch "tmBuf.isNull" (edgeTo "err1") (edgeTo "call")))
                                    (block "call"
                                      (list (callInstr "tmRes" (ty/tyPtr) "localtime_r" (list "timeBuf" "tmBuf"))
                                            (primInstr "tmRes.isNull" (ty/tyI1) "rawPtrIsNull" (list "tmRes")))
                                      (ty/termBranch "tmRes.isNull" (edgeTo "err2") (edgeTo "ok")))
                                    (block "err0"
                                      (list (callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list))
                                            (boxInstr "errnoBox0" "errno0") (constructResult "errv0" "err" "errnoBox0"))
                                      (ty/termReturn "errv0"))
                                    (block "err1"
                                      (listAppend (list (callInstr "errno1" (ty/tyI64) "sysErrnoValue" (list)))
                                        (list (freeInstr "free.time1" "timeBuf") (boxInstr "errnoBox1" "errno1") (constructResult "errv1" "err" "errnoBox1")))
                                      (ty/termReturn "errv1"))
                                    (block "err2"
                                      (listAppend (list (callInstr "errno2" (ty/tyI64) "sysErrnoValue" (list)))
                                        (list (freeInstr "free.time2" "timeBuf") (freeInstr "free.tm2" "tmBuf")
                                              (boxInstr "errnoBox2" "errno2") (constructResult "errv2" "err" "errnoBox2")))
                                      (ty/termReturn "errv2"))
                                    (block "ok"
                                      (listAppend
                                        (listAppend
                                          (list (int64Const "secOffC" secOff) (primInstr "secI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "secOffC")) (primInstr "secW" (ty/tyI64) "rawWidenI32" (list "secI"))
                                                (int64Const "minOffC" minOff) (primInstr "minI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "minOffC")) (primInstr "minW" (ty/tyI64) "rawWidenI32" (list "minI"))
                                                (int64Const "hourOffC" hourOff) (primInstr "hourI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "hourOffC")) (primInstr "hourW" (ty/tyI64) "rawWidenI32" (list "hourI"))
                                                (int64Const "mdayOffC" mdayOff) (primInstr "mdayI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "mdayOffC")) (primInstr "mdayW" (ty/tyI64) "rawWidenI32" (list "mdayI"))
                                                (int64Const "monOffC" monOff) (primInstr "monI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "monOffC")) (primInstr "monW" (ty/tyI64) "rawWidenI32" (list "monI")))
                                          (list (int64Const "yearOffC" yearOff) (primInstr "yearI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "yearOffC")) (primInstr "yearW" (ty/tyI64) "rawWidenI32" (list "yearI"))
                                                (int64Const "wdayOffC" wdayOff) (primInstr "wdayI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "wdayOffC")) (primInstr "wdayW" (ty/tyI64) "rawWidenI32" (list "wdayI"))
                                                (int64Const "ydayOffC" ydayOff) (primInstr "ydayI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "ydayOffC")) (primInstr "ydayW" (ty/tyI64) "rawWidenI32" (list "ydayI"))
                                                (int64Const "isdstOffC" isdstOff) (primInstr "isdstI" (ty/tyI32) "rawLoadI32" (list "tmBuf" "isdstOffC")) (primInstr "isdstW" (ty/tyI64) "rawWidenI32" (list "isdstI"))))
                                        (list
                                          (boxInstr "secBox" "secW") (boxInstr "minBox" "minW") (boxInstr "hourBox" "hourW") (boxInstr "mdayBox" "mdayW") (boxInstr "monBox" "monW")
                                          (boxInstr "yearBox" "yearW") (boxInstr "wdayBox" "wdayW") (boxInstr "ydayBox" "ydayW") (boxInstr "isdstBox" "isdstW")
                                          (freeInstr "free.time3" "timeBuf") (freeInstr "free.tm3" "tmBuf")
                                          (listInstr "tmListRes" (list "secBox" "minBox" "hourBox" "mdayBox" "monBox" "yearBox" "wdayBox" "ydayBox" "isdstBox"))
                                          (constructResult "okv" "ok" "tmListRes")))
                                      (ty/termReturn "okv")))))))))))))))))))))))))

fn getrusageExtern -> ty/SsaExtern
  (ty/ssaExternTyped "getrusage" (list (ty/tyI32) (ty/tyPtr)) (ty/tyI32))

fn sysGetrusageFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (structByteSize facts "rusage")
    ((err e) (err e))
    ((ok ruSize)
     (mt (structOffset facts "rusage" "ru_utime")
       ((err e) (err e))
       ((ok ruUtimeOff)
        (mt (structOffset facts "rusage" "ru_stime")
          ((err e) (err e))
          ((ok ruStimeOff)
           (mt (structOffset facts "rusage" "ru_maxrss")
             ((err e) (err e))
             ((ok ruMaxrssOff)
              (mt (timevalOffset facts "tv_sec")
                ((err e) (err e))
                ((ok tvSecOff)
                 (mt (timevalOffset facts "tv_usec")
                   ((err e) (err e))
                   ((ok tvUsecOff)
                    (mt (constOrErr facts "RUSAGE_SELF")
                      ((err e) (err e))
                      ((ok rusageSelf)
                       (let [(unit (libc/rusageMaxRssUnit facts.triple))
                             (userSecOff (+ ruUtimeOff tvSecOff)) (userUsecOff (+ ruUtimeOff tvUsecOff))
                             (sysSecOff (+ ruStimeOff tvSecOff)) (sysUsecOff (+ ruStimeOff tvUsecOff))]
                         (ok (ty/ssaFunction "sysGetrusage" (list) (list) (ty/tyVal)
                           (list
                             (block "entry"
                               (list (int64Const "ru.size" ruSize) (callInstr "ru" (ty/tyPtr) "malloc" (list "ru.size"))
                                     (primInstr "ru.isNull" (ty/tyI1) "rawPtrIsNull" (list "ru")))
                               (ty/termBranch "ru.isNull" (edgeTo "err0") (edgeTo "call")))
                             (block "call"
                               (list (int32Const "who" rusageSelf) (callInstr "call.raw" (ty/tyI32) "getrusage" (list "who" "ru"))
                                     (primInstr "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))
                                     (int64Const "call.zero" 0) (primInstr "call.isErr" (ty/tyI1) "neInt" (list "call.n" "call.zero")))
                               (ty/termBranch "call.isErr" (edgeTo "err1") (edgeTo "ok")))
                             (block "err0"
                               (list (callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list)) (boxInstr "errnoBox0" "errno0") (constructResult "errv0" "err" "errnoBox0"))
                               (ty/termReturn "errv0"))
                             (block "err1"
                               (listAppend (list (callInstr "errno1" (ty/tyI64) "sysErrnoValue" (list)))
                                 (list (freeInstr "free.ru1" "ru") (boxInstr "errnoBox1" "errno1") (constructResult "errv1" "err" "errnoBox1")))
                               (ty/termReturn "errv1"))
                             (block "ok"
                               (list
                                 (int64Const "maxrssOffC" ruMaxrssOff) (primInstr "maxrssRaw" (ty/tyI64) "rawLoadI64" (list "ru" "maxrssOffC"))
                                 (int64Const "rssUnitC" unit) (primInstr "maxrssDiv" (ty/tyI64) "divIntHost" (list "maxrssRaw" "rssUnitC"))
                                 (int64Const "userSecOffC" userSecOff) (primInstr "userSec" (ty/tyI64) "rawLoadI64" (list "ru" "userSecOffC"))
                                 (int64Const "userUsecOffC" userUsecOff) (primInstr "userUsec32" (ty/tyI32) "rawLoadI32" (list "ru" "userUsecOffC"))
                                 (primInstr "userUsec" (ty/tyI64) "rawWidenI32" (list "userUsec32"))
                                 (int64Const "million1" 1000000) (primInstr "userSecUs" (ty/tyI64) "mulInt" (list "userSec" "million1"))
                                 (primInstr "userUs" (ty/tyI64) "addInt" (list "userSecUs" "userUsec"))
                                 (int64Const "sysSecOffC" sysSecOff) (primInstr "sysSec" (ty/tyI64) "rawLoadI64" (list "ru" "sysSecOffC"))
                                 (int64Const "sysUsecOffC" sysUsecOff) (primInstr "sysUsec32" (ty/tyI32) "rawLoadI32" (list "ru" "sysUsecOffC"))
                                 (primInstr "sysUsec" (ty/tyI64) "rawWidenI32" (list "sysUsec32"))
                                 (int64Const "million2" 1000000) (primInstr "sysSecUs" (ty/tyI64) "mulInt" (list "sysSec" "million2"))
                                 (primInstr "sysUs" (ty/tyI64) "addInt" (list "sysSecUs" "sysUsec"))
                                 (freeInstr "free.ru2" "ru")
                                 (boxInstr "maxrssBox" "maxrssDiv") (boxInstr "userUsBox" "userUs") (boxInstr "sysUsBox" "sysUs")
                                 (listInstr "ruListRes" (list "maxrssBox" "userUsBox" "sysUsBox"))
                                 (constructResult "okv" "ok" "ruListRes"))
                               (ty/termReturn "okv"))))))))))))))))))))

fn unameExtern -> ty/SsaExtern
  (ty/ssaExternTyped "uname" (list (ty/tyPtr)) (ty/tyI32))

fn sysUnameFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (structByteSize facts "utsname")
    ((err e) (err e))
    ((ok unSize)
     (mt (structOffset facts "utsname" "sysname")
       ((err e) (err e))
       ((ok sysnameOff)
        (mt (structOffset facts "utsname" "machine")
          ((err e) (err e))
          ((ok machineOff)
           (let [(sysnameMax (- unSize sysnameOff)) (machineMax (- unSize machineOff))]
             (ok (ty/ssaFunction "sysUname" (list) (list) (ty/tyVal)
               (listAppend
                 (list
                   (block "entry"
                     (list (int64Const "un.size" unSize) (callInstr "un" (ty/tyPtr) "malloc" (list "un.size"))
                           (primInstr "un.isNull" (ty/tyI1) "rawPtrIsNull" (list "un")))
                     (ty/termBranch "un.isNull" (edgeTo "err0") (edgeTo "call")))
                   (block "call"
                     (list (callInstr "call.raw" (ty/tyI32) "uname" (list "un"))
                           (primInstr "call.n" (ty/tyI64) "rawWidenI32" (list "call.raw"))
                           (int64Const "call.zero" 0) (primInstr "call.isErr" (ty/tyI1) "neInt" (list "call.n" "call.zero")))
                     (ty/termBranch "call.isErr" (edgeTo "err1") (edgeTo "cstr.sysname.alloc")))
                   (block "err0"
                     (list (callInstr "errno0" (ty/tyI64) "sysErrnoValue" (list)) (boxInstr "errnoBox0" "errno0") (constructResult "errv0" "err" "errnoBox0"))
                     (ty/termReturn "errv0"))
                   (block "err1"
                     (listAppend (list (callInstr "errno1" (ty/tyI64) "sysErrnoValue" (list)))
                       (list (freeInstr "free.un1" "un") (boxInstr "errnoBox1" "errno1") (constructResult "errv1" "err" "errnoBox1")))
                     (ty/termReturn "errv1")))
                 (listAppend (cstrFieldBlocks "sysname" "un" sysnameOff sysnameMax "err1" "uname.gotSysname")
                   (listAppend
                     (list (ty/ssaBlock "uname.gotSysname" (list (ty/ssaParam "sysnameStr" (ty/tyVal)))
                             (list) (ty/termJump (ty/ssaEdge "cstr.machine.alloc" (list)))))
                     (listAppend (cstrFieldBlocks "machine" "un" machineOff machineMax "err1" "uname.gotMachine")
                       (list (ty/ssaBlock "uname.gotMachine" (list (ty/ssaParam "machineStr" (ty/tyVal)))
                               (list (freeInstr "free.un2" "un") (listInstr "unRes" (list "sysnameStr" "machineStr")) (constructResult "okv" "ok" "unRes"))
                               (ty/termReturn "okv"))))))))))))))))

fn opendirExtern -> ty/SsaExtern
  (ty/ssaExternTyped "opendir" (list (ty/tyPtr)) (ty/tyPtr))

fn readdirExtern -> ty/SsaExtern
  (ty/ssaExternTyped "readdir" (list (ty/tyPtr)) (ty/tyPtr))

fn closedirExtern -> ty/SsaExtern
  (ty/ssaExternTyped "closedir" (list (ty/tyPtr)) (ty/tyI32))

fn sysDirListFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (structByteSize facts "dirent")
    ((err e) (err e))
    ((ok direntSize)
     (mt (structOffset facts "dirent" "d_name")
       ((err e) (err e))
       ((ok dNameOff)
        (let [(dNameMax (- direntSize dNameOff)) (errAcc facts.errnoAccessor)]
          (ok (ty/ssaFunction "sysDirList" (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
            (listAppend
              (list
                (block "entry"
                  (listAppend (stringToPtrInstrs "p" "path")
                    (list (callInstr "dirp" (ty/tyPtr) "opendir" (list "p"))
                          (primInstr "dirp.isNull" (ty/tyI1) "rawPtrIsNull" (list "dirp"))
                          (listInstr "nilAcc" (list))))
                  (ty/termBranch "dirp.isNull" (edgeTo "err0") (ty/ssaEdge "loop" (list "nilAcc"))))
                (ty/ssaBlock "loop" (list (ty/ssaParam "acc" (ty/tyVal)))
                  (list (callInstr "errp" (ty/tyPtr) errAcc (list))
                        (int64Const "errp.off" 0) (int32Const "errp.zero" 0)
                        (primInstr "errp.reset" (ty/tyI1) "rawStoreI32" (list "errp" "errp.off" "errp.zero"))
                        (callInstr "ent" (ty/tyPtr) "readdir" (list "dirp"))
                        (primInstr "ent.isNull" (ty/tyI1) "rawPtrIsNull" (list "ent")))
                  (ty/termBranch "ent.isNull" (edgeTo "endCheck") (edgeTo "haveEntry")))
                (block "haveEntry"
                  (list (int64Const "dNameOff0" dNameOff) (primInstr "b0" (ty/tyI32) "rawLoadI8" (list "ent" "dNameOff0"))
                        (int64Const "dNameOff1" (+ dNameOff 1)) (primInstr "b1" (ty/tyI32) "rawLoadI8" (list "ent" "dNameOff1"))
                        (int64Const "dNameOff2" (+ dNameOff 2)) (primInstr "b2" (ty/tyI32) "rawLoadI8" (list "ent" "dNameOff2"))
                        (int32Const "dotC" 46) (int32Const "zeroC32" 0)
                        (primInstr "b0IsDot" (ty/tyI1) "rawEqI32" (list "b0" "dotC"))
                        (primInstr "b1IsZero" (ty/tyI1) "rawEqI32" (list "b1" "zeroC32"))
                        (primInstr "isDot" (ty/tyI1) "andBool" (list "b0IsDot" "b1IsZero"))
                        (primInstr "b1IsDot" (ty/tyI1) "rawEqI32" (list "b1" "dotC"))
                        (primInstr "b2IsZero" (ty/tyI1) "rawEqI32" (list "b2" "zeroC32"))
                        (primInstr "dotDotTail" (ty/tyI1) "andBool" (list "b1IsDot" "b2IsZero"))
                        (primInstr "isDotDot" (ty/tyI1) "andBool" (list "b0IsDot" "dotDotTail"))
                        (primInstr "skip" (ty/tyI1) "orBool" (list "isDot" "isDotDot")))
                  (ty/termBranch "skip" (edgeTo "skipEntry") (edgeTo "cstr.dname.alloc")))
                (block "skipEntry" (list) (ty/termJump (ty/ssaEdge "loop" (list "acc"))))
                (block "endCheck"
                  (list (callInstr "errnoAfter" (ty/tyI64) "sysErrnoValue" (list))
                        (callInstr "close.raw" (ty/tyI32) "closedir" (list "dirp"))
                        (primInstr "close.n" (ty/tyI64) "rawWidenI32" (list "close.raw"))
                        (int64Const "close.zero" 0) (primInstr "close.isErr" (ty/tyI1) "neInt" (list "close.n" "close.zero")))
                  (ty/termBranch "close.isErr" (edgeTo "closeErr") (edgeTo "checkReaddirEnd")))
                (block "closeErr"
                  (list (callInstr "errnoClose" (ty/tyI64) "sysErrnoValue" (list)) (freeInstr "free.p.ce" "p")
                        (boxInstr "errnoCloseBox" "errnoClose") (constructResult "errvCE" "err" "errnoCloseBox"))
                  (ty/termReturn "errvCE"))
                (block "checkReaddirEnd"
                  (list (int64Const "rdZero" 0) (primInstr "rdIsZero" (ty/tyI1) "eqInt" (list "errnoAfter" "rdZero")))
                  (ty/termBranch "rdIsZero" (edgeTo "allOk") (edgeTo "readdirErr")))
                (block "allOk"
                  (list (freeInstr "free.p.ok" "p") (constructResult "okv" "ok" "acc"))
                  (ty/termReturn "okv"))
                (block "readdirErr"
                  (list (freeInstr "free.p.re" "p") (boxInstr "errnoRdBox" "errnoAfter") (constructResult "errvRD" "err" "errnoRdBox"))
                  (ty/termReturn "errvRD"))
                (block "err0"
                  (list (callInstr "errnoOD" (ty/tyI64) "sysErrnoValue" (list)) (freeInstr "free.p.od" "p")
                        (boxInstr "errnoODBox" "errnoOD") (constructResult "errvOD" "err" "errnoODBox"))
                  (ty/termReturn "errvOD"))
                (block "allocErr"
                  (list (callInstr "errnoAE" (ty/tyI64) "sysErrnoValue" (list))
                        (callInstr "closeAE.raw" (ty/tyI32) "closedir" (list "dirp"))
                        (primInstr "closeAE.n" (ty/tyI64) "rawWidenI32" (list "closeAE.raw"))
                        (int64Const "closeAE.zero" 0) (primInstr "closeAE.isErr" (ty/tyI1) "neInt" (list "closeAE.n" "closeAE.zero")))
                  (ty/termBranch "closeAE.isErr" (edgeTo "allocErrCloseFailed") (edgeTo "allocErrReport")))
                (block "allocErrCloseFailed"
                  (list (callInstr "errnoAEC" (ty/tyI64) "sysErrnoValue" (list)) (freeInstr "free.p.aec" "p")
                        (boxInstr "b.aec" "errnoAEC") (constructResult "e.aec" "err" "b.aec"))
                  (ty/termReturn "e.aec"))
                (block "allocErrReport"
                  (list (freeInstr "free.p.aer" "p") (boxInstr "b.aer" "errnoAE") (constructResult "e.aer" "err" "b.aer"))
                  (ty/termReturn "e.aer")))
              (listAppend (cstrFieldBlocks "dname" "ent" dNameOff dNameMax "allocErr" "gotName")
                (list (ty/ssaBlock "gotName" (list (ty/ssaParam "nameStr" (ty/tyVal)))
                        (list (entryInstr "acc2" (ty/tyVal) "cons" (list "nameStr" "acc")))
                        (ty/termJump (ty/ssaEdge "loop" (list "acc2"))))))))))))))

fn sysExterns facts: libc/TripleFacts -> (List ty/SsaExtern)
  (listAppend (sysCommonExterns facts)
    (listAppend (list (getpidExtern) (readExtern) (writeExtern) (closeExtern) (preadExtern) (pwriteExtern)
          (killExtern) (fsyncExtern) (flockExtern) (renameExtern) (chmodExtern) (mkdirExtern)
          (unlinkExtern) (rmdirExtern) (symlinkExtern) (readlinkExtern) (sysconfExtern)
          (clockGettimeExtern) (usleepExtern) (strlenExtern) (getenvExtern) (fcntlExtern)
          (pollExtern) (nanosleepExtern)
          (statExtern) (lstatExtern) (utimesExtern) (localtimeRExtern) (getrusageExtern) (unameExtern)
          (opendirExtern) (readdirExtern) (closedirExtern) (realpathExtern))
      (exePathExterns facts)))

fn sysFunctions facts: libc/TripleFacts -> (Result (List ty/SsaFunction) String)
  (mt (sysClockGettimeFn facts)
    ((err e) (err e))
    ((ok clockGettimeFn)
     (mt (sysPollFn facts)
       ((err e) (err e))
       ((ok pollFn)
        (mt (sysNanosleepFn facts)
          ((err e) (err e))
          ((ok nanosleepFn)
           (mt (sysStatFn facts)
             ((err e) (err e))
             ((ok statFn)
              (mt (sysLstatFn facts)
                ((err e) (err e))
                ((ok lstatFn)
                 (mt (sysUtimesFn facts)
                   ((err e) (err e))
                   ((ok utimesFn)
                    (mt (sysLocaltimeFn facts)
                      ((err e) (err e))
                      ((ok localtimeFn)
                       (mt (sysGetrusageFn facts)
                         ((err e) (err e))
                         ((ok getrusageFn)
                          (mt (sysUnameFn facts)
                            ((err e) (err e))
                            ((ok unameFn)
                             (mt (sysDirListFn facts)
                               ((err e) (err e))
                               ((ok dirListFn)
                                (mt (sysExePathFn facts)
                                 ((err e) (err e))
                                 ((ok exePathFn)
                                (ok (list (sysErrnoValueFn facts) (sysGetpidFn) (sysReadFn) (sysWriteFn) (sysCloseFn)
                                      (sysPreadFn) (sysPwriteFn) (sysKillFn) (sysFsyncFn) (sysFlockFn) (sysRenameFn)
                                      (sysChmodFn) (sysMkdirFn) (sysUnlinkFn) (sysRmdirFn) (sysSymlinkFn) (sysReadlinkFn)
                                      (sysSysconfFn) clockGettimeFn (sysUsleepFn) (sysGetenvFn) (sysFcntlGetFn)
                                      (sysFcntlSetFn) pollFn nanosleepFn
                                      statFn lstatFn utimesFn localtimeFn getrusageFn unameFn dirListFn (sysRealpathFn) exePathFn))))))))))))))))))))))))

fn fileRouteBuiltins -> (List String)
  (listAppend (list "fileLock" "fileLockWait" "fileAppend" "fileLockAt" "fileReadAt" "fileWriteAt")
    (list "fileReadBytes" "fileReadString" "realPath" "fileWrite" "dirList" "fileStat" "fileReadRange" "envGet" "getHomeDir" "fileCreateExclusive" "dirCreate" "pathRemove" "pathRename" "fileChmod" "fileFsync" "fileReadlink" "fileLstat" "pathSymlink" "fileUtime"))

fn openExtern -> ty/SsaExtern
  (ty/ssaExternVariadic "open" (list (ty/tyPtr) (ty/tyI32)) (ty/tyI32))

fn openatExtern -> ty/SsaExtern
  (ty/ssaExternVariadic "openat" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))

fn fileRouteExterns facts: libc/TripleFacts -> (List ty/SsaExtern)
  (list (openExtern) (openatExtern)
        (ty/ssaExternTyped "fstatat" (list (ty/tyI32) (ty/tyPtr) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))
        (ty/ssaExternTyped "fstat" (list (ty/tyI32) (ty/tyPtr)) (ty/tyI32))
        (ty/ssaExternTyped "fchmod" (list (ty/tyI32) (ty/tyI32)) (ty/tyI32))
        (ty/ssaExternTyped "unlinkat" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))
        (ty/ssaExternTyped "renameat" (list (ty/tyI32) (ty/tyPtr) (ty/tyI32) (ty/tyPtr)) (ty/tyI32))
        (ty/ssaExternTyped "realloc" (list (ty/tyPtr) (ty/tyI64)) (ty/tyPtr))
        (ty/ssaExternTyped "strchr" (list (ty/tyPtr) (ty/tyI32)) (ty/tyPtr))
        (ty/ssaExternTyped "strerror" (list (ty/tyI32)) (ty/tyPtr))
        (ty/ssaExternTyped "strcmp" (list (ty/tyPtr) (ty/tyPtr)) (ty/tyI32))
        (ty/ssaExternTyped "utimensat" (list (ty/tyI32) (ty/tyPtr) (ty/tyPtr) (ty/tyI32)) (ty/tyI32))
        (ty/ssaExternTyped "lseek" (list (ty/tyI32) (ty/tyI64) (ty/tyI32)) (ty/tyI64))
        (ty/ssaExternTyped "getuid" (list) (ty/tyI32))
        (ty/ssaExternTyped "getpwuid" (list (ty/tyI32)) (ty/tyPtr)))

fn fileRouteStrings -> (List String)
  (list "io:22" "io:12" "io:36" "io:17" "busy" "ERR_PATH_TYPE" "ERR_PATH_SYMLINK" "ERR_TIMEOUT" ".asl-write-" "-" "" "/"
        "notFound" "permissionDenied" "alreadyExists" "invalidPath" "interrupted" "other" ": "
        "fileReadBytes" "fileReadString" "realPath" "fileWrite" "dirList" "fileStat" "fileReadRange" "getHomeDir" "fileCreateExclusive"
        "dirCreate" "pathRemove" "pathRename" "fileChmod" "fileFsync" "fileReadlink" "fileLstat" "pathSymlink" "fileUtime"
        "invalid argument" "out of memory" "negative offset" "negative length" "lengthLimitExceeded" "length exceeds 1 GiB cap"
        "nonSeekable" "positive offset on non-seekable file" "cannot determine home directory" "HOME"
        "ERR_TYPE" "fileReadBytes expects String, got " "fileReadString expects String, got " "realPath expects String, got "
        "fileWrite expects String, got " "dirList expects String, got " "fileStat expects String, got "
        "fileWrite expects String or Bytes content, got "
        "Unit" "Bool" "Int" "Float" "Keyword" "String" "List" "Record" "Variant" "Fn" "Bytes" "?")

fn fileW name: String -> String
  (str "asl-target-llvm/sysRoute." name)

fn fileRouteGlobals -> (List ty/SsaGlobal)
  (list (ty/ssaGlobal (fileW "fileTempSeq") (fileW "fileTempSeqInit")))

fn fileRouteRecords -> (List ty/SsaRecordDecl)
  (list (ty/ssaRecordDecl "FileStat" (list "isFile" "isDir" "size" "mtime" "mode" "mtimeNs"))
        (ty/ssaRecordDecl "LinkStat" (list "isFile" "isDir" "isSymlink" "size" "mtime" "mode" "mtimeNs")))

fn fileSlurpFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileSlurp") (list) (list (ty/ssaParam "fd" (ty/tyI32))) (ty/tyVal)
    (list
      (block "entry" (list (int64Const "initialCap" 4096)
                            (callInstr "initialBuf" (ty/tyPtr) "malloc" (list "initialCap"))
                            (primInstr "initialNull" (ty/tyI1) "rawPtrIsNull" (list "initialBuf")))
        (fileBr "initialNull" "allocErr" "loopStart"))
      (fileRet "allocErr" (list (callInstr "allocErrno" (ty/tyI64) "sysErrnoValue" (list))
                                  (boxInstr "allocErrBox" "allocErrno")
                                  (constructResult "allocErrValue" "err" "allocErrBox")) "allocErrValue")
      (block "loopStart" (list (primInstr "initialAt" (ty/tyI64) "rawPtrToInt" (list "initialBuf"))
                                (int64Const "zero" 0))
        (fileJump "loop" (list "initialAt" "initialCap" "zero")))
      (ty/ssaBlock "loop" (list (ty/ssaParam "bufAt" (ty/tyI64)) (ty/ssaParam "cap" (ty/tyI64)) (ty/ssaParam "len" (ty/tyI64)))
        (list (primInstr "buf" (ty/tyPtr) "rawIntToPtr" (list "bufAt"))
              (fileEq "full" "len" "cap"))
        (fileBr "full" "grow" "rd"))
      (block "grow" (list (int64Const "halfMax" 4611686018427387903)
                            (primInstr "tooBig" (ty/tyI1) "gtInt" (list "cap" "halfMax")))
        (fileBr "tooBig" "sizeErr" "regrow"))
      (fileRet "sizeErr" (list (freeInstr "sizeErrFree" "buf")
                                 (int64Const "enomem" (fileK k "ENOMEM")) (boxInstr "sizeErrBox" "enomem")
                                 (constructResult "sizeErrValue" "err" "sizeErrBox")) "sizeErrValue")
      (block "regrow" (list (int64Const "two" 2) (primInstr "nextCap" (ty/tyI64) "mulInt" (list "cap" "two"))
                              (callInstr "grown" (ty/tyPtr) "realloc" (list "buf" "nextCap"))
                              (primInstr "grownNull" (ty/tyI1) "rawPtrIsNull" (list "grown")))
        (fileBr "grownNull" "reallocErr" "regrown"))
      (fileRet "reallocErr" (list (callInstr "reallocErrno" (ty/tyI64) "sysErrnoValue" (list))
                                    (freeInstr "reallocErrFree" "buf")
                                    (boxInstr "reallocErrBox" "reallocErrno")
                                    (constructResult "reallocErrValue" "err" "reallocErrBox")) "reallocErrValue")
      (block "regrown" (list (primInstr "grownAt" (ty/tyI64) "rawPtrToInt" (list "grown")))
        (fileJump "loop" (list "grownAt" "nextCap" "len")))
      (block "rd" (list (primInstr "atI" (ty/tyI64) "rawAddI64" (list "bufAt" "len"))
                         (primInstr "at" (ty/tyPtr) "rawIntToPtr" (list "atI"))
                         (primInstr "room" (ty/tyI64) "subInt" (list "cap" "len"))
                         (callInstr "got" (ty/tyI64) "read" (list "fd" "at" "room"))
                         (primInstr "gotNeg" (ty/tyI1) "ltInt" (list "got" "zero")))
        (fileBr "gotNeg" "rdErr" "rdSome"))
      (block "rdErr" (list (callInstr "readErrno" (ty/tyI64) "sysErrnoValue" (list))
                            (int64Const "eintr" (fileK k "EINTR"))
                            (fileEq "isEintr" "readErrno" "eintr"))
        (ty/termBranch "isEintr" (ty/ssaEdge "loop" (list "bufAt" "cap" "len")) (edgeTo "done")))
      (block "rdSome" (list (fileEq "eof" "got" "zero")) (fileBr "eof" "done" "advance"))
      (block "advance" (list (primInstr "lenNext" (ty/tyI64) "addInt" (list "len" "got")))
        (fileJump "loop" (list "bufAt" "cap" "lenNext")))
      (fileRet "done" (list (callInstr "text" (ty/tyVal) "mkStr" (list "buf" "len"))
                              (freeInstr "doneFree" "buf")
                              (constructResult "doneValue" "ok" "text")) "doneValue")))

fn fileFactNames -> (List String)
  (list "O_RDONLY" "O_WRONLY" "O_RDWR" "O_CREAT" "O_EXCL" "O_TRUNC" "O_APPEND" "O_CLOEXEC" "O_NOFOLLOW" "O_DIRECTORY" "O_NONBLOCK"
        "LOCK_SH" "LOCK_EX" "LOCK_NB" "EWOULDBLOCK" "EAGAIN" "EBUSY" "EINTR" "EEXIST" "ELOOP" "ENOTDIR" "EINVAL" "ENAMETOOLONG" "ENOSPC"
        "ENOENT" "EACCES" "EPERM" "EROFS" "ENOTEMPTY" "EISDIR" "ENOMEM" "ESPIPE" "SEEK_SET" "SEEK_CUR"
        "AT_SYMLINK_NOFOLLOW" "AT_FDCWD" "NAME_MAX" "PATH_MAX" "S_IFMT" "S_IFREG" "S_IFDIR" "S_IFLNK" "CLOCK_MONOTONIC"
        "stat.size" "stat.st_mode" "stat.st_size" "timespec.size" "timespec.tv_sec" "timespec.tv_nsec" "passwd.pw_dir")

fn fileFacts facts: libc/TripleFacts -> (Result (Map String Int64) String)
  (fold (fn [(acc (Result (Map String Int64) String)) (n String)] -> (Result (Map String Int64) String)
          (mt acc
            ((err e) (err e))
            ((ok m)
              (let [(parts (stringSplit n "."))
                    (sname (optionOr (listGet parts 0) ""))
                    (field (optionOr (listGet parts 1) ""))
                    (v (cond ((< (listLength parts) 2) (constOrErr facts n))
                             ((= field "size") (structByteSize facts sname))
                             (else (structOffset facts sname field))))]
                (mt v
                  ((err e) (err e))
                  ((ok x) (ok (mapSet m n x))))))))
        (ok (mapEmpty)) (fileFactNames))

fn fileK k: (Map String Int64) name: String -> Int64
  (optionOr (mapGet k name) 0)

fn fileCall dest: String t: ty/SsaTy name: String args: (List String) -> ty/SsaInstr
  (callInstr dest t (fileW name) args)

fn fileVal dest: String op: ty/SsaOp -> ty/SsaInstr
  (ty/ssaInstr dest (ty/tyVal) op)

fn filePool pool: (Map String Int64) dest: String text: String -> ty/SsaInstr
  (fileVal dest (ty/opConst (ty/constStr (optionOr (mapGet pool text) -1))))

fn fileBr c: String yes: String no: String -> ty/SsaTerm
  (ty/termBranch c (edgeTo yes) (edgeTo no))

fn fileJump label: String args: (List String) -> ty/SsaTerm
  (ty/termJump (ty/ssaEdge label args))

fn fileOptSwitch v: String someLabel: String noneLabel: String -> ty/SsaTerm
  (ty/termSwitch v "Option" (list (ty/ssaCase "some" (edgeTo someLabel)) (ty/ssaCase "none" (edgeTo noneLabel))) (none))

fn fileResSwitch v: String okLabel: String errLabel: String -> ty/SsaTerm
  (ty/termSwitch v "Result" (list (ty/ssaCase "ok" (edgeTo okLabel)) (ty/ssaCase "err" (edgeTo errLabel))) (none))

fn fileRet label: String instrs: (List ty/SsaInstr) v: String -> ty/SsaBlock
  (block label instrs (ty/termReturn v))

fn fileErrVal pool: (Map String Int64) dest: String text: String -> (List ty/SsaInstr)
  (list (filePool pool (str dest ".text") text) (constructResult dest "err" (str dest ".text")))

fn fileErrTextBlock pool: (Map String Int64) label: String text: String -> ty/SsaBlock
  (fileRet label (fileErrVal pool (str label ".v") text) (str label ".v"))

fn fileErrTextJump pool: (Map String Int64) label: String text: String target: String -> ty/SsaBlock
  (block label (fileErrVal pool (str label ".v") text) (fileJump target (list (str label ".v"))))

fn fileEq dest: String a: String b: String -> ty/SsaInstr
  (primInstr dest (ty/tyI1) "eqInt" (list a b))

fn fileWiden dest: String v: String -> ty/SsaInstr
  (primInstr dest (ty/tyI64) "rawWidenI32" (list v))

fn fileNarrow dest: String v: String -> ty/SsaInstr
  (primInstr dest (ty/tyI32) "rawNarrowI32" (list v))

fn fileErrno dest: String -> ty/SsaInstr
  (callInstr dest (ty/tyI64) "sysErrnoValue" (list))

fn fileClose dest: String fd32: String -> ty/SsaInstr
  (callInstr dest (ty/tyI32) "close" (list fd32))

fn fileCStr dest: String v: String -> (List ty/SsaInstr)
  (stringToPtrInstrs dest v)

fn fileOr dest: String k: (Map String Int64) names: (List String) -> (List ty/SsaInstr)
  (let [(n (listLength names))
        (cname (fn [(i Int64)] -> String (str dest ".c" i)))
        (oname (fn [(i Int64)] -> String (if (= i 0) (cname 0) (str dest ".o" i))))
        (consts (map (fn [(i Int64)] -> ty/SsaInstr (int64Const (cname i) (fileK k (optionOr (listGet names i) "")))) (range 0 n)))
        (ors (map (fn [(i Int64)] -> ty/SsaInstr (primInstr (oname i) (ty/tyI64) "rawOrI64" (list (oname (- i 1)) (cname i)))) (range 1 n)))]
    (listAppend consts (listAppend ors (list (primInstr dest (ty/tyI32) "rawNarrowI32" (list (oname (- n 1))))))))

fn fileOpInstrs prefix: String k: (Map String Int64) flag: String nb: Bool -> (List ty/SsaInstr)
  (let [(base (list (int64Const (str prefix ".sh") (fileK k "LOCK_SH"))
                    (int64Const (str prefix ".diff") (- (fileK k "LOCK_EX") (fileK k "LOCK_SH")))
                    (primInstr (str prefix ".scaled") (ty/tyI64) "rawMulI64" (list flag (str prefix ".diff")))
                    (primInstr (str prefix ".op") (ty/tyI64) "rawAddI64" (list (str prefix ".sh") (str prefix ".scaled")))))
        (withNb (if nb
                  (list (int64Const (str prefix ".nb") (fileK k "LOCK_NB"))
                        (primInstr (str prefix ".opNb") (ty/tyI64) "rawOrI64" (list (str prefix ".op") (str prefix ".nb")))
                        (fileNarrow (str prefix ".op32") (str prefix ".opNb")))
                  (list (fileNarrow (str prefix ".op32") (str prefix ".op")))))]
    (listAppend base withNb))

fn fileErrnoIn prefix: String k: (Map String Int64) e: String names: (List String) -> (List ty/SsaInstr)
  (let [(n (listLength names))
        (hit (fn [(i Int64)] -> String (str prefix ".is" i)))
        (acc (fn [(i Int64)] -> String (cond ((= i 0) (hit 0)) ((= i (- n 1)) (str prefix ".in")) (else (str prefix ".any" i)))))
        (tests (fold (fn [(xs (List ty/SsaInstr)) (i Int64)] -> (List ty/SsaInstr)
                       (listAppend xs (list (int64Const (str prefix ".c" i) (fileK k (optionOr (listGet names i) "")))
                                            (fileEq (hit i) e (str prefix ".c" i)))))
                     (list) (range 0 n)))
        (ors (map (fn [(i Int64)] -> ty/SsaInstr (primInstr (acc i) (ty/tyI1) "orBool" (list (acc (- i 1)) (hit i)))) (range 1 n)))]
    (listAppend tests ors))

fn fileIoKindFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileIoKind") (list) (list (ty/ssaParam "code" (ty/tyI64))) (ty/tyVal)
    (list
      (block "entry" (fileErrnoIn "nf" k "code" (list "ENOENT" "ENOENT")) (fileBr "nf.in" "notFound" "permission"))
      (fileRet "notFound" (list (filePool pool "nf.text" "notFound")) "nf.text")
      (block "permission" (fileErrnoIn "perm" k "code" (list "EACCES" "EPERM" "EROFS")) (fileBr "perm.in" "permissionDenied" "exists"))
      (fileRet "permissionDenied" (list (filePool pool "perm.text" "permissionDenied")) "perm.text")
      (block "exists" (fileErrnoIn "exists" k "code" (list "EEXIST" "ENOTEMPTY")) (fileBr "exists.in" "alreadyExists" "invalid"))
      (fileRet "alreadyExists" (list (filePool pool "exists.text" "alreadyExists")) "exists.text")
      (block "invalid" (fileErrnoIn "invalid" k "code" (list "ENOTDIR" "EISDIR" "ENAMETOOLONG" "ELOOP" "EINVAL")) (fileBr "invalid.in" "invalidPath" "interrupted"))
      (fileRet "invalidPath" (list (filePool pool "invalid.text" "invalidPath")) "invalid.text")
      (block "interrupted" (fileErrnoIn "intr" k "code" (list "EINTR" "EINTR")) (fileBr "intr.in" "interruptedText" "other"))
      (fileRet "interruptedText" (list (filePool pool "intr.text" "interrupted")) "intr.text")
      (fileRet "other" (list (filePool pool "other.text" "other")) "other.text")))

fn fileIoErrorFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileIoError") (list)
    (list (ty/ssaParam "code" (ty/tyI64)) (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (int64Const "cap" (+ (fileK k "PATH_MAX") 159))
                            (fileCall "failed" (ty/tyVal) "fileIoErrorCap" (list "code" "path" "cap")))
        (ty/termReturn "failed"))))

fn fileFormatErrorFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileFormatError") (list)
    (list (ty/ssaParam "kind" (ty/tyVal)) (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "reason" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (int64Const "cap" (+ (fileK k "PATH_MAX") 159))
                            (fileCall "failed" (ty/tyVal) "fileFormatErrorCap" (list "kind" "path" "reason" "cap")))
        (ty/termReturn "failed"))))

fn fileIoErrorCapFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileIoErrorCap") (list)
    (list (ty/ssaParam "code" (ty/tyI64)) (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "cap" (ty/tyI64))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "kind" (ty/tyVal) "fileIoKind" (list "code"))
                            (fileNarrow "code32" "code")
                            (callInstr "reasonPtr" (ty/tyPtr) "strerror" (list "code32"))
                            (callInstr "reasonLen" (ty/tyI64) "strlen" (list "reasonPtr"))
                            (callInstr "reason" (ty/tyVal) "mkStr" (list "reasonPtr" "reasonLen"))
                            (fileCall "failed" (ty/tyVal) "fileFormatErrorCap" (list "kind" "path" "reason" "cap")))
        (ty/termReturn "failed"))))

fn fileFormatErrorCapFn pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileFormatErrorCap") (list)
    (list (ty/ssaParam "kind" (ty/tyVal)) (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "reason" (ty/tyVal)) (ty/ssaParam "cap" (ty/tyI64))) (ty/tyVal)
    (list
      (block "entry" (listAppend (fileCStr "pathC" "path")
                       (list (callInstr "pathLen" (ty/tyI64) "strlen" (list "pathC"))
                             (callInstr "pathText" (ty/tyVal) "mkStr" (list "pathC" "pathLen"))
                             (freeInstr "pathFree" "pathC")
                             (filePool pool "sep" ": ")
                             (entryInstr "kindSep" (ty/tyVal) "stringConcat" (list "kind" "sep"))
                             (entryInstr "head" (ty/tyVal) "stringConcat" (list "kindSep" "pathText"))
                             (entryInstr "headSep" (ty/tyVal) "stringConcat" (list "head" "sep"))
                             (entryInstr "full" (ty/tyVal) "stringConcat" (list "headSep" "reason"))
                             (entryInstr "fullLen" (ty/tyI64) "stringLength" (list "full"))
                             (primInstr "over" (ty/tyI1) "gtInt" (list "fullLen" "cap"))))
        (fileBr "over" "cut" "whole"))
      (block "cut" (listAppend (fileCStr "fullC" "full")
                     (list (callInstr "cutText" (ty/tyVal) "mkStr" (list "fullC" "cap"))
                           (freeInstr "fullFree" "fullC")
                           (constructResult "cutErr" "err" "cutText")))
        (ty/termReturn "cutErr"))
      (fileRet "whole" (list (constructResult "wholeErr" "err" "full")) "wholeErr")))

fn fileTypeNameFn pool: (Map String Int64) -> ty/SsaFunction
  (let [(kinds (list (pair "Unit" (fileVal "ex.Unit" (ty/opConst (ty/constUnit))))
                     (pair "Bool" (fileVal "ex.Bool" (ty/opConst (ty/constBool false))))
                     (pair "Int" (fileVal "ex.Int" (ty/opConst (ty/constInt 0))))
                     (pair "Float" (fileVal "ex.Float" (ty/opConst (ty/constFloat 0.0))))
                     (pair "Keyword" (fileVal "ex.Keyword" (ty/opConst (ty/constKeyword "ok"))))
                     (pair "String" (filePool pool "ex.String" ""))
                     (pair "List" (fileVal "ex.List" (ty/opList (list))))
                     (pair "Variant" (fileVal "ex.Variant" (ty/opConstruct "Option" "none" (list))))
                     (pair "Fn" (fileVal "ex.Fn" (ty/opMakeClosure (fileW "fileTypeName") (list))))))
        (n (listLength kinds))
        (label (fn [(i Int64)] -> String (if (= i 0) "entry" (str "try" i))))
        (tests (map (fn [(i Int64)] -> ty/SsaBlock
                      (let [(row (optionOr (listGet kinds i) (pair "" (fileVal "ex" (ty/opConst (ty/constUnit))))))
                            (name (pairFirst row))]
                        (block (label i)
                          (listAppend (if (= i 0) (list (fileCall "vt" (ty/tyI64) "tagOf" (list "v"))) (list))
                            (list (pairSecond row)
                                  (fileCall (str "t." name) (ty/tyI64) "tagOf" (list (str "ex." name)))
                                  (fileEq (str "is." name) "vt" (str "t." name))))
                          (fileBr (str "is." name) (str "name." name) (if (= i (- n 1)) "tryRecord" (label (+ i 1)))))))
                    (range 0 n)))
        (hits (map (fn [(i Int64)] -> ty/SsaBlock
                     (let [(name (pairFirst (optionOr (listGet kinds i) (pair "" (fileVal "ex" (ty/opConst (ty/constUnit)))))))]
                       (fileRet (str "name." name) (list (filePool pool (str "text." name) name)) (str "text." name))))
                   (range 0 n)))]
    (ty/ssaFunction (fileW "fileTypeName") (list) (list (ty/ssaParam "v" (ty/tyVal))) (ty/tyVal)
      (listAppend tests
        (listAppend hits
          (list
            (block "tryRecord" (list (fileVal "ex.false" (ty/opConst (ty/constBool false))) (fileVal "ex.zero" (ty/opConst (ty/constInt 0)))
                                     (fileVal "ex.Record" (ty/opRecord "FileStat" (list "isFile" "isDir" "size" "mtime" "mode" "mtimeNs")
                                                                     (list "ex.false" "ex.false" "ex.zero" "ex.zero" "ex.zero" "ex.zero")))
                                     (fileCall "t.Record" (ty/tyI64) "tagOf" (list "ex.Record")) (fileEq "is.Record" "vt" "t.Record"))
              (fileBr "is.Record" "name.Record" "tryBytes"))
            (fileRet "name.Record" (list (filePool pool "text.Record" "Record")) "text.Record")
            (block "tryBytes" (list (filePool pool "ex.empty" "") (entryInstr "ex.Bytes" (ty/tyVal) "stringToBytes" (list "ex.empty"))
                                    (fileCall "t.Bytes" (ty/tyI64) "tagOf" (list "ex.Bytes")) (fileEq "is.Bytes" "vt" "t.Bytes"))
              (fileBr "is.Bytes" "name.Bytes" "unknown"))
            (fileRet "name.Bytes" (list (filePool pool "text.Bytes" "Bytes")) "text.Bytes")
            (fileRet "unknown" (list (filePool pool "text.unknown" "?")) "text.unknown"))))))

fn fileTypeTrapFn pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileTypeTrap") (list) (list (ty/ssaParam "prefix" (ty/tyVal)) (ty/ssaParam "v" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "name" (ty/tyVal) "fileTypeName" (list "v"))
                            (entryInstr "message" (ty/tyVal) "stringConcat" (list "prefix" "name"))
                            (filePool pool "code" "ERR_TYPE")
                            (fileVal "trapped" (ty/opBuiltin "trap" (list "code" "message"))))
        (ty/termUnreachable))))
fn fileStrTrapBlock pool: (Map String Int64) label: String who: String arg: String -> ty/SsaBlock
  (fileRet label (list (filePool pool (str label ".prefix") (str who " expects String, got "))
                       (fileCall (str label ".v") (ty/tyVal) "fileTypeTrap" (list (str label ".prefix") arg)))
    (str label ".v"))

fn fileBadArgBlock pool: (Map String Int64) label: String who: String path: (Option String) -> ty/SsaBlock
  (fileRet label
    (listAppend (list (filePool pool (str label ".who") who) (filePool pool (str label ".reason") "invalid argument"))
      (mt path
        ((some p) (list (fileCall (str label ".v") (ty/tyVal) "fileFormatError" (list (str label ".who") p (str label ".reason")))))
        ((none) (list (filePool pool (str label ".dash") "-")
                      (fileCall (str label ".v") (ty/tyVal) "fileFormatError" (list (str label ".who") (str label ".dash") (str label ".reason")))))))
    (str label ".v"))

fn fileErrnoErrBlock label: String res: String path: String -> ty/SsaBlock
  (fileRet label (list (ty/ssaInstr (str label ".box") (ty/tyVal) (ty/opVariantField res 0))
                       (ty/ssaInstr (str label ".errno") (ty/tyI64) (ty/opUnbox (str label ".box")))
                       (fileCall (str label ".v") (ty/tyVal) "fileIoError" (list (str label ".errno") path)))
    (str label ".v"))

fn fileNth prefix: String xs: String i: Int64 -> (List ty/SsaInstr)
  (let [(cur (fn [(j Int64)] -> String (if (= j 0) xs (str prefix ".rest" j))))
        (walk (fold (fn [(acc (List ty/SsaInstr)) (j Int64)] -> (List ty/SsaInstr)
                      (listAppend acc (list (entryInstr (str prefix ".tail" j) (ty/tyVal) "listTail" (list (cur j)))
                                            (ty/ssaInstr (cur (+ j 1)) (ty/tyVal) (ty/opVariantField (str prefix ".tail" j) 0)))))
                    (list) (range 0 i)))]
    (listAppend walk (list (entryInstr (str prefix ".head") (ty/tyVal) "listHead" (list (cur i)))
                           (ty/ssaInstr prefix (ty/tyVal) (ty/opVariantField (str prefix ".head") 0)))))
fn fileMergeStringsFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileMergeStrings") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (listInstr "nil" (list))) (fileJump "loop" (list "a" "b" "nil")))
      (ty/ssaBlock "loop" (list (ty/ssaParam "xs" (ty/tyVal)) (ty/ssaParam "ys" (ty/tyVal)) (ty/ssaParam "acc" (ty/tyVal)))
        (list (entryInstr "hx" (ty/tyVal) "listHead" (list "xs"))) (fileOptSwitch "hx" "haveX" "restY"))
      (block "haveX" (list (entryInstr "hy" (ty/tyVal) "listHead" (list "ys"))) (fileOptSwitch "hy" "both" "restX"))
      (block "both" (list (ty/ssaInstr "x" (ty/tyVal) (ty/opVariantField "hx" 0))
                          (ty/ssaInstr "y" (ty/tyVal) (ty/opVariantField "hy" 0))
                          (fileCall "yFirst" (ty/tyI1) "fileNameLess" (list "y" "x")))
        (fileBr "yFirst" "takeY" "takeX"))
      (block "takeX" (list (entryInstr "xsT" (ty/tyVal) "listTail" (list "xs")) (ty/ssaInstr "xs2" (ty/tyVal) (ty/opVariantField "xsT" 0))
                           (entryInstr "accX" (ty/tyVal) "cons" (list "x" "acc")))
        (fileJump "loop" (list "xs2" "ys" "accX")))
      (block "takeY" (list (entryInstr "ysT" (ty/tyVal) "listTail" (list "ys")) (ty/ssaInstr "ys2" (ty/tyVal) (ty/opVariantField "ysT" 0))
                           (entryInstr "accY" (ty/tyVal) "cons" (list "y" "acc")))
        (fileJump "loop" (list "xs" "ys2" "accY")))
      (block "restX" (list) (fileJump "unwind" (list "acc" "xs")))
      (block "restY" (list) (fileJump "unwind" (list "acc" "ys")))
      (ty/ssaBlock "unwind" (list (ty/ssaParam "back" (ty/tyVal)) (ty/ssaParam "out" (ty/tyVal)))
        (list (entryInstr "hb" (ty/tyVal) "listHead" (list "back"))) (fileOptSwitch "hb" "unwindOne" "done"))
      (block "unwindOne" (list (ty/ssaInstr "z" (ty/tyVal) (ty/opVariantField "hb" 0))
                               (entryInstr "backT" (ty/tyVal) "listTail" (list "back")) (ty/ssaInstr "back2" (ty/tyVal) (ty/opVariantField "backT" 0))
                               (entryInstr "out2" (ty/tyVal) "cons" (list "z" "out")))
        (fileJump "unwind" (list "back2" "out2")))
      (fileRet "done" (list) "out")))
fn fileMapIoResultFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileMapIoResult") (list)
    (list (ty/ssaParam "res" (ty/tyVal)) (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list) (fileResSwitch "res" "ok" "error"))
      (fileRet "ok" (list) "res")
      (block "error" (list (ty/ssaInstr "errno.box" (ty/tyVal) (ty/opVariantField "res" 0))
                            (ty/ssaInstr "errno" (ty/tyI64) (ty/opUnbox "errno.box"))
                            (fileCall "mapped" (ty/tyVal) "fileIoError" (list "errno" "path")))
        (ty/termReturn "mapped"))))

fn fileMapUnitIoResultFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileMapUnitIoResult") (list)
    (list (ty/ssaParam "res" (ty/tyVal)) (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list) (fileResSwitch "res" "ok" "error"))
      (fileRet "ok" (list (fileVal "unit" (ty/opConst (ty/constUnit))) (constructResult "success" "ok" "unit")) "success")
      (block "error" (list (ty/ssaInstr "errno.box" (ty/tyVal) (ty/opVariantField "res" 0))
                            (ty/ssaInstr "errno" (ty/tyI64) (ty/opUnbox "errno.box"))
                            (fileCall "mapped" (ty/tyVal) "fileIoError" (list "errno" "path")))
        (ty/termReturn "mapped"))))

fn fileModeInstrs prefix: String k: (Map String Int64) st: String -> (List ty/SsaInstr)
  (list (int64Const (str prefix ".off") (fileK k "stat.st_mode"))
        (primInstr (str prefix ".raw") (ty/tyI32) "rawLoadI32" (list st (str prefix ".off")))
        (fileWiden (str prefix ".wide") (str prefix ".raw"))
        (int64Const (str prefix ".low") 65535)
        (primInstr (str prefix ".mode") (ty/tyI64) "rawAndI64" (list (str prefix ".wide") (str prefix ".low")))
        (int64Const (str prefix ".ifmt") (fileK k "S_IFMT"))
        (primInstr (str prefix ".fmt") (ty/tyI64) "rawAndI64" (list (str prefix ".mode") (str prefix ".ifmt"))))

fn fileSafePathErrFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileSafePathErr") (list) (list (ty/ssaParam "code" (ty/tyI64))) (ty/tyVal)
    (list
      (block "entry" (fileErrnoIn "link" k "code" (list "ELOOP" "ENOTDIR")) (fileBr "link.in" "symlink" "mapped"))
      (fileErrTextBlock pool "symlink" "ERR_PATH_SYMLINK")
      (fileRet "mapped" (list (fileCall "v" (ty/tyVal) "errnoErr" (list "code"))) "v")))

fn filePathCheckFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "filePathCheck") (list) (list (ty/ssaParam "v" (ty/tyVal))) (ty/tyI64)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "v"))) (fileBr "isText" "text" "bad"))
      (block "text"
        (listAppend (fileCStr "p" "v")
          (list (callInstr "cLen" (ty/tyI64) "strlen" (list "p")) (freeInstr "freeP" "p")
                (entryInstr "n" (ty/tyI64) "stringLength" (list "v"))
                (primInstr "hasNul" (ty/tyI1) "neInt" (list "cLen" "n"))))
        (fileBr "hasNul" "bad" "length"))
      (block "length" (list (int64Const "pathMax" (fileK k "PATH_MAX")) (primInstr "long" (ty/tyI1) "geInt" (list "n" "pathMax")))
        (fileBr "long" "tooLong" "good"))
      (fileRet "bad" (list (int64Const "one" 1)) "one")
      (fileRet "tooLong" (list (int64Const "two" 2)) "two")
      (fileRet "good" (list (int64Const "zero" 0)) "zero")))

fn fileNulFreeFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileNulFree") (list) (list (ty/ssaParam "v" (ty/tyVal))) (ty/tyI1)
    (list
      (block "entry"
        (listAppend (fileCStr "p" "v")
          (list (callInstr "cLen" (ty/tyI64) "strlen" (list "p")) (freeInstr "freeP" "p")
                (entryInstr "n" (ty/tyI64) "stringLength" (list "v"))
                (fileEq "clean" "cLen" "n")))
        (ty/termReturn "clean"))))

fn fileParentAtFn k: (Map String Int64) -> ty/SsaFunction
  (let [(dirFlags (list "O_RDONLY" "O_DIRECTORY" "O_NOFOLLOW" "O_CLOEXEC"))]
    (ty/ssaFunction (fileW "fileParentAt") (list) (list (ty/ssaParam "root" (ty/tyVal)) (ty/ssaParam "rel" (ty/tyVal))) (ty/tyVal)
      (list
        (block "entry"
          (list (entryInstr "rootLen" (ty/tyI64) "stringLength" (list "root")) (entryInstr "relLen" (ty/tyI64) "stringLength" (list "rel"))
                (int64Const "zero" 0) (fileEq "rootEmpty" "rootLen" "zero") (fileEq "relEmpty" "relLen" "zero")
                (primInstr "empty" (ty/tyI1) "orBool" (list "rootEmpty" "relEmpty")))
          (fileBr "empty" "einval" "shape"))
        (block "shape"
          (listAppend (fileCStr "path" "rel")
            (list (primInstr "first32" (ty/tyI32) "rawLoadI8" (list "path" "zero")) (fileWiden "first" "first32")
                  (int64Const "slashC" 47) (fileEq "absolute" "first" "slashC")
                  (int32Const "backslash32" 92) (callInstr "bs" (ty/tyPtr) "strchr" (list "path" "backslash32"))
                  (primInstr "noBs" (ty/tyI1) "rawPtrIsNull" (list "bs")) (primInstr "hasBs" (ty/tyI1) "notBool" (list "noBs"))
                  (primInstr "badShape" (ty/tyI1) "orBool" (list "absolute" "hasBs"))))
          (fileBr "badShape" "shapeBad" "length"))
        (block "shapeBad" (list (freeInstr "shapeBad.free" "path")) (fileJump "einval" (list)))
        (block "einval" (list (int64Const "einvalC" (fileK k "EINVAL"))) (fileJump "fail" (list "einvalC")))
        (block "length" (list (int64Const "pathMax" (fileK k "PATH_MAX")) (primInstr "relLong" (ty/tyI1) "geInt" (list "relLen" "pathMax")))
          (fileBr "relLong" "relTooLong" "openRoot"))
        (block "relTooLong" (list (freeInstr "relTooLong.free" "path") (int64Const "relTooLong.c" (fileK k "ENAMETOOLONG")))
          (fileJump "fail" (list "relTooLong.c")))
        (block "openRoot"
          (listAppend (fileCStr "rootC" "root")
            (listAppend (fileOr "rootFlags" k dirFlags)
              (list (callInstr "root32" (ty/tyI32) "open" (list "rootC" "rootFlags")) (fileWiden "rootFd" "root32")
                    (primInstr "rootFailed" (ty/tyI1) "ltInt" (list "rootFd" "zero")))))
          (fileBr "rootFailed" "rootErr" "rootOk"))
        (block "rootErr" (list (fileErrno "rootErr.e") (freeInstr "rootErr.freeRoot" "rootC") (freeInstr "rootErr.freePath" "path"))
          (fileJump "fail" (list "rootErr.e")))
        (block "rootOk" (list (freeInstr "rootOk.free" "rootC") (primInstr "pathAt" (ty/tyI64) "rawPtrToInt" (list "path")))
          (fileJump "walk" (list "rootFd" "zero")))
        (ty/ssaBlock "walk" (list (ty/ssaParam "dirfd" (ty/tyI64)) (ty/ssaParam "start" (ty/tyI64)))
          (list (fileNarrow "d32" "dirfd") (primInstr "partAt" (ty/tyI64) "rawAddI64" (list "pathAt" "start"))
                (primInstr "part" (ty/tyPtr) "rawIntToPtr" (list "partAt"))
                (int32Const "slash32" 47) (callInstr "slash" (ty/tyPtr) "strchr" (list "part" "slash32"))
                (primInstr "noSlash" (ty/tyI1) "rawPtrIsNull" (list "slash")))
          (fileBr "noSlash" "last" "cut"))
        (block "cut"
          (list (int32Const "nul32" 0) (primInstr "cut.st" (ty/tyI1) "rawStoreI8" (list "slash" "zero" "nul32"))
                (primInstr "slashAt" (ty/tyI64) "rawPtrToInt" (list "slash")) (primInstr "slashOff" (ty/tyI64) "rawSubI64" (list "slashAt" "pathAt"))
                (ty/ssaInstr "cut.yes" (ty/tyI1) (ty/opConst (ty/constBool true))))
          (fileJump "comp" (list "cut.yes" "slashOff")))
        (block "last" (list (ty/ssaInstr "last.no" (ty/tyI1) (ty/opConst (ty/constBool false)))) (fileJump "comp" (list "last.no" "zero")))
        (ty/ssaBlock "comp" (list (ty/ssaParam "hasSlash" (ty/tyI1)) (ty/ssaParam "slashIdx" (ty/tyI64)))
          (list (callInstr "partLen" (ty/tyI64) "strlen" (list "part")) (fileEq "partEmpty" "partLen" "zero"))
          (fileBr "partEmpty" "compBad" "dots"))
        (block "dots"
          (list (primInstr "c0_32" (ty/tyI32) "rawLoadI8" (list "part" "zero")) (fileWiden "c0" "c0_32")
                (int64Const "one" 1) (primInstr "c1_32" (ty/tyI32) "rawLoadI8" (list "part" "one")) (fileWiden "c1" "c1_32")
                (int64Const "dotC" 46) (int64Const "two" 2)
                (fileEq "len1" "partLen" "one") (fileEq "len2" "partLen" "two") (fileEq "dot0" "c0" "dotC") (fileEq "dot1" "c1" "dotC")
                (primInstr "isDot" (ty/tyI1) "andBool" (list "len1" "dot0"))
                (primInstr "dots01" (ty/tyI1) "andBool" (list "dot0" "dot1"))
                (primInstr "isDotDot" (ty/tyI1) "andBool" (list "len2" "dots01"))
                (primInstr "dotted" (ty/tyI1) "orBool" (list "isDot" "isDotDot")))
          (fileBr "dotted" "compBad" "compOk"))
        (block "compBad" (list (fileClose "compBad.close" "d32") (freeInstr "compBad.free" "path") (int64Const "compBad.c" (fileK k "EINVAL")))
          (fileJump "fail" (list "compBad.c")))
        (block "compOk" (list) (fileBr "hasSlash" "mid" "leaf"))
        (block "leaf" (list (int64Const "nameCap" (+ (fileK k "NAME_MAX") 1)) (primInstr "leafLong" (ty/tyI1) "geInt" (list "partLen" "nameCap")))
          (fileBr "leafLong" "leafTooLong" "leafOk"))
        (block "leafTooLong" (list (fileClose "leafTooLong.close" "d32") (freeInstr "leafTooLong.free" "path") (int64Const "leafTooLong.c" (fileK k "ENAMETOOLONG")))
          (fileJump "fail" (list "leafTooLong.c")))
        (fileRet "leafOk"
          (list (callInstr "leafV" (ty/tyVal) "mkStr" (list "part" "partLen")) (freeInstr "leafOk.free" "path") (boxInstr "dirBox" "dirfd")
                (fileVal "found" (ty/opConstruct "Pair" "pair" (list "dirBox" "leafV"))) (constructResult "foundOk" "ok" "found"))
          "foundOk")
        (block "mid"
          (list (primInstr "nextIdx" (ty/tyI64) "rawAddI64" (list "slashIdx" "one")) (primInstr "next32" (ty/tyI32) "rawLoadI8" (list "path" "nextIdx"))
                (fileWiden "nextC" "next32") (fileEq "trailing" "nextC" "zero"))
          (fileBr "trailing" "compBad" "descend"))
        (block "descend"
          (listAppend (fileOr "subFlags" k dirFlags)
            (list (callInstr "sub32" (ty/tyI32) "openat" (list "d32" "part" "subFlags")) (fileWiden "subFd" "sub32")
                  (primInstr "subFailed" (ty/tyI1) "ltInt" (list "subFd" "zero"))))
          (fileBr "subFailed" "subErr" "subOk"))
        (block "subErr" (list (fileErrno "subErr.e") (fileClose "subErr.close" "d32") (freeInstr "subErr.free" "path"))
          (fileJump "fail" (list "subErr.e")))
        (block "subOk" (list (fileClose "subOk.close" "d32")) (fileJump "walk" (list "subFd" "nextIdx")))
        (ty/ssaBlock "fail" (list (ty/ssaParam "code" (ty/tyI64)))
          (list (boxInstr "codeBox" "code") (constructResult "failed" "err" "codeBox"))
          (ty/termReturn "failed")))))

fn fileMonoMsFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileMonoMs") (list) (list (ty/ssaParam "tsAt" (ty/tyI64))) (ty/tyI64)
    (list
      (block "entry"
        (list (primInstr "ts" (ty/tyPtr) "rawIntToPtr" (list "tsAt")) (int32Const "clock" (fileK k "CLOCK_MONOTONIC"))
              (callInstr "got" (ty/tyI32) "clock_gettime" (list "clock" "ts"))
              (int64Const "secOff" (fileK k "timespec.tv_sec")) (int64Const "nsecOff" (fileK k "timespec.tv_nsec"))
              (primInstr "sec" (ty/tyI64) "rawLoadI64" (list "ts" "secOff")) (primInstr "nsec" (ty/tyI64) "rawLoadI64" (list "ts" "nsecOff"))
              (int64Const "thousand" 1000) (int64Const "million" 1000000)
              (primInstr "secMs" (ty/tyI64) "mulInt" (list "sec" "thousand")) (primInstr "nsecMs" (ty/tyI64) "quotInt" (list "nsec" "million"))
              (primInstr "ms" (ty/tyI64) "addInt" (list "secMs" "nsecMs")))
        (ty/termReturn "ms"))))

fn fileTempSeqInitFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileTempSeqInit") (list) (list) (ty/tyVal)
    (list
      (block "entry" (list (int64Const "eight" 8) (callInstr "cell" (ty/tyPtr) "malloc" (list "eight")) (primInstr "cellNull" (ty/tyI1) "rawPtrIsNull" (list "cell")))
        (fileBr "cellNull" "none" "zeroed"))
      (fileRet "none" (list (int64Const "none.zero" 0) (boxInstr "none.v" "none.zero")) "none.v")
      (fileRet "zeroed"
        (list (int64Const "zero" 0) (primInstr "st" (ty/tyI1) "rawStoreI64" (list "cell" "zero" "zero"))
              (primInstr "cellAt" (ty/tyI64) "rawPtrToInt" (list "cell")) (boxInstr "v" "cellAt"))
        "v")))

fn filePathBlocks k: (Map String Int64) pool: (Map String Int64) arg: String next: String -> (List ty/SsaBlock)
  (list
    (block "entry" (list (fileCall "pc" (ty/tyI64) "filePathCheck" (list arg)) (int64Const "pcOne" 1) (fileEq "pcBad" "pc" "pcOne"))
      (fileBr "pcBad" "inval" "pcLen"))
    (block "pcLen" (list (int64Const "pcTwo" 2) (fileEq "pcLong" "pc" "pcTwo")) (fileBr "pcLong" "tooLong" next))
    (fileRet "tooLong" (list (int64Const "tooLong.c" (fileK k "ENAMETOOLONG")) (fileCall "tooLong.v" (ty/tyVal) "errnoErr" (list "tooLong.c"))) "tooLong.v")
    (fileErrTextBlock pool "inval" "io:22"))

fn fileLockFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileLock") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal))) (ty/tyVal)
    (listAppend
      (list
        (block "start" (list (fileCall "isText" (ty/tyI1) "isStr" (list "a"))) (fileBr "isText" "flagCheck" "inval"))
        (block "flagCheck" (list (fileCall "flag" (ty/tyI64) "boolOf" (list "b")) (int64Const "minusOne" -1) (fileEq "notBool" "flag" "minusOne"))
          (fileBr "notBool" "inval" "entry")))
      (listAppend (filePathBlocks k pool "a" "open")
        (list
          (block "open"
            (listAppend (fileCStr "p" "a")
              (listAppend (fileOr "flags" k (list "O_RDWR" "O_CREAT" "O_CLOEXEC"))
                (list (int32Const "mode" 438) (callInstr "fd32" (ty/tyI32) "open" (list "p" "flags" "mode")) (fileWiden "fd" "fd32")
                      (int64Const "zero" 0) (primInstr "openFailed" (ty/tyI1) "ltInt" (list "fd" "zero")))))
            (fileBr "openFailed" "openErr" "opened"))
          (fileRet "openErr" (list (fileErrno "openErr.e") (freeInstr "openErr.free" "p") (fileCall "openErr.v" (ty/tyVal) "errnoErr" (list "openErr.e"))) "openErr.v")
          (block "opened"
            (listAppend (list (freeInstr "opened.free" "p"))
              (listAppend (fileOpInstrs "lk" k "flag" true)
                (list (callInstr "locked32" (ty/tyI32) "flock" (list "fd32" "lk.op32")) (fileWiden "locked" "locked32")
                      (primInstr "lockFailed" (ty/tyI1) "neInt" (list "locked" "zero")))))
            (fileBr "lockFailed" "lockErr" "ok"))
          (block "lockErr" (cons (fileErrno "lockErr.e") (cons (fileClose "lockErr.close" "fd32") (fileErrnoIn "wb" k "lockErr.e" (list "EWOULDBLOCK" "EAGAIN" "EBUSY"))))
            (fileBr "wb.in" "busy" "mapped"))
          (fileErrTextBlock pool "busy" "busy")
          (fileRet "mapped" (list (fileCall "mapped.v" (ty/tyVal) "errnoErr" (list "lockErr.e"))) "mapped.v")
          (fileRet "ok" (list (boxInstr "fdBox" "fd") (constructResult "ok.v" "ok" "fdBox")) "ok.v")))))

fn fileLockWaitCoreFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (let [(okBlk (fn [(label String)] -> ty/SsaBlock (fileRet label (list (constructResult (str label ".v") "ok" "fdBox")) (str label ".v"))))]
    (ty/ssaFunction (fileW "fileLockWaitCore") (list)
      (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "exclusive" (ty/tyI64)) (ty/ssaParam "timeout" (ty/tyI64))) (ty/tyVal)
      (list
        (block "entry"
          (listAppend (fileCStr "p" "path")
            (listAppend (fileOr "flags" k (list "O_RDWR" "O_CREAT" "O_CLOEXEC"))
              (list (int32Const "mode" 438) (callInstr "fd32" (ty/tyI32) "open" (list "p" "flags" "mode")) (fileWiden "fd" "fd32")
                    (int64Const "zero" 0) (primInstr "openFailed" (ty/tyI1) "ltInt" (list "fd" "zero")))))
          (fileBr "openFailed" "openErr" "opened"))
        (fileRet "openErr" (list (fileErrno "openErr.e") (freeInstr "openErr.free" "p") (fileCall "openErr.v" (ty/tyVal) "errnoErr" (list "openErr.e"))) "openErr.v")
        (block "opened"
          (listAppend (list (freeInstr "opened.free" "p") (boxInstr "fdBox" "fd"))
            (listAppend (fileOpInstrs "lk" k "exclusive" false)
              (listAppend (fileOpInstrs "nb" k "exclusive" true)
                (list (primInstr "negative" (ty/tyI1) "ltInt" (list "timeout" "zero")) (int64Const "cap" 1125899906842624)
                      (primInstr "huge" (ty/tyI1) "gtInt" (list "timeout" "cap")) (primInstr "forever" (ty/tyI1) "orBool" (list "negative" "huge"))))))
          (fileBr "forever" "blocking" "try"))
        (block "blocking" (list (callInstr "b32" (ty/tyI32) "flock" (list "fd32" "lk.op32")) (fileWiden "bRes" "b32") (primInstr "bFailed" (ty/tyI1) "neInt" (list "bRes" "zero")))
          (fileBr "bFailed" "blockErr" "gotBlocking"))
        (block "blockErr" (list (fileErrno "blockErr.e") (int64Const "eintr" (fileK k "EINTR")) (fileEq "blockErr.intr" "blockErr.e" "eintr"))
          (fileBr "blockErr.intr" "blocking" "blockFail"))
        (fileRet "blockFail" (list (fileClose "blockFail.close" "fd32") (fileCall "blockFail.v" (ty/tyVal) "errnoErr" (list "blockErr.e"))) "blockFail.v")
        (okBlk "gotBlocking")
        (block "try" (list (callInstr "t32" (ty/tyI32) "flock" (list "fd32" "nb.op32")) (fileWiden "tRes" "t32") (fileEq "tOk" "tRes" "zero"))
          (fileBr "tOk" "gotFirst" "tryErr"))
        (okBlk "gotFirst")
        (block "tryErr" (cons (fileErrno "tryErr.e") (fileErrnoIn "tw" k "tryErr.e" (list "EWOULDBLOCK" "EAGAIN" "EBUSY")))
          (fileBr "tw.in" "held" "tryFail"))
        (fileRet "tryFail" (list (fileClose "tryFail.close" "fd32") (fileCall "tryFail.v" (ty/tyVal) "errnoErr" (list "tryErr.e"))) "tryFail.v")
        (block "held" (list (fileEq "noWait" "timeout" "zero")) (fileBr "noWait" "timedOutNow" "timed"))
        (block "timedOutNow" (cons (fileClose "timedOutNow.close" "fd32") (fileErrVal pool "timedOutNow.v" "ERR_TIMEOUT")) (ty/termReturn "timedOutNow.v"))
        (block "timed" (list (int64Const "tsSize" (fileK k "timespec.size")) (callInstr "ts" (ty/tyPtr) "malloc" (list "tsSize")) (primInstr "tsNull" (ty/tyI1) "rawPtrIsNull" (list "ts")))
          (fileBr "tsNull" "noMem" "start"))
        (block "noMem" (cons (fileClose "noMem.close" "fd32") (fileErrVal pool "noMem.v" "io:12")) (ty/termReturn "noMem.v"))
        (block "start"
          (list (primInstr "tsAt" (ty/tyI64) "rawPtrToInt" (list "ts")) (fileCall "now0" (ty/tyI64) "fileMonoMs" (list "tsAt"))
                (primInstr "deadline" (ty/tyI64) "addInt" (list "now0" "timeout")) (int64Const "one" 1) (int64Const "twenty" 20) (int64Const "twoC" 2))
          (fileJump "loop" (list "one")))
        (ty/ssaBlock "loop" (list (ty/ssaParam "step" (ty/tyI64)))
          (list (fileCall "now" (ty/tyI64) "fileMonoMs" (list "tsAt")) (primInstr "expired" (ty/tyI1) "geInt" (list "now" "deadline")))
          (fileBr "expired" "timedOut" "wait"))
        (block "timedOut" (cons (fileClose "timedOut.close" "fd32") (cons (freeInstr "timedOut.free" "ts") (fileErrVal pool "timedOut.v" "ERR_TIMEOUT"))) (ty/termReturn "timedOut.v"))
        (block "wait" (list (primInstr "rem" (ty/tyI64) "subInt" (list "deadline" "now")) (primInstr "remFirst" (ty/tyI1) "ltInt" (list "rem" "step")))
          (fileBr "remFirst" "useRem" "useStep"))
        (block "useRem" (list) (fileJump "clamp" (list "rem")))
        (block "useStep" (list) (fileJump "clamp" (list "step")))
        (ty/ssaBlock "clamp" (list (ty/ssaParam "waitMs" (ty/tyI64)))
          (list (primInstr "nonPositive" (ty/tyI1) "leInt" (list "waitMs" "zero")))
          (ty/termBranch "nonPositive" (edgeTo "atLeastOne") (ty/ssaEdge "nap" (list "waitMs"))))
        (block "atLeastOne" (list) (fileJump "nap" (list "one")))
        (ty/ssaBlock "nap" (list (ty/ssaParam "napMs" (ty/tyI64)))
          (list (primInstr "noFds" (ty/tyPtr) "rawIntToPtr" (list "zero")) (fileNarrow "nap32" "napMs")
                (callInstr "polled" (ty/tyI32) "poll" (list "noFds" "zero" "nap32"))
                (callInstr "r32" (ty/tyI32) "flock" (list "fd32" "nb.op32")) (fileWiden "rRes" "r32") (fileEq "rOk" "rRes" "zero"))
          (fileBr "rOk" "gotLater" "retryErr"))
        (block "gotLater" (list (freeInstr "gotLater.free" "ts") (constructResult "gotLater.v" "ok" "fdBox")) (ty/termReturn "gotLater.v"))
        (block "retryErr" (cons (fileErrno "retryErr.e") (fileErrnoIn "rw" k "retryErr.e" (list "EWOULDBLOCK" "EAGAIN" "EBUSY" "EINTR")))
          (fileBr "rw.in" "again" "retryFail"))
        (fileRet "retryFail" (list (fileClose "retryFail.close" "fd32") (freeInstr "retryFail.free" "ts") (fileCall "retryFail.v" (ty/tyVal) "errnoErr" (list "retryErr.e"))) "retryFail.v")
        (block "again" (list (primInstr "small" (ty/tyI1) "ltInt" (list "step" "twenty"))) (fileBr "small" "double" "keep"))
        (block "double" (list (primInstr "doubled" (ty/tyI64) "mulInt" (list "step" "twoC"))) (fileJump "loop" (list "doubled")))
        (block "keep" (list) (fileJump "loop" (list "step"))))))

fn fileWaitTail prefix: String exclusive: String timeout: String -> (List ty/SsaInstr)
  (list (fileCall (str prefix ".v") (ty/tyVal) "fileLockWaitCore" (list "a" exclusive timeout)))

fn fileTimeoutBlocks k: (Map String Int64) pool: (Map String Int64) arg: String exclusive: String -> (List ty/SsaBlock)
  (list
    (block "timeoutArg" (list (fileCall "ti" (ty/tyVal) "intOf" (list arg))) (fileOptSwitch "ti" "asInt" "notInt"))
    (fileRet "asInt" (cons (fileField0 "asInt.box" "ti") (cons (ty/ssaInstr "asInt.n" (ty/tyI64) (ty/opUnbox "asInt.box")) (fileWaitTail "asInt" exclusive "asInt.n"))) "asInt.v")
    (block "notInt" (list (fileCall "oa" (ty/tyI64) "optionArg" (list arg)) (int64Const "oaNone" 0) (fileEq "isNone" "oa" "oaNone"))
      (fileBr "isNone" "asNone" "notNone"))
    (fileRet "asNone" (cons (int64Const "asNone.m1" -1) (fileWaitTail "asNone" exclusive "asNone.m1")) "asNone.v")
    (block "notNone" (list (int64Const "oaSome" 1) (fileEq "isSome" "oa" "oaSome")) (fileBr "isSome" "asSome" "inval"))
    (block "asSome" (list (fileVal "inner" (ty/opVariantField arg 0)) (fileCall "ii" (ty/tyVal) "intOf" (list "inner"))) (fileOptSwitch "ii" "innerInt" "inval"))
    (fileRet "innerInt" (cons (fileField0 "innerInt.box" "ii") (cons (ty/ssaInstr "innerInt.n" (ty/tyI64) (ty/opUnbox "innerInt.box")) (fileWaitTail "innerInt" exclusive "innerInt.n"))) "innerInt.v"))

fn fileField0 dest: String v: String -> ty/SsaInstr
  (fileVal dest (ty/opVariantField v 0))

fn fileLockWait1Fn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileLockWait/1") (list) (list (ty/ssaParam "a" (ty/tyVal))) (ty/tyVal)
    (listAppend (filePathBlocks k pool "a" "go")
      (list (fileRet "go" (list (int64Const "one" 1) (int64Const "minusOne" -1) (fileCall "go.v" (ty/tyVal) "fileLockWaitCore" (list "a" "one" "minusOne"))) "go.v"))))

fn fileLockWait2Fn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileLockWait/2") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal))) (ty/tyVal)
    (listAppend (filePathBlocks k pool "a" "second")
      (listAppend
        (list (block "second" (list (fileCall "flag" (ty/tyI64) "boolOf" (list "b")) (int64Const "minusOne" -1) (int64Const "one" 1)
                                    (primInstr "isBool" (ty/tyI1) "neInt" (list "flag" "minusOne")))
                (fileBr "isBool" "asBool" "timeoutArg"))
              (fileRet "asBool" (fileWaitTail "asBool" "flag" "minusOne") "asBool.v"))
        (fileTimeoutBlocks k pool "b" "one"))))

fn fileLockWait3Fn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileLockWait/3") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal)) (ty/ssaParam "c" (ty/tyVal))) (ty/tyVal)
    (listAppend (filePathBlocks k pool "a" "second")
      (cons (block "second" (list (fileCall "flag" (ty/tyI64) "boolOf" (list "b")) (int64Const "minusOne" -1) (fileEq "notBool" "flag" "minusOne"))
              (fileBr "notBool" "inval" "timeoutArg"))
        (fileTimeoutBlocks k pool "c" "flag"))))

fn fileLockWaitBadFn pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileLockWait/bad") (list) (list) (ty/tyVal) (list (fileErrTextBlock pool "entry" "io:22")))

fn fileAppendFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileAppend") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal))) (ty/tyVal)
    (listAppend (filePathBlocks k pool "a" "data")
      (list
        (block "data" (list (fileCall "isText" (ty/tyI1) "isStr" (list "b")) (int64Const "zero" 0) (int64Const "one" 1)) (fileBr "isText" "textData" "notText"))
        (block "textData" (listAppend (fileCStr "tp" "b") (list (entryInstr "tn" (ty/tyI64) "stringLength" (list "b")) (primInstr "tAt" (ty/tyI64) "rawPtrToInt" (list "tp"))))
          (fileJump "write" (list "tAt" "tn")))
        (block "notText" (list (fileCall "isRaw" (ty/tyI1) "isBytes" (list "b"))) (fileBr "isRaw" "rawData" "inval"))
        (block "rawData" (list (entryInstr "bn" (ty/tyI64) "bytesLength" (list "b")) (primInstr "bSize" (ty/tyI64) "rawAddI64" (list "bn" "one"))
                               (callInstr "bp" (ty/tyPtr) "malloc" (list "bSize")) (primInstr "bpNull" (ty/tyI1) "rawPtrIsNull" (list "bp")))
          (ty/termBranch "bpNull" (edgeTo "noMem") (ty/ssaEdge "copy" (list "zero"))))
        (fileErrTextBlock pool "noMem" "io:12")
        (ty/ssaBlock "copy" (list (ty/ssaParam "ci" (ty/tyI64))) (list (primInstr "copied" (ty/tyI1) "geInt" (list "ci" "bn"))) (fileBr "copied" "copyDone" "copyByte"))
        (block "copyByte"
          (list (entryInstr "byte" (ty/tyI64) "bytesGet" (list "b" "ci")) (fileNarrow "byte32" "byte")
                (primInstr "stored" (ty/tyI1) "rawStoreI8" (list "bp" "ci" "byte32")) (primInstr "ciNext" (ty/tyI64) "rawAddI64" (list "ci" "one")))
          (fileJump "copy" (list "ciNext")))
        (block "copyDone" (list (primInstr "bAt" (ty/tyI64) "rawPtrToInt" (list "bp"))) (fileJump "write" (list "bAt" "bn")))
        (ty/ssaBlock "write" (list (ty/ssaParam "dAt" (ty/tyI64)) (ty/ssaParam "dLen" (ty/tyI64)))
          (listAppend (list (primInstr "dp" (ty/tyPtr) "rawIntToPtr" (list "dAt")))
            (listAppend (fileCStr "p" "a")
              (listAppend (fileOr "flags" k (list "O_WRONLY" "O_CREAT" "O_APPEND" "O_CLOEXEC"))
                (list (int32Const "mode" 438) (callInstr "fd32" (ty/tyI32) "open" (list "p" "flags" "mode")) (fileWiden "fd" "fd32")
                      (primInstr "openFailed" (ty/tyI1) "ltInt" (list "fd" "zero"))))))
          (fileBr "openFailed" "openErr" "opened"))
        (fileRet "openErr" (list (fileErrno "openErr.e") (freeInstr "openErr.freeP" "p") (freeInstr "openErr.freeD" "dp") (fileCall "openErr.v" (ty/tyVal) "errnoErr" (list "openErr.e"))) "openErr.v")
        (block "opened" (list (freeInstr "opened.free" "p")) (fileJump "wloop" (list "zero")))
        (ty/ssaBlock "wloop" (list (ty/ssaParam "off" (ty/tyI64)))
          (list (primInstr "rem" (ty/tyI64) "subInt" (list "dLen" "off")) (primInstr "more" (ty/tyI1) "gtInt" (list "rem" "zero")))
          (fileBr "more" "wr" "closeIt"))
        (block "wr"
          (list (primInstr "atI" (ty/tyI64) "rawAddI64" (list "dAt" "off")) (primInstr "at" (ty/tyPtr) "rawIntToPtr" (list "atI"))
                (callInstr "w" (ty/tyI64) "write" (list "fd32" "at" "rem")) (primInstr "wNeg" (ty/tyI1) "ltInt" (list "w" "zero")))
          (fileBr "wNeg" "wErr" "wSome"))
        (block "wErr" (list (fileErrno "wErr.e") (int64Const "eintr" (fileK k "EINTR")) (fileEq "wErr.intr" "wErr.e" "eintr"))
          (ty/termBranch "wErr.intr" (ty/ssaEdge "wloop" (list "off")) (edgeTo "wFail")))
        (fileRet "wFail" (list (fileClose "wFail.close" "fd32") (freeInstr "wFail.free" "dp") (fileCall "wFail.v" (ty/tyVal) "errnoErr" (list "wErr.e"))) "wFail.v")
        (block "wSome" (list (fileEq "wNone" "w" "zero")) (fileBr "wNone" "noSpace" "wAdv"))
        (fileRet "noSpace" (list (fileClose "noSpace.close" "fd32") (freeInstr "noSpace.free" "dp") (int64Const "enospc" (fileK k "ENOSPC"))
                                 (fileCall "noSpace.v" (ty/tyVal) "errnoErr" (list "enospc"))) "noSpace.v")
        (block "wAdv" (list (primInstr "offNext" (ty/tyI64) "addInt" (list "off" "w"))) (fileJump "wloop" (list "offNext")))
        (block "closeIt" (list (fileClose "closed32" "fd32") (fileWiden "closed" "closed32") (primInstr "closeFailed" (ty/tyI1) "ltInt" (list "closed" "zero")))
          (fileBr "closeFailed" "closeErr" "done"))
        (fileRet "closeErr" (list (fileErrno "closeErr.e") (freeInstr "closeErr.free" "dp") (fileCall "closeErr.v" (ty/tyVal) "errnoErr" (list "closeErr.e"))) "closeErr.v")
        (fileRet "done" (list (freeInstr "done.free" "dp") (fileVal "unit" (ty/opConst (ty/constUnit))) (constructResult "done.v" "ok" "unit")) "done.v"))))

fn fileAtBlocks pool: (Map String Int64) strArgs: (List String) boolArg: (Option String) -> (List ty/SsaBlock)
  (let [(n (listLength strArgs))
        (label (fn [(i Int64)] -> String (if (= i 0) "entry" (str "str" i))))
        (afterStrs (mt boolArg ((some _) "flagCheck") ((none) "nulA")))
        (strBlocks (map (fn [(i Int64)] -> ty/SsaBlock
                          (block (label i) (list (fileCall (str "isText" i) (ty/tyI1) "isStr" (list (optionOr (listGet strArgs i) ""))))
                            (fileBr (str "isText" i) (if (= i (- n 1)) afterStrs (label (+ i 1))) "inval")))
                        (range 0 n)))
        (flagBlocks (mt boolArg
                      ((some arg) (list (block "flagCheck" (list (fileCall "flag" (ty/tyI64) "boolOf" (list arg)) (int64Const "minusOne" -1) (fileEq "notBool" "flag" "minusOne"))
                                          (fileBr "notBool" "inval" "nulA"))))
                      ((none) (list))))]
    (listAppend strBlocks
      (listAppend flagBlocks
        (list (block "nulA" (list (fileCall "cleanA" (ty/tyI1) "fileNulFree" (list "a"))) (fileBr "cleanA" "nulB" "inval"))
              (block "nulB" (list (fileCall "cleanB" (ty/tyI1) "fileNulFree" (list "b"))) (fileBr "cleanB" "parent" "inval"))
              (block "parent" (list (fileCall "walked" (ty/tyVal) "fileParentAt" (list "a" "b"))) (fileResSwitch "walked" "haveDir" "walkErr"))
              (fileRet "walkErr" (list (fileField0 "walkErr.box" "walked") (ty/ssaInstr "walkErr.e" (ty/tyI64) (ty/opUnbox "walkErr.box"))
                                       (fileCall "walkErr.v" (ty/tyVal) "fileSafePathErr" (list "walkErr.e"))) "walkErr.v")
              (fileErrTextBlock pool "inval" "io:22")))))

fn fileHaveDirInstrs -> (List ty/SsaInstr)
  (listAppend
    (list (fileField0 "found" "walked") (fileField0 "dirBox" "found") (ty/ssaInstr "dirfd" (ty/tyI64) (ty/opUnbox "dirBox"))
          (fileVal "leaf" (ty/opVariantField "found" 1)) (fileNarrow "d32" "dirfd") (int64Const "zero" 0))
    (fileCStr "lc" "leaf"))

fn fileLockAtFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileLockAt") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal)) (ty/ssaParam "c" (ty/tyVal))) (ty/tyVal)
    (listAppend (fileAtBlocks pool (list "a" "b") (some "c"))
      (list
        (block "haveDir"
          (listAppend (fileHaveDirInstrs)
            (listAppend (fileOr "createFlags" k (list "O_RDWR" "O_CREAT" "O_EXCL" "O_NOFOLLOW" "O_CLOEXEC"))
              (list (int32Const "mode" 438) (callInstr "fd1_32" (ty/tyI32) "openat" (list "d32" "lc" "createFlags" "mode")) (fileWiden "fd1" "fd1_32")
                    (primInstr "fd1Failed" (ty/tyI1) "ltInt" (list "fd1" "zero")))))
          (ty/termBranch "fd1Failed" (edgeTo "createErr") (ty/ssaEdge "opened" (list "fd1"))))
        (block "createErr" (list (fileErrno "createErr.e") (int64Const "eexist" (fileK k "EEXIST")) (fileEq "exists" "createErr.e" "eexist"))
          (ty/termBranch "exists" (edgeTo "reopen") (ty/ssaEdge "openFail" (list "createErr.e"))))
        (block "reopen"
          (listAppend (fileOr "openFlags" k (list "O_RDWR" "O_NOFOLLOW" "O_CLOEXEC"))
            (list (callInstr "fd2_32" (ty/tyI32) "openat" (list "d32" "lc" "openFlags")) (fileWiden "fd2" "fd2_32")
                  (primInstr "fd2Failed" (ty/tyI1) "ltInt" (list "fd2" "zero"))))
          (ty/termBranch "fd2Failed" (edgeTo "reopenErr") (ty/ssaEdge "opened" (list "fd2"))))
        (block "reopenErr" (list (fileErrno "reopenErr.e")) (fileJump "openFail" (list "reopenErr.e")))
        (ty/ssaBlock "openFail" (list (ty/ssaParam "e" (ty/tyI64)))
          (list (fileClose "openFail.close" "d32") (freeInstr "openFail.free" "lc") (fileCall "openFail.v" (ty/tyVal) "fileSafePathErr" (list "e")))
          (ty/termReturn "openFail.v"))
        (ty/ssaBlock "opened" (list (ty/ssaParam "fd" (ty/tyI64)))
          (listAppend (list (fileClose "opened.close" "d32") (freeInstr "opened.free" "lc") (fileNarrow "fd32" "fd"))
            (listAppend (fileOpInstrs "lk" k "flag" true)
              (list (callInstr "locked32" (ty/tyI32) "flock" (list "fd32" "lk.op32")) (fileWiden "locked" "locked32")
                    (primInstr "lockFailed" (ty/tyI1) "neInt" (list "locked" "zero")))))
          (fileBr "lockFailed" "lockErr" "ok"))
        (block "lockErr" (cons (fileErrno "lockErr.e") (cons (fileClose "lockErr.close" "fd32") (fileErrnoIn "wb" k "lockErr.e" (list "EWOULDBLOCK" "EAGAIN" "EBUSY"))))
          (fileBr "wb.in" "busy" "mapped"))
        (fileErrTextBlock pool "busy" "busy")
        (fileRet "mapped" (list (fileCall "mapped.v" (ty/tyVal) "fileSafePathErr" (list "lockErr.e"))) "mapped.v")
        (fileRet "ok" (list (boxInstr "fdBox" "fd") (constructResult "ok.v" "ok" "fdBox")) "ok.v"))))

fn fileReadAtFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileReadAt") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal))) (ty/tyVal)
    (listAppend (fileAtBlocks pool (list "a" "b") (none))
      (list
        (block "haveDir"
          (listAppend (fileHaveDirInstrs)
            (listAppend (fileOr "flags" k (list "O_RDONLY" "O_NOFOLLOW" "O_CLOEXEC" "O_NONBLOCK"))
              (list (callInstr "fd32" (ty/tyI32) "openat" (list "d32" "lc" "flags")) (fileWiden "fd" "fd32")
                    (primInstr "openFailed" (ty/tyI1) "ltInt" (list "fd" "zero")))))
          (fileBr "openFailed" "openErr" "opened"))
        (fileRet "openErr" (list (fileErrno "openErr.e") (fileClose "openErr.close" "d32") (freeInstr "openErr.free" "lc")
                                 (fileCall "openErr.v" (ty/tyVal) "fileSafePathErr" (list "openErr.e"))) "openErr.v")
        (block "opened"
          (list (fileClose "opened.close" "d32") (freeInstr "opened.free" "lc") (int64Const "stSize" (fileK k "stat.size"))
                (callInstr "st" (ty/tyPtr) "malloc" (list "stSize")) (primInstr "stNull" (ty/tyI1) "rawPtrIsNull" (list "st")))
          (fileBr "stNull" "stNoMem" "doStat"))
        (block "stNoMem" (cons (fileClose "stNoMem.close" "fd32") (fileErrVal pool "stNoMem.v" "io:12")) (ty/termReturn "stNoMem.v"))
        (block "doStat" (list (callInstr "stat32" (ty/tyI32) "fstat" (list "fd32" "st")) (fileWiden "statRes" "stat32") (primInstr "statFailed" (ty/tyI1) "neInt" (list "statRes" "zero")))
          (fileBr "statFailed" "statErr" "statOk"))
        (fileRet "statErr" (list (fileErrno "statErr.e") (fileClose "statErr.close" "fd32") (freeInstr "statErr.free" "st")
                                 (fileCall "statErr.v" (ty/tyVal) "fileSafePathErr" (list "statErr.e"))) "statErr.v")
        (block "statOk"
          (listAppend (fileModeInstrs "m" k "st")
            (list (int64Const "ifreg" (fileK k "S_IFREG")) (fileEq "isReg" "m.fmt" "ifreg")
                  (int64Const "sizeOff" (fileK k "stat.st_size")) (primInstr "size" (ty/tyI64) "rawLoadI64" (list "st" "sizeOff"))
                  (freeInstr "statOk.free" "st") (int64Const "minCap" 4096) (primInstr "sizeBig" (ty/tyI1) "gtInt" (list "size" "minCap"))))
          (fileBr "isReg" "sizing" "notReg"))
        (block "notReg" (cons (fileClose "notReg.close" "fd32") (fileErrVal pool "notReg.v" "ERR_PATH_TYPE")) (ty/termReturn "notReg.v"))
        (block "sizing" (list) (fileBr "sizeBig" "capSize" "capMin"))
        (block "capSize" (list) (fileJump "alloc" (list "size")))
        (block "capMin" (list) (fileJump "alloc" (list "minCap")))
        (ty/ssaBlock "alloc" (list (ty/ssaParam "cap0" (ty/tyI64)))
          (list (callInstr "buf0" (ty/tyPtr) "malloc" (list "cap0")) (primInstr "buf0Null" (ty/tyI1) "rawPtrIsNull" (list "buf0"))
                (primInstr "buf0At" (ty/tyI64) "rawPtrToInt" (list "buf0")))
          (ty/termBranch "buf0Null" (edgeTo "bufNoMem") (ty/ssaEdge "loop" (list "buf0At" "cap0" "zero"))))
        (block "bufNoMem" (cons (fileClose "bufNoMem.close" "fd32") (fileErrVal pool "bufNoMem.v" "io:12")) (ty/termReturn "bufNoMem.v"))
        (ty/ssaBlock "loop" (list (ty/ssaParam "bufAt" (ty/tyI64)) (ty/ssaParam "cap" (ty/tyI64)) (ty/ssaParam "len" (ty/tyI64)))
          (list (primInstr "buf" (ty/tyPtr) "rawIntToPtr" (list "bufAt")) (fileEq "full" "len" "cap"))
          (fileBr "full" "grow" "rd"))
        (block "grow" (list (int64Const "halfMax" 4611686018427387903) (primInstr "tooBig" (ty/tyI1) "gtInt" (list "cap" "halfMax")))
          (fileBr "tooBig" "growNoMem" "regrow"))
        (block "growNoMem" (cons (freeInstr "growNoMem.free" "buf") (cons (fileClose "growNoMem.close" "fd32") (fileErrVal pool "growNoMem.v" "io:12"))) (ty/termReturn "growNoMem.v"))
        (block "regrow" (list (int64Const "two" 2) (primInstr "next" (ty/tyI64) "mulInt" (list "cap" "two"))
                              (callInstr "grown" (ty/tyPtr) "realloc" (list "buf" "next")) (primInstr "grownNull" (ty/tyI1) "rawPtrIsNull" (list "grown")))
          (fileBr "grownNull" "reallocFail" "regrown"))
        (block "reallocFail" (cons (freeInstr "reallocFail.free" "buf") (cons (fileClose "reallocFail.close" "fd32") (fileErrVal pool "reallocFail.v" "io:12"))) (ty/termReturn "reallocFail.v"))
        (block "regrown" (list (primInstr "grownAt" (ty/tyI64) "rawPtrToInt" (list "grown"))) (fileJump "loop" (list "grownAt" "next" "len")))
        (block "rd"
          (list (primInstr "atI" (ty/tyI64) "rawAddI64" (list "bufAt" "len")) (primInstr "at" (ty/tyPtr) "rawIntToPtr" (list "atI"))
                (primInstr "room" (ty/tyI64) "subInt" (list "cap" "len"))
                (callInstr "got" (ty/tyI64) "read" (list "fd32" "at" "room")) (primInstr "gotNeg" (ty/tyI1) "ltInt" (list "got" "zero")))
          (fileBr "gotNeg" "rdErr" "rdSome"))
        (block "rdErr" (list (fileErrno "rdErr.e") (int64Const "eintr" (fileK k "EINTR")) (fileEq "rdErr.intr" "rdErr.e" "eintr"))
          (ty/termBranch "rdErr.intr" (ty/ssaEdge "loop" (list "bufAt" "cap" "len")) (edgeTo "rdFail")))
        (fileRet "rdFail" (list (freeInstr "rdFail.free" "buf") (fileClose "rdFail.close" "fd32") (fileCall "rdFail.v" (ty/tyVal) "fileSafePathErr" (list "rdErr.e"))) "rdFail.v")
        (block "rdSome" (list (fileEq "eof" "got" "zero")) (fileBr "eof" "eofB" "adv"))
        (block "adv" (list (primInstr "lenNext" (ty/tyI64) "addInt" (list "len" "got"))) (fileJump "loop" (list "bufAt" "cap" "lenNext")))
        (block "eofB" (list (fileClose "closed32" "fd32") (fileWiden "closed" "closed32") (primInstr "closeFailed" (ty/tyI1) "neInt" (list "closed" "zero")))
          (fileBr "closeFailed" "closeErr" "fin"))
        (fileRet "closeErr" (list (fileErrno "closeErr.e") (freeInstr "closeErr.free" "buf") (fileCall "closeErr.v" (ty/tyVal) "fileSafePathErr" (list "closeErr.e"))) "closeErr.v")
        (fileRet "fin" (list (callInstr "text" (ty/tyVal) "mkStr" (list "buf" "len")) (freeInstr "fin.free" "buf") (constructResult "fin.v" "ok" "text")) "fin.v"))))

fn fileWriteAtFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (let [(failJoin (fn [(label String) (cleanup (List ty/SsaInstr))] -> ty/SsaBlock
                    (ty/ssaBlock label (list (ty/ssaParam (str label ".ev") (ty/tyVal))) cleanup (ty/termReturn (str label ".ev")))))
        (errnoTo (fn [(label String) (target String)] -> ty/SsaBlock
                   (block label (list (fileErrno (str label ".e")) (fileCall (str label ".v") (ty/tyVal) "fileSafePathErr" (list (str label ".e"))))
                     (fileJump target (list (str label ".v"))))))
        (eintrRetry (fn [(label String) (retry String) (fail String)] -> ty/SsaBlock
                      (block label (list (fileErrno (str label ".e")) (int64Const (str label ".eintr") (fileK k "EINTR")) (fileEq (str label ".intr") (str label ".e") (str label ".eintr")))
                        (fileBr (str label ".intr") retry fail))))
        (failWith (fn [(label String) (from String) (target String)] -> ty/SsaBlock
                    (block label (list (fileCall (str label ".v") (ty/tyVal) "fileSafePathErr" (list (str from ".e")))) (fileJump target (list (str label ".v"))))))
        (unlinkTemp (fn [(prefix String)] -> (List ty/SsaInstr)
                      (list (int32Const (str prefix ".flags") 0) (callInstr (str prefix ".unlinked") (ty/tyI32) "unlinkat" (list "d32" "tc" (str prefix ".flags")))
                            (freeInstr (str prefix ".freeTemp") "tc"))))
        (release (fn [(prefix String)] -> (List ty/SsaInstr)
                   (list (fileClose (str prefix ".closeDir") "d32") (freeInstr (str prefix ".freeLeaf") "lc") (freeInstr (str prefix ".freeSt") "st"))))]
    (ty/ssaFunction (fileW "fileWriteAt") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal)) (ty/ssaParam "c" (ty/tyVal))) (ty/tyVal)
      (listAppend (fileAtBlocks pool (list "a" "b" "c") (none))
        (list
          (block "haveDir"
            (listAppend (fileHaveDirInstrs)
              (list (int64Const "stSize" (fileK k "stat.size")) (callInstr "st" (ty/tyPtr) "malloc" (list "stSize")) (primInstr "stNull" (ty/tyI1) "rawPtrIsNull" (list "st"))))
            (fileBr "stNull" "stNoMem" "stat1"))
          (block "stNoMem" (cons (fileClose "stNoMem.close" "d32") (cons (freeInstr "stNoMem.free" "lc") (fileErrVal pool "stNoMem.v" "io:12"))) (ty/termReturn "stNoMem.v"))
          (block "stat1" (list (int32Const "noFollow" (fileK k "AT_SYMLINK_NOFOLLOW")) (callInstr "s1_32" (ty/tyI32) "fstatat" (list "d32" "lc" "st" "noFollow"))
                               (fileWiden "s1" "s1_32") (primInstr "s1Failed" (ty/tyI1) "neInt" (list "s1" "zero")))
            (fileBr "s1Failed" "stat1Err" "kind1"))
          (errnoTo "stat1Err" "fail1")
          (block "kind1"
            (listAppend (fileModeInstrs "m1" k "st")
              (list (int64Const "iflnk" (fileK k "S_IFLNK")) (int64Const "ifreg" (fileK k "S_IFREG")) (fileEq "isLink1" "m1.fmt" "iflnk")))
            (fileBr "isLink1" "link1" "reg1"))
          (fileErrTextJump pool "link1" "ERR_PATH_SYMLINK" "fail1")
          (block "reg1" (list (fileEq "isReg1" "m1.fmt" "ifreg")) (fileBr "isReg1" "seqStart" "type1"))
          (fileErrTextJump pool "type1" "ERR_PATH_TYPE" "fail1")
          (block "seqStart"
            (list (int64Const "perm777" 511) (primInstr "perm" (ty/tyI64) "rawAndI64" (list "m1.mode" "perm777")) (fileNarrow "perm32" "perm")
                  (int64Const "perm7777" 4095) (primInstr "fullPerm" (ty/tyI64) "rawAndI64" (list "m1.mode" "perm7777")) (fileNarrow "fullPerm32" "fullPerm")
                  (fileVal "cellBox" (ty/opGlobal (fileW "fileTempSeq"))) (ty/ssaInstr "cellAt" (ty/tyI64) (ty/opUnbox "cellBox"))
                  (fileEq "noCell" "cellAt" "zero"))
            (fileBr "noCell" "cellMissing" "seqCell"))
          (fileErrTextJump pool "cellMissing" "io:12" "fail1")
          (block "seqCell" (list (primInstr "cell" (ty/tyPtr) "rawIntToPtr" (list "cellAt")) (int64Const "one" 1) (int64Const "attempts" 128)
                                 (int64Const "nameCap" (+ (fileK k "NAME_MAX") 1)))
            (fileJump "attempt" (list "zero")))
          (ty/ssaBlock "attempt" (list (ty/ssaParam "tries" (ty/tyI64))) (list (primInstr "exhausted" (ty/tyI1) "geInt" (list "tries" "attempts")))
            (fileBr "exhausted" "allTaken" "nextName"))
          (fileErrTextJump pool "allTaken" "io:17" "fail1")
          (block "nextName"
            (list (primInstr "lastSeq" (ty/tyI64) "rawLoadI64" (list "cell" "zero")) (primInstr "seq" (ty/tyI64) "rawAddI64" (list "lastSeq" "one"))
                  (primInstr "seqStored" (ty/tyI1) "rawStoreI64" (list "cell" "zero" "seq"))
                  (callInstr "pid32" (ty/tyI32) "getpid" (list)) (fileWiden "pid" "pid32")
                  (filePool pool "namePrefix" ".asl-write-") (filePool pool "dash" "-")
                  (entryInstr "pidText" (ty/tyVal) "stringFromInt64" (list "pid")) (entryInstr "seqText" (ty/tyVal) "stringFromInt64" (list "seq"))
                  (entryInstr "name1" (ty/tyVal) "stringConcat" (list "namePrefix" "pidText")) (entryInstr "name2" (ty/tyVal) "stringConcat" (list "name1" "dash"))
                  (entryInstr "name" (ty/tyVal) "stringConcat" (list "name2" "seqText")) (entryInstr "nameLen" (ty/tyI64) "stringLength" (list "name"))
                  (primInstr "nameLong" (ty/tyI1) "geInt" (list "nameLen" "nameCap")))
            (fileBr "nameLong" "nameTooLong" "tryTemp"))
          (fileErrTextJump pool "nameTooLong" "io:36" "fail1")
          (block "tryTemp"
            (listAppend (fileCStr "tc" "name")
              (listAppend (fileOr "tempFlags" k (list "O_WRONLY" "O_CREAT" "O_EXCL" "O_NOFOLLOW" "O_CLOEXEC"))
                (list (callInstr "fd32" (ty/tyI32) "openat" (list "d32" "tc" "tempFlags" "perm32")) (fileWiden "fd" "fd32")
                      (primInstr "tempFailed" (ty/tyI1) "ltInt" (list "fd" "zero")))))
            (fileBr "tempFailed" "tempErr" "created"))
          (block "tempErr" (list (fileErrno "tempErr.e") (freeInstr "tempErr.free" "tc") (int64Const "eexist" (fileK k "EEXIST")) (fileEq "taken" "tempErr.e" "eexist"))
            (fileBr "taken" "retryName" "tempFail"))
          (block "retryName" (list (primInstr "triesNext" (ty/tyI64) "rawAddI64" (list "tries" "one"))) (fileJump "attempt" (list "triesNext")))
          (failWith "tempFail" "tempErr" "fail1")
          (failJoin "fail1" (list (fileClose "fail1.closeDir" "d32") (freeInstr "fail1.freeLeaf" "lc") (freeInstr "fail1.freeSt" "st")))
          (block "created" (list (callInstr "chmod32" (ty/tyI32) "fchmod" (list "fd32" "fullPerm32")) (fileWiden "chmodRes" "chmod32") (primInstr "chmodFailed" (ty/tyI1) "neInt" (list "chmodRes" "zero")))
            (fileBr "chmodFailed" "chmodErr" "dataPrep"))
          (errnoTo "chmodErr" "fail2")
          (block "dataPrep" (listAppend (fileCStr "dp" "c") (list (entryInstr "dn" (ty/tyI64) "stringLength" (list "c")) (primInstr "dAt" (ty/tyI64) "rawPtrToInt" (list "dp"))))
            (fileJump "wloop" (list "zero")))
          (ty/ssaBlock "wloop" (list (ty/ssaParam "done" (ty/tyI64))) (list (primInstr "more" (ty/tyI1) "ltInt" (list "done" "dn")))
            (fileBr "more" "wr" "written"))
          (block "wr"
            (list (primInstr "atI" (ty/tyI64) "rawAddI64" (list "dAt" "done")) (primInstr "at" (ty/tyPtr) "rawIntToPtr" (list "atI"))
                  (primInstr "rem" (ty/tyI64) "subInt" (list "dn" "done")) (callInstr "w" (ty/tyI64) "write" (list "fd32" "at" "rem"))
                  (primInstr "wNeg" (ty/tyI1) "ltInt" (list "w" "zero")))
            (fileBr "wNeg" "wErr" "wAdv"))
          (block "wErr" (list (fileErrno "wErr.e") (int64Const "wErr.eintr" (fileK k "EINTR")) (fileEq "wErr.intr" "wErr.e" "wErr.eintr"))
            (ty/termBranch "wErr.intr" (ty/ssaEdge "wloop" (list "done")) (edgeTo "wFail")))
          (block "wFail" (list (freeInstr "wFail.free" "dp") (fileCall "wFail.v" (ty/tyVal) "fileSafePathErr" (list "wErr.e"))) (fileJump "fail2" (list "wFail.v")))
          (block "wAdv" (list (primInstr "doneNext" (ty/tyI64) "addInt" (list "done" "w"))) (fileJump "wloop" (list "doneNext")))
          (block "written" (list (freeInstr "written.free" "dp")) (fileJump "sync" (list)))
          (block "sync" (list (callInstr "sync32" (ty/tyI32) "fsync" (list "fd32")) (fileWiden "syncRes" "sync32") (primInstr "syncFailed" (ty/tyI1) "neInt" (list "syncRes" "zero")))
            (fileBr "syncFailed" "syncErr" "closeTemp"))
          (eintrRetry "syncErr" "sync" "syncFail")
          (failWith "syncFail" "syncErr" "fail2")
          (failJoin "fail2" (listAppend (list (fileClose "fail2.closeFd" "fd32")) (listAppend (unlinkTemp "fail2") (release "fail2"))))
          (block "closeTemp" (list (fileClose "closeTemp32" "fd32") (fileWiden "closeTempRes" "closeTemp32") (primInstr "closeTempFailed" (ty/tyI1) "neInt" (list "closeTempRes" "zero")))
            (fileBr "closeTempFailed" "closeTempErr" "stat2"))
          (errnoTo "closeTempErr" "fail3")
          (block "stat2" (list (callInstr "s2_32" (ty/tyI32) "fstatat" (list "d32" "lc" "st" "noFollow")) (fileWiden "s2" "s2_32") (primInstr "s2Failed" (ty/tyI1) "neInt" (list "s2" "zero")))
            (fileBr "s2Failed" "stat2Err" "kind2"))
          (errnoTo "stat2Err" "fail3")
          (block "kind2" (listAppend (fileModeInstrs "m2" k "st") (list (fileEq "isLink2" "m2.fmt" "iflnk"))) (fileBr "isLink2" "link2" "reg2"))
          (fileErrTextJump pool "link2" "ERR_PATH_SYMLINK" "fail3")
          (block "reg2" (list (fileEq "isReg2" "m2.fmt" "ifreg")) (fileBr "isReg2" "rename" "type2"))
          (fileErrTextJump pool "type2" "ERR_PATH_TYPE" "fail3")
          (block "rename" (list (callInstr "ren32" (ty/tyI32) "renameat" (list "d32" "tc" "d32" "lc")) (fileWiden "renRes" "ren32") (primInstr "renFailed" (ty/tyI1) "neInt" (list "renRes" "zero")))
            (fileBr "renFailed" "renameErr" "renamed"))
          (errnoTo "renameErr" "fail3")
          (failJoin "fail3" (listAppend (unlinkTemp "fail3") (release "fail3")))
          (block "renamed" (list (freeInstr "renamed.freeTemp" "tc") (freeInstr "renamed.freeLeaf" "lc") (freeInstr "renamed.freeSt" "st")) (fileJump "dirSync" (list)))
          (block "dirSync" (list (callInstr "dsync32" (ty/tyI32) "fsync" (list "d32")) (fileWiden "dsyncRes" "dsync32") (primInstr "dsyncFailed" (ty/tyI1) "neInt" (list "dsyncRes" "zero")))
            (fileBr "dsyncFailed" "dirSyncErr" "dirClose"))
          (eintrRetry "dirSyncErr" "dirSync" "dirSyncFail")
          (fileRet "dirSyncFail" (list (fileClose "dirSyncFail.close" "d32") (fileCall "dirSyncFail.v" (ty/tyVal) "fileSafePathErr" (list "dirSyncErr.e"))) "dirSyncFail.v")
          (block "dirClose" (list (fileClose "dclose32" "d32") (fileWiden "dcloseRes" "dclose32") (primInstr "dcloseFailed" (ty/tyI1) "neInt" (list "dcloseRes" "zero")))
            (fileBr "dcloseFailed" "dirCloseErr" "done"))
          (fileRet "dirCloseErr" (list (fileErrno "dirCloseErr.e") (fileCall "dirCloseErr.v" (ty/tyVal) "fileSafePathErr" (list "dirCloseErr.e"))) "dirCloseErr.v")
          (fileRet "done" (list (fileVal "unit" (ty/opConst (ty/constUnit))) (constructResult "done.v" "ok" "unit")) "done.v")))))

fn fileEnvGetFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "envGet") (list) (list (ty/ssaParam "name" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isName" (ty/tyI1) "isStr" (list "name"))) (fileBr "isName" "checkNul" "none"))
      (block "checkNul" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "name"))) (fileBr "clean" "lookup" "none"))
      (block "lookup" (listAppend (stringToPtrInstrs "p" "name")
                     (list (callInstr "found" (ty/tyPtr) "getenv" (list "p")) (freeInstr "free.p" "p")
                           (primInstr "isNull" (ty/tyI1) "rawPtrIsNull" (list "found"))))
        (fileBr "isNull" "none" "some"))
      (fileRet "none" (list (ty/ssaInstr "noneV" (ty/tyVal) (ty/opConstruct "Option" "none" (list)))) "noneV")
      (fileRet "some" (list (callInstr "len" (ty/tyI64) "strlen" (list "found"))
                             (callInstr "text" (ty/tyVal) "mkStr" (list "found" "len"))
                             (ty/ssaInstr "someV" (ty/tyVal) (ty/opConstruct "Option" "some" (list "text")))) "someV")))

fn fileGetHomeDirFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "getHomeDir") (list) (list) (ty/tyVal)
    (list
      (block "entry" (listAppend (list (filePool pool "key" "HOME"))
                       (listAppend (fileCStr "keyp" "key")
                         (list (callInstr "home" (ty/tyPtr) "getenv" (list "keyp"))
                               (freeInstr "freekey" "keyp")
                               (primInstr "homeNull" (ty/tyI1) "rawPtrIsNull" (list "home")))))
        (fileBr "homeNull" "fallback" "homeLength"))
      (block "homeLength" (list (callInstr "homeLen" (ty/tyI64) "strlen" (list "home"))
                                 (int64Const "zero.home" 0) (fileEq "homeEmpty" "homeLen" "zero.home"))
        (fileBr "homeEmpty" "fallback" "homeOk"))
      (fileRet "homeOk" (list (callInstr "homeText" (ty/tyVal) "mkStr" (list "home" "homeLen"))
                               (constructResult "homeResult" "ok" "homeText")) "homeResult")
      (block "fallback" (list (callInstr "uid" (ty/tyI32) "getuid" (list))
                               (callInstr "pw" (ty/tyPtr) "getpwuid" (list "uid"))
                               (primInstr "pwNull" (ty/tyI1) "rawPtrIsNull" (list "pw")))
        (fileBr "pwNull" "noHome" "passwdDir"))
      (block "passwdDir" (list (int64Const "pwDirOff" (fileK k "passwd.pw_dir"))
                                (primInstr "pwDirInt" (ty/tyI64) "rawLoadI64" (list "pw" "pwDirOff"))
                                (primInstr "pwDir" (ty/tyPtr) "rawIntToPtr" (list "pwDirInt"))
                                (primInstr "pwDirNull" (ty/tyI1) "rawPtrIsNull" (list "pwDir")))
        (fileBr "pwDirNull" "noHome" "pwLength"))
      (block "pwLength" (list (callInstr "pwLen" (ty/tyI64) "strlen" (list "pwDir"))
                               (int64Const "zero.pw" 0) (fileEq "pwEmpty" "pwLen" "zero.pw"))
        (fileBr "pwEmpty" "noHome" "pwOk"))
      (fileRet "pwOk" (list (callInstr "pwText" (ty/tyVal) "mkStr" (list "pwDir" "pwLen"))
                             (constructResult "pwResult" "ok" "pwText")) "pwResult")
      (fileRet "noHome" (list (filePool pool "kind" "getHomeDir") (filePool pool "dash" "-")
                               (filePool pool "reason" "cannot determine home directory")
                               (fileCall "noHomeResult" (ty/tyVal) "fileFormatError" (list "kind" "dash" "reason"))) "noHomeResult")))

fn fileReadWholeFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction "sysReadWhole" (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (listAppend (stringToPtrInstrs "p" "path")
                       (listAppend (fileOr "flags" k (list "O_RDONLY"))
                         (list (callInstr "fd" (ty/tyI32) "open" (list "p" "flags"))
                               (primInstr "fd64" (ty/tyI64) "rawWidenI32" (list "fd"))
                               (int64Const "zero" 0) (primInstr "fdFailed" (ty/tyI1) "ltInt" (list "fd64" "zero")))))
        (fileBr "fdFailed" "openError" "read"))
      (block "openError" (list (callInstr "errno" (ty/tyI64) "sysErrnoValue" (list))
                                (freeInstr "openFree" "p") (boxInstr "errnoBox" "errno")
                                (constructResult "err" "err" "errnoBox")) (ty/termReturn "err"))
      (block "read" (list (freeInstr "pathFree" "p")
                           (callInstr "raw" (ty/tyVal) (fileW "fileSlurp") (list "fd"))
                           (callInstr "closed" (ty/tyI32) "close" (list "fd"))) (ty/termReturn "raw"))))

fn fileReadStringFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileReadString") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "call" "badType"))
      (fileStrTrapBlock pool "badType" "fileReadString" "path")
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysReadWhole" (list "path"))) (fileResSwitch "raw" "done" "failed"))
      (fileRet "done" (list) "raw")
      (fileErrnoErrBlock "failed" "raw" "path")))

fn fileReadBytesFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileReadBytes") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "call" "badType"))
      (fileStrTrapBlock pool "badType" "fileReadBytes" "path")
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysReadWhole" (list "path"))) (fileResSwitch "raw" "done" "failed"))
      (fileRet "done" (list (ty/ssaInstr "text" (ty/tyVal) (ty/opVariantField "raw" 0))
                            (entryInstr "bytes" (ty/tyVal) "stringToBytes" (list "text"))
                            (constructResult "okv" "ok" "bytes")) "okv")
      (fileErrnoErrBlock "failed" "raw" "path")))

fn fileReadRangeFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileReadRange") (list)
    (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "offset" (ty/tyVal)) (ty/ssaParam "length" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "pathText" (ty/tyI1) "isStr" (list "path"))
                            (fileCall "offsetOpt" (ty/tyVal) "intOf" (list "offset"))
                            (fileCall "lengthOpt" (ty/tyVal) "intOf" (list "length")))
        (fileBr "pathText" "offsetCheck" "badArgs"))
      (fileBadArgBlock pool "badArgs" "fileReadRange" (none))
      (block "offsetCheck" (list) (fileOptSwitch "offsetOpt" "offsetOk" "badArgs"))
      (block "offsetOk" (list (ty/ssaInstr "offset.box" (ty/tyVal) (ty/opVariantField "offsetOpt" 0))
                              (ty/ssaInstr "offset.i" (ty/tyI64) (ty/opUnbox "offset.box")))
        (fileOptSwitch "lengthOpt" "lengthOk" "badArgs"))
      (block "lengthOk" (list (ty/ssaInstr "length.box" (ty/tyVal) (ty/opVariantField "lengthOpt" 0))
                              (ty/ssaInstr "length.i" (ty/tyI64) (ty/opUnbox "length.box"))
                              (int64Const "zero" 0) (primInstr "offsetNeg" (ty/tyI1) "ltInt" (list "offset.i" "zero")))
        (fileBr "offsetNeg" "negOffset" "lengthNegCheck"))
      (fileRet "negOffset" (list (filePool pool "negOffset.who" "fileReadRange") (filePool pool "negOffset.reason" "negative offset")
                                 (fileCall "negOffset.v" (ty/tyVal) "fileFormatError" (list "negOffset.who" "path" "negOffset.reason"))) "negOffset.v")
      (block "lengthNegCheck" (list (primInstr "lengthNeg" (ty/tyI1) "ltInt" (list "length.i" "zero")))
        (fileBr "lengthNeg" "negLength" "capCheck"))
      (fileRet "negLength" (list (filePool pool "negLength.who" "fileReadRange") (filePool pool "negLength.reason" "negative length")
                                 (fileCall "negLength.v" (ty/tyVal) "fileFormatError" (list "negLength.who" "path" "negLength.reason"))) "negLength.v")
      (block "capCheck" (list (int64Const "maxLen" 1073741824) (primInstr "tooBig" (ty/tyI1) "gtInt" (list "length.i" "maxLen")))
        (fileBr "tooBig" "limit" "open"))
      (fileRet "limit" (list (filePool pool "limit.kind" "lengthLimitExceeded") (filePool pool "limit.reason" "length exceeds 1 GiB cap")
                             (fileCall "limit.v" (ty/tyVal) "fileFormatError" (list "limit.kind" "path" "limit.reason"))) "limit.v")
      (block "open" (listAppend (fileCStr "p" "path")
                      (listAppend (fileOr "oflags" k (list "O_RDONLY"))
                        (list (callInstr "fd32" (ty/tyI32) "open" (list "p" "oflags"))
                              (fileWiden "fd" "fd32")
                              (primInstr "fdFailed" (ty/tyI1) "ltInt" (list "fd" "zero")))))
        (fileBr "fdFailed" "openErr" "read"))
      (fileRet "openErr" (list (fileErrno "openErr.e") (freeInstr "openErr.free" "p")
                               (fileCall "openErr.v" (ty/tyVal) "fileIoError" (list "openErr.e" "path"))) "openErr.v")
      (block "read" (list (freeInstr "read.free" "p")
                          (fileCall "result" (ty/tyVal) "fileReadRangeFd" (list "path" "fd32" "offset.i" "length.i")))
        (ty/termReturn "result"))))

fn fileReadRangeFdFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileReadRangeFd") (list)
    (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "fd" (ty/tyI32)) (ty/ssaParam "offset" (ty/tyI64)) (ty/ssaParam "length" (ty/tyI64))) (ty/tyVal)
    (list
      (block "entry" (list (int64Const "stSize" (fileK k "stat.size")) (int64Const "zero" 0) (int64Const "one" 1)
                           (callInstr "st" (ty/tyPtr) "malloc" (list "stSize"))
                           (primInstr "stNull" (ty/tyI1) "rawPtrIsNull" (list "st")))
        (fileBr "stNull" "noMem" "fstat"))
      (fileRet "noMem" (list (fileClose "noMem.close" "fd") (filePool pool "noMem.who" "fileReadRange") (filePool pool "noMem.reason" "out of memory")
                             (fileCall "noMem.v" (ty/tyVal) "fileFormatError" (list "noMem.who" "path" "noMem.reason"))) "noMem.v")
      (block "fstat" (list (callInstr "fstat32" (ty/tyI32) "fstat" (list "fd" "st")) (fileWiden "fstatRes" "fstat32")
                           (primInstr "fstatFailed" (ty/tyI1) "neInt" (list "fstatRes" "zero")))
        (fileBr "fstatFailed" "fstatErr" "classify"))
      (fileRet "fstatErr" (list (fileErrno "fstatErr.e") (freeInstr "fstatErr.free" "st") (fileClose "fstatErr.close" "fd")
                                (fileCall "fstatErr.v" (ty/tyVal) "fileIoError" (list "fstatErr.e" "path"))) "fstatErr.v")
      (block "classify" (listAppend (fileModeInstrs "m" k "st")
                          (list (int64Const "sizeOff" (fileK k "stat.st_size"))
                                (primInstr "fileSize" (ty/tyI64) "rawLoadI64" (list "st" "sizeOff"))
                                (freeInstr "classify.free" "st")
                                (int64Const "ifreg" (fileK k "S_IFREG")) (fileEq "regular" "m.fmt" "ifreg")))
        (fileBr "regular" "regularLen" "seekCur"))
      (block "regularLen" (list (primInstr "pastEnd" (ty/tyI1) "leInt" (list "fileSize" "offset")))
        (ty/termBranch "pastEnd" (ty/ssaEdge "sized" (list "zero" "regular")) (edgeTo "available")))
      (block "available" (list (primInstr "avail" (ty/tyI64) "subInt" (list "fileSize" "offset"))
                               (primInstr "clamp" (ty/tyI1) "gtInt" (list "length" "avail")))
        (ty/termBranch "clamp" (ty/ssaEdge "sized" (list "avail" "regular")) (ty/ssaEdge "sized" (list "length" "regular"))))
      (block "seekCur" (list (int32Const "seekCur.whence" (fileK k "SEEK_CUR"))
                             (callInstr "seekCur.r" (ty/tyI64) "lseek" (list "fd" "zero" "seekCur.whence"))
                             (primInstr "seekCur.failed" (ty/tyI1) "ltInt" (list "seekCur.r" "zero"))
                             (primInstr "positive" (ty/tyI1) "gtInt" (list "offset" "zero")))
        (fileBr "seekCur.failed" "seekCurErr" "seekable"))
      (block "seekCurErr" (list (fileErrno "seekCurErr.e") (int64Const "espipe" (fileK k "ESPIPE"))
                                (fileEq "pipe" "seekCurErr.e" "espipe"))
        (fileBr "pipe" "pipeOffset" "seekable"))
      (block "pipeOffset" (list) (ty/termBranch "positive" (edgeTo "nonSeekable") (ty/ssaEdge "sized" (list "length" "regular"))))
      (block "seekable" (list) (ty/termBranch "positive" (edgeTo "seekSet") (ty/ssaEdge "sized" (list "length" "regular"))))
      (block "seekSet" (list (int32Const "seekSet.whence" (fileK k "SEEK_SET"))
                             (callInstr "seekSet.r" (ty/tyI64) "lseek" (list "fd" "offset" "seekSet.whence"))
                             (primInstr "seekSet.failed" (ty/tyI1) "ltInt" (list "seekSet.r" "zero")))
        (ty/termBranch "seekSet.failed" (edgeTo "seekSetErr") (ty/ssaEdge "sized" (list "length" "regular"))))
      (block "seekSetErr" (list (fileErrno "seekSetErr.e") (fileClose "seekSetErr.close" "fd")
                                (int64Const "espipe2" (fileK k "ESPIPE")) (fileEq "pipe2" "seekSetErr.e" "espipe2"))
        (fileBr "pipe2" "nonSeekableClosed" "seekSetIo"))
      (fileRet "seekSetIo" (list (fileCall "seekSetIo.v" (ty/tyVal) "fileIoError" (list "seekSetErr.e" "path"))) "seekSetIo.v")
      (block "nonSeekable" (list (fileClose "nonSeekable.close" "fd")) (fileJump "nonSeekableClosed" (list)))
      (fileRet "nonSeekableClosed" (list (filePool pool "nonSeek.kind" "nonSeekable") (filePool pool "nonSeek.reason" "positive offset on non-seekable file")
                                         (fileCall "nonSeek.v" (ty/tyVal) "fileFormatError" (list "nonSeek.kind" "path" "nonSeek.reason"))) "nonSeek.v")
      (ty/ssaBlock "sized" (list (ty/ssaParam "want" (ty/tyI64)) (ty/ssaParam "isReg" (ty/tyI1)))
        (list (fileEq "empty" "want" "zero"))
        (fileBr "empty" "emptyBytes" "alloc"))
      (fileRet "emptyBytes" (list (fileClose "emptyBytes.close" "fd") (filePool pool "emptyBytes.text" "")
                                  (entryInstr "emptyBytes.bytes" (ty/tyVal) "stringToBytes" (list "emptyBytes.text"))
                                  (constructResult "emptyBytes.v" "ok" "emptyBytes.bytes")) "emptyBytes.v")
      (block "alloc" (list (primInstr "bufSize" (ty/tyI64) "addInt" (list "want" "one"))
                           (callInstr "buf" (ty/tyPtr) "malloc" (list "bufSize"))
                           (primInstr "bufNull" (ty/tyI1) "rawPtrIsNull" (list "buf")))
        (fileBr "bufNull" "bufNoMem" "start"))
      (fileRet "bufNoMem" (list (fileClose "bufNoMem.close" "fd") (filePool pool "bufNoMem.who" "fileReadRange") (filePool pool "bufNoMem.reason" "out of memory")
                                (fileCall "bufNoMem.v" (ty/tyVal) "fileFormatError" (list "bufNoMem.who" "path" "bufNoMem.reason"))) "bufNoMem.v")
      (block "start" (list (primInstr "base" (ty/tyI64) "rawPtrToInt" (list "buf"))) (fileJump "loop" (list "zero")))
      (ty/ssaBlock "loop" (list (ty/ssaParam "total" (ty/tyI64)))
        (list (primInstr "full" (ty/tyI1) "geInt" (list "total" "want")))
        (fileBr "full" "done" "readMore"))
      (block "readMore" (list (primInstr "atI" (ty/tyI64) "rawAddI64" (list "base" "total")) (primInstr "at" (ty/tyPtr) "rawIntToPtr" (list "atI"))
                              (primInstr "room" (ty/tyI64) "subInt" (list "want" "total")))
        (fileBr "isReg" "pread" "plainRead"))
      (block "pread" (list (primInstr "preadAt" (ty/tyI64) "addInt" (list "offset" "total"))
                           (callInstr "preadGot" (ty/tyI64) "pread" (list "fd" "at" "room" "preadAt")))
        (fileJump "got" (list "preadGot")))
      (block "plainRead" (list (callInstr "readGot" (ty/tyI64) "read" (list "fd" "at" "room"))) (fileJump "got" (list "readGot")))
      (ty/ssaBlock "got" (list (ty/ssaParam "n" (ty/tyI64)))
        (list (primInstr "nNeg" (ty/tyI1) "ltInt" (list "n" "zero")) (fileEq "nZero" "n" "zero"))
        (fileBr "nNeg" "readErr" "gotSome"))
      (block "gotSome" (list (primInstr "next" (ty/tyI64) "addInt" (list "total" "n")))
        (ty/termBranch "nZero" (edgeTo "done") (ty/ssaEdge "loop" (list "next"))))
      (block "readErr" (list (fileErrno "readErr.e") (int64Const "eintr" (fileK k "EINTR")) (fileEq "intr" "readErr.e" "eintr"))
        (ty/termBranch "intr" (ty/ssaEdge "loop" (list "total")) (edgeTo "readFail")))
      (fileRet "readFail" (list (freeInstr "readFail.free" "buf") (fileClose "readFail.close" "fd")
                                (fileCall "readFail.v" (ty/tyVal) "fileIoError" (list "readErr.e" "path"))) "readFail.v")
      (fileRet "done" (list (fileClose "done.close" "fd")
                            (callInstr "bytes" (ty/tyVal) "mkBytes" (list "buf" "total"))
                            (freeInstr "done.free" "buf")
                            (constructResult "done.v" "ok" "bytes")) "done.v")))

fn fileWriteCoreFn k: (Map String Int64) pool: (Map String Int64) name: String flags: (List String) exclusive: Bool -> ty/SsaFunction
  (let [(failCleanup (fn [(prefix String)] -> (List ty/SsaInstr)
                       (listAppend (if exclusive (list (callInstr (str prefix ".unlink") (ty/tyI32) "unlink" (list "p"))) (list))
                         (list (freeInstr (str prefix ".freeP") "p") (freeInstr (str prefix ".freeD") "dp")))))]
    (ty/ssaFunction (fileW name) (list) (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "content" (ty/tyVal))) (ty/tyVal)
      (listAppend
        (if exclusive
          (list (block "entry" (list (fileCall "pathText" (ty/tyI1) "isStr" (list "path"))) (fileBr "pathText" "nulCheck" "badPath"))
                (fileBadArgBlock pool "badPath" name (none))
                (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "content" "nulPath"))
                (fileRet "nulPath" (list (int64Const "einval" (fileK k "EINVAL")) (fileCall "nulPath.v" (ty/tyVal) "fileIoError" (list "einval" "path"))) "nulPath.v")
                (fileBadArgBlock pool "badContent" name (some "path")))
          (list (block "entry" (list (fileCall "pathText" (ty/tyI1) "isStr" (list "path"))) (fileBr "pathText" "content" "badPath"))
                (fileStrTrapBlock pool "badPath" name "path")
                (fileRet "badContent" (list (filePool pool "badContent.prefix" "fileWrite expects String or Bytes content, got ")
                                            (fileCall "badContent.v" (ty/tyVal) "fileTypeTrap" (list "badContent.prefix" "content"))) "badContent.v")))
        (list
          (block "content" (list (fileCall "isText" (ty/tyI1) "isStr" (list "content")) (int64Const "zero" 0) (int64Const "one" 1))
            (fileBr "isText" "textData" "notText"))
          (block "textData" (listAppend (fileCStr "tp" "content")
                              (list (entryInstr "tn" (ty/tyI64) "stringLength" (list "content")) (primInstr "tAt" (ty/tyI64) "rawPtrToInt" (list "tp"))))
            (fileJump "open" (list "tAt" "tn")))
          (block "notText" (list (fileCall "isRaw" (ty/tyI1) "isBytes" (list "content"))) (fileBr "isRaw" "rawData" "badContent"))
          (block "rawData" (list (entryInstr "bn" (ty/tyI64) "bytesLength" (list "content")) (primInstr "bSize" (ty/tyI64) "rawAddI64" (list "bn" "one"))
                                 (callInstr "bp" (ty/tyPtr) "malloc" (list "bSize")) (primInstr "bpNull" (ty/tyI1) "rawPtrIsNull" (list "bp")))
            (ty/termBranch "bpNull" (edgeTo "noMem") (ty/ssaEdge "copy" (list "zero"))))
          (fileRet "noMem" (list (filePool pool "noMem.who" name) (filePool pool "noMem.reason" "out of memory")
                                 (fileCall "noMem.v" (ty/tyVal) "fileFormatError" (list "noMem.who" "path" "noMem.reason"))) "noMem.v")
          (ty/ssaBlock "copy" (list (ty/ssaParam "ci" (ty/tyI64))) (list (primInstr "copied" (ty/tyI1) "geInt" (list "ci" "bn"))) (fileBr "copied" "copyDone" "copyByte"))
          (block "copyByte"
            (list (entryInstr "byte" (ty/tyI64) "bytesGet" (list "content" "ci")) (fileNarrow "byte32" "byte")
                  (primInstr "stored" (ty/tyI1) "rawStoreI8" (list "bp" "ci" "byte32")) (primInstr "ciNext" (ty/tyI64) "rawAddI64" (list "ci" "one")))
            (fileJump "copy" (list "ciNext")))
          (block "copyDone" (list (primInstr "bAt" (ty/tyI64) "rawPtrToInt" (list "bp"))) (fileJump "open" (list "bAt" "bn")))
          (ty/ssaBlock "open" (list (ty/ssaParam "dAt" (ty/tyI64)) (ty/ssaParam "dLen" (ty/tyI64)))
            (listAppend (list (primInstr "dp" (ty/tyPtr) "rawIntToPtr" (list "dAt")))
              (listAppend (fileCStr "p" "path")
                (listAppend (fileOr "oflags" k flags)
                  (list (int32Const "perm" 438) (callInstr "fd32" (ty/tyI32) "open" (list "p" "oflags" "perm")) (fileWiden "fd" "fd32")
                        (primInstr "openFailed" (ty/tyI1) "ltInt" (list "fd" "zero"))))))
            (fileBr "openFailed" "openErr" "opened"))
          (fileRet "openErr" (list (fileErrno "openErr.e") (freeInstr "openErr.freeP" "p") (freeInstr "openErr.freeD" "dp")
                                   (fileCall "openErr.v" (ty/tyVal) "fileIoError" (list "openErr.e" "path"))) "openErr.v")
          (block "opened" (list) (fileJump "wloop" (list "zero")))
          (ty/ssaBlock "wloop" (list (ty/ssaParam "off" (ty/tyI64)))
            (list (primInstr "rem" (ty/tyI64) "subInt" (list "dLen" "off")) (primInstr "more" (ty/tyI1) "gtInt" (list "rem" "zero")))
            (ty/termBranch "more" (edgeTo "wr") (ty/ssaEdge "closeIt" (list "zero"))))
          (block "wr"
            (list (primInstr "atI" (ty/tyI64) "rawAddI64" (list "dAt" "off")) (primInstr "at" (ty/tyPtr) "rawIntToPtr" (list "atI"))
                  (callInstr "w" (ty/tyI64) "write" (list "fd32" "at" "rem")) (primInstr "wNeg" (ty/tyI1) "ltInt" (list "w" "zero")))
            (fileBr "wNeg" "wErr" "wSome"))
          (block "wErr" (list (fileErrno "wErr.e") (int64Const "eintr" (fileK k "EINTR")) (fileEq "wErr.intr" "wErr.e" "eintr"))
            (ty/termBranch "wErr.intr" (ty/ssaEdge "wloop" (list "off")) (ty/ssaEdge "closeIt" (list "wErr.e"))))
          (block "wSome" (list (fileEq "wNone" "w" "zero") (int64Const "enospc" (fileK k "ENOSPC")))
            (ty/termBranch "wNone" (ty/ssaEdge "closeIt" (list "enospc")) (edgeTo "wAdv")))
          (block "wAdv" (list (primInstr "offNext" (ty/tyI64) "addInt" (list "off" "w"))) (fileJump "wloop" (list "offNext")))
          (ty/ssaBlock "closeIt" (list (ty/ssaParam "writeErr" (ty/tyI64)))
            (list (fileClose "closed32" "fd32") (fileWiden "closed" "closed32") (primInstr "closeFailed" (ty/tyI1) "neInt" (list "closed" "zero"))
                  (primInstr "wrote" (ty/tyI1) "eqInt" (list "writeErr" "zero")))
            (fileBr "closeFailed" "closeBad" "closeGood"))
          (block "closeBad" (list (fileErrno "closeBad.e"))
            (ty/termBranch "wrote" (ty/ssaEdge "failed" (list "closeBad.e")) (ty/ssaEdge "failed" (list "writeErr"))))
          (block "closeGood" (list) (ty/termBranch "wrote" (edgeTo "done") (ty/ssaEdge "failed" (list "writeErr"))))
          (ty/ssaBlock "failed" (list (ty/ssaParam "e" (ty/tyI64)))
            (listAppend (failCleanup "failed") (list (fileCall "failed.v" (ty/tyVal) "fileIoError" (list "e" "path"))))
            (ty/termReturn "failed.v"))
          (fileRet "done" (list (freeInstr "done.freeP" "p") (freeInstr "done.freeD" "dp")
                                (fileVal "unit" (ty/opConst (ty/constUnit))) (constructResult "done.v" "ok" "unit")) "done.v")))))

fn fileWriteFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (fileWriteCoreFn k pool "fileWrite" (list "O_WRONLY" "O_CREAT" "O_TRUNC") false)

fn fileCreateExclusiveFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (fileWriteCoreFn k pool "fileCreateExclusive" (list "O_WRONLY" "O_CREAT" "O_EXCL") true)

fn fileDirCreateFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "dirCreate") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "lengthCheck" "badType"))
      (fileBadArgBlock pool "badType" "dirCreate" (none))
      (block "lengthCheck" (list (entryInstr "len" (ty/tyI64) "stringLength" (list "path")) (int64Const "zero" 0) (fileEq "empty" "len" "zero"))
        (fileBr "empty" "invalid" "nulCheck"))
      (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "maxCheck" "invalid"))
      (fileRet "invalid" (list (int64Const "einval" (fileK k "EINVAL")) (fileCall "invalid.v" (ty/tyVal) "fileIoError" (list "einval" "path"))) "invalid.v")
      (block "maxCheck" (list (int64Const "pathMax" (fileK k "PATH_MAX")) (primInstr "tooLong" (ty/tyI1) "geInt" (list "len" "pathMax")))
        (fileBr "tooLong" "long" "walk"))
      (fileRet "long" (list (int64Const "enametoolong" (fileK k "ENAMETOOLONG")) (fileCall "long.v" (ty/tyVal) "fileIoError" (list "enametoolong" "path"))) "long.v")
      (block "walk" (listAppend (fileCStr "p" "path")
                      (list (fileCall "walked" (ty/tyVal) "fileDirCreateWalk" (list "p" "len"))
                            (freeInstr "walk.free" "p")))
        (ty/termReturn "walked"))))

fn fileDirCreateWalkFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileDirCreateWalk") (list) (list (ty/ssaParam "p" (ty/tyPtr)) (ty/ssaParam "len" (ty/tyI64))) (ty/tyVal)
    (list
      (block "entry" (list (int64Const "one" 1) (int64Const "zero" 0) (int32Const "slash" 47) (int32Const "nul" 0)
                           (int64Const "ifdir" (fileK k "S_IFDIR")) (int64Const "enotdir" (fileK k "ENOTDIR")))
        (fileJump "loop" (list "one")))
      (ty/ssaBlock "loop" (list (ty/ssaParam "i" (ty/tyI64)))
        (list (primInstr "past" (ty/tyI1) "gtInt" (list "i" "len"))) (fileBr "past" "done" "look"))
      (block "look" (list (primInstr "c" (ty/tyI32) "rawLoadI8" (list "p" "i"))
                          (primInstr "isSlash" (ty/tyI1) "rawEqI32" (list "c" "slash"))
                          (primInstr "isEnd" (ty/tyI1) "rawEqI32" (list "c" "nul"))
                          (primInstr "cut" (ty/tyI1) "orBool" (list "isSlash" "isEnd"))
                          (primInstr "next" (ty/tyI64) "addInt" (list "i" "one")))
        (ty/termBranch "cut" (edgeTo "rootCheck") (ty/ssaEdge "loop" (list "next"))))
      (block "rootCheck" (list (fileEq "atOne" "i" "one")
                               (primInstr "c0" (ty/tyI32) "rawLoadI8" (list "p" "zero"))
                               (primInstr "firstSlash" (ty/tyI1) "rawEqI32" (list "c0" "slash"))
                               (primInstr "isRoot" (ty/tyI1) "andBool" (list "atOne" "firstSlash")))
        (ty/termBranch "isRoot" (ty/ssaEdge "loop" (list "next")) (edgeTo "statPrefix")))
      (block "statPrefix" (list (callInstr "prefix" (ty/tyVal) "mkStr" (list "p" "i"))
                                (callInstr "st" (ty/tyVal) "sysStat" (list "prefix")))
        (fileResSwitch "st" "statOk" "makeDir"))
      (block "statOk" (listAppend (list (ty/ssaInstr "tuple" (ty/tyVal) (ty/opVariantField "st" 0)))
                        (listAppend (fileNth "kind" "tuple" 3)
                          (list (ty/ssaInstr "kind.i" (ty/tyI64) (ty/opUnbox "kind")) (fileEq "isDir" "kind.i" "ifdir"))))
        (ty/termBranch "isDir" (ty/ssaEdge "loop" (list "next")) (edgeTo "notDir")))
      (fileRet "notDir" (list (fileCall "notDir.v" (ty/tyVal) "fileIoError" (list "enotdir" "prefix"))) "notDir.v")
      (block "makeDir" (list (int32Const "mode" 511) (callInstr "made" (ty/tyVal) "sysMkdir" (list "prefix" "mode")))
        (fileResSwitch "made" "restat" "mkdirErr"))
      (block "mkdirErr" (list (ty/ssaInstr "mkdirErr.box" (ty/tyVal) (ty/opVariantField "made" 0))
                              (ty/ssaInstr "mkdirErr.e" (ty/tyI64) (ty/opUnbox "mkdirErr.box"))
                              (int64Const "eexist" (fileK k "EEXIST")) (fileEq "exists" "mkdirErr.e" "eexist"))
        (fileBr "exists" "restat" "mkdirFail"))
      (fileRet "mkdirFail" (list (fileCall "mkdirFail.v" (ty/tyVal) "fileIoError" (list "mkdirErr.e" "prefix"))) "mkdirFail.v")
      (block "restat" (list (callInstr "st2" (ty/tyVal) "sysStat" (list "prefix"))) (fileResSwitch "st2" "restatOk" "notDir"))
      (block "restatOk" (listAppend (list (ty/ssaInstr "tuple2" (ty/tyVal) (ty/opVariantField "st2" 0)))
                          (listAppend (fileNth "kind2" "tuple2" 3)
                            (list (ty/ssaInstr "kind2.i" (ty/tyI64) (ty/opUnbox "kind2")) (fileEq "isDir2" "kind2.i" "ifdir"))))
        (ty/termBranch "isDir2" (ty/ssaEdge "loop" (list "next")) (edgeTo "notDir")))
      (fileRet "done" (list (fileVal "unit" (ty/opConst (ty/constUnit))) (constructResult "done.v" "ok" "unit")) "done.v")))

fn filePathRemoveRecFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "filePathRemoveRec") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (int64Const "cap" 511) (callInstr "st" (ty/tyVal) "sysLstat" (list "path"))) (fileResSwitch "st" "kind" "lstatErr"))
      (block "kind" (listAppend (list (ty/ssaInstr "tuple" (ty/tyVal) (ty/opVariantField "st" 0)))
                      (listAppend (fileNth "kind" "tuple" 3)
                        (list (ty/ssaInstr "kind.i" (ty/tyI64) (ty/opUnbox "kind"))
                              (int64Const "ifdir" (fileK k "S_IFDIR")) (fileEq "isDir" "kind.i" "ifdir"))))
        (fileBr "isDir" "list" "unlink"))
      (block "list" (list (callInstr "children" (ty/tyVal) "sysDirList" (list "path"))) (fileResSwitch "children" "iterate" "listErr"))
      (block "iterate" (list (ty/ssaInstr "items" (ty/tyVal) (ty/opVariantField "children" 0))
                             (filePool pool "slash" "/")
                             (entryInstr "dirSlash" (ty/tyVal) "stringConcat" (list "path" "slash"))
                             (int64Const "pathMax" (fileK k "PATH_MAX")))
        (fileJump "loop" (list "items")))
      (ty/ssaBlock "loop" (list (ty/ssaParam "remaining" (ty/tyVal)))
        (list (entryInstr "childOpt" (ty/tyVal) "listHead" (list "remaining")))
        (fileOptSwitch "childOpt" "child" "rmdir"))
      (block "child" (list (ty/ssaInstr "name" (ty/tyVal) (ty/opVariantField "childOpt" 0))
                           (entryInstr "full" (ty/tyVal) "stringConcat" (list "dirSlash" "name"))
                           (entryInstr "fullLen" (ty/tyI64) "stringLength" (list "full"))
                           (primInstr "tooLong" (ty/tyI1) "geInt" (list "fullLen" "pathMax")))
        (fileBr "tooLong" "longErr" "recurse"))
      (fileRet "longErr" (list (int64Const "enametoolong" (fileK k "ENAMETOOLONG"))
                               (fileCall "longErr.v" (ty/tyVal) "fileIoErrorCap" (list "enametoolong" "path" "cap"))) "longErr.v")
      (block "recurse" (list (fileCall "removed" (ty/tyVal) "filePathRemoveRec" (list "full"))) (fileResSwitch "removed" "advance" "childErr"))
      (fileRet "childErr" (list) "removed")
      (block "advance" (list (entryInstr "tailOpt" (ty/tyVal) "listTail" (list "remaining"))
                             (ty/ssaInstr "tail" (ty/tyVal) (ty/opVariantField "tailOpt" 0)))
        (fileJump "loop" (list "tail")))
      (block "rmdir" (list (callInstr "rmdirRes" (ty/tyVal) "sysRmdir" (list "path"))) (fileResSwitch "rmdirRes" "done" "rmdirErr"))
      (block "unlink" (list (callInstr "unlinkRes" (ty/tyVal) "sysUnlink" (list "path"))) (fileResSwitch "unlinkRes" "done" "unlinkErr"))
      (fileRet "done" (list (fileVal "unit" (ty/opConst (ty/constUnit))) (constructResult "done.v" "ok" "unit")) "done.v")
      (fileRet "lstatErr" (list (ty/ssaInstr "lstatErr.box" (ty/tyVal) (ty/opVariantField "st" 0)) (ty/ssaInstr "lstatErr.e" (ty/tyI64) (ty/opUnbox "lstatErr.box"))
                                (fileCall "lstatErr.v" (ty/tyVal) "fileIoErrorCap" (list "lstatErr.e" "path" "cap"))) "lstatErr.v")
      (fileRet "listErr" (list (ty/ssaInstr "listErr.box" (ty/tyVal) (ty/opVariantField "children" 0)) (ty/ssaInstr "listErr.e" (ty/tyI64) (ty/opUnbox "listErr.box"))
                               (fileCall "listErr.v" (ty/tyVal) "fileIoErrorCap" (list "listErr.e" "path" "cap"))) "listErr.v")
      (fileRet "rmdirErr" (list (ty/ssaInstr "rmdirErr.box" (ty/tyVal) (ty/opVariantField "rmdirRes" 0)) (ty/ssaInstr "rmdirErr.e" (ty/tyI64) (ty/opUnbox "rmdirErr.box"))
                                (fileCall "rmdirErr.v" (ty/tyVal) "fileIoErrorCap" (list "rmdirErr.e" "path" "cap"))) "rmdirErr.v")
      (fileRet "unlinkErr" (list (ty/ssaInstr "unlinkErr.box" (ty/tyVal) (ty/opVariantField "unlinkRes" 0)) (ty/ssaInstr "unlinkErr.e" (ty/tyI64) (ty/opUnbox "unlinkErr.box"))
                                 (fileCall "unlinkErr.v" (ty/tyVal) "fileIoErrorCap" (list "unlinkErr.e" "path" "cap"))) "unlinkErr.v")))

fn filePathRemoveFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "pathRemove") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "nulCheck" "badType"))
      (fileBadArgBlock pool "badType" "pathRemove" (none))
      (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "call" "badNul"))
      (fileRet "badNul" (list (int64Const "einval" (fileK k "EINVAL")) (fileCall "badNul.v" (ty/tyVal) "fileIoError" (list "einval" "path"))) "badNul.v")
      (block "call" (list (fileCall "result" (ty/tyVal) "filePathRemoveRec" (list "path"))) (ty/termReturn "result"))))

fn fileReadlinkRawFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction "sysFileReadlink" (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (listAppend (fileCStr "p" "path")
                       (list (int64Const "initialCap" 256)
                             (callInstr "buf" (ty/tyPtr) "malloc" (list "initialCap"))
                             (primInstr "bufNull" (ty/tyI1) "rawPtrIsNull" (list "buf"))))
        (fileBr "bufNull" "allocError" "start"))
      (fileRet "allocError" (list (callInstr "alloc.errno" (ty/tyI64) "sysErrnoValue" (list))
                                    (freeInstr "alloc.free.path" "p")
                                    (boxInstr "alloc.errbox" "alloc.errno") (constructResult "alloc.err" "err" "alloc.errbox")) "alloc.err")
      (block "start" (list) (ty/termJump (ty/ssaEdge "loop" (list "buf" "initialCap"))))
      (ty/ssaBlock "loop" (list (ty/ssaParam "loop.buffer" (ty/tyPtr)) (ty/ssaParam "loop.cap" (ty/tyI64)))
        (list (callInstr "loop.n" (ty/tyI64) "readlink" (list "p" "loop.buffer" "loop.cap"))
              (int64Const "loop.zero" 0) (primInstr "loop.failed" (ty/tyI1) "ltInt" (list "loop.n" "loop.zero")))
        (ty/termBranch "loop.failed" (ty/ssaEdge "readError" (list "loop.buffer")) (ty/ssaEdge "checkFit" (list "loop.buffer" "loop.cap" "loop.n"))))
      (ty/ssaBlock "checkFit" (list (ty/ssaParam "check.buffer" (ty/tyPtr)) (ty/ssaParam "check.cap" (ty/tyI64)) (ty/ssaParam "check.n" (ty/tyI64)))
        (list (primInstr "fits" (ty/tyI1) "ltInt" (list "check.n" "check.cap")))
        (ty/termBranch "fits" (ty/ssaEdge "done" (list "check.buffer" "check.n")) (ty/ssaEdge "grow" (list "check.buffer" "check.cap"))))
      (ty/ssaBlock "grow" (list (ty/ssaParam "grow.buffer" (ty/tyPtr)) (ty/ssaParam "grow.cap" (ty/tyI64)))
        (list (int64Const "maxCap" 1048576)
              (primInstr "atLimit" (ty/tyI1) "geInt" (list "grow.cap" "maxCap")))
        (ty/termBranch "atLimit" (ty/ssaEdge "tooLong" (list "grow.buffer")) (ty/ssaEdge "resize" (list "grow.buffer" "grow.cap"))))
      (ty/ssaBlock "tooLong" (list (ty/ssaParam "long.buffer" (ty/tyPtr)))
        (listAppend (list (freeInstr "long.free.path" "p") (freeInstr "long.free.buf" "long.buffer")
                           (int64Const "enametoolong" (fileK k "ENAMETOOLONG"))
                           (boxInstr "long.errbox" "enametoolong") (constructResult "long.error" "err" "long.errbox"))
          (list)) (ty/termReturn "long.error"))
      (ty/ssaBlock "resize" (list (ty/ssaParam "resize.buffer" (ty/tyPtr)) (ty/ssaParam "resize.cap" (ty/tyI64)))
        (list (int64Const "two" 2) (primInstr "nextCap" (ty/tyI64) "mulInt" (list "resize.cap" "two"))
              (callInstr "nextBuf" (ty/tyPtr) "realloc" (list "resize.buffer" "nextCap"))
              (primInstr "nextNull" (ty/tyI1) "rawPtrIsNull" (list "nextBuf")))
        (ty/termBranch "nextNull" (ty/ssaEdge "resizeError" (list "resize.buffer")) (ty/ssaEdge "retry" (list "nextBuf" "nextCap"))))
      (ty/ssaBlock "resizeError" (list (ty/ssaParam "resize.error.buffer" (ty/tyPtr)))
        (list (callInstr "resize.errno" (ty/tyI64) "sysErrnoValue" (list))
              (freeInstr "resize.free.path" "p") (freeInstr "resize.free.buf" "resize.error.buffer")
              (boxInstr "resize.errbox" "resize.errno") (constructResult "resize.error" "err" "resize.errbox"))
        (ty/termReturn "resize.error"))
      (ty/ssaBlock "retry" (list (ty/ssaParam "retry.buffer" (ty/tyPtr)) (ty/ssaParam "retry.cap" (ty/tyI64)))
        (list) (ty/termJump (ty/ssaEdge "loop" (list "retry.buffer" "retry.cap"))))
      (ty/ssaBlock "readError" (list (ty/ssaParam "readError.buffer" (ty/tyPtr)))
        (list (callInstr "read.errno" (ty/tyI64) "sysErrnoValue" (list))
              (freeInstr "read.free.path" "p") (freeInstr "read.free.buf" "readError.buffer")
              (boxInstr "read.errbox" "read.errno") (constructResult "read.error" "err" "read.errbox"))
        (ty/termReturn "read.error"))
      (ty/ssaBlock "done" (list (ty/ssaParam "done.buffer" (ty/tyPtr)) (ty/ssaParam "done.n" (ty/tyI64)))
        (list (callInstr "text" (ty/tyVal) "mkStr" (list "done.buffer" "done.n"))
              (freeInstr "done.free.path" "p") (freeInstr "done.free.buf" "done.buffer")
              (constructResult "done.result" "ok" "text")) (ty/termReturn "done.result"))))

fn fileReadlinkFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileReadlink") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "nulCheck" "badArg"))
      (fileBadArgBlock pool "badArg" "fileReadlink" (none))
      (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "call" "badArg"))
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysFileReadlink" (list "path"))) (fileResSwitch "raw" "done" "failed"))
      (fileRet "done" (list) "raw")
      (fileErrnoErrBlock "failed" "raw" "path")))

fn sysUtimensatFn facts: libc/TripleFacts -> (Result ty/SsaFunction String)
  (mt (structByteSize facts "timespec")
    ((err e) (err e))
    ((ok tsSize)
     (mt (structOffset facts "timespec" "tv_sec")
       ((err e) (err e))
       ((ok secOff)
        (mt (structOffset facts "timespec" "tv_nsec")
          ((err e) (err e))
          ((ok nsecOff)
           (mt (constOrErr facts "AT_FDCWD")
             ((err e) (err e))
             ((ok cwd)
              (ok (ty/ssaFunction "sysUtimensat" (list)
                (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "ns" (ty/tyI64))) (ty/tyVal)
                (list
                  (block "entry" (listAppend (stringToPtrInstrs "p" "path")
                           (list (int64Const "size" (* tsSize 2))
                                 (callInstr "times" (ty/tyPtr) "malloc" (list "size"))
                                 (primInstr "isNull" (ty/tyI1) "rawPtrIsNull" (list "times"))))
                    (fileBr "isNull" "allocError" "fill"))
                  (fileRet "allocError" (list (callInstr "alloc.errno" (ty/tyI64) "sysErrnoValue" (list))
                                                (freeInstr "alloc.free.path" "p")
                                                (boxInstr "alloc.errbox" "alloc.errno") (constructResult "alloc.err" "err" "alloc.errbox")) "alloc.err")
                  (block "fill" (list (int64Const "billion" 1000000000)
                                        (primInstr "sec" (ty/tyI64) "divIntHost" (list "ns" "billion"))
                                        (primInstr "rem" (ty/tyI64) "modIntHost" (list "ns" "billion"))
                                        (int64Const "zero" 0)
                                        (primInstr "negative" (ty/tyI1) "ltInt" (list "rem" "zero")))
                    (ty/termBranch "negative" (edgeTo "normalize") (ty/ssaEdge "store" (list "sec" "rem"))))
                  (block "normalize" (list (primInstr "nsec" (ty/tyI64) "addInt" (list "rem" "billion"))
                                             (int64Const "one" 1)
                                             (primInstr "sec.adjusted" (ty/tyI64) "subInt" (list "sec" "one")))
                    (ty/termJump (ty/ssaEdge "storeNormalized" (list "sec.adjusted" "nsec"))))
                  (ty/ssaBlock "store" (list (ty/ssaParam "sec.store" (ty/tyI64)) (ty/ssaParam "nsec.store" (ty/tyI64)))
                    (list) (ty/termJump (ty/ssaEdge "call" (list "sec.store" "nsec.store"))))
                  (ty/ssaBlock "storeNormalized" (list (ty/ssaParam "sec.normalized" (ty/tyI64)) (ty/ssaParam "nsec.normalized" (ty/tyI64)))
                    (list) (ty/termJump (ty/ssaEdge "call" (list "sec.normalized" "nsec.normalized"))))
                  (ty/ssaBlock "call" (list (ty/ssaParam "sec.call" (ty/tyI64)) (ty/ssaParam "nsec.call" (ty/tyI64)))
                    (list (int64Const "sec.off" secOff)
                          (primInstr "sec.st1" (ty/tyI1) "rawStoreI64" (list "times" "sec.off" "sec.call"))
                          (int64Const "nsec.off" nsecOff)
                          (primInstr "nsec.st1" (ty/tyI1) "rawStoreI64" (list "times" "nsec.off" "nsec.call"))
                          (int64Const "second.base" tsSize)
                          (primInstr "second.sec.off" (ty/tyI64) "addInt" (list "second.base" "sec.off"))
                          (primInstr "sec.st2" (ty/tyI1) "rawStoreI64" (list "times" "second.sec.off" "sec.call"))
                          (primInstr "second.nsec.off" (ty/tyI64) "addInt" (list "second.base" "nsec.off"))
                          (primInstr "nsec.st2" (ty/tyI1) "rawStoreI64" (list "times" "second.nsec.off" "nsec.call"))
                          (int32Const "dirfd" cwd) (int32Const "flags" 0)
                          (callInstr "raw" (ty/tyI32) "utimensat" (list "dirfd" "p" "times" "flags"))
                          (fileWiden "result" "raw") (int64Const "zero.result" 0)
                          (primInstr "failed" (ty/tyI1) "neInt" (list "result" "zero.result")))
                    (fileBr "failed" "callError" "success"))
                  (fileRet "callError" (list (callInstr "errno" (ty/tyI64) "sysErrnoValue" (list))
                                               (freeInstr "error.free.path" "p") (freeInstr "error.free.times" "times")
                                               (boxInstr "error.box" "errno") (constructResult "error" "err" "error.box")) "error")
                  (fileRet "success" (list (freeInstr "success.free.path" "p") (freeInstr "success.free.times" "times")
                                             (int64Const "success.zero" 0) (boxInstr "success.box" "success.zero")
                                             (constructResult "success" "ok" "success.box")) "success"))))))))))))

fn fileUtimeFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileUtime") (list)
    (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "mtimeNs" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "nulCheck" "badType"))
      (fileRet "badType" (list (filePool pool "op.type" "fileUtime") (filePool pool "dash.type" "-") (filePool pool "reason.type" "invalid argument")
                                (fileCall "bad.type" (ty/tyVal) "fileFormatError" (list "op.type" "dash.type" "reason.type"))) "bad.type")
      (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "intCheck" "badNul"))
      (fileRet "badNul" (list (filePool pool "op.nul" "fileUtime") (filePool pool "dash.nul" "-") (filePool pool "reason.nul" "invalid argument")
                               (fileCall "bad.nul" (ty/tyVal) "fileFormatError" (list "op.nul" "dash.nul" "reason.nul"))) "bad.nul")
      (block "intCheck" (list (int64Const "zero.tag" 0) (boxInstr "zero.box" "zero.tag")
                               (fileCall "actual.tag" (ty/tyI64) "tagOf" (list "mtimeNs"))
                               (fileCall "int.tag" (ty/tyI64) "tagOf" (list "zero.box"))
                               (fileEq "isInt" "actual.tag" "int.tag")) (fileBr "isInt" "call" "badValue"))
      (fileRet "badValue" (list (filePool pool "op.value" "fileUtime") (filePool pool "reason.value" "invalid argument")
                                 (fileCall "bad.value" (ty/tyVal) "fileFormatError" (list "op.value" "path" "reason.value"))) "bad.value")
      (block "call" (list (ty/ssaInstr "ns" (ty/tyI64) (ty/opUnbox "mtimeNs"))
                           (callInstr "raw" (ty/tyVal) "sysUtimensat" (list "path" "ns"))
                           (fileCall "mapped" (ty/tyVal) "fileMapUnitIoResult" (list "raw" "path")))
        (ty/termReturn "mapped"))))

fn fileRealPathFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "realPath") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "call" "badType"))
      (fileStrTrapBlock pool "badType" "realPath" "path")
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysRealpath" (list "path"))) (fileResSwitch "raw" "done" "failed"))
      (fileRet "done" (list) "raw")
      (fileErrnoErrBlock "failed" "raw" "path")))

fn filePathRenameFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "pathRename") (list) (list (ty/ssaParam "from" (ty/tyVal)) (ty/ssaParam "to" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "fromText" (ty/tyI1) "isStr" (list "from")) (fileCall "toText" (ty/tyI1) "isStr" (list "to"))
                            (primInstr "bothText" (ty/tyI1) "andBool" (list "fromText" "toText"))) (fileBr "bothText" "fromNul" "badType"))
      (fileRet "badType" (list (filePool pool "op.type" "pathRename") (filePool pool "dash.type" "-") (filePool pool "reason.type" "invalid argument")
                                (fileCall "bad.type" (ty/tyVal) "fileFormatError" (list "op.type" "dash.type" "reason.type"))) "bad.type")
      (block "fromNul" (list (fileCall "cleanFrom" (ty/tyI1) "fileNulFree" (list "from"))) (fileBr "cleanFrom" "toNul" "fromError"))
      (fileRet "fromError" (list (int64Const "einval.from" (fileK k "EINVAL")) (fileCall "bad.from" (ty/tyVal) "fileIoError" (list "einval.from" "from"))) "bad.from")
      (block "toNul" (list (fileCall "cleanTo" (ty/tyI1) "fileNulFree" (list "to"))) (fileBr "cleanTo" "call" "toError"))
      (fileRet "toError" (list (int64Const "einval.to" (fileK k "EINVAL")) (fileCall "bad.to" (ty/tyVal) "fileIoError" (list "einval.to" "to"))) "bad.to")
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysRename" (list "from" "to"))
                           (fileCall "mapped" (ty/tyVal) "fileMapUnitIoResult" (list "raw" "from")))
        (ty/termReturn "mapped"))))

fn filePathSymlinkFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "pathSymlink") (list)
    (list (ty/ssaParam "target" (ty/tyVal)) (ty/ssaParam "linkPath" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "linkText" (ty/tyI1) "isStr" (list "linkPath"))) (fileBr "linkText" "linkNul" "badDash"))
      (block "linkNul" (list (fileCall "linkClean" (ty/tyI1) "fileNulFree" (list "linkPath"))) (fileBr "linkClean" "targetText" "badDash"))
      (block "targetText" (list (fileCall "targetIsText" (ty/tyI1) "isStr" (list "target"))) (fileBr "targetIsText" "targetNul" "badLink"))
      (block "targetNul" (list (fileCall "targetClean" (ty/tyI1) "fileNulFree" (list "target"))) (fileBr "targetClean" "targetLen" "badLink"))
      (block "targetLen" (list (entryInstr "len" (ty/tyI64) "stringLength" (list "target")) (int64Const "zero" 0) (fileEq "empty" "len" "zero"))
        (fileBr "empty" "badLink" "call"))
      (fileBadArgBlock pool "badDash" "pathSymlink" (none))
      (fileBadArgBlock pool "badLink" "pathSymlink" (some "linkPath"))
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysSymlink" (list "target" "linkPath"))) (fileResSwitch "raw" "done" "failed"))
      (fileRet "done" (list (fileVal "unit" (ty/opConst (ty/constUnit))) (constructResult "done.v" "ok" "unit")) "done.v")
      (fileErrnoErrBlock "failed" "raw" "linkPath")))

fn fileChmodFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileChmod") (list) (list (ty/ssaParam "path" (ty/tyVal)) (ty/ssaParam "mode" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "nulCheck" "badType"))
      (fileRet "badType" (list (filePool pool "op.type" "fileChmod") (filePool pool "dash.type" "-") (filePool pool "reason.type" "invalid argument")
                                (fileCall "bad.type" (ty/tyVal) "fileFormatError" (list "op.type" "dash.type" "reason.type"))) "bad.type")
      (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "intCheck" "badNul"))
      (fileRet "badNul" (list (filePool pool "op.nul" "fileChmod") (filePool pool "dash.nul" "-") (filePool pool "reason.nul" "invalid argument")
                               (fileCall "bad.nul" (ty/tyVal) "fileFormatError" (list "op.nul" "dash.nul" "reason.nul"))) "bad.nul")
      (block "intCheck" (list (int64Const "zero.tag" 0) (boxInstr "zero.box" "zero.tag")
                               (fileCall "actual.tag" (ty/tyI64) "tagOf" (list "mode"))
                               (fileCall "int.tag" (ty/tyI64) "tagOf" (list "zero.box"))
                               (fileEq "isInt" "actual.tag" "int.tag")) (fileBr "isInt" "bounds" "badMode"))
      (block "bounds" (list (ty/ssaInstr "modeInt" (ty/tyI64) (ty/opUnbox "mode"))
                             (int64Const "zero" 0) (int64Const "maxMode" 4095)
                             (primInstr "low" (ty/tyI1) "geInt" (list "modeInt" "zero"))
                             (primInstr "high" (ty/tyI1) "leInt" (list "modeInt" "maxMode"))
                             (primInstr "valid" (ty/tyI1) "andBool" (list "low" "high"))) (fileBr "valid" "call" "badMode"))
      (fileRet "badMode" (list (filePool pool "op.mode" "fileChmod") (filePool pool "reason.mode" "invalid argument")
                                (fileCall "bad.mode" (ty/tyVal) "fileFormatError" (list "op.mode" "path" "reason.mode"))) "bad.mode")
      (block "call" (list (fileNarrow "mode32" "modeInt")
                           (callInstr "raw" (ty/tyVal) "sysChmod" (list "path" "mode32"))
                           (fileCall "mapped" (ty/tyVal) "fileMapUnitIoResult" (list "raw" "path")))
        (ty/termReturn "mapped"))))

fn fileSysFsyncPathFn k: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction "sysFsyncPath" (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (listAppend (stringToPtrInstrs "p" "path")
                     (listAppend (list (int64Const "zero" 0) (int64Const "eintr" (fileK k "EINTR")))
                       (listAppend (fileOr "flags" k (list "O_RDONLY" "O_CLOEXEC"))
                       (list (callInstr "fd" (ty/tyI32) "open" (list "p" "flags"))
                             (primInstr "fd64" (ty/tyI64) "rawWidenI32" (list "fd"))
                             (primInstr "fdNeg" (ty/tyI1) "ltInt" (list "fd64" "zero"))))))
        (fileBr "fdNeg" "openError" "sync"))
      (block "openError" (list (callInstr "openErrno" (ty/tyI64) "sysErrnoValue" (list))
                                (freeInstr "openFree" "p") (boxInstr "openErrBox" "openErrno")
                                (constructResult "openErr" "err" "openErrBox")) (ty/termReturn "openErr"))
      (block "sync" (list (callInstr "sync32" (ty/tyI32) "fsync" (list "fd"))
                            (primInstr "sync" (ty/tyI64) "rawWidenI32" (list "sync32"))
                                (primInstr "syncFailed" (ty/tyI1) "neInt" (list "sync" "zero")))
        (fileBr "syncFailed" "syncError" "closeOk"))
      (block "syncError" (list (callInstr "syncErrno" (ty/tyI64) "sysErrnoValue" (list))
                                (fileEq "syncInterrupted" "syncErrno" "eintr"))
        (fileBr "syncInterrupted" "sync" "syncFailedClose"))
      (block "syncFailedClose" (list (callInstr "closeAfterSync" (ty/tyI32) "close" (list "fd"))
                                       (freeInstr "freeAfterSync" "p") (boxInstr "syncErrBox" "syncErrno")
                                       (constructResult "syncErr" "err" "syncErrBox")) (ty/termReturn "syncErr"))
      (block "closeOk" (list (callInstr "close32" (ty/tyI32) "close" (list "fd"))
                               (primInstr "close64" (ty/tyI64) "rawWidenI32" (list "close32"))
                               (primInstr "closeFailed" (ty/tyI1) "neInt" (list "close64" "zero")))
        (fileBr "closeFailed" "closeError" "success"))
      (block "closeError" (list (callInstr "closeErrno" (ty/tyI64) "sysErrnoValue" (list))
                                  (fileEq "closeInterrupted" "closeErrno" "eintr"))
        (fileBr "closeInterrupted" "success" "closeFailedValue"))
      (block "closeFailedValue" (list (freeInstr "freeCloseFail" "p") (boxInstr "closeErrBox" "closeErrno")
                                       (constructResult "closeErr" "err" "closeErrBox")) (ty/termReturn "closeErr"))
      (fileRet "success" (list (freeInstr "successFree" "p") (int64Const "okInt" 0)
                                 (boxInstr "okBox" "okInt") (constructResult "ok" "ok" "okBox")) "ok")))

fn fileFsyncFn pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileFsync") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "nulCheck" "badType"))
      (fileRet "badType" (list (filePool pool "op.type" "fileFsync") (filePool pool "dash.type" "-") (filePool pool "reason.type" "invalid argument")
                                (fileCall "bad.type" (ty/tyVal) "fileFormatError" (list "op.type" "dash.type" "reason.type"))) "bad.type")
      (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "call" "badNul"))
      (fileRet "badNul" (list (filePool pool "op.nul" "fileFsync") (filePool pool "dash.nul" "-") (filePool pool "reason.nul" "invalid argument")
                               (fileCall "bad.nul" (ty/tyVal) "fileFormatError" (list "op.nul" "dash.nul" "reason.nul"))) "bad.nul")
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysFsyncPath" (list "path"))
                           (fileCall "mapped" (ty/tyVal) "fileMapUnitIoResult" (list "raw" "path")))
        (ty/termReturn "mapped"))))

fn fileNameLessFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileNameLess") (list) (list (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal))) (ty/tyI1)
    (list
      (block "entry" (listAppend (fileCStr "ac" "a")
                       (listAppend (fileCStr "bc" "b")
                         (list (callInstr "cmp32" (ty/tyI32) "strcmp" (list "ac" "bc"))
                               (freeInstr "aFree" "ac") (freeInstr "bFree" "bc")
                               (fileWiden "cmp" "cmp32") (int64Const "zero" 0)
                               (primInstr "less" (ty/tyI1) "ltInt" (list "cmp" "zero")))))
        (ty/termReturn "less"))))

fn fileSortStringsFn -> ty/SsaFunction
  (ty/ssaFunction (fileW "fileSortStrings") (list) (list (ty/ssaParam "xs" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (entryInstr "h0" (ty/tyVal) "listHead" (list "xs"))) (fileOptSwitch "h0" "second" "trivial"))
      (block "second" (list (entryInstr "t0" (ty/tyVal) "listTail" (list "xs"))
                            (ty/ssaInstr "rest0" (ty/tyVal) (ty/opVariantField "t0" 0))
                            (entryInstr "h1" (ty/tyVal) "listHead" (list "rest0")))
        (fileOptSwitch "h1" "split" "trivial"))
      (fileRet "trivial" (list) "xs")
      (block "split" (list (listInstr "nilA" (list)) (listInstr "nilB" (list))) (fileJump "deal" (list "xs" "nilA" "nilB")))
      (ty/ssaBlock "deal" (list (ty/ssaParam "rest" (ty/tyVal)) (ty/ssaParam "a" (ty/tyVal)) (ty/ssaParam "b" (ty/tyVal)))
        (list (entryInstr "next" (ty/tyVal) "listHead" (list "rest")))
        (fileOptSwitch "next" "dealOne" "halves"))
      (block "dealOne" (list (ty/ssaInstr "x" (ty/tyVal) (ty/opVariantField "next" 0))
                             (entryInstr "restT" (ty/tyVal) "listTail" (list "rest"))
                             (ty/ssaInstr "rest2" (ty/tyVal) (ty/opVariantField "restT" 0))
                             (entryInstr "a2" (ty/tyVal) "cons" (list "x" "a")))
        (fileJump "deal" (list "rest2" "b" "a2")))
      (block "halves" (list (fileCall "sa" (ty/tyVal) "fileSortStrings" (list "a"))
                            (fileCall "sb" (ty/tyVal) "fileSortStrings" (list "b"))
                            (fileCall "merged" (ty/tyVal) "fileMergeStrings" (list "sa" "sb")))
        (ty/termReturn "merged"))))

fn fileDirListFn k: (Map String Int64) pool: (Map String Int64) -> ty/SsaFunction
  (ty/ssaFunction (fileW "dirList") (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (list
      (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "call" "badType"))
      (fileStrTrapBlock pool "badType" "dirList" "path")
      (block "call" (list (callInstr "raw" (ty/tyVal) "sysDirList" (list "path"))) (fileResSwitch "raw" "sorted" "failed"))
      (fileRet "sorted" (list (ty/ssaInstr "items" (ty/tyVal) (ty/opVariantField "raw" 0))
                              (fileCall "ordered" (ty/tyVal) "fileSortStrings" (list "items"))
                              (constructResult "okv" "ok" "ordered")) "okv")
      (fileErrnoErrBlock "failed" "raw" "path")))

fn fileStatRouteFn k: (Map String Int64) pool: (Map String Int64) name: String rawName: String recordName: String link: Bool -> ty/SsaFunction
  (ty/ssaFunction (fileW name) (list) (list (ty/ssaParam "path" (ty/tyVal))) (ty/tyVal)
    (listAppend
      (if link
        (list (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "nulCheck" "badType"))
              (fileBadArgBlock pool "badType" name (none))
              (block "nulCheck" (list (fileCall "clean" (ty/tyI1) "fileNulFree" (list "path"))) (fileBr "clean" "call" "badType")))
        (list (block "entry" (list (fileCall "isText" (ty/tyI1) "isStr" (list "path"))) (fileBr "isText" "call" "badType"))
              (fileStrTrapBlock pool "badType" name "path")))
     (list
      (block "call" (list (callInstr "raw" (ty/tyVal) rawName (list "path"))) (fileResSwitch "raw" "build" "failed"))
      (fileErrnoErrBlock "failed" "raw" "path")
      (block "build"
        (listAppend (list (ty/ssaInstr "tuple" (ty/tyVal) (ty/opVariantField "raw" 0)))
          (listAppend (fileNth "size" "tuple" 0)
            (listAppend (fileNth "mode" "tuple" 1)
              (listAppend (fileNth "mtime" "tuple" 2)
                (listAppend (fileNth "kind" "tuple" 3)
                  (listAppend (fileNth "mtimeNs" "tuple" 4)
                    (list (ty/ssaInstr "kind.i" (ty/tyI64) (ty/opUnbox "kind"))
                          (int64Const "ifreg" (fileK k "S_IFREG")) (fileEq "isFile.i" "kind.i" "ifreg") (boxInstr "isFile" "isFile.i")
                          (int64Const "ifdir" (fileK k "S_IFDIR")) (fileEq "isDir.i" "kind.i" "ifdir") (boxInstr "isDir" "isDir.i")
                          (int64Const "iflnk" (fileK k "S_IFLNK")) (fileEq "isLink.i" "kind.i" "iflnk") (boxInstr "isLink" "isLink.i")
                          (if link
                            (fileVal "record" (ty/opRecord recordName (list "isFile" "isDir" "isSymlink" "size" "mtime" "mode" "mtimeNs")
                                                           (list "isFile" "isDir" "isLink" "size" "mtime" "mode" "mtimeNs")))
                            (fileVal "record" (ty/opRecord recordName (list "isFile" "isDir" "size" "mtime" "mode" "mtimeNs")
                                                           (list "isFile" "isDir" "size" "mtime" "mode" "mtimeNs"))))
                          (constructResult "okv" "ok" "record"))))))))
        (ty/termReturn "okv")))))

fn fileRouteFunctions facts: libc/TripleFacts pool: (Map String Int64) -> (Result (List ty/SsaFunction) String)
  (mt (fileFacts facts)
    ((err e) (err e))
    ((ok k)
      (mt (sysDirListFn facts)
        ((err e) (err e))
        ((ok dirListFn)
          (mt (sysStatFn facts)
            ((err e) (err e))
            ((ok statFn)
              (mt (sysLstatFn facts)
                ((err e) (err e))
                ((ok lstatFn)
                  (mt (sysUtimensatFn facts)
                    ((err e) (err e))
                    ((ok utimensatFn)
                      (ok (list (fileSafePathErrFn k pool) (filePathCheckFn k) (fileNulFreeFn) (fileParentAtFn k) (fileMonoMsFn k) (fileLockWaitCoreFn k pool) (fileTempSeqInitFn)
                                (fileLockFn k pool) (fileLockWait1Fn k pool) (fileLockWait2Fn k pool) (fileLockWait3Fn k pool) (fileLockWaitBadFn pool)
                                (fileAppendFn k pool) (fileLockAtFn k pool) (fileReadAtFn k pool) (fileWriteAtFn k pool)
                                (sysRealpathFn) (sysRenameFn) (sysChmodFn) (sysMkdirFn) (sysUnlinkFn) (sysRmdirFn) (sysSymlinkFn)
                                dirListFn statFn lstatFn utimensatFn (fileReadWholeFn k) (fileSlurpFn k) (fileReadlinkRawFn k) (fileSysFsyncPathFn k)
                                (fileIoKindFn k pool) (fileIoErrorFn k) (fileIoErrorCapFn) (fileFormatErrorFn k) (fileFormatErrorCapFn pool)
                                (fileTypeNameFn pool) (fileTypeTrapFn pool) (fileMapIoResultFn) (fileMapUnitIoResultFn)
                                (fileNameLessFn) (fileSortStringsFn) (fileMergeStringsFn) (fileDirCreateWalkFn k pool) (filePathRemoveRecFn k pool) (fileReadRangeFdFn k pool)
                                (fileReadBytesFn k pool) (fileReadStringFn k pool) (fileRealPathFn k pool) (fileWriteFn k pool) (fileDirListFn k pool)
                                (fileStatRouteFn k pool "fileStat" "sysStat" "FileStat" false) (fileReadRangeFn k pool) (fileEnvGetFn) (fileGetHomeDirFn k pool)
                                (fileCreateExclusiveFn k pool) (fileDirCreateFn k pool) (filePathRemoveFn k pool) (filePathRenameFn k pool) (fileChmodFn k pool)
                                (fileFsyncFn pool) (fileReadlinkFn k pool) (fileStatRouteFn k pool "fileLstat" "sysLstat" "LinkStat" true)
                                (filePathSymlinkFn k pool) (fileUtimeFn k pool)))))))))))))
