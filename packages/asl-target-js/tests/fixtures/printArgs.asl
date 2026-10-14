(module jsFixtures/printArgs :x [main])

fn ! main -> Int64
  (do (println "a" 1 (list "x")) (print "b" "c") (println "") (println (stringChars "héllo")) 0)
