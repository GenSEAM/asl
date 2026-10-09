(module asl-syntax/tests/core/corpusTest
  :x [runTests]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)
      (asl-syntax/core/print :a pr)
      (asl-syntax/core/corpus :a crp)
      (asl-syntax/core/bench :a bch)])

fn testDeliberatelyLossyPrinterYieldsMismatchWithRightOffset! -> Bool
  (let [(files (list "asl/packages/asl-syntax/manifest.asn"))
        (lossyPipeline (fn [(bs Bytes)] -> (Result Bytes String)
                         (let [(len (bytesLength bs))]
                           (if (<= len 10)
                             (ok bs)
                             (let [(mut (crp/cloneBytes! bs))]
                               (do
                                 (bytesSet mut 10 (+ (bytesGet bs 10) 1))
                                 (ok mut)))))))
        (report (crp/runCorpusOnFiles! lossyPipeline files))]
    (assert (= (crp/reportFiles report) 1) "files count is 1")
    (assert (= (crp/reportMismatchCount report) 1) "mismatch count is 1")
    (assert (not (crp/reportSuccess? report)) "success is false on lossy printer")
    (let [(m (optionOr (listHead (crp/reportMismatches report))
                       (crp/makeCorpusMismatch "" -1 0 0 "")))]
      (assert (= (crp/mismatchPath m) "asl/packages/asl-syntax/manifest.asn") "mismatch path is manifest")
      (assert (= (crp/mismatchOffset m) 10) "first differing offset is 10")
      (assert (= (crp/mismatchReason m) "print mismatch") "reason is print mismatch"))
    true)

fn testDeliberatelyLossyTruncationMismatch! -> Bool
  (let [(files (list "asl/packages/asl-syntax/manifest.asn"))
        (lossyPipeline (fn [(bs Bytes)] -> (Result Bytes String)
                         (let [(len (bytesLength bs))]
                           (if (<= len 5)
                             (ok bs)
                             (let [(mut (bytesAlloc 5))]
                               (do
                                 (crp/copyBytes! bs mut 0 5)
                                 (ok mut)))))))
        (report (crp/runCorpusOnFiles! lossyPipeline files))]
    (assert (= (crp/reportMismatchCount report) 1) "truncation yields 1 mismatch")
    (let [(m (optionOr (listHead (crp/reportMismatches report))
                       (crp/makeCorpusMismatch "" -1 0 0 "")))]
      (assert (= (crp/mismatchOffset m) 5) "truncation first diff offset is truncated length")
      (assert (= (crp/mismatchActualLen m) 5) "actual length is 5"))
    true)

fn testDeliberatelyLossyInsertionMismatch! -> Bool
  (let [(files (list "asl/packages/asl-syntax/manifest.asn"))
        (lossyPipeline (fn [(bs Bytes)] -> (Result Bytes String)
                         (let [(origLen (bytesLength bs))
                               (newLen (+ origLen 1))
                               (mut (bytesAlloc newLen))]
                           (do
                             (crp/copyBytes! bs mut 0 origLen)
                             (bytesSet mut 0 33)
                             (ok mut)))))
        (report (crp/runCorpusOnFiles! lossyPipeline files))]
    (assert (= (crp/reportMismatchCount report) 1) "insertion yields 1 mismatch")
    (let [(m (optionOr (listHead (crp/reportMismatches report))
                       (crp/makeCorpusMismatch "" -1 0 0 "")))]
      (assert (= (crp/mismatchOffset m) 0) "insertion diff offset is 0")
      (assert (= (crp/mismatchActualLen m) (+ (crp/mismatchExpectedLen m) 1)) "actual length increased by 1"))
    true)

fn testFindFirstDiffOffset -> Bool
  (let [(b1 (stringToBytes "abcdef"))
        (b2 (stringToBytes "abcdef"))
        (b3 (stringToBytes "abcxef"))
        (b4 (stringToBytes "abc"))
        (b5 (stringToBytes "xbcdef"))
        (bEmpty (stringToBytes ""))]
    (assert (= (crp/findFirstDiffOffset b1 b2) (none)) "identical bytes have no diff offset")
    (assert (= (crp/findFirstDiffOffset bEmpty bEmpty) (none)) "empty bytes have no diff offset")
    (assert (= (crp/findFirstDiffOffset b1 b3) (some 3)) "diff at index 3")
    (assert (= (crp/findFirstDiffOffset b1 b4) (some 3)) "diff at prefix end index 3")
    (assert (= (crp/findFirstDiffOffset b4 b1) (some 3)) "diff at prefix end index 3 reverse")
    (assert (= (crp/findFirstDiffOffset b1 b5) (some 0)) "diff at index 0")
    (assert (= (crp/findFirstDiffOffset bEmpty b1) (some 0)) "empty vs non-empty diff at 0")
    (assert (= (crp/findFirstDiffOffset b1 bEmpty) (some 0)) "non-empty vs empty diff at 0")
    true)

