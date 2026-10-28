(module asl-target-llvm/tests/hostArchiveLinksTest
  :x [runTests])

; (:m :ref COUNTED-RT-KEY-OTHER-TESTS :do "each test file's mentions of the host archive are classified by line: boot when the line builds a native asl1 (cache/nativeAsl1!), link otherwise (an executable linked against the host archive instead of rc/runtimes!); every file must match its row, a migrated file has zero links, and a file without a row has no mention at all")
(schema Row
  (:f file String)
  (:f boot Int64)
  (:f link Int64))

fn rows -> (List Row)
  (list
        (Row :file "allocInlineTest.asl" :boot 0 :link 1)
        (Row :file "arrayNativeTest.asl" :boot 0 :link 1)
        (Row :file "arrayRouteTest.asl" :boot 0 :link 1)
        (Row :file "coreTableGoneTest.asl" :boot 0 :link 1)
        (Row :file "deepStackTest.asl" :boot 1 :link 1)
        (Row :file "entryResultTest.asl" :boot 0 :link 1)
        (Row :file "eqAliasNativeTest.asl" :boot 0 :link 1)
        (Row :file "gcMarkSpeedTest.asl" :boot 0 :link 1)
        (Row :file "gcPolicyTest.asl" :boot 0 :link 1)
        (Row :file "gcStressTest.asl" :boot 0 :link 2)
        (Row :file "lowerPairOptionTest.asl" :boot 0 :link 2)
        (Row :file "lowerScaleTest.asl" :boot 0 :link 1)
        (Row :file "multiModuleTest.asl" :boot 0 :link 1)
        (Row :file "musttailClangTest.asl" :boot 0 :link 2)
        (Row :file "mutualTailChildTest.asl" :boot 0 :link 1)
        (Row :file "nativeBuiltinGapsTest.asl" :boot 0 :link 2)
        (Row :file "nativeFormatTest.asl" :boot 1 :link 1)
        (Row :file "nativeFormGapsTest.asl" :boot 0 :link 3)
        (Row :file "nativeGapsTest.asl" :boot 0 :link 1)
        (Row :file "nativeHangTest.asl" :boot 0 :link 1)
        (Row :file "nativeListBytesTest.asl" :boot 0 :link 1)
        (Row :file "nativeObjectTest.asl" :boot 0 :link 2)
        (Row :file "nativeOpsTest.asl" :boot 0 :link 3)
        (Row :file "nativeRtGapsTest.asl" :boot 0 :link 1)
        (Row :file "nativeRunTest.asl" :boot 0 :link 1)
        (Row :file "nativeStringTest.asl" :boot 0 :link 2)
        (Row :file "nativeTrapTest.asl" :boot 1 :link 1)
        (Row :file "nativeValueTest.asl" :boot 0 :link 1)
        (Row :file "parRouteTest.asl" :boot 0 :link 1)
        (Row :file "preludeFsRouteTest.asl" :boot 0 :link 1)
        (Row :file "preludeProcRouteTest.asl" :boot 0 :link 1)
        (Row :file "rcSelfCompileTest.asl" :boot 0 :link 1)
        (Row :file "rcTest.asl" :boot 4 :link 0)
        (Row :file "recordLayoutRtTest.asl" :boot 0 :link 1)
        (Row :file "recordTyRunTest.asl" :boot 0 :link 1)
        (Row :file "rtAbiTest.asl" :boot 0 :link 1)
        (Row :file "rtFloorTest.asl" :boot 0 :link 1)
        (Row :file "slurpSizeTest.asl" :boot 0 :link 1)
        (Row :file "stdioFlushTest.asl" :boot 1 :link 0)
        (Row :file "sysDirectTest.asl" :boot 0 :link 1)
        (Row :file "sysNetRouteTest.asl" :boot 1 :link 1)
        (Row :file "sysNetTest.asl" :boot 0 :link 1)
        (Row :file "sysProcTest.asl" :boot 0 :link 1)
        (Row :file "sysRouteSlimTest.asl" :boot 0 :link 1)
        (Row :file "sysRouteTest.asl" :boot 0 :link 1)
        (Row :file "tailCallNativeTest.asl" :boot 0 :link 1)
        (Row :file "tailCallSpillGcTest.asl" :boot 0 :link 2)
        (Row :file "wasmE2eTest.asl" :boot 0 :link 1)
        (Row :file "wasmNoLibcTest.asl" :boot 0 :link 1)
        (Row :file "wasmStackRootsTest.asl" :boot 0 :link 1)
        (Row :file "wasmTrapTest.asl" :boot 0 :link 1)
        (Row :file "exitCodeTest.asl" :boot 0 :link 0)
        (Row :file "gcSweepTest.asl" :boot 0 :link 0))

; (:m :do "rcTest names the host archive in its plain binding, which feeds nativeAsl1! and the variant builds' Build :lib, never an executable link")
fn bootByBinding -> (List String)
  (list "rcTest.asl")

fn needle -> String
  (str "asl/host/out/" "libaslrt.a")

fn dir -> String
  "asl/packages/asl-target-llvm/tests"

fn ! classify name: String -> Row
  (let [(ls (filter (fn [(l String)] -> Bool (stringContains? l (needle))) (stringLines (resultOr (fileReadString (str (dir) "/" name)) ""))))
        (boot (listLength (filter (fn [(l String)] -> Bool (or (stringContains? l "nativeAsl1!") (listContains? (bootByBinding) name))) ls)))]
    (Row :file name :boot boot :link (- (listLength ls) boot)))

fn ! linksIn name: String -> Int64
  (let [(g (classify name))] g.link)

fn rowOf name: String -> Row
  (optionOr (listHead (filter (fn [(r Row)] -> Bool (= r.file name)) (rows))) (Row :file name :boot 0 :link 0))

fn ! runTests -> Bool
  (let [(names (filter (fn [(n String)] -> Bool (and (stringEndsWith? n ".asl") (!= n "hostArchiveLinksTest.asl"))) (resultOr (dirList (dir)) (list))))
        (wrong (filter (fn [(n String)] -> Bool (let [(got (classify n)) (want (rowOf n))] (or (!= got.boot want.boot) (!= got.link want.link)))) names))
        (migrated (filter (fn [(r Row)] -> Bool (and (= r.boot 0) (= r.link 0))) (rows)))]
    (do (assert (> (listLength names) 40) (str "the test directory is listed: " (listLength names) " files"))
        (assert (listEmpty? wrong) (str "files whose host-archive mentions differ from their row (a new executable link goes through rc/runtimes!; after moving one, lower its row): " (stringJoin (map (fn [(n String)] -> String (let [(g (classify n))] (str n " boot " g.boot " link " g.link))) wrong) ", ")))
        (assert (listContains? (map (fn [(r Row)] -> String r.file) migrated) "exitCodeTest.asl") "exitCodeTest is recorded as migrated")
        (assert (= (linksIn "gcSweepTest.asl") 0) "gcSweepTest links no executable against the host archive")
        true))
