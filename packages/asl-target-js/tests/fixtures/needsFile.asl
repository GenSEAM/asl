(module jsFixtures/needsFile :x [main])

fn ! main -> Int64
  (match (fileReadString "/etc/hostname") ((ok s) (stringLength s)) ((err e) 0))
