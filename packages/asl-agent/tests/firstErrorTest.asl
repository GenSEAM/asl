(module aslAgent/tests/firstErrorTest
  :x [runTests]
  :i [(aslAgent/firstError :a fe)])

fn got o: (Option String) -> String
  (optionOr o "")

fn hasValue o: (Option String) -> Bool
  (match o ((some _) true) ((none) false))

fn fill n: Int64 acc: (List String) -> (List String)
  (if (<= n 0) acc (fill (- n 1) (cons "ok sub line" acc)))

fn rep n: Int64 acc: String -> String
  (if (<= n 0) acc (rep (- n 1) (stringConcat acc "y")))

fn ! runTests -> Bool
  (let [(filler (stringJoin (fill 28 (list)) "\n"))
        (thirty (stringJoin (list "ok a" "src/f.py:2:3: ERR_Y boom" filler) "\n"))
        (longline (stringConcat "src/f.py:1:1: ERR_X " (rep 780 "")))]
    (do
      (assert (= (got (fe/firstErrorLine "src/f.py:3:7: ERR_UNKNOWN_SYMBOL nope\nsrc/g.py:9:1: ERR_TYPE mismatch"))
                 "src/f.py:3:7: ERR_UNKNOWN_SYMBOL nope")
              "first of two diagnostics keeps its path:line:col")
      (assert (= (got (fe/firstErrorLine "FAIL asl/packages/asl-agent/tests/x.asl\nsrc/f.py:1:2: ERR_X nope"))
                 "FAIL asl/packages/asl-agent/tests/x.asl")
              "FAIL line before a later ERR_ wins")
      (assert (= (got (fe/firstErrorLine thirty)) "src/f.py:2:3: ERR_Y boom")
              "error on line 2 of 30 lines")
      (assert (not (hasValue (fe/firstErrorLine "ok asl/packages/asl-agent/tests/x.asl: (:checked 1 (:asserts 3) (:refutes 0))")))
              "green output yields none")
      (assert (= (stringLength (got (fe/firstErrorLine longline))) 400)
              "800-char diagnostic line comes back 400 chars")
      (assert (= (got (fe/firstErrorLine "src/f.py:1:1: ERR_X ")) "src/f.py:1:1: ERR_X")
              "line is trimmed and keeps its prefix")
      (assert (not (hasValue (fe/firstErrorLine "some prose\nwith no diagnostics\n")))
              "diagnostic-free output yields none")
      true))
