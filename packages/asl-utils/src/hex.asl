(module asl-utils/hex
  :x [hexEncode hexDecode hexDump]
  :i [])

fn hexDigit v: Int64 -> String
  (optionOr (stringSlice "0123456789abcdef" v (+ v 1)) "")

fn hexEncodeStep bs: Bytes i: Int64 n: Int64 -> String
  (if (>= i n) ""
    (let [(b (bytesGet bs i))]
      (str (hexDigit (/ b 16)) (hexDigit (mod b 16))
           (hexEncodeStep bs (+ i 1) n))))

fn hexEncode bs: Bytes -> String
  (hexEncodeStep bs 0 (bytesLength bs))

fn nibble c: String -> Int64
  (optionOr (stringIndexOf "0123456789abcdef" c) -1)

fn hexDecodeStep s: String i: Int64 n: Int64 out: Bytes -> (Result Bytes String)
  (if (>= i n) (ok out)
    (let [(hi (nibble (optionOr (stringSlice s (* i 2) (+ (* i 2) 1)) "")))
          (lo (nibble (optionOr (stringSlice s (+ (* i 2) 1) (+ (* i 2) 2)) "")))]
      (if (< hi 0) (err (str "invalid hex char at index " (stringFromInt64 (* i 2))))
        (if (< lo 0) (err (str "invalid hex char at index " (stringFromInt64 (+ (* i 2) 1))))
          (do (bytesSet out i (+ (* hi 16) lo))
              (hexDecodeStep s (+ i 1) n out))))))

fn hexDecode s: String -> (Result Bytes String)
  (let [(n (stringLength s))]
    (if (!= (mod n 2) 0) (err (str "odd hex length " (stringFromInt64 n)))
      (if (= n 0) (ok (stringToBytes ""))
        (hexDecodeStep (stringLower s) 0 (/ n 2) (bytesAlloc (/ n 2))))))

fn padLeft s: String w: Int64 -> String
  (if (>= (stringLength s) w) s
    (padLeft (str "0" s) w))

fn hexOfInt v: Int64 -> String
  (if (< v 16) (hexDigit v)
    (str (hexOfInt (/ v 16)) (hexDigit (mod v 16))))

fn printable b: Int64 -> String
  (if (and (>= b 32) (<= b 126))
    (optionOr (stringSlice " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~" (- b 32) (- b 31)) ".")
    ".")

fn rowHex bs: Bytes start: Int64 n: Int64 width: Int64 j: Int64 -> String
  (if (>= j width) ""
    (if (< (+ start j) n)
      (let [(b (bytesGet bs (+ start j)))]
        (str (hexDigit (/ b 16)) (hexDigit (mod b 16))
             (if (< (+ j 1) width) " " "")
             (rowHex bs start n width (+ j 1))))
      (str "  " (if (< (+ j 1) width) " " "")
           (rowHex bs start n width (+ j 1)))))

fn rowAscii bs: Bytes start: Int64 n: Int64 width: Int64 j: Int64 -> String
  (if (>= j width) ""
    (if (< (+ start j) n)
      (str (printable (bytesGet bs (+ start j)))
           (rowAscii bs start n width (+ j 1)))
      (rowAscii bs start n width (+ j 1))))

fn hexRow bs: Bytes start: Int64 n: Int64 width: Int64 -> String
  (str (padLeft (hexOfInt start) 8) "  "
       (rowHex bs start n width 0) "  |"
       (rowAscii bs start n width 0) "|")

fn hexDumpStep bs: Bytes start: Int64 n: Int64 width: Int64 -> String
  (if (>= start n) ""
    (str (hexRow bs start n width)
         (if (< (+ start width) n) "\n" "")
         (hexDumpStep bs (+ start width) n width)))

fn hexDump bs: Bytes width: Int64 -> String
  (if (or (<= (bytesLength bs) 0) (<= width 0)) ""
    (hexDumpStep bs 0 (bytesLength bs) width))