fn testGitTrackedFiles! -> Bool
  (let [(aslRes (crp/gitTrackedFiles! "asl"))
        (asnRes (crp/gitTrackedFiles! ".asn"))
        (allRes (crp/gitTrackedFiles! ""))]
    (assert (ok? aslRes) "gitTrackedFiles asl is ok")
    (assert (ok? asnRes) "gitTrackedFiles .asn is ok")
    (assert (ok? allRes) "gitTrackedFiles all is ok")
    (let [(aslFiles (resultOr aslRes (list)))
          (asnFiles (resultOr asnRes (list)))]
      (assert (> (listLength aslFiles) 100) "tracked asl files count > 100")
      (assert (> (listLength asnFiles) 50) "tracked asn files count > 50")
      (assert (stringContains? (stringJoin aslFiles " ") "asl/packages/asl-syntax/src/core/source.asl")
              "asl list includes source.asl")
      (assert (stringContains? (stringJoin asnFiles " ") "asl/packages/asl-syntax/manifest.asn")
              "asn list includes manifest.asn"))
    true)

fn testCorpusLosslessFiles! -> Bool
  (let [(files (list "asl/packages/asl-syntax/manifest.asn"
                     "asl/packages/asl-syntax/src/core/tree.asl"))
        (losslessPipeline (fn [(bs Bytes)] -> (Result Bytes String) (ok bs)))
        (report (crp/runCorpusOnFiles! losslessPipeline files))]
    (assert (= (crp/reportFiles report) 2) "report files is 2")
    (assert (> (crp/reportBytes report) 0) "report bytes > 0")
    (assert (= (crp/reportMismatchCount report) 0) "lossless mismatch count is 0")
    (assert (crp/reportSuccess? report) "lossless reportSuccess is true")
    (assert (listEmpty? (crp/reportMismatches report)) "mismatches list is empty")
    true)

fn testUpstreamEntryValid! -> Bool
  (let [(entry (crp/makeUpstreamEntry
                 "https://github.com/agent-script/asex"
                 "0ddf291142993115146c70aeb5a06749126cea90"
                 "be0106ad10c83661edf4f03bc5c9d55f1e0b9c1f936349ecd6eec638ebedd260"
                 "MIT"
                 "asl/packages/asl-syntax/manifest.asn"))
        (res (crp/verifyUpstreamEntry! entry))]
    (assert (ok? res) "valid upstream entry passes verification")
    (assert (= (resultOr res false) true) "valid entry returns true")
    true)

fn testUpstreamEntryInvalidSha! -> Bool
  (let [(entry (crp/makeUpstreamEntry
                 "https://github.com/agent-script/asex"
                 "0ddf291142993115146c70aeb5a06749126cea90"
                 "0000000000000000000000000000000000000000000000000000000000000000"
                 "MIT"
                 "asl/packages/asl-syntax/manifest.asn"))
        (res (crp/verifyUpstreamEntry! entry))]
    (assert (err? res) "corrupted sha256 fails verification")
    (mt res
      ((ok _) (assert false "expected sha mismatch error"))
      ((err msg)
       (do
         (assert (stringContains? msg "sha256 mismatch") "error names sha256 mismatch")
         (assert (stringContains? msg "be0106ad10c8") "error names actual hash"))))
    true)

fn testUpstreamEntryMissingFile! -> Bool
  (let [(entry (crp/makeUpstreamEntry
                 "https://github.com/agent-script/asex"
                 "0ddf291142993115146c70aeb5a06749126cea90"
                 "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
                 "MIT"
                 "nonexistent/file/path/sample.asn"))
        (res (crp/verifyUpstreamEntry! entry))]
    (assert (err? res) "missing file fails verification")
    (mt res
      ((ok _) (assert false "expected file missing error"))
      ((err msg)
       (assert (stringContains? msg "not found") "error reports file not found")))
    true)

