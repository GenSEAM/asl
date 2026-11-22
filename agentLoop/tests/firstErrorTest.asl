(module asl/agentLoop/tests/firstErrorTest
  :x [runTests]
  :i [(asl/agentLoop/firstError :a fe)])

fn got o: (Option String) -> String
  (optionOr o "")

fn hasValue o: (Option String) -> Bool
  (match o ((some _) true) ((none) false))

fn runTests -> Bool
  (let [(filler (stringJoin (map (fn [(i Int64)] -> String "ok sub line") (range 0 28)) "\n"))
        (thirty (stringJoin (list "ok a" "src/f.py:2:3: ERR_Y boom" filler) "\n"))
        (longline (stringConcat "src/f.py:1:1: ERR_X " (stringRepeat "y" 780)))]
    (do
      (assert (= (got (fe/firstErrorLine "src/f.py:3:7: ERR_UNKNOWN_SYMBOL nope\nsrc/g.py:9:1: ERR_TYPE mismatch"))
                 "src/f.py:3:7: ERR_UNKNOWN_SYMBOL nope")
              "first of two diagnostics keeps its path:line:col")
      (assert (= (got (fe/firstErrorLine "FAIL asl/agentLoop/tests/x.asl\nsrc/f.py:1:2: ERR_X nope"))
                 "FAIL asl/agentLoop/tests/x.asl")
              "FAIL line before a later ERR_ wins")
      (assert (= (got (fe/firstErrorLine thirty)) "src/f.py:2:3: ERR_Y boom")
              "error on line 2 of 30 lines")
      (assert (not (hasValue (fe/firstErrorLine "ok asl/agentLoop/tests/x.asl: (:checked 1 (:asserts 3) (:refutes 0))")))
              "green output yields none")
      (assert (= (stringLength (got (fe/firstErrorLine longline))) 400)
              "800-char diagnostic line comes back 400 chars")
      (assert (= (got (fe/firstErrorLine "src/f.py:1:1: ERR_X ")) "src/f.py:1:1: ERR_X")
              "line is trimmed and keeps its prefix")
      (assert (not (hasValue (fe/firstErrorLine "some prose\nwith no diagnostics\n")))
              "diagnostic-free output yields none")
      true))
