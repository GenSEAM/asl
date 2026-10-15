(module jsFixtures/overflow :x [main])

fn grow n: Int64 -> Int64
  (if (> n 0) (grow (* n 2)) n)

fn ! main -> Int64
  (do (println "before") (grow 1))