fn testUpstreamEntryMissingFields! -> Bool
  (let [(e1 (crp/makeUpstreamEntry "" "commit" "sha" "mit" "path"))
        (e2 (crp/makeUpstreamEntry "url" "" "sha" "mit" "path"))
        (e3 (crp/makeUpstreamEntry "url" "commit" "" "mit" "path"))
        (e4 (crp/makeUpstreamEntry "url" "commit" "sha" "" "path"))
        (e5 (crp/makeUpstreamEntry "url" "commit" "sha" "mit" ""))]
    (assert (err? (crp/verifyUpstreamEntry! e1)) "missing url fails")
    (assert (err? (crp/verifyUpstreamEntry! e2)) "missing commit fails")
    (assert (err? (crp/verifyUpstreamEntry! e3)) "missing sha fails")
    (assert (err? (crp/verifyUpstreamEntry! e4)) "missing license fails")
    (assert (err? (crp/verifyUpstreamEntry! e5)) "missing path fails")
    true)

fn testUpstreamManifestParsingAndVerification! -> Bool
  (let [(manifestPath "asl/packages/asl-syntax/tests/fixtures/upstream/manifest.asn")
        (verifyRes (crp/verifyUpstreamManifestFile! manifestPath))]
    (assert (ok? verifyRes) "manifest file verification passes")
    (let [(contentRes (fileReadString manifestPath))
          (manifestText (resultOr contentRes ""))
          (parseRes (crp/parseUpstreamManifest manifestText))]
      (assert (ok? parseRes) "manifest parses successfully")
      (let [(manifest (resultOr parseRes (crp/makeUpstreamManifest (list))))
            (entries (crp/manifestEntries manifest))]
        (assert (>= (listLength entries) 1) "manifest has at least the self entry; upstream rows are added by language units")
        (let [(entry (optionOr (listHead entries) (crp/makeUpstreamEntry "" "" "" "" "")))]
          (assert (= entry.license "MIT") "manifest entry license is MIT")
          (assert (= entry.path "asl/packages/asl-syntax/manifest.asn") "manifest entry path is correct"))))
    true)

fn benchTestLoop n: Int64 -> Unit
  (if (<= n 0)
    ()
    (benchTestLoop (- n (listLength (list n)))))

fn testBenchReportsFigureWithMethodScopeDate! -> Bool
  (let [(workload (fn [] -> Unit
                    (benchTestLoop 5000)))
        (fig (bch/benchMedian5! workload 102400 "testSyntaxWorkload" "2026-09-26"))]
    (assert (= (bch/figureMethod fig) "median of 5 runs, monotonicNs") "bench method is median of 5")
    (assert (= (bch/figureScope fig) "testSyntaxWorkload") "bench scope is testSyntaxWorkload")
    (assert (= (bch/figureDate fig) "2026-09-26") "bench date is 2026-09-26")
    (assert (= (listLength (bch/figureSamples fig)) 5) "figure has 5 samples")
    (assert (> (bch/figureMedianNs fig) 0) "median ns > 0")
    (assert (> (bch/figureMedianMs fig) 0.0) "median ms > 0.0")
    (assert (= (bch/figureBytes fig) 102400) "bytes is 102400")
    (assert (> (bch/figureMsPer100Kb fig) 0.0) "ms per 100 KB > 0.0")
    (let [(rendered (bch/renderBenchFigure fig))]
      (assert (stringContains? rendered ":method \"median of 5 runs, monotonicNs\"") "render has method")
      (assert (stringContains? rendered ":scope \"testSyntaxWorkload\"") "render has scope")
      (assert (stringContains? rendered ":date \"2026-09-26\"") "render has date")
      (assert (stringContains? rendered ":msPer100Kb ") "render has msPer100Kb"))
    true)

fn testComputeMedian -> Bool
  (let [(m1 (bch/computeMedian (list 50 20 90 10 70)))
        (m2 (bch/computeMedian (list 100 100 100 100 100)))
        (m3 (bch/computeMedian (list 42)))
        (m4 (bch/computeMedian (list 30 10 20)))
        (mEmpty (bch/computeMedian (list)))]
    (assert (= m1 50) "median of [50 20 90 10 70] is 50")
    (assert (= m2 100) "median of identical items is 100")
    (assert (= m3 42) "median of single element is 42")
    (assert (= m4 20) "median of [30 10 20] is 20")
    (assert (= mEmpty 0) "median of empty list is 0")
    true)

fn testComputeMsPer100Kb -> Bool
  (let [(r1 (bch/computeMsPer100Kb 10.0 102400))
        (r2 (bch/computeMsPer100Kb 20.0 204800))
        (r3 (bch/computeMsPer100Kb 5.0 51200))
        (rZero (bch/computeMsPer100Kb 10.0 0))]
    (assert (= r1 10.0) "10 ms for 102400 bytes is 10.0 ms/100KB")
    (assert (= r2 10.0) "20 ms for 204800 bytes is 10.0 ms/100KB")
    (assert (= r3 10.0) "5 ms for 51200 bytes is 10.0 ms/100KB")
    (assert (= rZero 0.0) "zero bytes yields 0.0 ms/100KB")
    true)

