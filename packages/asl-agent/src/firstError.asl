(module aslAgent/firstError
  :x [firstErrorLine]
  :i [])

fn charAt s: String i: Int64 -> String
  (optionOr (stringSlice s i (+ i 1)) "")

fn trimLeft s: String i: Int64 n: Int64 -> Int64
  (if (>= i n) i
    (if (= (charAt s i) " ") (trimLeft s (+ i 1) n) i))

fn trimRight s: String i: Int64 -> Int64
  (if (< i 0) i
    (if (= (charAt s i) " ") (trimRight s (- i 1)) i))

fn trim s: String -> String
  (let [(n (stringLength s))
        (a (trimLeft s 0 n))
        (b (trimRight s (- n 1)))]
    (if (or (<= n 0) (> a b)) ""
      (optionOr (stringSlice s a (+ b 1)) "")))

fn cut400 s: String -> String
  (if (> (stringLength s) 400) (optionOr (stringSlice s 0 400) s) s)

fn hasSub s: String sub: String -> Bool
  (match (listGet (stringSplit s sub) 1)
    ((some _) true)
    ((none) false))

fn startsWith? s: String p: String -> Bool
  (= (optionOr (stringSlice s 0 (stringLength p)) "") p)

fn intAt parts: (List String) i: Int64 -> Bool
  (match (listGet parts i)
    ((some v)
     (match (stringToInt64 v)
       ((some _) true)
       ((none) false)))
    ((none) false))

fn isDiagnostic line: String -> Bool
  (let [(parts (stringSplit line ":"))]
    (and (hasSub line "ERR_") (intAt parts 1) (intAt parts 2)))

fn isTestFailure line: String -> Bool
  (or (startsWith? line "FAIL")
      (startsWith? line "ERR_ASSERT")
      (startsWith? line "ERR_REFUTE")
      (startsWith? line "ERR_TEST_FAILED")
      (hasSub line "assertion failed"))

fn isFailureLine line: String -> Bool
  (or (isDiagnostic line) (isTestFailure line))

fn pick acc: (Option String) rawLine: String -> (Option String)
  (match acc
    ((some _) acc)
    ((none)
     (let [(t (trim rawLine))]
       (if (isFailureLine t) (some (cut400 t)) (none)))))

fn firstErrorLine output: String -> (Option String)
  (fold pick (none) (stringSplit output "\n"))
