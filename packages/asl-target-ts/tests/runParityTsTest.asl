(module asl-target-ts/tests/runParityTsTest
  :x [testSampleParity testStringsParity testRecordsParity testListsParity testResultParity testErrorsParity runTests]
  :i [(asl-target-ts/runTs :a tsRunner)])

fn ! testCorpusParity path: String -> Bool
  (mt (fileRead path)
    ((err e) (do (assert false (str "read corpus file failed: " path " error: " e)) false))
    ((ok src)
      (let [(oracle (processRun (str "asl/host/out/asl-host run " path)))
            (target (tsRunner/compileAndRunTs src))]
        (do
          (assert (not (stringEmpty? src)) (str "read corpus file: " path))
          (assert (= target.exitCode oracle.exitCode)
                  (str path " exit code parity: oracle=" (stringFromInt64 oracle.exitCode) " ts=" (stringFromInt64 target.exitCode) " stderr: " target.stderr))
          (assert (= target.stdout oracle.stdout)
                  (str path " stdout parity: oracle=" oracle.stdout " ts=" target.stdout))
          true))))

fn ! testSampleParity -> Bool
  (testCorpusParity "tests/acceptance/targetParity/corpus/sample.asl")

fn ! testStringsParity -> Bool
  (testCorpusParity "tests/acceptance/targetParity/corpus/strings.asl")

fn ! testRecordsParity -> Bool
  (testCorpusParity "tests/acceptance/targetParity/corpus/records.asl")

fn ! testListsParity -> Bool
  (testCorpusParity "tests/acceptance/targetParity/corpus/lists.asl")

fn ! testResultParity -> Bool
  (testCorpusParity "tests/acceptance/targetParity/corpus/result.asl")

fn ! testErrorsParity -> Bool
  (testCorpusParity "tests/acceptance/targetParity/corpus/errors.asl")

fn ! runTests -> Bool
  (do
    (assert (testSampleParity) "testSampleParity")
    (assert (testStringsParity) "testStringsParity")
    (assert (testRecordsParity) "testRecordsParity")
    (assert (testListsParity) "testListsParity")
    (assert (testResultParity) "testResultParity")
    (assert (testErrorsParity) "testErrorsParity")
    true)
