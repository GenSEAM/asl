(module asl-ir/tests/linkTest
  :x [geomSource utilSource appSource writeFixture! runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/printer :a prn)
      (asl-ir/link :a lk)
      (asl-parser/ast :a ast)])

fn joinLines xs: (List String) -> String
  (stringJoin xs "\n")

fn geomSource -> String
  (joinLines (list
    "(module linkfx/geom :x [Shape Box area size boxArea firstSide])"
    ""
    "(enum Shape (:c circle [(r Int64)] \"round\") (:c rect [(w Int64) (h Int64)] \"box\"))"
    ""
    "(schema Box (:f w Int64 \"width\") (:f h Int64 \"height\"))"
    ""
    "(fn area [(s Shape)] -> Int64"
    "  (mt s ((circle r) (* 3 (* r r))) ((rect w h) (* w h))))"
    ""
    "(fn size [(s Shape)] -> Int64"
    "  (mt s ((circle r) r) ((rect w h) (+ w h))))"
    ""
    "(fn boxArea [(b Box)] -> Int64"
    "  (* b.w b.h))"
    ""
    "(fn firstSide [(s Shape)] -> (Option Int64)"
    "  (mt s ((circle r) (some r)) ((rect w _) (some w))))"))

fn utilSource -> String
  (joinLines (list
    "(module linkfx/util :x [size widen describe] :i [(linkfx/geom :a g)])"
    ""
    "(fn size [(n Int64)] -> Int64"
    "  (+ (g/size (g/rect n 1)) (secret n)))"
    ""
    "(fn secret [(n Int64)] -> Int64"
    "  (* n 2))"
    ""
    "(fn widen [(s g/Shape)] -> g/Box"
    "  (mt s ((g/circle r) (g/Box :w r :h r)) ((g/rect w h) (g/Box :h h :w (+ w 1)))))"
    ""
    "(fn describe [(s g/Shape)] -> String"
    "  (str \"shape \" (g/size s)))"))

fn appSource -> String
  (joinLines (list
    "(module linkfx/app :x [main size] :i [(linkfx/util :a u) (linkfx/geom :a g)])"
    ""
    "(fn size [(n Int64)] -> Int64"
    "  (+ n 5))"
    ""
    "(fn pick [(o (Option Int64))] -> Int64"
    "  (mt o ((some v) v) ((none) 0)))"
    ""
    "(fn main [] -> Int64"
    "  (let [(box (u/widen (g/rect 3 4)))"
    "        (sz g/size)"
    "        (f (fn [x] (+ x (size 2))))"
    "        (zero (- (pick (g/firstSide (g/rect 7 9))) (stringLength (u/describe (g/circle 7)))))]"
    "    (+ (+ (g/boxArea box) (sz (g/circle zero))) (+ (u/size 5) (f (g/area (g/circle 1)))))))"))

fn badHiddenSource -> String
  (joinLines (list
    "(module linkfx/badHidden :x [main] :i [(linkfx/util :a u)])"
    ""
    "(fn main [] -> Int64"
    "  (u/secret 1))"))

fn badAliasSource -> String
  (joinLines (list
    "(module linkfx/badAlias :x [main] :i [(linkfx/util :a u)])"
    ""
    "(fn helper [] -> Int64"
    "  (u/size 1))"
    ""
    "(fn main [] -> Int64"
    "  (+ (helper) (q/size 1)))"))

fn missingSource -> String
  (joinLines (list
    "(module linkfx/missing :x [main] :i [(linkfx/nowhere :a nw)])"
    ""
    "(fn main [] -> Int64"
    "  1)"))

fn evilPreludeSource -> String
  (joinLines (list
    "(module prelude :x [evilMarker])"
    ""
    "(fn evilMarker [] -> Int64"
    "  100)"))

fn preludeNameClashSource -> String
  (joinLines (list
    "(module linkfx/preludeNameClash :x [main] :i [(linkfx/evilPrelude :a ev)])"
    ""
    "(fn main [] -> Int64"
    "  (ev/evilMarker))"))

fn usesPreludeSource -> String
  (joinLines (list
    "(module linkfx/usesPrelude :x [main])"
    ""
    "(fn main [] -> Int64"
    "  (let [(h twice)] (+ (h 20) (unwrapOr (wrap 2)))))"))

