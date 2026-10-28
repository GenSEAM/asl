(module asl-proc/tests/apmAcceptanceTest
  :x [runTests RunTests testStreamFramingNewlineAndMultiline testCountParenBalance testOobDemuxerMemoryBounds testDualPolarityRefutations]
  :i [(asl-proc/apm :a apm)])

fn testStreamFramingNewlineAndMultiline -> Bool
  (let [(b1 "(:ping)\n(:next)\n")
        (r1 (apm/parseStreamFrame b1))
        (f1 (pairFirst r1))
        (rem1 (pairSecond r1))
        (bMulti "(:task\n  :name \"build\"\n  :timeout 5000)\n(:next)\n")
        (rMulti (apm/parseStreamFrame bMulti))
        (fMulti (pairFirst rMulti))
        (remMulti (pairSecond rMulti))
        (rNext (apm/parseStreamFrame remMulti))
        (fNext (pairFirst rNext))
        (remNext (pairSecond rNext))
        (bCl "Content-Length: 14\n\n(:ping :seq 1)TRAILING")
        (rCl (apm/parseStreamFrame bCl))
        (fCl (pairFirst rCl))
        (remCl (pairSecond rCl))
        (bIncomp "(:task\n  :name \"incomplete\"\n")
        (rIncomp (apm/parseStreamFrame bIncomp))
        (fIncomp (pairFirst rIncomp))]
    (assert (some? f1) "First newline frame must be extracted")
    (refute (none? f1) "Extracted frame must not be none")
    (match f1
      ((some frame)
        (do
          (assert (= frame.payload "(:ping)") "Frame payload must be (:ping)")
          (assert (= frame.kind "newline") "Frame kind must be newline")
          (assert frame.valid "Frame must be marked valid")
          (assert (= rem1 "(:next)\n") "Remaining buffer preserves unconsumed input")
          true))
      ((none) false))
    (assert (some? fMulti) "Multiline frame must be extracted as a single unit")
    (refute (none? fMulti) "Multiline frame must not be rejected")
    (match fMulti
      ((some mFrame)
        (do
          (assert (= mFrame.payload "(:task\n  :name \"build\"\n  :timeout 5000)") "Multiline payload matches full expression")
          (assert (= mFrame.kind "newline") "Multiline frame kind is newline")
          (assert mFrame.valid "Multiline frame is valid")
          (assert (= remMulti "(:next)\n") "Remaining buffer preserved after multiline frame")
          true))
      ((none) false))
    (assert (some? fNext) "Subsequent frame extracted cleanly")
    (match fNext
      ((some nFrame)
        (do
          (assert (= nFrame.payload "(:next)") "Subsequent frame payload is (:next)")
          (assert (= remNext "") "Remaining buffer empty after all frames")
          true))
      ((none) false))
    (assert (some? fCl) "Content-Length frame must be parsed")
    (match fCl
      ((some clFrame)
        (do
          (assert (= clFrame.kind "content-length") "Frame kind must be content-length")
          (assert (= clFrame.length 14) "Content-Length extracted length is 14")
          (assert (= clFrame.payload "(:ping :seq 1)") "Content-Length payload matches chunk")
          (assert (= remCl "TRAILING") "Remaining buffer preserved after Content-Length chunk")
          true))
      ((none) false))
    (assert (none? fIncomp) "Incomplete unbalanced multiline buffer yields none")
    (refute (some? fIncomp) "Incomplete multiline buffer must not produce frame")
    true)

