(module asl-mesh/tests/coordTest
  :x [RunTests runTests testCanFitPartitionWithReadClosureFencing testScheduleDisjointTasksWithReadClosure testCanStealTaskWithReadClosure]
  :i [(asl-mesh/coord :a coord)])

fn testCanFitPartitionWithReadClosureFencing -> Bool
  (let [(claim (coord/makeSwarmClaim "task-1" "worker-1" 1000 (list "out.asn") (list "shared.asn") "root-hash"))
        (partWriteConflict (coord/makeWorkerPartition "worker-2" (list "task-2") (list "out.asn")))
        (partReadConflict (coord/makeWorkerPartition "worker-3" (list "task-3") (list "shared.asn")))
        (partClean (coord/makeWorkerPartition "worker-4" (list "task-4") (list "other.asn")))]
    (assert (not (coord/canFitPartitionWithReadClosure claim partWriteConflict)) "write-write conflict cannot fit partition")
    (assert (not (coord/canFitPartitionWithReadClosure claim partReadConflict)) "read-write conflict cannot fit partition")
    (assert (coord/canFitPartitionWithReadClosure claim partClean) "clean disjoint partition fits")
    true)

fn testScheduleDisjointTasksWithReadClosure -> Bool
  (let [(claim1 (coord/makeSwarmClaim "t1" "w1" 1000 (list "shared.asn") (list) "h1"))
        (claim2 (coord/makeSwarmClaim "t2" "w2" 1000 (list "other.asn") (list "shared.asn") "h1"))
        (parts (coord/scheduleDisjointTasks (list claim1 claim2)))]
    (assert (= (listLength parts) 2) "read-write conflict forces allocation of distinct partitions")
    (refute (= (listLength parts) 1) "refutation: read-write conflict must not merge into single partition")
    true)

fn testCanStealTaskWithReadClosure -> Bool
  (let [(claim (coord/makeSwarmClaim "t1" "w1" 1000 (list "local.asn") (list "shared.asn") "h1"))
        (thiefClean (coord/makeWorkerPartition "thief1" (list) (list "other.asn")))
        (thiefConflict (coord/makeWorkerPartition "thief2" (list) (list "shared.asn")))]
    (assert (coord/canStealTask? thiefClean claim) "thief without overlap can steal task")
    (assert (not (coord/canStealTask? thiefConflict claim)) "thief with write set overlapping read closure cannot steal task")
    (refute (coord/canStealTask? thiefConflict claim) "refutation: thief with read-closure collision cannot steal")
    true)

fn RunTests -> Bool
  (and (testCanFitPartitionWithReadClosureFencing)
       (and (testScheduleDisjointTasksWithReadClosure)
            (testCanStealTaskWithReadClosure)))

fn runTests -> Bool
  (RunTests)
