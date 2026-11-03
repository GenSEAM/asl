(module asl-agent-bus/tests/partitionTest :x [runTests] :i [(aslAgentBus/cluster :a cl)])

; (:m :ref COVBATCH4 :do "partition ownership: deriving a partition, path containment in both directions, conflicts between owner lists, disjoint partitions")
fn part owns: (List String) -> cl/TaskPartition
  (cl/derivePartitionFromTask "t1" "s1" owns)

fn runTests -> Bool
  (let [(p (cl/derivePartitionFromTask "t1" "s1" (list "src/a" "docs")))]
    (do
      (assert (= p.taskId "t1") "the task id is kept")
      (assert (= p.sessionId "s1") "the session id is kept")
      (assert (= p.owns (list "src/a" "docs")) "the owned paths are kept")
      (assert (cl/isPathInPartition? p "src/a") "an owned path")
      (assert (cl/isPathInPartition? p "src/a/file.txt") "a path below an owned directory")
      (assert (cl/isPathInPartition? p "src") "a parent of an owned directory overlaps it")
      (assert (not (cl/isPathInPartition? p "src/ab")) "a sibling with the same prefix is not inside")
      (assert (not (cl/isPathInPartition? p "other")) "an unrelated path")
      (assert (not (cl/isPathInPartition? (part (list)) "src")) "an empty partition owns nothing")
      (assert (cl/checkPartitionConflicts (list "src/a") (list "src/a/b")) "a child of an owned path conflicts")
      (assert (cl/checkPartitionConflicts (list "src/a/b") (list "src/a")) "a parent of an owned path conflicts")
      (assert (cl/checkPartitionConflicts (list "x" "src/a") (list "y" "src/a")) "a shared path later in the list conflicts")
      (assert (not (cl/checkPartitionConflicts (list "src/a") (list "src/b"))) "different paths do not conflict")
      (assert (not (cl/checkPartitionConflicts (list "src/a") (list "src/ab"))) "a shared prefix without a slash does not conflict")
      (assert (not (cl/checkPartitionConflicts (list) (list "src/a"))) "no owned paths, no conflict")
      (assert (not (cl/checkPartitionConflicts (list "src/a") (list))) "against no owned paths, no conflict")
      (assert (cl/partitionsDisjoint? (part (list "src/a")) (part (list "src/b"))) "separate directories are disjoint")
      (assert (not (cl/partitionsDisjoint? (part (list "src/a")) (part (list "src/a/b")))) "nested directories are not disjoint")
      (assert (cl/partitionsDisjoint? (part (list)) (part (list "src/a"))) "an empty partition is disjoint from any")
      true))
