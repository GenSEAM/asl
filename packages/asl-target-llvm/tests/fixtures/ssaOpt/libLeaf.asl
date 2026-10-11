(module asl-target-llvm/tests/fixtures/ssaOpt/libLeaf
  :x [Shade shadeDark shadeLight shadeTinted dark light shadeName noneOf incBy twice inc]
  :i [])

enum Shade
  (shadeDark)
  (shadeLight)
  (shadeTinted level: Int64)

fn dark -> Shade
  (shadeDark)

fn light -> Shade
  (shadeLight)

fn shadeName s: Shade -> String
  (mt s ((shadeDark) "dark") ((shadeLight) "light") ((shadeTinted n) (str "tinted" n)))

fn noneOf -> (Option Int64)
  (none)

fn inc x: Int64 -> Int64
  (+ x 1)

fn incBy -> (fn [Int64] -> Int64)
  inc

fn twice f: (fn [Int64] -> Int64) x: Int64 -> Int64
  (f (f x))