fn bareSource -> String
  (joinLines (list
    "(module linkfx/bare :x [main] :i [(linkfx/geom :a g)])"
    ""
    "(fn main [] -> Int64"
    "  (mt (rect 6 7) ((circle r) r) ((rect w h) (* w h))))"))

fn fusedSource -> String
  (joinLines (list
    "(module linkfx/fused :x [main] :i [])"
    ""
    "(fn pick [(xs (List Int64)) (s String)] -> Int64"
    "  (+ (optionOr (listHead xs) 0) (+ (listLength (optionOr (listTail xs) (list))) (+ (optionOr (listGet xs 2) 5) (stringLength (optionOr (stringSlice s 1 3) \"\"))))))"
    ""
    "(fn kept [(o (Option Int64))] -> Int64"
    "  (optionOr o 9))"
    ""
    "(fn main [] -> Int64"
    "  (+ (pick (list 1 2 3) \"abcd\") (kept (none))))"))

fn fixturePreludeSource -> String
  (joinLines (list
    "(module prelude :x [])"
    ""
    "(enum Unused (:c nothing [] \"never used\"))"
    ""
    "(enum Wrap (:c wrap [(v Int64)] \"one value\"))"
    ""
    "(fn twice [(x Int64)] -> Int64"
    "  (addSelf x))"
    ""
    "(fn addSelf [(x Int64)] -> Int64"
    "  (+ x x))"
    ""
    "(fn unwrapOr [(w Wrap)] -> Int64"
    "  (mt w ((wrap v) v)))"
    ""
    "(fn unused [] -> Int64"
    "  (twice 0))"))

fn ! writeOne! dir: String name: String src: String -> Bool
  (ok? (fileWrite (str dir "/linkfx/" name ".asl") src))

fn ! writeFixture! dir: String -> Bool
  (and (= (processRun (str "mkdir -p " dir "/linkfx")).exitCode 0)
       (and (ok? (fileWrite (str dir "/.asl.config.asn") "(:aslConfig)\n"))
       (and (writeOne! dir "geom" (geomSource))
            (and (writeOne! dir "util" (utilSource))
                 (and (writeOne! dir "app" (appSource))
                      (and (writeOne! dir "badHidden" (badHiddenSource))
                           (and (writeOne! dir "badAlias" (badAliasSource))
                                (and (writeOne! dir "missing" (missingSource))
                                     (and (writeOne! dir "usesPrelude" (usesPreludeSource))
                                          (and (writeOne! dir "bare" (bareSource))
                                               (and (writeOne! dir "fused" (fusedSource))
                                                    (and (writeOne! dir "evilPrelude" (evilPreludeSource))
                                                         (and (writeOne! dir "preludeNameClash" (preludeNameClashSource))
                                                              (writeOne! dir "prelude" (fixturePreludeSource)))))))))))))))

