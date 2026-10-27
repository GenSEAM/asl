(module asl-intel/tests/toolsWaveOneTest
  :x [runTests]
  :i [(asl-intel :a intel)
      (asl-intel/deadcode :a dc)
      (asl-intel/stubs :a st)])

fn ! fixtureDir! tag: String -> String
  (let [(base (optionOr (envGet "TMPDIR") "/tmp"))
        (dir (str base "/asl-intel-w1-" tag "-" (stringFromInt64 (monotonicNs))))
        (made (dirCreate dir))]
    (do (assert (ok? made) (str "dirCreate failed for fixture " dir))
        dir))

fn ! writeIn! dir: String rel: String text: String -> Bool
  (let [(path (str dir "/" rel))
        (parts (stringSplit rel "/"))
        (sub (stringJoin (listTake parts (- (listLength parts) 1)) "/"))
        (made (dirCreate (str dir "/" sub)))
        (written (fileWrite path text))]
    (do (assert (ok? made) (str "mkdir " sub))
        (assert (ok? written) (str "write " rel))
        true))

fn ! testDeadcodeSkipsCache -> Bool
  (let [(dir (fixtureDir! "dead"))
        (w1 (writeIn! dir "src/a.asl" "(module a :x [pub])\n\nfn pub -> Int64\n  1\n\nfn liveOrphan -> Int64\n  2\n"))
        (w2 (writeIn! dir ".asl/cache/s/b.asl" "(module b :x [])\n\nfn cachedOrphan -> Int64\n  3\n"))
        (r (dc/analyzeDeadcode! (intel/makeCtx!) dir ""))
        (cleaned (pathRemove dir))]
    (match r
      ((err e) (do (assert false (str "analyzeDeadcode! failed: " e)) false))
      ((ok s)
        (let [(names (dc/formatDeadcodeAsn s))]
          (do (assert (stringContains? names ":name \"liveOrphan\"") (str "a private unreferenced fn in src is reported: " names))
              (assert (not (stringContains? names "cachedOrphan")) (str ".asl/cache copy is not scanned: " names))
              (assert (= s.filesScanned 1) (str "only the source file is scanned, got " (stringFromInt64 s.filesScanned)))
              (assert (ok? cleaned) "cleanup")
              true)))))

fn ! testStubsProdScope -> Bool
  (let [(dir (fixtureDir! "stubs"))
        (stubSrc "(module s :x [stubby])\n\nfn stubby x: Int64 -> Int64\n  0\n")
        (w1 (writeIn! dir "src/real.asl" stubSrc))
        (w2 (writeIn! dir "tests/fixtures/fx.asl" stubSrc))
        (w3 (writeIn! dir "corpus/c.asl" stubSrc))
        (w4 (writeIn! dir "examples/e.asl" stubSrc))
        (r (st/analyzeStubs! (intel/makeCtx!) dir))
        (cleaned (pathRemove dir))]
    (match r
      ((err e) (do (assert false (str "analyzeStubs! failed: " e)) false))
      ((ok s)
        (let [(files (map (fn [(f st/StubFinding)] -> String f.file) s.stubs))
              (asn (st/formatStubsAsn s))]
          (do (assert (= (listLength files) 1) (str "only the production stub counts: " (stringJoin files " ")))
              (assert (stringContains? (optionOr (listHead files) "") "src/real.asl") "the finding is the src file")
              (assert (= s.files 1) (str "fixture, corpus, examples files are out of scope, scanned " (stringFromInt64 s.files)))
              (assert (stringContains? asn ":scope") "receipt states its scope")
              (assert (ok? cleaned) "cleanup")
              true)))))

fn ! runTests -> Bool
  (do (assert (testDeadcodeSkipsCache) "deadcode ignores .asl/cache copies")
      (assert (testStubsProdScope) "stubs excludes fixtures, corpus and examples and says so")
      true)