fn testCorpusTreeRunner! -> Bool
  (let [(files (list "asl/packages/asl-syntax/manifest.asn"))
        (treeParse (fn [(bs Bytes)] -> (Result tr/Node String)
                     (let [(len (bytesLength bs))
                           (tok (tr/makeToken "text" 0 len))]
                       (ok (tr/makeNode "root" 0 len (list (tr/elemToken tok)))))))
        (losslessPrint (fn [(bs Bytes) (root tr/Node)] -> Bytes
                         (pr/printTreeBytes! bs root)))
        (reportOk (crp/runCorpusTreeOnFiles! treeParse losslessPrint files))]
    (assert (= (crp/reportMismatchCount reportOk) 0) "tree runner lossless mismatch count is 0")
    (assert (crp/reportSuccess? reportOk) "tree runner lossless succeeds")
    (let [(lossyPrint (fn [(bs Bytes) (root tr/Node)] -> Bytes
                        (let [(good (pr/printTreeBytes! bs root))
                              (len (bytesLength good))]
                          (if (<= len 4)
                            good
                            (let [(mut (crp/cloneBytes! good))]
                              (do
                                (bytesSet mut 4 (+ (bytesGet good 4) 1))
                                mut))))))
          (reportBad (crp/runCorpusTreeOnFiles! treeParse lossyPrint files))]
      (assert (= (crp/reportMismatchCount reportBad) 1) "tree runner lossy mismatch count is 1")
      (assert (not (crp/reportSuccess? reportBad)) "tree runner lossy fails")
      (let [(m (optionOr (listHead (crp/reportMismatches reportBad))
                         (crp/makeCorpusMismatch "" -1 0 0 "")))]
        (assert (= (crp/mismatchOffset m) 4) "tree runner lossy diff offset is 4")))
    true)

fn testBrokenManifestUnbalanced! -> Bool
  (let [(_ (dirCreate "scratch/broken-manifests"))
        (path "scratch/broken-manifests/unbalanced.asn")
        (content "(:upstreamManifest\n  :version \"1.0.0\"\n  :entries [\n    (:entry\n      :url \"https://github.com/agent-script/asex\"\n      :commit \"0ddf291142993115146c70aeb5a06749126cea90\"\n      :sha256 \"be0106ad10c83661edf4f03bc5c9d55f1e0b9c1f936349ecd6eec638ebedd260\"\n      :license \"MIT\"\n      :path \"asl/packages/asl-syntax/manifest.asn\")\n      :url \"https://github.com/SimonSapin/css-parsing-tests\"\n      :commit \"203ce36bffd617db7f118c551e32794561fb273d\"\n      :sha256 \"a8d7a5252373b892cfcac359360930ad9a57ed918a84331bcf0c872b80f83200\"\n      :license \"CC0-1.0\"\n      :path \"asl/packages/asl-syntax/tests/fixtures/upstream/css/component_value_list.json.sample\")\n  ])\n")
        (_ (fileWrite path content))
        (parseRes (crp/parseUpstreamManifest content))
        (verifyRes (crp/verifyUpstreamManifestFile! path))]
    (assert (err? parseRes) "unbalanced manifest parse rejected")
    (mt parseRes
      ((ok _) (assert false "expected unbalanced manifest parse error"))
      ((err msg) (assert (stringContains? msg "byte") "unbalanced parse error names byte offset")))
    (assert (err? verifyRes) "unbalanced manifest verify rejected")
    true)

fn testBrokenManifestDuplicateKey! -> Bool
  (let [(_ (dirCreate "scratch/broken-manifests"))
        (path "scratch/broken-manifests/duplicate_key.asn")
        (content "(:upstreamManifest\n  :version \"1.0.0\"\n  :entries [\n    (:entry\n      :url \"https://github.com/agent-script/asex\"\n      :url \"https://github.com/agent-script/asex-dup\"\n      :commit \"0ddf291142993115146c70aeb5a06749126cea90\"\n      :sha256 \"be0106ad10c83661edf4f03bc5c9d55f1e0b9c1f936349ecd6eec638ebedd260\"\n      :license \"MIT\"\n      :path \"asl/packages/asl-syntax/manifest.asn\")\n  ])\n")
        (_ (fileWrite path content))
        (parseRes (crp/parseUpstreamManifest content))
        (verifyRes (crp/verifyUpstreamManifestFile! path))]
    (assert (err? parseRes) "duplicate key manifest parse rejected")
    (assert (err? verifyRes) "duplicate key manifest verify rejected")
    true)

