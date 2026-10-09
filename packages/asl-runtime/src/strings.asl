(module asl-runtime/strings
  :x [strPadLeft strPadRight strTrimLeft strTrimRight strTrim strReplaceAll strSplitLines strSliceSafe repeatChar repeatCharFast strContains? strStartsWith? strEndsWith? isWhitespaceChar]
  :i [])

fn isWhitespaceChar c: String -> Bool
  (or (= c " ") (or (= c "\t") (or (= c "\n") (= c "\r"))))

fn repeatChar ch: String count: Int64 acc: String -> String
  (if (<= count 0)
    acc
    (repeatChar ch (- count 1) (str acc ch)))

fn repeatCharFast ch: String count: Int64 -> String
  (if (<= count 0)
    ""
    (if (= count 1)
      ch
      (let [(half (/ count 2))
            (rem (mod count 2))
            (halfStr (repeatCharFast ch half))]
        (if (= rem 0)
          (str halfStr halfStr)
          (str halfStr halfStr ch)))))

fn strPadLeft s: String targetLen: Int64 padChar: String -> String
  (let [(curLen (stringLength s))]
    (if (>= curLen targetLen)
      s
      (let [(diff (- targetLen curLen))
            (padStr (repeatCharFast padChar diff))]
        (str padStr s))))

fn strPadRight s: String targetLen: Int64 padChar: String -> String
  (let [(curLen (stringLength s))]
    (if (>= curLen targetLen)
      s
      (let [(diff (- targetLen curLen))
            (padStr (repeatCharFast padChar diff))]
        (str s padStr))))

fn trimLeftIndex s: String idx: Int64 len: Int64 -> Int64
  (if (>= idx len)
    len
    (let [(c (optionOr (stringSlice s idx (+ idx 1)) ""))]
      (if (isWhitespaceChar c)
        (trimLeftIndex s (+ idx 1) len)
        idx)))

fn strTrimLeft s: String -> String
  (let [(len (stringLength s))]
    (if (= len 0)
      ""
      (let [(start (trimLeftIndex s 0 len))]
        (if (>= start len)
          ""
          (optionOr (stringSlice s start len) "")))))

fn trimRightIndex s: String idx: Int64 -> Int64
  (if (<= idx 0)
    0
    (let [(c (optionOr (stringSlice s (- idx 1) idx) ""))]
      (if (isWhitespaceChar c)
        (trimRightIndex s (- idx 1))
        idx)))

fn strTrimRight s: String -> String
  (let [(len (stringLength s))]
    (if (= len 0)
      ""
      (let [(end (trimRightIndex s len))]
        (if (<= end 0)
          ""
          (optionOr (stringSlice s 0 end) "")))))

fn strTrim s: String -> String
  (stringTrim s)

fn strContains? s: String sub: String -> Bool
  (stringContains? s sub)

fn strStartsWith? s: String prefix: String -> Bool
  (stringStartsWith? s prefix)

fn strEndsWith? s: String suffix: String -> Bool
  (stringEndsWith? s suffix)

fn strReplaceAll s: String oldSub: String newSub: String -> String
  (if (or (stringEmpty? oldSub) (not (stringContains? s oldSub)))
    s
    (stringJoin (stringSplit s oldSub) newSub))

fn cleanCarriageReturn line: String -> String
  (if (stringEndsWith? line "\r")
    (let [(len (stringLength line))]
      (if (> len 0)
        (optionOr (stringSlice line 0 (- len 1)) "")
        ""))
    line)

fn strSplitLines s: String -> (List String)
  (let [(rawLines (stringSplit s "\n"))]
    (map cleanCarriageReturn rawLines))

fn strSliceSafe s: String start: Int64 end: Int64 -> String
  (let [(len (stringLength s))
        (sClamped (if (< start 0) 0 (if (> start len) len start)))
        (eClamped (if (< end sClamped) sClamped (if (> end len) len end)))]
    (if (>= sClamped eClamped)
      ""
      (optionOr (stringSlice s sClamped eClamped) "")))