fn appGolden -> String
  (joinLines (list
    "(ssa-module \"linkfx/app\""
    "  (strings \"shape \")"
    "  (type linkfx/geom.Shape (circle 1) (rect 2))"
    "  (type Option (some 1) (none 0))"
    "  (record linkfx/geom.Box w h)"
    "  (fn linkfx/geom.area (captures) (params (s val)) (returns i64)"
    "    (block entry ()"
    "      (switch s linkfx/geom.Shape (circle (arm0.0)) (rect (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (let %1 i64 (const int 3))"
    "      (let %2 val (entry \"*\" %0 %0))"
    "      (let %3 i64 (unbox %2))"
    "      (let %4 i64 (prim mulIntHost %1 %3))"
    "      (let %8 val (box %4))"
    "      (jump (join0 %8)))"
    "    (block arm0.1 ()"
    "      (let %5 val (variant-field s 0))"
    "      (let %6 val (variant-field s 1))"
    "      (let %7 val (entry \"*\" %5 %6))"
    "      (jump (join0 %7)))"
    "    (block join0 ((%9 val))"
    "      (let %10 i64 (unbox %9))"
    "      (return %10)))"
    "  (fn linkfx/geom.size (captures) (params (s val)) (returns i64)"
    "    (block entry ()"
    "      (switch s linkfx/geom.Shape (circle (arm0.0)) (rect (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (jump (join0 %0)))"
    "    (block arm0.1 ()"
    "      (let %1 val (variant-field s 0))"
    "      (let %2 val (variant-field s 1))"
    "      (let %3 val (entry \"+\" %1 %2))"
    "      (jump (join0 %3)))"
    "    (block join0 ((%4 val))"
    "      (let %5 i64 (unbox %4))"
    "      (return %5)))"
    "  (fn linkfx/geom.boxArea (captures) (params (b rec:linkfx/geom.Box)) (returns i64)"
    "    (block entry ()"
    "      (let %0 val (field b w))"
    "      (let %1 i64 (unbox %0))"
    "      (let %2 val (field b h))"
    "      (let %3 i64 (unbox %2))"
    "      (let %4 i64 (prim mulIntHost %1 %3))"
    "      (return %4)))"
    "  (fn linkfx/geom.firstSide (captures) (params (s val)) (returns val)"
    "    (block entry ()"
    "      (switch s linkfx/geom.Shape (circle (arm0.0)) (rect (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (let %1 val (construct Option some %0))"
    "      (jump (join0 %1)))"
    "    (block arm0.1 ()"
    "      (let %2 val (variant-field s 0))"
    "      (let %3 val (construct Option some %2))"
    "      (jump (join0 %3)))"
    "    (block join0 ((%4 val))"
    "      (return %4)))"
    "  (fn linkfx/util.size (captures) (params (n i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 1))"
    "      (let %1 val (box n))"
    "      (let %2 val (box %0))"
    "      (let %3 val (construct linkfx/geom.Shape rect %1 %2))"
    "      (let %4 i64 (call linkfx/geom.size %3))"
    "      (let %5 i64 (call linkfx/util.secret n))"
    "      (let %6 i64 (prim addIntHost %4 %5))"
    "      (return %6)))"
    "  (fn linkfx/util.secret (captures) (params (n i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 2))"
    "      (let %1 i64 (prim mulIntHost n %0))"
    "      (return %1)))"
    "  (fn linkfx/util.widen (captures) (params (s val)) (returns rec:linkfx/geom.Box)"
    "    (block entry ()"
    "      (switch s linkfx/geom.Shape (circle (arm0.0)) (rect (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field s 0))"
    "      (let %1 rec:linkfx/geom.Box (record linkfx/geom.Box (w %0) (h %0)))"
    "      (jump (join0 %1)))"
    "    (block arm0.1 ()"
    "      (let %2 val (variant-field s 0))"
    "      (let %3 val (variant-field s 1))"
    "      (let %4 i64 (const int 1))"
    "      (let %5 i64 (unbox %2))"
    "      (let %6 i64 (prim addIntHost %5 %4))"
    "      (let %7 val (box %6))"
    "      (let %8 rec:linkfx/geom.Box (record linkfx/geom.Box (w %7) (h %3)))"
    "      (jump (join0 %8)))"
    "    (block join0 ((%9 rec:linkfx/geom.Box))"
    "      (return %9)))"
    "  (fn linkfx/util.describe (captures) (params (s val)) (returns val)"
    "    (block entry ()"
    "      (let %0 val (const str 0))"
    "      (let %1 i64 (call linkfx/geom.size s))"
    "      (let %2 val (box %1))"
    "      (let %3 val (builtin \"str\" %0 %2))"
    "      (return %3)))"
    "  (fn linkfx/app.size (captures) (params (n i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (const int 5))"
    "      (let %1 i64 (prim addIntHost n %0))"
    "      (return %1)))"
    "  (fn linkfx/app.pick (captures) (params (o val)) (returns i64)"
    "    (block entry ()"
    "      (switch o Option (some (arm0.0)) (none (arm0.1))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field o 0))"
    "      (jump (join0 %0)))"
    "    (block arm0.1 ()"
    "      (let %1 i64 (const int 0))"
    "      (let %2 val (box %1))"
    "      (jump (join0 %2)))"
    "    (block join0 ((%3 val))"
    "      (let %4 i64 (unbox %3))"
    "      (return %4)))"
    "  (fn linkfx/app.main (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 3))"
    "      (let %1 i64 (const int 4))"
    "      (let %2 val (box %0))"
    "      (let %3 val (box %1))"
    "      (let %4 val (construct linkfx/geom.Shape rect %2 %3))"
    "      (let %5 rec:linkfx/geom.Box (call linkfx/util.widen %4))"
    "      (let %6 val (make-closure linkfx/app.main@lambda0))"
    "      (let %7 val (make-closure linkfx/app.main@lambda1))"
    "      (let %8 i64 (const int 7))"
    "      (let %9 i64 (const int 9))"
    "      (let %10 val (box %8))"
    "      (let %11 val (box %9))"
    "      (let %12 val (construct linkfx/geom.Shape rect %10 %11))"
    "      (let %13 val (call linkfx/geom.firstSide %12))"
    "      (let %14 i64 (call linkfx/app.pick %13))"
    "      (let %15 i64 (const int 7))"
    "      (let %16 val (box %15))"
    "      (let %17 val (construct linkfx/geom.Shape circle %16))"
    "      (let %18 val (call linkfx/util.describe %17))"
    "      (let %19 i64 (entry \"stringLength\" %18))"
    "      (let %20 i64 (prim subIntHost %14 %19))"
    "      (let %21 i64 (call linkfx/geom.boxArea %5))"
    "      (let %22 val (box %20))"
    "      (let %23 val (construct linkfx/geom.Shape circle %22))"
    "      (let %24 val (call-closure %6 %23))"
    "      (let %25 i64 (unbox %24))"
    "      (let %26 i64 (prim addIntHost %21 %25))"
    "      (let %27 i64 (const int 5))"
    "      (let %28 i64 (call linkfx/util.size %27))"
    "      (let %29 i64 (const int 1))"
    "      (let %30 val (box %29))"
    "      (let %31 val (construct linkfx/geom.Shape circle %30))"
    "      (let %32 i64 (call linkfx/geom.area %31))"
    "      (let %33 val (box %32))"
    "      (let %34 val (call-closure %7 %33))"
    "      (let %35 i64 (unbox %34))"
    "      (let %36 i64 (prim addIntHost %28 %35))"
    "      (let %37 i64 (prim addIntHost %26 %36))"
    "      (let %38 val (box %37))"
    "      (return %38)))"
    "  (fn linkfx/app.main@lambda0 (captures) (params (@0 val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (call linkfx/geom.size @0))"
    "      (let %1 val (box %0))"
    "      (return %1)))"
    "  (fn linkfx/app.main@lambda1 (captures) (params (x val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (const int 2))"
    "      (let %1 i64 (call linkfx/app.size %0))"
    "      (let %2 i64 (unbox x))"
    "      (let %3 i64 (prim addIntHost %2 %1))"
    "      (let %4 val (box %3))"
    "      (return %4))))"))

