(module asl-utils/tests/hexTest
  :x [runTests]
  :i [(asl-utils/hex :a hx)])

fn fillAll b: Bytes i: Int64 n: Int64 -> Int64
  (if (>= i n) 0
    (do (bytesSet b i i) (fillAll b (+ i 1) n)))

fn spaces n: Int64 -> String
  (if (<= n 0) "" (str " " (spaces (- n 1))))

fn expectedDump -> String
  (str "00000000  00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  |................|"
       "\n"
       "00000010  10 11 12 13" (spaces 38) "|....|")

fn testEmpty -> Bool
  (do (assert (= (hx/hexEncode (stringToBytes "")) "") "hexEncode empty is empty")
      (match (hx/hexDecode "")
        ((ok d) (assert (= (bytesLength d) 0) "hexDecode empty is empty bytes"))
        ((err e) (assert false e)))
      true)

fn testBytes -> Bool
  (let [(b (bytesAlloc 3))]
    (do (bytesSet b 0 0)
        (bytesSet b 1 255)
        (bytesSet b 2 16)
        (assert (= (hx/hexEncode b) "00ff10") "hexEncode 00 ff 10")
        (match (hx/hexDecode "00ff10")
          ((ok d) (assert (= (hx/hexEncode d) "00ff10") "hexDecode 00 ff 10"))
          ((err e) (assert false e)))
        true))

fn testRoundTrip -> Bool
  (let [(b (bytesAlloc 256))]
    (do (fillAll b 0 256)
        (let [(s (hx/hexEncode b))]
          (assert (= (stringLength s) 512) "hexEncode 256 bytes is 512 chars")
          (match (hx/hexDecode s)
            ((ok d) (assert (= (hx/hexEncode d) s) "round-trip all 256 byte values"))
            ((err e) (assert false e))))
        true))

fn testOdd -> Bool
  (match (hx/hexDecode "abc")
    ((ok _) false)
    ((err e) (stringContains? e "odd")))

fn testZz -> Bool
  (match (hx/hexDecode "zz")
    ((ok _) false)
    ((err e) (stringContains? e "0")))

fn testDump -> Bool
  (let [(b (bytesAlloc 20))]
    (do (fillAll b 0 20)
        (assert (= (hx/hexDump b 16) (expectedDump)) "pinned 20-byte dump at width 16")
        true))

fn testZeroWidth -> Bool
  (let [(b (bytesAlloc 4))]
    (do (fillAll b 0 4)
        (assert (= (hx/hexDump b 0) "") "hexDump width 0 is empty")
        (assert (= (hx/hexDump b -1) "") "hexDump negative width is empty")
        true))

fn runTests -> Bool
  (and (testEmpty) (testBytes) (testRoundTrip) (testOdd) (testZz) (testDump) (testZeroWidth))
