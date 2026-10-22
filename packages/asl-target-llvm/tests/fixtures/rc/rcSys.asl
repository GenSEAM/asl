(module rcSys
  :x [main]
  :i [])

fn dir -> String
  "asl/packages/asl-target-llvm/tests/fixtures/rc"

fn self -> String
  (str (dir) "/rcSys.asl")

fn ! score -> Int64
  (let [(stat (if (ok? (fileStat (dir))) 1 0))
        (real (match (realPath (self)) ((ok p) (if (stringEndsWith? p "/rcSys.asl") 1 0)) ((err _) 0)))
        (text (match (fileReadString (self)) ((ok s) (if (stringContains? s "fn ! score") 1 0)) ((err _) 0)))
        (listed (match (dirList (dir)) ((ok names) (if (listContains? names "rcSys.asl") 1 0)) ((err _) 0)))
        (exists (if (fileExists? (self)) 1 0))]
    (+ stat (+ real (+ text (+ listed exists)))))

fn ! probe n: Int64 acc: Int64 -> Int64
  (if (= n 0) acc (probe (- n 1) (+ acc (score))))

fn ! main args: (List String) -> (Result Int64 String)
  (do (println (str (probe 2000 0)))
      (ok 0))