fn preludeGolden -> String
  (joinLines (list
    "(ssa-module \"linkfx/usesPrelude\""
    "  (strings)"
    "  (type prelude.Wrap (wrap 1))"
    "  (fn linkfx/usesPrelude.main (captures) (params) (returns val)"
    "    (block entry ()"
    "      (let %0 val (make-closure linkfx/usesPrelude.main@lambda0))"
    "      (let %1 i64 (const int 20))"
    "      (let %2 val (box %1))"
    "      (let %3 val (call-closure %0 %2))"
    "      (let %4 i64 (const int 2))"
    "      (let %5 val (box %4))"
    "      (let %6 val (construct prelude.Wrap wrap %5))"
    "      (let %7 i64 (call prelude.unwrapOr %6))"
    "      (let %8 i64 (unbox %3))"
    "      (let %9 i64 (prim addIntHost %8 %7))"
    "      (let %10 val (box %9))"
    "      (return %10)))"
    "  (fn linkfx/usesPrelude.main@lambda0 (captures) (params (@0 val)) (returns val)"
    "    (block entry ()"
    "      (let %0 i64 (unbox @0))"
    "      (let %1 i64 (call prelude.twice %0))"
    "      (let %2 val (box %1))"
    "      (return %2)))"
    "  (fn prelude.twice (captures) (params (x i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (call prelude.addSelf x))"
    "      (return %0)))"
    "  (fn prelude.unwrapOr (captures) (params (w val)) (returns i64)"
    "    (block entry ()"
    "      (switch w prelude.Wrap (wrap (arm0.0))))"
    "    (block arm0.0 ()"
    "      (let %0 val (variant-field w 0))"
    "      (jump (join0 %0)))"
    "    (block join0 ((%1 val))"
    "      (let %2 i64 (unbox %1))"
    "      (return %2)))"
    "  (fn prelude.addSelf (captures) (params (x i64)) (returns i64)"
    "    (block entry ()"
    "      (let %0 i64 (prim addIntHost x x))"
    "      (return %0))))"))