fn testCountParenBalance -> Bool
  (let [(bOk (apm/countParenBalance "(:ok)"))
        (bNested (apm/countParenBalance "(:task\n  :name \"build\"\n  :timeout 5000)"))
        (bDeep (apm/countParenBalance "(:a (:b (:c 123)))"))
        (bStr (apm/countParenBalance "(\"hello (nested) parens\" 42)"))
        (bInvalid (apm/countParenBalance ")("))
        (bExtraClose (apm/countParenBalance "())("))
        (bUnclosed (apm/countParenBalance "(:open 1 2 3"))]
    (assert (= bOk 0) "(:ok) has zero balance")
    (assert (= bNested 0) "Multiline balanced form has zero balance")
    (assert (= bDeep 0) "Deeply nested balanced form has zero balance")
    (assert (= bStr 0) "Form with parens inside string literal has zero balance")
    (assert (apm/isBalancedFrame? "(:ok)") "(:ok) is recognized as balanced frame")
    (assert (apm/isBalancedFrame? "(:task\n  :name \"build\")") "Multiline form is balanced frame")
    (refute (not (apm/isBalancedFrame? "(:ok)")) "(:ok) must not be reported unbalanced")
    (assert (< bInvalid 0) ")( yields negative balance due to guard")
    (refute (apm/isBalancedFrame? ")(") ")( must not be considered balanced")
    (assert (< bExtraClose 0) "())( yields negative balance")
    (refute (apm/isBalancedFrame? "())(") "())( must not be considered balanced")
    (assert (> bUnclosed 0) "Unclosed form yields positive balance")
    (refute (apm/isBalancedFrame? "(:open 1 2 3") "Unclosed form must not be balanced")
    (refute (apm/isBalancedFrame? "") "Empty string is not a balanced frame")
    true)

fn testOobDemuxerMemoryBounds -> Bool
  (let [(d0 (apm/makeOobDemuxer "tmp/task55606-oob.spool" 67108864))
        (chunk "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n")
        (d300 (fold (fn [(demuxer apm/OobDemuxer) (_i Int64)] -> apm/OobDemuxer (apm/oobDemuxChunk demuxer chunk)) d0 (range 0 300)))
        (dSmall (apm/makeOobDemuxer "tmp/task55606-small.spool" 50))
        (dOver (apm/oobDemuxChunk dSmall chunk))]
    (assert (= d0.bufferBytes 0) "Initial bufferBytes is zero")
    (assert (= d0.totalBytes 0) "Initial totalBytes is zero")
    (refute d0.isTerminated "Initial demuxer is not terminated")
    (assert (= d0.terminationReason ":none") "Initial terminationReason is :none")
    (assert (= d300.totalBytes 24300) "Total bytes reflects cumulative throughput (300 * 81)")
    (assert (<= d300.bufferBytes 17000) "Active bufferBytes bounded by 200-line RAM ring buffer (<= 200 * 81)")
    (refute d300.isTerminated "Demuxer is not terminated under nominal streaming")
    (refute (!= d300.terminationReason ":none") "Termination reason remains :none under nominal streaming")
    (assert dOver.isTerminated "Demuxer terminates when active RAM exceeds configured limit")
    (refute (not dOver.isTerminated) "Demuxer must not remain active on RAM overflow")
    (assert (= dOver.terminationReason ":buffer-overflow") "Termination reason is :buffer-overflow")
    true)

fn testDualPolarityRefutations -> Bool
  (let [(badStream "(:unclosed_stream_frame\n  :step 1\n")
        (rBad (apm/parseStreamFrame badStream))
        (fBad (pairFirst rBad))
        (supFast (apm/superviseStep 200 10000 ":fast-op"))
        (supSlow (apm/superviseStep 11000 10000 ":slow-op"))]
    (assert (none? fBad) "Arbitrary unparenthesized input produces no frame")
    (refute (some? fBad) "Arbitrary input must not produce valid frame")
    (refute (apm/isBalancedFrame? badStream) "Unclosed form is not balanced frame")
    (assert (= supFast.status ":ok") "SuperviseStep status for fast step is :ok")
    (refute supFast.workerRecycled "Fast step must not recycle worker")
    (assert (= supSlow.status ":recycled") "SuperviseStep status for slow step is :recycled")
    (refute (!= supSlow.exitCode 124) "Slow step exit code must be 124")
    (assert supSlow.workerRecycled "Slow step must mark worker recycled")
    true)

fn RunTests -> Bool
  (do
    (assert (testStreamFramingNewlineAndMultiline) "testStreamFramingNewlineAndMultiline must pass")
    (assert (testCountParenBalance) "testCountParenBalance must pass")
    (assert (testOobDemuxerMemoryBounds) "testOobDemuxerMemoryBounds must pass")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations must pass")
    true)

fn runTests -> Bool
  (RunTests)
