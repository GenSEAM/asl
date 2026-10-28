(module asl-cli/tests/asl1CacheBaseTest
  :x [runTests main]
  :i [(asl-cli/asl1Cache :a cache) (asl-cli/system :a sys)])

; (:m :ref ASL1-COLD-COMPILE :do "two worktrees holding the same compiler source and runtime archive get the same cache base, so the second reuses the first's asl1-native; a changed byte, a changed runtime or another clang gets a new base; stamps go to a scratch dir, never the live cache")

fn ! tempRoot -> String
  (str "/tmp/asl1CacheBaseTest_" (stringFromInt64 (procSelf)) "_" (stringFromInt64 (monotonicNs)))

fn ! tree! root: String name: String compiler: String lib: String -> (Pair String String)
  (let [(dir (str root "/" name))
        (_ (dirCreate dir))
        (c (str dir "/asl1.asl"))
        (l (str dir "/libaslrt.a"))
        (_w (fileWrite c compiler))
        (_x (fileWrite l lib))]
    (pair c l))

fn ! baseOf stamps: String t: (Pair String String) clang: String -> String
  (match (cache/baseHashesIn stamps (pairFirst t) (pairSecond t) clang)
    ((ok b) b)
    ((err e) (str "ERR " e)))

fn ! runTests -> Bool
  (let [(root (tempRoot))
        (stamps (str root "/stamps"))
        (made (ok? (dirCreate root)))
        (a (tree! root "worktreeA" "fn main -> Int64\n  0\n" "lib-1"))
        (b (tree! root "worktreeB" "fn main -> Int64\n  0\n" "lib-1"))
        (edited (tree! root "worktreeC" "fn main -> Int64\n  1\n" "lib-1"))
        (relinked (tree! root "worktreeD" "fn main -> Int64\n  0\n" "lib-2"))
        (baseA (baseOf stamps a "clang 18"))
        (baseB (baseOf stamps b "clang 18"))
        (baseEdited (baseOf stamps edited "clang 18"))
        (baseRelinked (baseOf stamps relinked "clang 18"))
        (baseClang (baseOf stamps b "clang 19"))
        (cleaned (sys/capture! (list "rm" "-rf" root) (none)))]
    (do
      (assert made "scratch root created")
      (assert (stringStartsWith? baseA "compiler=") "the base hashes the compiler by role")
      (refute (stringContains? baseA root) "the base carries no worktree path")
      (assert (= baseA baseB) "two worktrees with the same compiler and runtime share one base")
      (refute (= baseA baseEdited) "a changed compiler byte misses")
      (refute (= baseA baseRelinked) "a changed runtime archive misses")
      (refute (= baseB baseClang) "another clang misses")
      (assert (ok? cleaned) "scratch root removed")
      true))

fn ! main -> Bool
  (runTests)
