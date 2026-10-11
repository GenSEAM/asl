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
  (mt (route/hostFactsOf "Darwin arm64")
    ((ok o) o)
    ((err _) (none)))

fn ! digestOf text: String -> String
  (bytesSha256 (stringToBytes text))

fn diagText ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.locus ": [" d.code "] " d.message)) ds) "; ")

fn lowerUnit units: (List lk/LinkUnit) prelude: lk/LinkUnit acc: lk/LinkAcc u: lk/LinkUnit -> lk/LinkAcc
  (mt (low/lowerLinked u.forms u.positions (low/LinkScope :path u.path :imports (lk/importForms units u) :prelude prelude.forms :strings acc.strings :only (none)))
    ((ok m) (lk/LinkAcc :strings m.strings :modules (listAppend acc.modules (list m)) :requested acc.requested :diags acc.diags))
    ((err ds) (lk/LinkAcc :strings acc.strings :modules acc.modules :requested acc.requested :diags (listAppend acc.diags ds))))

fn ! corpusTexts -> (List (Pair String String))
  (mt (lk/loadClosure! (entryPath))
    ((err ds) (list (pair "closure" (str "ERR " (diagText ds)))))
    ((ok units)
      (mt (lk/loadClosure! (lk/preludePath))
        ((err ds) (list (pair "prelude" (str "ERR " (diagText ds)))))
        ((ok pUnits)
          (mt (facts)
           ((none) (list (pair "facts" "ERR Darwin arm64 has no route facts")))
           ((some f)
          (let [(prelude (optionOr (listHead pUnits) (lk/emptyUnit "prelude")))
                (entryName (optionOr (listHead (map (fn [(u lk/LinkUnit)] -> String u.name) (filter (fn [(u lk/LinkUnit)] -> Bool (= u.path (entryPath))) units))) ""))
                (lowered (fold (fn [(acc lk/LinkAcc) (u lk/LinkUnit)] -> lk/LinkAcc (lowerUnit units prelude acc u))
                               (lk/LinkAcc :strings (list) :modules (list) :requested (list) :diags (list)) units))
                (rows (map (fn [(m irTy/SsaModule)] -> (Pair String String)
                             (let [(res (if (= m.name entryName) (nat/emitLlvmProgramFor f m (str m.name ".main")) (nat/emitLlvmModuleFor f m)))]
                               (mt res
                                 ((ok text) (pair m.name text))
                                 ((err ds) (pair m.name (str "ERR " (diagText ds)))))))
                           lowered.modules))
                (withPrelude (lk/lowerPrelude prelude lowered))
                (preludeMods (filter (fn [(m irTy/SsaModule)] -> Bool (= m.name prelude.name)) withPrelude.modules))
                (preludeMod (irTy/ssaModule "prelude" withPrelude.strings (lk/firstByName (fold (fn [(a (List irTy/SsaTypeDecl)) (m irTy/SsaModule)] -> (List irTy/SsaTypeDecl) (listAppend a m.types)) (list) preludeMods))
                                            (lk/firstRecordByName (fold (fn [(a (List irTy/SsaRecordDecl)) (m irTy/SsaModule)] -> (List irTy/SsaRecordDecl) (listAppend a m.records)) (list) preludeMods))
                                            (list) (list) (lk/allFunctions preludeMods)))
                (preludeRow (mt (nat/emitLlvmModuleFor f preludeMod)
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
               (if (stringEmpty? dir) () (mt (fileWrite (str dir "/" (stringReplace (pairFirst r) "/" "-") ".ll") (pairSecond r)) ((ok _) ()) ((err e) (eprintln (str "write failed: " e)))))))
           rows)
      (ok 0)))

fn expectedDigests -> (List (Pair String String))
  (list
    (pair "asl-syntax/core/source 407026" "bbc21deb2bc7ee5a9a08b31eb65d3b9b43e3a28ef4dfeaae051baefbdfe9a912")
    (pair "asl-syntax/core/tree 295047" "f915f855eff903faf430dbd1176af339bb17aede7edad357b3f0641c6c6fb45e")
    (pair "asl-syntax/core/symbols 361575" "3ee63ad639ff65537e6a71ca443d4d11eedde2b741e6edbce5f79edd7797a364")
    (pair "asl-syntax/core/outline 87472" "20218665b69969c2956e9c944c7e9f5aaf31737aa90fbfe7c239b042b2f41d6c")
    (pair "asl-syntax/core/print 60704" "43df06143166f200bf4ccb3350ef50d7e083576e8a82bee213e00ebdc8d5e166")
    (pair "asl-json/json 458057" "319e75e47f277a5ac4967a35eacff284142d06abbea537f498c85e155793fd78")
    (pair "asl-syntax/core/bytesText 32401" "4ee17d9ec2a8e876a470edd331b953781d724a4694d982dab7dd70f584c44f27")
    (pair "asl-syntax/json 781805" "f69cce1b184c8d3bcf180481f277612769a2d2143adb597452a09ec8230bf49f")
    (pair "asl-syntax/js/lex 674886" "d48edad6706c2ca35790d77e472cbfb6a522da882a3862a3a17415de9571c394")
    (pair "asl-syntax/js/expr 880802" "8b383ee00f0689abb707a78225f3a708be0a3de3222f5e68082780340b9a9cde")
    (pair "asl-syntax/js/cover 1270969" "9c4579e2c8f07411ce7b06226fb9f85f61b042c6f46ece9b6217bac3c6fedaea")
    (pair "asl-syntax/js/stmt 1000531" "3d28f2c031b30e8bd63359dfafa6c72ac5684daf418d90bb82b8ae5efb87c55d")
    (pair "asl-syntax/js/module 515991" "18b2167af42321b8be0e869427a7c83b1d5f6142e119c725ce19a229361a8ea1")
    (pair "asl-syntax/js/recover 411364" "b93cc5c72af788b96510cd40ac694516b15268b56228934540d9019262cbb5af")
    (pair "asl-syntax/ts/types 1234070" "022583f504883451771fbc99117e2176c6b7dc678deeaeeb55a77edeab3e65f8")
    (pair "asl-syntax/ts/decl 1159145" "8e4117f2b52249707e8f9059d8287eb765aa53683a324e77ff701a9cbab4cb93")
    (pair "asl-syntax/ts/module 209828" "92cdf3b54b99b73e8f3e20b87a651bbdb5f0bdb5cac70657a646e8baced7f46a")
    (pair "asl-syntax/jsx 844596" "e3c6432a4ef2e15f63a2a4ea6ec9897a7b40482fcaab3d92a88cfa1ba915c806")
    (pair "asl-syntax/tsx 609926" "42b9293b93606406243dfa0a52384550644268c0766f5fd9a867174cafe583fa")
    (pair "asl-syntax/css/lex 266351" "06fd5ae2864328c6936faebadb2ecfd5e444ab4891e7e8fe33687cbd55eb6f5f")
    (pair "asl-syntax/css/rules 622816" "cab573df9e5d748e085316f3c7efaae4de3963b61e2db331d3472ba3a031bf67")
    (pair "asl-syntax/html/lex 739371" "d2368151a945c3b0f1a933d3fd98805ac6db42a9d855e22bb93b37d3fa4a75cf")
    (pair "asl-syntax/html/tree 426098" "4300c67727e690da0f23477a7f108e660531e1b73e290575dfc7fd013585ad43")
    (pair "asl-syntax/xml 641436" "707452060d294fe8c506b1fe15fc3cba0964b90911114d60525428fdb72e6f98")
    (pair "asl-forms/kernel 579283" "1adf2b0c98f6d27bac4498a6b3c37252779df29ed9663db7108f3c2ff93059c5")
    (pair "asl-forms/check 928035" "fec94d9668fddabf39751b23c5595320462f039b29cdb2bd95bc075b67155158")
    (pair "asl-forms/tests/checkSemanticTest 614421" "a8bdb57c5441c710761eda21300b9e109bdc19d558257b8266b536971be652f2")
    (pair "emitRefsEntry 144139" "1eb45f7524e204045eb03fdc37099047bf7188142755188b6b9bc13fe8043b84")
    (pair "prelude 604395" "b32b66134018c47d65682a8b7b120b489b416c0b156fed2e47365c437dd64bb6"))

fn ! runTests -> Bool
  (let [(got (corpusDigests))
        (want (expectedDigests))]
    (do
      (assert (= (listLength got) (listLength want)) (str "corpus has " (listLength want) " modules, emitted " (listLength got)))
      (assert (listEmpty? (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want))
              (str "every module keeps its digest; changed: " (stringJoin (map (fn [(w (Pair String String))] -> String (pairFirst w)) (filter (fn [(w (Pair String String))] -> Bool (not (listContains? got w))) want)) ", ")))
      true))
