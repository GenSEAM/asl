(module prelude/tests/nativeOverlayTest
  :x [runTests]
  :i [(asl-ir/link :a lk) (asl-ir/types :a irTy) (asl-ir/verify :a vfy) (asl-target-llvm :a llvm)])

fn host -> String
  "asl/host/out/asl-host"

fn fixtureSrc -> String
  (stringJoin
    (list
      "(module overlayFixture :x [main] :i [])"
      ""
      "fn vec448 -> String"
      "  \"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq\""
      ""
      "fn vec896 -> String"
      "  \"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu\""
      ""
      "fn ! checkRange i: Int64 n: Int64 -> Bool"
      "  (if (> i n) true"
      "    (do (println (bytesSha256 (bytesAlloc i))) (checkRange (+ i 1) n)))"
      ""
      "fn ! digestOnly n: Int64 -> Bool"
      "  (do (println (bytesSha256 (stringToBytes (stringRepeat \"a\" n)))) true)"
      ""
      "fn pick b: Bool -> Float"
      "  (if b (floatNan) (floatInf))"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (do"
      "    (println (bytesSha256 (stringToBytes \"\")))"
      "    (println (bytesSha256 (stringToBytes \"abc\")))"
      "    (println (bytesSha256 (stringToBytes (vec448))))"
      "    (println (bytesSha256 (stringToBytes (vec896))))"
      "    (println (stringJoin (map bytesSha256 (list (stringToBytes \"abc\") (stringToBytes \"\") (stringToBytes (vec448)))) \",\"))"
      "    (checkRange 0 130)"
      "    (digestOnly 65536)"
      "    (println (str (floatNan)))"
      "    (println (str (floatInf)))"
      "    (println (str (floatNegInf)))"
      "    (println (str (pick true) \",\" (pick false)))"
      "    (ok 0))")
    "\n")


fn hugeFixtureSrc -> String
  (stringJoin
    (list
      "(module overlayHugeFixture :x [main] :i [])"
      ""
      "fn ! main -> (Result Int64 String)"
      "  (let [(t0 (monotonicNs))"
      "        (digest (bytesSha256 (stringToBytes (stringRepeat \"a\" 1048576))))"
      "        (t1 (monotonicNs))]"
      "    (do (println digest) (println (stringFromInt64 (/ (- t1 t0) 1000000))) (ok 0)))")
    "\n")

fn ! compiled dir: String name: String src: String -> (Result String String)
  (do (assert (ok? (fileWrite (str dir "/" name ".asl") src)) (str "fileWrite " dir "/" name ".asl"))
      (mt (lk/linkEntry! (str dir "/" name ".asl"))
        ((err ds) (err (formatDiags ds)))
        ((ok m) (mt (llvm/emitLlvmProgramNative! m (str m.name ".main"))
                  ((err ds) (err (formatDiags ds)))
                  ((ok code) (ok code))))))

fn formatDiags ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn codeOf res: (Result String String) -> String
  (mt res
    ((ok code) code)
    ((err e) (str "error: " e)))

fn ! buildNative dir: String name: String src: String -> String
  (let [(ll (str dir "/" name ".ll")) (exe (str dir "/" name))]
    (do
      (assert (ok? (fileWrite ll (codeOf (compiled dir name src)))) (str "fileWrite " ll))
      (let [(linked (processRun (str "/usr/bin/clang -Wno-override-module -x ir " ll " -x none asl/host/out/libaslrt.a -lm -o " exe)))]
        (assert (= linked.exitCode 0) (str name ": clang links against libaslrt.a: " linked.stderr)))
      exe))

fn ! runNative dir: String name: String src: String -> ProcessOutput
  (processRun (buildNative dir name src))

fn ! childCpuUs -> Int64
  (mt (procRusage) ((ok u) (+ u.childrenUserUs u.childrenSysUs)) ((err _) -1))

fn ! testOverlayLinked dir: String -> Bool
  (let [(code (codeOf (compiled dir "overlayFixture" (fixtureSrc))))]
    (do
      (refute (stringStartsWith? code "error: ") (str "overlayFixture links and emits: " code))
      (refute (stringContains? code "@name.bytesSha256") "no asl_rt_builtin call naming bytesSha256 (no @name.bytesSha256 constant)")
      (assert (stringContains? code "native$2EbytesSha256(") "the emitted IR defines the overlay function native.bytesSha256")
      (assert (stringContains? code "define") "sanity: the module defines at least one function")
      true))

fn ! testFixtureParity dir: String -> Bool
  (let [(srcPath (str dir "/overlayFixture.asl"))
        (native (runNative dir "overlayFixture" (fixtureSrc)))
        (interp (processRun (str (host) " run " srcPath)))]
    (do
      (assert (= native.exitCode 0) (str "native overlayFixture exit " native.exitCode "; stderr: " native.stderr))
      (assert (= interp.exitCode 0) (str "asl-host run overlayFixture exit " interp.exitCode "; stderr: " interp.stderr))
      (assert (= native.stdout interp.stdout) "native stdout equals asl-host run stdout byte for byte (NIST vectors, direct and value-position calls, the 0..130-byte padding range, a 64KiB input, and floatNan/floatInf/floatNegInf)")
      true))

fn ! testHugeInput dir: String -> Bool
  (let [(srcPath (str dir "/overlayHugeFixture.asl"))
        (exe (buildNative dir "overlayHugeFixture" (hugeFixtureSrc)))
        (c0 (childCpuUs))
        (native (processRun exe))
        (c1 (childCpuUs))
        (cpuMs (if (and (>= c0 0) (>= c1 0)) (/ (- c1 c0) 1000) -1))
        (interp (processRun (str (host) " run " srcPath)))
        (nativeLines (stringSplit native.stdout "\n"))]
    (do
      (assert (= native.exitCode 0) (str "native overlayHugeFixture exit " native.exitCode "; stderr: " native.stderr))
      (assert (= interp.exitCode 0) (str "asl-host run overlayHugeFixture exit " interp.exitCode "; stderr: " interp.stderr))
      (assert (= (optionOr (listGet nativeLines 0) "") (optionOr (listGet (stringSplit interp.stdout "\n") 0) "")) "the 1 MiB digest matches asl-host run")
      (assert (> cpuMs 0) (str "procRusage measured the native run's CPU time: " cpuMs " ms"))
      (assert (< cpuMs 30000) (str "the native 1 MiB bytesSha256 run takes under 30000 CPU ms (user plus system of the child process, so a loaded machine stretching wall time does not count; measured near 17.3s on the reference machine, the ASL overlay running boxed Bytes ops byte at a time, far slower than prelude.c's bSha256, by design per PRELUDEASL-0); took " cpuMs " CPU ms; digest and wall ms: " native.stdout))
      true))

fn rawCaller -> irTy/SsaFunction
  (irTy/ssaFunction "m.caller" (list) (list) (irTy/tyVal)
    (list (irTy/ssaBlock "entry" (list)
            (list (irTy/ssaInstr "%a" (irTy/tyVal) (irTy/opConst (irTy/constInt 5)))
                  (irTy/ssaInstr "%c" (irTy/tyI1) (irTy/opConst (irTy/constBool true)))
                  (irTy/ssaInstr "%r" (irTy/tyVal) (irTy/opBuiltin "rawId" (list "%a"))))
            (irTy/termBranch "%c" (irTy/ssaEdge "then0" (list)) (irTy/ssaEdge "else0" (list))))
          (irTy/ssaBlock "then0" (list) (list (irTy/ssaInstr "%s" (irTy/tyVal) (irTy/opBuiltin "rawId" (list "%a")))) (irTy/termReturn "%s"))
          (irTy/ssaBlock "else0" (list) (list (irTy/ssaInstr "%t" (irTy/tyVal) (irTy/opBuiltin "rawId" (list "%r")))) (irTy/termReturn "%t"))))

fn rawCallee -> irTy/SsaFunction
  (irTy/ssaFunction "m.raw" (list) (list (irTy/ssaParam "x" (irTy/tyI64))) (irTy/tyI64)
    (list (irTy/ssaBlock "entry" (list) (list) (irTy/termReturn "x"))))

fn instrsOf f: irTy/SsaFunction -> (List irTy/SsaInstr)
  (fold (fn [(acc (List irTy/SsaInstr)) (b irTy/SsaBlock)] -> (List irTy/SsaInstr) (listAppend acc b.instrs)) (list) f.blocks)

fn countOps f: irTy/SsaFunction keep: (Fn irTy/SsaOp Bool) -> Int64
  (listLength (filter (fn [(i irTy/SsaInstr)] -> Bool (keep i.op)) (instrsOf f)))

fn ! testRewriteRawSignature -> Bool
  (let [(m (irTy/ssaModule "m" (list) (list) (list) (list) (list) (list (rawCallee) (rawCaller))))
        (rw (lk/rewriteModuleBuiltins (mapSet (mapEmpty) "rawId" "m.raw") m))
        (caller (optionOr (listGet (filter (fn [(f irTy/SsaFunction)] -> Bool (= f.name "m.caller")) rw.functions) 0) (rawCallee)))
        (verified (vfy/verifySsa rw))
        (dests (map (fn [(i irTy/SsaInstr)] -> String i.dest) (instrsOf caller)))]
    (do
      (assert (ok? verified) (str "rewritten module verifies: " (mt verified ((ok _) "ok") ((err ds) (formatDiags ds)))))
      (assert (= caller.name "m.caller") "m.caller survives the rewrite")
      (assert (= (countOps caller (fn [(o irTy/SsaOp)] -> Bool (mt o ((irTy/opBuiltin _ _) true) (_ false)))) 0) "no opBuiltin rawId remains")
      (assert (= (countOps caller (fn [(o irTy/SsaOp)] -> Bool (mt o ((irTy/opCall c _) (= c "m.raw")) (_ false)))) 3) "three calls of m.raw")
      (assert (= (countOps caller (fn [(o irTy/SsaOp)] -> Bool (mt o ((irTy/opUnbox _) true) (_ false)))) 3) "three argument unboxes to i64")
      (assert (= (countOps caller (fn [(o irTy/SsaOp)] -> Bool (mt o ((irTy/opBox _) true) (_ false)))) 3) "three result reboxes to Val")
      (assert (= (listLength dests) (listLength (distinct dests))) (str "every value is defined once in m.caller: " (stringJoin dests " ")))
      true))

fn distinct names: (List String) -> (List String)
  (fold (fn [(acc (List String)) (n String)] -> (List String) (if (listContains? acc n) acc (listAppend acc (list n)))) (list) names)

fn hasCode? res: (Result lk/LinkUnit (List irTy/IrDiag)) code: String -> Bool
  (mt res ((ok _) false) ((err ds) (listAny? (fn [(d irTy/IrDiag)] -> Bool (= d.code code)) ds)))

fn builtinNames m: irTy/SsaModule -> (List String)
  (fold (fn [(acc (List String)) (f irTy/SsaFunction)] -> (List String)
          (listAppend acc (fold (fn [(names (List String)) (i irTy/SsaInstr)] -> (List String) (mt i.op ((irTy/opBuiltin n _) (listAppend names (list n))) (_ names))) (list) (instrsOf f))))
        (list) m.functions)

fn functionNamed m: irTy/SsaModule name: String -> (Option irTy/SsaFunction)
  (listHead (filter (fn [(f irTy/SsaFunction)] -> Bool (= f.name name)) m.functions))

fn callsIn f: (Option irTy/SsaFunction) callee: String -> Bool
  (mt f
    ((none) false)
    ((some g) (> (countOps g (fn [(o irTy/SsaOp)] -> Bool (mt o ((irTy/opCall c _) (= c callee)) (_ false)))) 0)))

fn ! testRequestedBuiltin dir: String -> Bool
  (let [(src (stringJoin (list "(module overlayRequested :x [main] :i [])"
                               ""
                               "fn ! main -> (Result Int64 String)"
                               "  (do (println (str (isFinite? 1.0) \",\" (isFinite? (floatNan)) \",\" (floatInf))) (ok 0))")
                         "\n"))
        (path (str dir "/overlayRequested.asl"))]
    (do
      (assert (ok? (fileWrite path src)) (str "fileWrite " path))
      (mt (lk/linkEntry! path)
        ((err ds) (assert false (str "overlayRequested links: " (formatDiags ds))))
        ((ok m) (do
                  (assert (callsIn (functionNamed m "prelude.isFinite?") "prelude.floatInf") "precondition: prelude.isFinite? reaches floatInf by an ordinary call of prelude.floatInf")
                  (assert (callsIn (functionNamed m "overlayRequested.main") "prelude.floatInf") "overlayRequested.main's opBuiltin floatInf is rewritten into a call of prelude.floatInf")
                  (refute (listContains? (builtinNames m) "floatInf") (str "no opBuiltin floatInf remains; opBuiltins: " (stringJoin (builtinNames m) " "))))))
      (let [(native (runNative dir "overlayRequested" src))
            (interp (processRun (str (host) " run " path)))]
        (do
          (assert (= native.exitCode 0) (str "native overlayRequested exit " native.exitCode "; stderr: " native.stderr))
          (assert (= native.stdout interp.stdout) (str "native stdout equals asl-host run: " native.stdout " vs " interp.stdout))))
      true))

fn ! testLateBuiltin dir: String -> Bool
  (let [(real (fileRead "asl/prelude/prelude.asl"))
        (realText (mt real ((ok t) t) ((err _) "")))
        (customText (stringReplace realText "fn floatInf -> Float64\n  (/ 1.0 0.0)" "fn floatInf -> Float64\n  (do (bytesSha256 (bytesAlloc 0)) (/ 1.0 0.0))"))
        (preludeFile (str dir "/latePrelude.asl"))
        (path (str dir "/overlayLate.asl"))]
    (do
      (assert (ok? real) "read asl/prelude/prelude.asl")
      (refute (= customText realText) "the custom prelude's floatInf body calls bytesSha256")
      (assert (ok? (fileWrite preludeFile customText)) (str "fileWrite " preludeFile))
      (assert (ok? (fileWrite path "(module overlayLate :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println (str (floatInf))) (ok 0))\n")) (str "fileWrite " path))
      (mt (lk/linkWith! path preludeFile)
        ((err ds) (assert false (str "overlayLate links: " (formatDiags ds))))
        ((ok m) (do
                  (assert (callsIn (functionNamed m "prelude.floatInf") "native.bytesSha256") "prelude.floatInf's opBuiltin bytesSha256 is rewritten into a call of native.bytesSha256")
                  (refute (listContains? (builtinNames m) "bytesSha256") (str "no opBuiltin bytesSha256 remains; opBuiltins: " (stringJoin (builtinNames m) " "))))))
      true))

fn ! testCollidingDefinitionName dir: String -> Bool
  (let [(real (fileRead "asl/prelude/prelude.asl"))
        (realText (mt real ((ok t) t) ((err _) "")))
        (customText (str realText "\nfn mask32 x: Int64 -> Int64\n  (+ x 1)\n\nfn ! triggerMask32 -> Int64\n  (mask32 7)\n"))
        (preludeFile (str dir "/collidingPrelude.asl"))
        (path (str dir "/overlayCollide.asl"))]
    (do
      (assert (ok? real) "read asl/prelude/prelude.asl")
      (refute (stringContains? realText "mask32") "precondition: the real prelude does not already define mask32")
      (assert (ok? (fileWrite preludeFile customText)) (str "fileWrite " preludeFile))
      (assert (ok? (fileWrite path "(module overlayCollide :x [main] :i [])\n\nfn ! main -> (Result Int64 String)\n  (do (println (bytesSha256 (stringToBytes \"abc\"))) (println (str (triggerMask32))) (ok 0))\n")) (str "fileWrite " path))
      (mt (lk/linkWith! path preludeFile)
        ((err ds) (assert false (str "overlayCollide links: " (formatDiags ds))))
        ((ok m) (do
                  (assert (someOf? (functionNamed m "native.mask32")) "the overlay's own internal mask32 is still lowered")
                  (assert (someOf? (functionNamed m "prelude.mask32")) "the colliding prelude's own distinct mask32 is also lowered, not starved by the overlay's same-named request")
                  (assert (callsIn (functionNamed m "native.compressBlock") "native.mask32") "the overlay's compressBlock still calls its own mask32")
                  (assert (callsIn (functionNamed m "prelude.triggerMask32") "prelude.mask32") "the colliding prelude's triggerMask32 calls its own mask32"))))
      true))

fn someOf? o: (Option irTy/SsaFunction) -> Bool
  (mt o ((some _) true) ((none) false))

fn ! testOverlayErrors dir: String -> Bool
  (let [(bad (str dir "/ovlBad/")) (unreadable (str dir "/ovlUnreadable/")) (good (str dir "/ovlGood/")) (missing (str dir "/ovlMissing/"))]
    (do
      (assert (= (processRun (str "mkdir -p " bad " " good " " unreadable)).exitCode 0) "mkdir overlay fixture directories")
      (assert (ok? (fileWrite (str bad "broken.asl") "(module native :x [] :i [])\n\nfn broken -> Int64\n  (+ 1")) "fileWrite broken.asl")
      (assert (ok? (fileWrite (str unreadable "locked.asl") "(module native :x [] :i [])\n")) "fileWrite locked.asl")
      (assert (= (processRun (str "chmod 000 " unreadable "locked.asl")).exitCode 0) "chmod 000 locked.asl")
      (assert (ok? (fileWrite (str good "one.asl") "(module native :x [] :i [])\n\nfn one -> Int64\n  1\n")) "fileWrite one.asl")
      (let [(badRes (lk/overlayUnitAt! bad))
            (unreadableRes (lk/overlayUnitAt! unreadable))
            (goodRes (lk/overlayUnitAt! good))
            (missingRes (lk/overlayUnitAt! missing))]
        (do
          (assert (hasCode? badRes "ERR_LOWER_PARSE") "a parse error in an overlay file is ERR_LOWER_PARSE")
          (assert (hasCode? unreadableRes "ERR_LINK_READ") "an unreadable overlay *.asl file is ERR_LINK_READ")
          (assert (= (mt goodRes ((ok u) (listLength u.forms)) ((err _) -1)) 2) "a good overlay file gives its header plus its one defun")
          (assert (= (mt missingRes ((ok u) (listLength u.forms)) ((err _) -1)) 1) "a missing overlay directory is the bare header")
          (mt (lk/loadClosure! (str dir "/overlayFixture.asl"))
            ((err ds) (assert false (str "loadClosure overlayFixture: " (formatDiags ds))))
            ((ok units) (assert (mt (lk/linkUnitsWith units (err (list)) badRes) ((ok _) false) ((err ds) (listAny? (fn [(d irTy/IrDiag)] -> Bool (= d.code "ERR_LOWER_PARSE")) ds)))
                                "linkUnitsWith fails with the overlay's ERR_LOWER_PARSE rather than linking past it")))
          true))))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a work directory")
      (testOverlayLinked dir)
      (testFixtureParity dir)
      (testHugeInput dir)
      (testRewriteRawSignature)
      (testRequestedBuiltin dir)
      (testLateBuiltin dir)
      (testCollidingDefinitionName dir)
      (testOverlayErrors dir)
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "work directory removed")
      true))
