(module aslExamples/moduleUser
  :x [quad squarePlusOne doublePlusSquare]
  :i [(aslExamples/moduleExample :a modEx)])

fn quad n: Int64 -> Int64
  (modEx/double (modEx/double n))

fn squarePlusOne n: Int64 -> Int64
  (+ (modEx/square n) 1)

fn doublePlusSquare n: Int64 -> Int64
  (+ (modEx/double n) (modEx/square n))
