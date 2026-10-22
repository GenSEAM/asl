(module asl-sched/interval
  :x [Interval intervalValue interval intervalNextFire]
  :i [])

enum Interval
  (intervalValue everySeconds: Int64 startSeconds: Int64)

fn interval everySeconds: Int64 startSeconds: Int64 -> (Result Interval String)
  (if (< everySeconds 1) (err "interval must be at least one second")
    (ok (intervalValue everySeconds startSeconds)))

fn intervalNextFire schedule: Interval afterSeconds: Int64 -> (Result Int64 String)
  (match schedule
    ((intervalValue step start)
      (let [(elapsed (- afterSeconds start))
            (n (if (< elapsed 0) 0 (+ (/ elapsed step) 1)))
            (candidate (+ start (* n step)))]
        (if (> candidate afterSeconds) (ok candidate)
          (ok (+ candidate step))))))
