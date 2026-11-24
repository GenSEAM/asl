(module asl-tools/coord/tests/throughputUnitsTest
  :x [runTests]
  :i [(asl-tools/coord/throughput :a tp) (asl-tools/coord/store :a st)])

fn task id: String channel: String stv: String -> st/Task
  (st/Task :id id :owns (list) :reads (list) :gate "" :channel channel :model "" :base "" :after (list) :st stv :epoch 0 :receipt "")

fn rowText d: tp/UnitDay -> String
  (str d.day "|" d.channel "|" (stringFromInt64 d.merged) "|" (stringFromInt64 d.failed) "|" (stringFromInt64 d.escalated))

fn emptyRow -> tp/UnitDay
  (tp/UnitDay :day "" :channel "" :merged 0 :failed 0 :escalated 0)

fn rowAt rows: (List tp/UnitDay) i: Int64 -> tp/UnitDay
  (optionOr (listGet rows i) (emptyRow))

fn ! runTests -> Bool
  (let [(units (list (task "u1" "alpha" "merged")
                     (task "u2" "alpha" "failed")
                     (task "u3" "beta" "blocked")
                     (task "u4" "beta" "merged")
                     (task "u5" "alpha" "queued")))
        (days (list (pair "u1" "2026-10-01")
                    (pair "u2" "2026-10-01")
                    (pair "u3" "2026-10-01")
                    (pair "u4" "2026-10-02")
                    (pair "u5" "2026-10-02")))
        (rows (tp/unitsByDay units days))]
    (do
      (assert (= (listLength rows) 3) "one row per day and channel, the queued unit is ignored")
      (assert (= (rowText (rowAt rows 0)) "2026-10-01|alpha|1|1|0") "alpha day one: one merged, one failed")
      (assert (= (rowText (rowAt rows 1)) "2026-10-01|beta|0|0|1") "beta day one: one escalated")
      (assert (= (rowText (rowAt rows 2)) "2026-10-02|beta|1|0|0") "beta day two: one merged")
      true))
