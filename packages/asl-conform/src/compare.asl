(module aslConform/compare
  :d "Output and exit code comparison utilities for multi-target conformance"
  :x [compareOutput
      invertComparison])

(df compareOutput [(actualStdout Str) (actualExit I64) (expectStdout Str) (expectExit I64)] -> Bool
  :d "Compares observed process stdout and exit code against expected oracle."
  (and (= (string-trim actualStdout) (string-trim expectStdout))
       (= actualExit expectExit)))

(df invertComparison [(actualStdout Str) (actualExit I64) (expectStdout Str) (expectExit I64)] -> Bool
  :d "Inverts comparison to test assertion reachability under D77 refutation."
  (not (compareOutput actualStdout actualExit expectStdout expectExit)))