fn testBrokenManifestMissingKey! -> Bool
  (let [(_ (dirCreate "scratch/broken-manifests"))
        (path "scratch/broken-manifests/missing_key.asn")
        (content "(:upstreamManifest\n  :version \"1.0.0\"\n  :entries [\n    (:entry\n      :url \"https://github.com/agent-script/asex\"\n      :commit \"0ddf291142993115146c70aeb5a06749126cea90\"\n      :sha256 \"be0106ad10c83661edf4f03bc5c9d55f1e0b9c1f936349ecd6eec638ebedd260\"\n      :path \"asl/packages/asl-syntax/manifest.asn\")\n  ])\n")
        (_ (fileWrite path content))
        (parseRes (crp/parseUpstreamManifest content))
        (verifyRes (crp/verifyUpstreamManifestFile! path))]
    (assert (err? parseRes) "missing key manifest parse rejected")
    (assert (err? verifyRes) "missing key manifest verify rejected")
    true)

fn testBrokenManifestUnknownKey! -> Bool
  (let [(_ (dirCreate "scratch/broken-manifests"))
        (path "scratch/broken-manifests/unknown_key.asn")
        (content "(:upstreamManifest\n  :version \"1.0.0\"\n  :entries [\n    (:entry\n      :url \"https://github.com/agent-script/asex\"\n      :commit \"0ddf291142993115146c70aeb5a06749126cea90\"\n      :sha256 \"be0106ad10c83661edf4f03bc5c9d55f1e0b9c1f936349ecd6eec638ebedd260\"\n      :license \"MIT\"\n      :path \"asl/packages/asl-syntax/manifest.asn\"\n      :unknownKey \"bad\")\n  ])\n")
        (_ (fileWrite path content))
        (parseRes (crp/parseUpstreamManifest content))
        (verifyRes (crp/verifyUpstreamManifestFile! path))]
    (assert (err? parseRes) "unknown key manifest parse rejected")
    (assert (err? verifyRes) "unknown key manifest verify rejected")
    true)

fn testBrokenManifestWrongSha256! -> Bool
  (let [(_ (dirCreate "scratch/broken-manifests"))
        (path "scratch/broken-manifests/wrong_sha256.asn")
        (content "(:upstreamManifest\n  :version \"1.0.0\"\n  :entries [\n    (:entry\n      :url \"https://github.com/agent-script/asex\"\n      :commit \"0ddf291142993115146c70aeb5a06749126cea90\"\n      :sha256 \"0000000000000000000000000000000000000000000000000000000000000000\"\n      :license \"MIT\"\n      :path \"asl/packages/asl-syntax/manifest.asn\")\n  ])\n")
        (_ (fileWrite path content))
        (parseRes (crp/parseUpstreamManifest content))
        (verifyRes (crp/verifyUpstreamManifestFile! path))]
    (assert (ok? parseRes) "wrong sha256 manifest parse succeeds")
    (assert (err? verifyRes) "wrong sha256 manifest verify rejected")
    true)

fn ! runTests -> Bool
  (let [(r1 (testDeliberatelyLossyPrinterYieldsMismatchWithRightOffset!))
        (r2 (testDeliberatelyLossyTruncationMismatch!))
        (r3 (testDeliberatelyLossyInsertionMismatch!))
        (r4 (testFindFirstDiffOffset))
        (r5 (testGitTrackedFiles!))
        (r6 (testCorpusLosslessFiles!))
        (r7 (testUpstreamEntryValid!))
        (r8 (testUpstreamEntryInvalidSha!))
        (r9 (testUpstreamEntryMissingFile!))
        (r10 (testUpstreamEntryMissingFields!))
        (r11 (testUpstreamManifestParsingAndVerification!))
        (r12 (testBenchReportsFigureWithMethodScopeDate!))
        (r13 (testComputeMedian))
        (r14 (testComputeMsPer100Kb))
        (r15 (testCorpusTreeRunner!))
        (r16 (testBrokenManifestUnbalanced!))
        (r17 (testBrokenManifestDuplicateKey!))
        (r18 (testBrokenManifestMissingKey!))
        (r19 (testBrokenManifestUnknownKey!))
        (r20 (testBrokenManifestWrongSha256!))]
    (and r1
    (and r2
    (and r3
    (and r4
    (and r5
    (and r6
    (and r7
    (and r8
    (and r9
    (and r10
    (and r11
    (and r12
    (and r13
    (and r14
    (and r15
    (and r16
    (and r17
    (and r18
    (and r19
         r20))))))))))))))))))))
