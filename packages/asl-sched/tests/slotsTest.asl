(module asl-sched/tests/slotsTest
  :x [runTests]
  :i [(asl-sched/interval :a iv) (asl-sched/slots :a s) (asl-sched/cron :a c)])

fn runTests -> Bool
  (let [(slot (s/slot "job" 100 "" 0 0))
        (schedule (iv/intervalValue 10 100))]
    (assert (mt (iv/interval 0 1) ((err _) true) ((ok _) false)) "interval rejects zero")
    (assert (= (iv/intervalNextFire schedule 99) (ok 100)) "interval anchored before start")
    (assert (= (iv/intervalNextFire schedule 110) (ok 120)) "interval is strictly after")
    (assert (mt (s/slotClaim slot "worker-a" 99 5) ((notDue) true) ((claimed _) false) ((alreadyClaimed) false) ((invalidLease) false)) "claim before due is not due")
    (assert (mt (s/slotClaim slot "worker-a" 100 0) ((invalidLease) true) ((claimed _) false) ((alreadyClaimed) false) ((notDue) false)) "claim rejects empty lease")
    (assert (mt (s/slotClaim slot "worker-a" 100 5) ((claimed value) (= value (s/slot "job" 100 "worker-a" 105 1))) ((alreadyClaimed) false) ((notDue) false) ((invalidLease) false)) "due slot is claimed")
    (assert (mt (s/slotClaim (s/slot "job" 100 "worker-a" 105 1) "worker-b" 104 5) ((alreadyClaimed) true) ((claimed _) false) ((notDue) false) ((invalidLease) false)) "live claim blocks second worker")
    (assert (mt (s/slotClaim (s/slot "job" 100 "worker-a" 105 1) "worker-b" 105 5) ((claimed value) (= value (s/slot "job" 100 "worker-b" 110 2))) ((alreadyClaimed) false) ((notDue) false) ((invalidLease) false)) "expired claim can be replaced")
    (assert (= (s/slotExpire (s/slot "job" 100 "worker-a" 105 1) 105) (s/slot "job" 100 "" 0 1)) "lease expiry releases claim")
    (assert (= (s/slotExpire (s/slot "job" 100 "worker-a" 105 1) 104) (s/slot "job" 100 "worker-a" 105 1)) "live lease remains claimed")
    (assert (= (s/recoverSlots [(s/slot "job" 100 "worker-a" 105 1)] 105) [(s/slot "job" 100 "" 0 1)]) "recovery releases expired slot")
    (assert (= (s/recoverSlots (s/recoverSlots [(s/slot "job" 100 "worker-a" 105 1)] 105) 105) []) "recovered claim is returned exactly once")
    (assert (mt (s/slotComplete (s/slot "job" 100 "worker-a" 105 1) (s/intervalSchedule schedule) 110) ((ok next) (= next (s/slot "job" 120 "" 0 0))) ((err _) false)) "complete schedules next interval slot")
    (assert (mt (c/parseCron "@hourly") ((ok cron) (mt (s/slotComplete slot (s/cronSchedule cron) 0) ((ok next) (= next (s/slot "job" 3600 "" 0 0))) ((err _) false))) ((err _) false)) "complete schedules next cron slot")
    (assert (mt (s/parseSlot (s/serializeSlot (s/slot "job" 100 "worker" 105 2))) ((ok parsed) (= parsed (s/slot "job" 100 "worker" 105 2))) ((err _) false)) "slot ASN round trip")
    (assert (mt (s/parseSlot (s/serializeSlot (s/slot "job name (\"queued\")\nnext" 100 "worker one\\node\tend\x00" 105 2))) ((ok parsed) (= parsed (s/slot "job name (\"queued\")\nnext" 100 "worker one\\node\tend\x00" 105 2))) ((err _) false)) "ASN strings round trip with whitespace and syntax characters")
    (assert (mt (s/parseSlot "not a slot") ((err _) true) ((ok _) false)) "invalid ASN is rejected")
    true)
