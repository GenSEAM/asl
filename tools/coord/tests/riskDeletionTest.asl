(module asl-tools/coord/tests/riskDeletionTest
  :x [runTests]
  :i [(asl-tools/coord/risk :a r)])

fn refused path: String oldLines: Int64 deletedLines: Int64 task: String -> Bool
  (match (r/deletionRefusal path oldLines deletedLines task)
    ((some t) (and (stringContains? t path)
                   (stringContains? t (stringFromInt64 deletedLines))
                   (stringContains? t (stringFromInt64 oldLines))))
    ((none) false))

fn allowed path: String oldLines: Int64 deletedLines: Int64 task: String -> Bool
  (none? (r/deletionRefusal path oldLines deletedLines task))

fn testMassDeletionRefused -> Bool
  (do (assert (refused "asl/tools/remote/vps.asl" 1481 1470 "cut tools/remote/vps.asl from 1481 lines to 24")
              "1481/1470 is refused and the refusal names the path and both counts")
      true)

fn testUnderHalfAllowed -> Bool
  (do (assert (allowed "asl/tools/remote/vps.asl" 1481 700 "trim tools/remote/vps.asl")
              "700 of 1481 is under half and allowed")
      true)

fn testSmallFileAllowed -> Bool
  (do (assert (allowed "asl/tools/remote/vps.asl" 30 29 "shrink a small file")
              "a 30-line file is under the 40-line floor and allowed")
      true)

fn testRewriteTaskAllowed -> Bool
  (do (assert (allowed "asl/tools/remote/vps.asl" 1481 1470 "rewrite vps.asl")
              "a task containing rewrite allows the deletion")
      (assert (allowed "asl/tools/remote/vps.asl" 1481 1470 "Rewrite VPS.ASL")
              "rewrite matches case-insensitively")
      true)

fn testExactlyHalfAllowed -> Bool
  (do (assert (allowed "asl/tools/remote/vps.asl" 100 50 "trim half the file")
              "exactly 0.5 is not over half and allowed")
      (assert (allowed "asl/tools/remote/vps.asl" 40 20 "trim half of a 40-line file")
              "exactly 0.5 at the 40-line floor is allowed")
      true)

fn ! runTests -> Bool
  (do (assert (testMassDeletionRefused) "mass deletion refused")
      (assert (testUnderHalfAllowed) "under half allowed")
      (assert (testSmallFileAllowed) "small file allowed")
      (assert (testRewriteTaskAllowed) "rewrite task allowed")
      (assert (testExactlyHalfAllowed) "exactly half allowed")
      true)
