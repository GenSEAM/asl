(module asl-target-llvm/tests/emitRefsGoldenTest
  :x [runTests main corpusDigests]
  :i [(asl-ir/types :a irTy)
      (asl-ir/lower :a low)
      (asl-ir/link :a lk)
      (asl-target-llvm :a nat)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/sysRoute :a route)])

fn entryPath -> String
  "asl/packages/asl-target-llvm/tests/fixtures/emitRefs/entry.asl"

fn facts -> (Option libc/TripleFacts)
  (match (route/hostFactsOf "Darwin arm64")
    ((ok o) o)
    ((err _) (none)))

fn ! digestOf text: String -> String
  (bytesSha256 (stringToBytes text))

fn diagText ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn lowerUnit units: (List lk/LinkUnit) prelude: lk/LinkUnit acc: lk/LinkAcc u: lk/LinkUnit -> lk/LinkAcc
  (match (low/lowerLinked u.forms u.positions (low/LinkScope :path u.path :imports (lk/importForms units u) :prelude prelude.forms :strings acc.strings :only (none)))
    ((ok m) (lk/LinkAcc :strings m.strings :modules (listAppend acc.modules (list m)) :requested acc.requested :diags acc.diags))
    ((err ds) (lk/LinkAcc :strings acc.strings :modules acc.modules :requested acc.requested :diags (listAppend acc.diags ds))))

fn ! corpusTexts -> (List (Pair String String))
  (match (lk/loadClosure! (entryPath))
    ((err ds) (list (pair "closure" (str "ERR " (diagText ds)))))
    ((ok units)
      (match (lk/loadClosure! (lk/preludePath))
        ((err ds) (list (pair "prelude" (str "ERR " (diagText ds)))))
        ((ok pUnits)
          (match (facts)
           ((none) (list (pair "facts" "ERR Darwin arm64 has no route facts")))
           ((some f)
          (let [(prelude (optionOr (listHead pUnits) (lk/emptyUnit "prelude")))
                (entryName (optionOr (listHead (map (fn [(u lk/LinkUnit)] -> String u.name) (filter (fn [(u lk/LinkUnit)] -> Bool (= u.path (entryPath))) units))) ""))
                (lowered (fold (fn [(acc lk/LinkAcc) (u lk/LinkUnit)] -> lk/LinkAcc (lowerUnit units prelude acc u))
                               (lk/LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) units))
                (rows (map (fn [(m irTy/SsaModule)] -> (Pair String String)
                             (let [(res (if (= m.name entryName) (nat/emitLlvmProgramFor f m (str m.name ".main")) (nat/emitLlvmModuleFor f m)))]
                               (match res
                                 ((ok text) (pair m.name text))
                                 ((err ds) (pair m.name (str "ERR " (diagText ds)))))))
                           lowered.modules))
                (withPrelude (lk/lowerPrelude prelude lowered))
                (preludeMods (filter (fn [(m irTy/SsaModule)] -> Bool (= m.name prelude.name)) withPrelude.modules))
                (preludeMod (irTy/ssaModule "prelude" withPrelude.strings (lk/firstByName (fold (fn [(a (List irTy/SsaTypeDecl)) (m irTy/SsaModule)] -> (List irTy/SsaTypeDecl) (listAppend a m.types)) (list) preludeMods))
                                            (lk/firstRecordByName (fold (fn [(a (List irTy/SsaRecordDecl)) (m irTy/SsaModule)] -> (List irTy/SsaRecordDecl) (listAppend a m.records)) (list) preludeMods))
                                            (list) (list) (lk/allFunctions preludeMods)))
                (preludeRow (match (nat/emitLlvmModuleFor f preludeMod)
                              ((ok text) (pair "prelude" text))
                              ((err ds) (pair "prelude" (str "ERR " (diagText ds))))))]
            (if (listEmpty? lowered.diags)
              (listAppend rows (list preludeRow))
              (list (pair "lower" (str "ERR " (diagText lowered.diags))))))))))))

fn ! corpusDigests -> (List (Pair String String))
  (map (fn [(r (Pair String String))] -> (Pair String String) (pair (str (pairFirst r) " " (stringLength (pairSecond r))) (digestOf (pairSecond r)))) (corpusTexts))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(rows (corpusTexts))
        (dir (optionOr (listHead args) ""))]
    (do
      (map (fn [(r (Pair String String))] -> ()
             (do
               (println (str "(pair \"" (pairFirst r) " " (stringLength (pairSecond r)) "\" \"" (digestOf (pairSecond r)) "\")"))
               (if (stringEmpty? dir) () (match (fileWrite (str dir "/" (stringReplace (pairFirst r) "/" "-") ".ll") (pairSecond r)) ((ok _) ()) ((err e) (eprintln (str "write failed: " e)))))))
           rows)
      (ok 0)))

