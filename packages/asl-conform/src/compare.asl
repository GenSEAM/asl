(module aslConform/compare :x [compareOutput invertComparison])

fn compareOutput actualStdout: Str actualExit: I64 expectStdout: Str expectExit: I64 -> Bool
  (and (= (stringTrim actualStdout) (stringTrim expectStdout)) (= actualExit expectExit))

fn invertComparison actualStdout: Str actualExit: I64 expectStdout: Str expectExit: I64 -> Bool
  (not (compareOutput actualStdout actualExit expectStdout expectExit))
