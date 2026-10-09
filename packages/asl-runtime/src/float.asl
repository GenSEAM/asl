(module asl-runtime/float :x [rtFormatF64 rtParseF64] :i [])

fn rtFormatF64 val: Float64 -> String
  (stringFromFloat64 val)

fn rtParseF64 s: String -> (Option Float64)
  (stringToFloat64 s)
