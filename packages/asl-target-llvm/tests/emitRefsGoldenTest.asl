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
; (:m :ref UNBOXFIELDS :do "40 rows repinned after UFEMIT + UFRT: schemas with Int64/Float64/Bool fields get descriptor globals, permuted raw stores and descriptor-guarded reads, and record readers go through recArity/recKeys/recGet; size and sha256 printed by this file's own main")
; (:m :ref WAVE2 :do "42 rows repinned on the integrated tree (UFEMIT unboxed record fields, hashRt, loop closure clones, FREECHAIN2 rc changes); size and sha256 printed by this file own main, never hand-written")
fn expectedDigests -> (List (Pair String String))
  (list
    (pair "asl-syntax/core/source 422108" "1b84386fee83d7ffd9b220bd606dbfde5de7189345192643bdda051c76f1aee7")
    (pair "asl-syntax/core/tree 273747" "c8753ed63fcde4b11c82196f3e09cacae45fb320dd639e4267b82a88ae68eea4")
    (pair "asl-syntax/core/symbols 339034" "5047081b707644f3245a589a6936025f64eaa7619f87a9261bc1f6d70cfcf11f")
    (pair "asl-syntax/core/outline 97807" "05f0e852ae74d0b3730ef411b7b9079af23d25339091d7affa1199d232f23450")
    (pair "asl-syntax/core/print 63173" "e476abb357b1f0ce88a183e5c38036fe7a6dc3b6a8716a87a66951a7485d03a4")
    (pair "asl-json/json 461593" "2f9bebd75f4e70843257c95ddd05b470a81b09d5b8f6cb01c50b40a4d6bed02d")
    (pair "asl-syntax/core/bytesText 32401" "4ee17d9ec2a8e876a470edd331b953781d724a4694d982dab7dd70f584c44f27")
    (pair "asl-syntax/json 769057" "d9af9967129dc1e7b166d52d52d188935119fa8afad4d5a2faa48f8a923e8882")
    (pair "asl-syntax/js/lex 676645" "d74c5d56b67f97628186e133451a605f6b9c281931417d04c3ba211b77b7ad61")
    (pair "asl-syntax/js/expr 898822" "907dc674916e551cba683169cf325977ef8785c109b84c524c4f02e0b60cf4d4")
    (pair "asl-syntax/js/cover 1295378" "c104286d20aa1dfa6f66134a04f36b2203764d75c8c15bbe189ab12f244ce66d")
    (pair "asl-syntax/js/stmt 1047551" "1763b6ad3fa9ed3da5d0d6180cb9f59c8a44584de6453dccbd70591df0aa996a")
    (pair "asl-syntax/js/module 520661" "3093430e677608268ab28d3b8caa253f4b92975402a657121a854d03ebd994c6")
    (pair "asl-syntax/js/recover 417804" "78944eaff936164da558753c6f3796385e58c0387fcbdc360961b5bdbd44b48b")
    (pair "asl-syntax/ts/types 1269914" "192fd21d763ae7d7e27b088e4990e62d13ebf383bf1dda1781011e8d1b3c2a3c")
    (pair "asl-syntax/ts/decl 1213500" "cabb3b57cf315dfaaf5e70f20958745e2cebfea5c8c50a5ff98cf9d595072faf")
    (pair "asl-syntax/ts/module 217106" "c324a815e4ad851801aba18f47228fc92646ff38fb2066f37a07331de61a4abd")
    (pair "asl-syntax/jsx 850307" "e9efc582bfc0575ee724f2ff9563b965757ca1d08e154329084b43e05538c1f2")
    (pair "asl-syntax/tsx 628690" "aed1b35c54915e734ba2307d73eb3f8b6bb4b6848d2f1aeecef955497b99d7e9")
    (pair "asl-syntax/css/lex 266351" "06fd5ae2864328c6936faebadb2ecfd5e444ab4891e7e8fe33687cbd55eb6f5f")
    (pair "asl-syntax/css/rules 658615" "159b9dd992ddc3d2eefa21f699c3d5e51afc3f944d97b0dbd7759c12c8a9cc0d")
    (pair "asl-syntax/html/lex 768732" "90c16a55d4bf1b53d0a69757c5afc25feed83f22ee78110be76ff7903fb5e27c")
    (pair "asl-syntax/html/tree 450107" "aab044b56d567d1f00385dae154bc0393595056fd1e325087e3e5d828d4c77a1")
    (pair "asl-syntax/xml 650192" "1ae1e850ac30c0a13a43b0b61f6c4a1dce9a869733b38dae26ff298bb8e29edf")
    (pair "asl-forms/kernel 589491" "b4853b7eae381a57fca42ab963876943727f3239cd6dc687cac1c6a969118237")
    (pair "asl-checker/types 654830" "909c12474ee2989d26ce9eeb274b81842dac4901ce3ed3cca20934de17737455")
    (pair "asl-parser/lexer 470534" "699267de10160a5005cc624623aab70e09643da50f0a3ce6d98c8ebc9e6176ba")
    (pair "asl-parser/reader 359729" "892154fe89c81ad1153f3df7d3aa76fec52a6fb9a265083cc9f740145ed31b8c")
    (pair "asl-parser/indentLexer 1016444" "923f3d88ff2ad48351750c7d9b38717a7faebe224c5b046ddc2905341ac3a0a7")
    (pair "asl-parser/fnHeader 214091" "b050c9ba518d220a5a15607f4e8e5f833a7a6a0cebecfb47628eb60cb784ac6e")
    (pair "asl-parser/indentParser 2607518" "2ec70cbcca006fb31400b81770b9668f2f1cdc4fa34e9a25d62a35002a94804c")
    (pair "asl-parser/ast 1991024" "7c082d5a73f40080a595a6473dbc9bc7d68641268811034d8dad0bc1de90a32d")
    (pair "asl-checker/resolve 3425335" "1ab15b504f722e8f4afdf621759a50872f92a06d13c1dc28f03b053eb1d8ba79")
    (pair "asl-checker/unify 404738" "165e6069ce5b2f4268bd1d0ae28f952e9e29f6301014da5d6b65180055f0b64a")
    (pair "asl-checker/tailPos 439677" "da26e40e1c3e70887fd6cc429aa44ca02208f2582c0c54f9eb805014a3b73b61")
    (pair "asl-checker/constAssert 448026" "5bfd7c1151b0da09c93792d0dd26c933965512c441694ff5e3a69352a7927670")
    (pair "asl-checker/check 2224295" "a830e229622b247532e6a3b1cd73a144f572f2c51e800d40c690ca170a6448b3")
    (pair "asl-checker/checkCached 331525" "6dccbdfd848922771fe9ed4163201aa7cf53720b5b5fb89422f27f22c5da3260")
    (pair "asl-forms/check 934449" "3180eeb9f4cd057c9dbe0fc1ba4a4c2ca43509d85bfdba3fe70fe7016ca729fe")
    (pair "asl-forms/tests/checkSemanticTest 725814" "ace01b604aabce3fa9e412049f22e877b4042fd8c187560c7801d3887ad3fa14")
    (pair "emitRefsEntry 231101" "815dcd75bbf1a7d85a1e7e7a0be2c9cd4ed0f6593d7d7c97ca229fe76807172a")
    (pair "prelude 765943" "3b9a4d17cc9afc3eff661c75063561a6f1960cecaec1fc90b5d3adf449975ba3"))

fn ! runTests -> Bool
  (let [(got (corpusDigests))
        (want (expectedDigests))]
    (do
      (assert (= (listLength got) (listLength want)) (str "corpus has " (listLength want) " modules, emitted " (listLength got)))
      (assert (listEmpty? (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want))
              (str "every module keeps its digest; changed: " (stringJoin (map (fn [(w (Pair String String))] -> String (pairFirst w)) (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want)) ", ")))
      true))
