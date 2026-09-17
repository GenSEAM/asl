(module asl-runtime/float
  :d "Shortest round-trip IEEE 754 float formatting and parsing"
  :x [rtFormatF64
      rtParseF64]
  :i [])

(df rtFormatF64 [(val Float64)] -> String
  :d "Formats a 64-bit float using shortest lossless round-trip representation."
  (string-from-float64 val))

(df rtParseF64 [(s String)] -> Float64
  :d "Parses a string into a 64-bit IEEE 754 float."
  (option-or (string-to-float64 s) 0.0))
