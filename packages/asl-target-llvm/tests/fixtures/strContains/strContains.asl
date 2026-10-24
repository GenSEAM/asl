(module strContains
  :x [main]
  :i [])
fn bit b: Bool -> String
  (if b "1" "0")
fn cases -> (List (Pair String String))
  (list (pair "abc" "") (pair "" "") (pair "" "a") (pair "abc" "abcd") (pair "abc" "abc") (pair "abc" "a") (pair "abc" "c")
        (pair "abc" "bc") (pair "abc" "abd") (pair "abc" "xbc") (pair "aaaaab" "aaab") (pair "aaaaaa" "aaab") (pair "aaaab" "aab")
        (pair "abababac" "abac") (pair "abababab" "babc") (pair "a\x00b" "\x00b") (pair "a\x00b" "\x00c") (pair "a\x00b" "b\x00")
        (pair "\x00\x00\x00" "\x00\x00") (pair "ab" "a\x00") (pair "héllo wörld 世界" "世界")
        (pair "héllo" "él") (pair "héllo" "è") (pair "世界" "畍") (pair "xyz" "xyzz"))
fn run cs: (List (Pair String String)) acc: String -> String
  (fold (fn [(a String) (c (Pair String String))] -> String (str a (bit (stringContains? (pairFirst c) (pairSecond c))))) acc cs)

fn scan i: Int64 n: Int64 hay: String needle: String hits: Int64 -> Int64
  (if (= i n) hits
    (scan (+ i 1) n hay needle (if (stringContains? hay needle) (+ hits 1) hits)))
fn ! big n: Int64 -> Unit
  (let [(hay (stringRepeat "abcdefgh" 4194304))
        (tail (str hay "needleXYZ"))]
    (do (println (str "len " (stringFromInt64 (stringLength hay))))
        (println (str "absent " (stringFromInt64 (scan 0 n hay "abcdefgx" 0))))
        (println (str "absentLong " (stringFromInt64 (scan 0 n hay "hhhhhhhhhhhhhhhh" 0))))
        (println (str "atEnd " (stringFromInt64 (scan 0 n tail "needleXYZ" 0))))
        (println (str "atStart " (stringFromInt64 (scan 0 n tail "abcdefgh" 0))))
        (println (str "nearEnd " (stringFromInt64 (scan 0 n tail "gheedle" 0))))))
fn ! main args: (List String) -> (Result Unit String)
  (if (= (optionOr (listHead args) "") "big")
    (do (big 20) (ok ()))
    (do (println (run (cases) "")) (ok ())))
