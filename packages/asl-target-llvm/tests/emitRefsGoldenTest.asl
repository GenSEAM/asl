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

; (:m :ref HLLOWSMERGE :do "11 rows repinned on merge main into sh/HLLOWS (asl-parser/ast, asl-checker/resolve|unify|tailPos|constAssert|check|checkCached, asl-forms/check|tests/checkSemanticTest, emitRefsEntry, prelude): each pair's own size and sha256 were printed by this file's own main on the merged tree, never hand-written; the other rows are unchanged")
fn expectedDigests -> (List (Pair String String))
  (list
    (pair "asl-syntax/core/source 407026" "bbc21deb2bc7ee5a9a08b31eb65d3b9b43e3a28ef4dfeaae051baefbdfe9a912")
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
    (pair "asl-forms/kernel 585898" "057b726aa79bbf7838b67208229f390a2f3419d312eedb5a1aaf3ed8d6c379b1")
    (pair "asl-checker/types 640125" "aaec0a9ebe6ed723b53c0d04ee56d88c086dc2be16129e57c4d2668ac18a9d8e")
    (pair "asl-parser/lexer 490996" "b83b11e3aeeb2209079bc3b044d3d001569b26d589c5723383e260392f8ecbaa")
    (pair "asl-parser/reader 365352" "e95dc63c422b1e9a93017d1e9d6ca34c4c7ac5f2d9f1a9321b274e32ce57f3d4")
    (pair "asl-parser/indentLexer 1046485" "d44f1418aaddae073b2f231e319ca9c9674eed267f1cb1b0871542c71830a95e")
    (pair "asl-parser/fnHeader 209482" "5b5d0981af189e8222d0c93b9bd4f1a5e67a7ac81f14deb060f73bf809abfdce")
    (pair "asl-parser/indentParser 2539876" "98d6b562824006dfd5a6daa988b3f7ba4fd19170c401aea57913f629e9a9d966")
    (pair "asl-parser/ast 1928172" "749367f421444e9c847df552894ac1c3a81962b2af3cd0918b8ffd0aa0210b50")
    (pair "asl-checker/resolve 3411741" "814ce7067f959de30d1db170ad356fbd8b2e4e228914c1ad86af84c1ecc60902")
    (pair "asl-checker/unify 400064" "86ecf7082eadc8b9de5a00442165446f1e29584276c0901b914829957d102bdf")
    (pair "asl-checker/tailPos 435197" "c83ee72a3147abb38fb076ad622e5efdb993a6665bc4deb2b4c96719083165c7")
    (pair "asl-checker/constAssert 443218" "4072803ca88559b71096ae4f6cbda3a8bc66b139bde1f473f09d737b13b416bd")
    (pair "asl-checker/check 2338865" "1a1bb2732f3939f4e36c8ed830e54622436ed110350bace12ffc7a4f1c586b31")
    (pair "asl-checker/checkCached 325967" "3a8960fc9f145fcd9cd3c350126b281b116f6479daa9a9b47c9f27773e01aa9a")
    (pair "asl-forms/check 926510" "83967c0a6a190a0fa696993519df640a1b16f5a85cea3ee1c95299cb0e1b52e0")
    (pair "asl-forms/tests/checkSemanticTest 719113" "74fe30d3208ca86a2f72f5377819623c2e3f5f64f52e6a619ab99df99b3020b9")
    (pair "emitRefsEntry 228068" "7a7bd515947ee626e86ab4510b0ccd4dba9e86e8b2fb07c487e8157b59b46095")
    (pair "prelude 741161" "022fc84f72bcb5550b1db69b40c94dcc0a487322d172cc788fa797a6d00e2271"))

fn ! runTests -> Bool
  (let [(got (corpusDigests))
        (want (expectedDigests))]
    (do
      (assert (= (listLength got) (listLength want)) (str "corpus has " (listLength want) " modules, emitted " (listLength got)))
      (assert (listEmpty? (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want))
              (str "every module keeps its digest; changed: " (stringJoin (map (fn [(w (Pair String String))] -> String (pairFirst w)) (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want)) ", ")))
      true))
