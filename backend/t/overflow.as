; §3 says wrapping is an error, not a behavior. Nothing exercised that: no
; benchmark case overflows, so the three backends were free to disagree and did.

(module t/overflow
  :doc "Force Int64 overflow so every backend can be held to the same rule."
  :export [blow-up safe-sum])

(defun safe-sum [(a Int64) (b Int64)] -> Int64
  :doc "Ordinary addition, well inside the range."
  (+ a b))

(defun blow-up [(n Int64)] -> Int64
  :doc "Addition that leaves Int64 for any positive n."
  (+ 9223372036854775807 n))
