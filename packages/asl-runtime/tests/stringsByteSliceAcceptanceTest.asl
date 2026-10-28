(module asl-runtime/tests/stringsByteSliceAcceptanceTest
  :x [runTests RunTests testByteSliceSpanOperations testClampingBehavior testDualPolarityRefutations]
  :i [(asl-runtime/strings :a str)])

fn bytesSameFrom? a: Bytes b: Bytes i: Int64 -> Bool
  (if (>= i (bytesLength a))
    true
    (and (= (bytesGet a i) (bytesGet b i)) (bytesSameFrom? a b (+ i 1))))

fn bytesSame? a: Bytes b: Bytes -> Bool
  (and (= (bytesLength a) (bytesLength b)) (bytesSameFrom? a b 0))

fn testByteSliceSpanOperations -> Bool
  (let [(original "Header: HTTP/2 Payload Data Block")
        (bytes (stringToBytes original))
        (sub (stringToBytes (str/strSliceSafe original 8 14)))]
    (assert (= (bytesLength bytes) 33) "Bytes length matches UTF-8 input")
    (refute (!= (bytesLength bytes) 33) "Bytes length refutes mismatch")
    (assert (= (bytesLength sub) 6) "runtime slice 8..14 has 6 bytes")
    (assert (= (bytesGet sub 0) 72) "slice starts with H")
    (assert (= (bytesGet sub 1) 84) "slice contains T")
    (assert (= (bytesGet sub 2) 84) "slice contains second T")
    (assert (= (bytesGet sub 3) 80) "slice contains P")
    (assert (= (bytesGet sub 4) 47) "slice contains slash")
    (assert (= (bytesGet sub 5) 50) "slice ends with 2")
    (assert (= (bytesGet sub 0) (bytesGet bytes 8)) "slice byte 0 is source byte 8")
    (assert (bytesSame? sub (stringToBytes "HTTP/2")) "slice 8..14 equals the whole HTTP/2 buffer"))
  true

fn testClampingBehavior -> Bool
  (let [(over (stringToBytes (str/strSliceSafe "ABC" 1 51)))
        (under (stringToBytes (str/strSliceSafe "ABC" -5 2)))]
    (assert (= (bytesLength over) 2) "oversized slice end clamps to remaining bytes")
    (refute (!= (bytesLength over) 2) "clamped slice refutes non-2 length")
    (assert (= (bytesGet over 0) 66) "clamped slice starts with B")
    (assert (= (bytesGet over 1) 67) "clamped slice ends with C")
    (assert (= (bytesLength under) 2) "negative slice start clamps to 0")
    (assert (= (bytesGet under 0) 65) "start-clamped slice starts with A")
    (assert (bytesSame? over (stringToBytes "BC")) "end-clamped slice equals the whole BC buffer")
    (assert (bytesSame? under (stringToBytes "AB")) "start-clamped slice equals the whole AB buffer"))
  true

fn testDualPolarityRefutations -> Bool
  (let [(s1 (stringToBytes "foo"))
        (s2 (stringToBytes "bar"))
        (s3 (stringToBytes "fob"))
        (s4 (stringToBytes "fo"))]
    (assert (bytesSame? s1 (stringToBytes "foo")) "separately built equal buffers compare equal")
    (refute (bytesSame? s1 s2) "buffers differing at the first byte refute equality")
    (refute (bytesSame? s1 s3) "buffers differing only at the last byte refute equality")
    (refute (bytesSame? s1 s4) "a strict prefix buffer refutes equality")
    (refute (bytesSame? s4 s1) "a longer buffer refutes equality with its prefix"))
  true

fn runTests -> Bool
  (do
    (assert (testByteSliceSpanOperations) "testByteSliceSpanOperations passed")
    (assert (testClampingBehavior) "testClampingBehavior passed")
    (assert (testDualPolarityRefutations) "testDualPolarityRefutations passed")
    true)

fn RunTests -> Bool
  (runTests)
