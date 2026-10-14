(module jsFixtures/needsFile :x [main])

fn ! main -> Int64
  (mt (fileRead "/etc/hostname") ((ok s) (stringLength s)) ((err e) 0))