; (:m :ref PERF-MAPRANK :do "prelude row repinned: the treap rank hash changed, then PERF-MONO-MAPKEY added opsrt.keyCmp and PERF-FREECHAIN the has and getOr walks; size and sha256 printed by this file's own main, the other rows unchanged")
; (:m :ref HLLOWSMERGE :do "11 rows repinned on merge main into sh/HLLOWS (asl-parser/ast, asl-checker/resolve|unify|tailPos|constAssert|check|checkCached, asl-forms/check|tests/checkSemanticTest, emitRefsEntry, prelude): each pair's own size and sha256 were printed by this file's own main on the merged tree, never hand-written; the other rows are unchanged")
; (:m :ref LLVM-TAILCALL-UNSUPPORTED-20261022 :do "8 rows repinned (asl-checker/check|checkCached|resolve, asl-forms/check|kernel|tests/checkSemanticTest, asl-syntax/core/source, prelude): the emitted text of each differs from the previous pin only by the appended @llvm.compiler.used line of pinMusttailCallees, checked by diffing this file's main output with and without the pass; sizes and digests printed by main")
; (:m :ref PERF-MONO-MAPKEY :do "prelude row repinned: keyCompare and the FNV rank step moved from lowering to the LLVM-only ssaOpt nativePrelude pass, so treap call sites call prelude.preludeKeyOrder and only its body is opsrt.keyCmp; size and sha256 printed by this file's own main")
; (:m :ref PERF-REALPATH-CACHE :do "asl-checker/resolve row repinned: the walk lstats instead of realpath plus stat, the index caches each importer directory's climb, loadModuleDepsIx! hands the index back; size and sha256 printed by this file's own main")
; (:m :ref RECSROA :do "asl-checker/resolve row repinned: recordScalar turns scanUp! and headerStep into wrappers over workers that take the record fields; size and sha256 printed by this file's own main, the other rows unchanged")
fn expectedDigests -> (List (Pair String String))
  (list
    (pair "asl-syntax/core/source 424536" "5e8d286dd00d7512928a8e55610e7e0fd070352dc35e933ef67a31627947bc98")
    (pair "asl-syntax/core/tree 295301" "1632379eeed6ceca23c4a38323f6e6cdf2c0db2e1dfd6c1dd2854873c4f4fe80")
    (pair "asl-syntax/core/symbols 361570" "e6e4edc97121367826b949d58295792d6c8f82d11e179edfaf56e128f4388c8f")
    (pair "asl-syntax/core/outline 87472" "20218665b69969c2956e9c944c7e9f5aaf31737aa90fbfe7c239b042b2f41d6c")
    (pair "asl-syntax/core/print 60704" "43df06143166f200bf4ccb3350ef50d7e083576e8a82bee213e00ebdc8d5e166")
    (pair "asl-json/json 458057" "319e75e47f277a5ac4967a35eacff284142d06abbea537f498c85e155793fd78")
    (pair "asl-syntax/core/bytesText 32401" "4ee17d9ec2a8e876a470edd331b953781d724a4694d982dab7dd70f584c44f27")
    (pair "asl-syntax/json 781805" "f69cce1b184c8d3bcf180481f277612769a2d2143adb597452a09ec8230bf49f")
    (pair "asl-syntax/js/lex 674886" "d48edad6706c2ca35790d77e472cbfb6a522da882a3862a3a17415de9571c394")
    (pair "asl-syntax/js/expr 881132" "d7e3d4191c06fff4d1d14c538dba13b721c4560e628db9835d2ffb8034460fe3")
    (pair "asl-syntax/js/cover 1271244" "ed54e387ab22a389e2e9b0f2389dfe1fddc8e50b7db5d5f86998cbcbb24a9223")
    (pair "asl-syntax/js/stmt 1023929" "deade5fed60c9e0319f5e6e1789720f3f020572834c17d88da4c616f6008a767")
    (pair "asl-syntax/js/module 515991" "10800e2cdc142b9d35b98a3c080ccee78479ddba1f9134b500632b4d0eff1215")
    (pair "asl-syntax/js/recover 411364" "b93cc5c72af788b96510cd40ac694516b15268b56228934540d9019262cbb5af")
    (pair "asl-syntax/ts/types 1242868" "d7b185922a9db526ba2fa48a2eeee3cdf81e573fcb3030efa7505427ece210e3")
    (pair "asl-syntax/ts/decl 1187854" "1a4d1c0a52361098f97fd47aea9bd845e0710d8ffc58d3988a3d28c7ccdb1ea9")
    (pair "asl-syntax/ts/module 212484" "8c64c74a633a412a96c6bbf07dcf2a74c81f843b1b2e6789cf36993fef4eb520")
    (pair "asl-syntax/jsx 844596" "e3c6432a4ef2e15f63a2a4ea6ec9897a7b40482fcaab3d92a88cfa1ba915c806")
    (pair "asl-syntax/tsx 618116" "042a40d1f77b4e505bc06964b702e24927a1ca84fb08d3fc3033ee2481b16c5b")
    (pair "asl-syntax/css/lex 266351" "06fd5ae2864328c6936faebadb2ecfd5e444ab4891e7e8fe33687cbd55eb6f5f")
    (pair "asl-syntax/css/rules 622816" "cab573df9e5d748e085316f3c7efaae4de3963b61e2db331d3472ba3a031bf67")
    (pair "asl-syntax/html/lex 739371" "d2368151a945c3b0f1a933d3fd98805ac6db42a9d855e22bb93b37d3fa4a75cf")
    (pair "asl-syntax/html/tree 426084" "52efe6c9f4a8ec2fd3fd8461e237d0be3b37003ba8c491dec05fe324386d8cfa")
    (pair "asl-syntax/xml 641502" "075bda825830a82711eb8e0ede2363973d0c55481bfe8c43d28af559e031a086")
    (pair "asl-forms/kernel 586026" "8950f729588d330d1b20e50a75452e60f5411bda3e5f1d3e6d8854d095cdd420")
    (pair "asl-checker/types 640989" "fa9debc48392ca600ff454d59d0ac4662ffed64b025340767771e1bb553b0bd4")
    (pair "asl-parser/lexer 491133" "c6590f8943ba167e862a5439d5452216afb8ff60ce12bf3908da1bd5b0532610")
    (pair "asl-parser/reader 365489" "ac7e6adf567aea0c54d9c1cf9edd7df683a7b64b60244117be09a05245c92bda")
    (pair "asl-parser/indentLexer 1046622" "f301bb7cd7c112367fa974499f33e8d05147b13cc048bc956214748843fe7f1f")
    (pair "asl-parser/fnHeader 209619" "e4a2b5493a95744b4a83c980dcc4791f1bf233bc3901950479df945f44b66f38")
    (pair "asl-parser/indentParser 2540013" "b460dbd75300807daa393d713f38749ae29d5c31cd595f48c7184c897ec0d569")
    (pair "asl-parser/ast 1928309" "c4a2e924d13bb201a68bfd464dbf4e49c65aacbe6accbf7ea6df13d86ce26226")
    (pair "asl-checker/resolve 3449101" "83558462d1896692b2b9aebcb84b0c8d16b284f96c822782c1716c71f1e34902")
    (pair "asl-checker/unify 400201" "9feec72acedd814ef1e8e20d578a1808c40067164a22114eba7c422f0962496b")
    (pair "asl-checker/tailPos 435334" "2d4f611f89a9339aa360f4f3a7b96879ced1519ebe6973c9e80f2e019ac54c8b")
    (pair "asl-checker/constAssert 443355" "f5f14846a5be15aae2513af4877513c8f0e674af898940199e3c4fb5a8094bd2")
    (pair "asl-checker/check 2339151" "8f55cf2fb9d7c375a585fd8f6fdee68b281498a20e75c1e1b642a2c09d107eed")
    (pair "asl-checker/checkCached 326232" "813040cc88f393b849a01f0d4da70a482e09e90002cd06443ee6081e37e41671")
    (pair "asl-forms/check 926775" "616744bef1d57260283acff603687ccdd272cdfd47e975eda66c17377f2205ff")
    (pair "asl-forms/tests/checkSemanticTest 719378" "b2bf046b16e544cd84782dca5286be9b86f8b3aa218f18c5d3c95c5ee5383c5c")
    (pair "emitRefsEntry 228205" "f4edb6d636684c2b765d49abd814773752f80af6b4ad5dfb4c935f18f4d547ff")
    (pair "prelude 753769" "5bf0e2eafb04192006781495439d551769773c2830ba5123377897d28f036b50"))

fn ! runTests -> Bool
  (let [(got (corpusDigests))
        (want (expectedDigests))]
    (do
      (assert (= (listLength got) (listLength want)) (str "corpus has " (listLength want) " modules, emitted " (listLength got)))
      (assert (listEmpty? (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want))
              (str "every module keeps its digest; changed: " (stringJoin (map (fn [(w (Pair String String))] -> String (pairFirst w)) (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want)) ", ")))
      true))