fn printed res: (Result ty/SsaModule (List ty/IrDiag)) -> String
  (mt res
    ((ok m) (prn/printSsa m))
    ((err ds) (str "link failed: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.locus ": " d.message)) ds) "; "))))

fn diagsOf res: (Result ty/SsaModule (List ty/IrDiag)) -> (List ty/IrDiag)
  (mt res ((ok _) (list)) ((err ds) ds))

fn ! testAppLinks dir: String -> Bool
  (let [(res (lk/linkEntry! (str dir "/linkfx/app.asl")))
        (again (lk/linkEntry! (str dir "/linkfx/app.asl")))]
    (do
      (assert (ok? res) (str "the 3-module fixture links and verifies: " (printed res)))
      (assert (= (printed res) (appGolden)) (str "linked module prints as its golden:\n" (printed res)))
      (assert (= (printed again) (printed res)) "linking again prints the same module")
      true))

fn ! testPreludeClosure dir: String -> Bool
  (let [(res (lk/linkWith! (str dir "/linkfx/usesPrelude.asl") (str dir "/linkfx/prelude.asl")))
        (text (printed res))]
    (do
      (assert (= text (preludeGolden)) (str "prelude functions reached from the closure are linked, qualified prelude.:\n" text))
      (refute (stringContains? text "unused") "an unreached prelude function stays out")
      (refute (stringContains? text "Unused") "an unused prelude enum stays out")
      true))

fn ! testFusedOptionOr dir: String -> Bool
  (let [(res (lk/linkEntry! (str dir "/linkfx/fused.asl")))
        (text (printed res))]
    (do
      (assert (ok? res) (str "optionOr over listHead, listTail, listGet and stringSlice links and verifies against the host prelude: " text))
      (map (fn [(e String)] -> Bool (do (assert (stringContains? text (str "(entry \"" e "\"")) (str e " computes its optionOr without the Option:\n" text)) true))
           (list "@listHeadOr" "@listTailOr" "@listGetOr" "@stringSliceOr"))
      (assert (stringContains? text "(call prelude.optionOr o ") (str "optionOr of an Option value still calls the prelude function:\n" text))
      (refute (stringContains? text "(entry \"listHead\"") (str "no listHead Option is built:\n" text))
      (refute (stringContains? text "(call prelude.listGet") (str "no listGet Option is built:\n" text))
      true))

fn ! testBareCtors dir: String -> Bool
  (let [(res (lk/linkWith! (str dir "/linkfx/bare.asl") (str dir "/linkfx/prelude.asl")))
        (text (printed res))]
    (do
      (assert (ok? res) (str "unqualified constructors of an imported enum link and verify: " text))
      (assert (stringContains? text "(construct linkfx/geom.Shape rect %2 %3)") (str "an unqualified constructor builds the imported enum:\n" text))
      (assert (stringContains? text "(switch %4 linkfx/geom.Shape (circle (arm0.0)) (rect (arm0.1)))") (str "unqualified patterns switch on the imported enum:\n" text))
      true))

fn ! testUnexported dir: String -> Bool
  (let [(ds (diagsOf (lk/linkEntry! (str dir "/linkfx/badHidden.asl"))))
        (d (optionOr (listHead ds) (ty/makeIrDiag "" "" "")))]
    (do
      (assert (= (listLength ds) 1) (str "one diagnostic for the unexported call, got " (listLength ds)))
      (assert (= d.code "ERR_LOWER_UNEXPORTED") (str "unexported name code: " d.code))
      (assert (= d.locus (str "linkfx/badHidden.main@" dir "/linkfx/badHidden.asl:3:1")) (str "unexported name locus: " d.locus))
      (assert (stringContains? d.message "module linkfx/util does not export 'secret'") (str "unexported name message: " d.message))
      true))

fn ! testUnknownAlias dir: String -> Bool
  (let [(ds (diagsOf (lk/linkEntry! (str dir "/linkfx/badAlias.asl"))))
        (d (optionOr (listHead ds) (ty/makeIrDiag "" "" "")))]
    (do
      (assert (= (listLength ds) 1) (str "one diagnostic for the unknown alias, got " (listLength ds)))
      (assert (= d.code "ERR_LOWER_UNKNOWN_ALIAS") (str "unknown alias code: " d.code))
      (assert (= d.locus (str "linkfx/badAlias.main@" dir "/linkfx/badAlias.asl:6:1")) (str "unknown alias locus: " d.locus))
      (assert (stringContains? d.message "'q/size' names the alias 'q'") (str "unknown alias message: " d.message))
      true))

fn ! testSysImport dir: String -> Bool
  (let [(path (str dir "/linkfx/sysEntry.asl"))
        (written (processRun (str "mkdir -p " dir "/linkfx")))
        (src (joinLines (list
          "(module linkfx/sysEntry :x [main] :i [(sys :a sys)] )"
          ""
          "(fn main [] -> Int64"
          "  42)")))
        (saved (fileWrite path src))
        (linked (lk/linkEntry! path))]
    (do
      (assert (= written.exitCode 0) "directory for sys import fixture is created")
      (assert (ok? saved) "sys import fixture is written")
      (assert (ok? linked) (str "IR linker accepts sys imports without resolving a module: " (stringJoin (map (fn [(d ty/IrDiag)] -> String d.message) (mt linked ((ok _) (list)) ((err ds) ds))) "; ")))
      true))

fn ! testUnresolvedImport dir: String -> Bool
  (let [(ds (diagsOf (lk/linkEntry! (str dir "/linkfx/missing.asl"))))
        (d (optionOr (listHead ds) (ty/makeIrDiag "" "" "")))]
    (do
      (assert (= d.code "ERR_LINK_UNRESOLVED_IMPORT") (str "unresolved import code: " d.code))
      (assert (stringContains? d.message "imports linkfx/nowhere") (str "unresolved import message: " d.message))
      true))

fn ! testPreludeNameClash dir: String -> Bool
  (let [(ds (diagsOf (lk/linkEntry! (str dir "/linkfx/preludeNameClash.asl"))))
        (d (optionOr (listHead ds) (ty/makeIrDiag "" "" "")))]
    (do
      (assert (= (listLength ds) 1) (str "one diagnostic for the reserved module name, got " (listLength ds)))
      (assert (= d.code "ERR_LINK_RESERVED_MODULE_NAME") (str "reserved module name code: " d.code))
      (assert (stringContains? d.message "reserved for the designated prelude") (str "reserved module name message: " d.message))
      (assert (stringContains? d.message (str dir "/linkfx/evilPrelude.asl")) (str "reserved module name message names the offending file: " d.message))
      true))

fn twinSource body: String -> String
  (joinLines (list "(module linkfx/twin :x [f])" "" "(fn f [] -> Int64" (str "  " body ")")))

fn sourceUnit path: String src: String -> (List lk/LinkUnit)
  (mt (ast/parse src)
    ((err _) (list))
    ((ok forms) (list (lk/LinkUnit :path path :name "linkfx/twin" :forms forms :positions (mapEmpty) :imports (list)))))

fn ! testDuplicateFunction -> Bool
  (let [(units (listAppend (sourceUnit "twinA.asl" (twinSource "1")) (sourceUnit "twinB.asl" (twinSource "2"))))
        (ds (diagsOf (lk/linkUnits units (err (list)))))
        (single (lk/linkUnits (sourceUnit "twinA.asl" (twinSource "1")) (err (list))))]
    (do
      (assert (= (listLength units) 2) "two units parsed, both declaring module linkfx/twin with fn f")
      (assert (= (map (fn [(d ty/IrDiag)] -> String d.code) ds) (list "ERR_LINK_DUPLICATE_FUNCTION")) (str "two linked modules defining linkfx/twin.f fail with ERR_LINK_DUPLICATE_FUNCTION: " (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")))
      (assert (listAny? (fn [(d ty/IrDiag)] -> Bool (stringContains? d.message "linkfx/twin.f")) ds) "the diagnostic names the duplicated linkfx/twin.f")
      (assert (ok? single) (str "the same module linked once has no duplicate: " (printed single)))
      true))

fn ! runTests -> Bool
  (let [(made (processRun "mktemp -d"))
        (dir (stringReplace made.stdout "\n" ""))]
    (do
      (assert (= made.exitCode 0) "mktemp -d makes a fixture directory")
      (assert (writeFixture! dir) "fixture modules written")
      (testAppLinks dir)
      (testSysImport dir)
      (testPreludeClosure dir)
      (testBareCtors dir)
      (testFusedOptionOr dir)
      (testUnexported dir)
      (testUnknownAlias dir)
      (testUnresolvedImport dir)
      (testPreludeNameClash dir)
      (testDuplicateFunction)
      (assert (= (processRun (str "rm -rf " dir)).exitCode 0) "fixture directory removed")
      true))
