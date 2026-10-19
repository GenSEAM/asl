(module prelude/tests/stringSliceUtf8Test :x [runTests] :i [])

; (:m :ref STR-UTF8 :do "stringSlice (the native @strrt.slice builtin) stays byte-blind on purpose: much of the self-hosted compiler slices strings one raw byte at a time (its own UTF-8 decoder among them) and depends on that byte-blind behaviour never trapping; making the shared builtin itself codepoint-aware broke nativeStringTest's utf8 fixture and the native CLI's own build self-probe (ERR_MATCH_NONEXHAUSTIVE in prelude.preludeSlice) the first time this was tried. stringSliceUtf8 is new and additive: it layers the codepoint-boundary check on top of the unchanged stringSlice/stringToBytes/bytesGet builtins entirely in ASL, so nothing that already calls stringSlice is affected")

fn ! testMidCodepointTwoByte -> Bool
  (let [(s "é")]
    (do
      (assert (= (stringLength s) 2) "the 2-byte accented character occupies 2 bytes (byte length, not codepoint length)")
      (assert (= (stringSliceUtf8 s 0 1) none) "slicing [0,1) stops after only the first of 2 bytes: mid-codepoint, none")
      (assert (= (stringSliceUtf8 s 1 2) none) "slicing [1,2) starts at the continuation byte: mid-codepoint, none")
      (assert (= (stringSliceUtf8 s 0 2) (some s)) "slicing the whole 2-byte character on its own boundaries still works")
      (assert (= (stringSliceUtf8 s 0 0) (some "")) "an empty slice at the start boundary still works")
      (assert (= (stringSliceUtf8 s 2 2) (some "")) "an empty slice at the end boundary still works")
      true))

fn ! testMidCodepointThreeByte -> Bool
  (let [(s "日")]
    (do
      (assert (= (stringLength s) 3) "the 3-byte CJK character occupies 3 bytes")
      (assert (= (stringSliceUtf8 s 0 1) none) "slicing after only the lead byte of a 3-byte character: none")
      (assert (= (stringSliceUtf8 s 0 2) none) "slicing after only 2 of the 3 bytes: none")
      (assert (= (stringSliceUtf8 s 1 3) none) "slicing starting at the first continuation byte: none")
      (assert (= (stringSliceUtf8 s 2 3) none) "slicing starting at the second continuation byte: none")
      (assert (= (stringSliceUtf8 s 0 3) (some s)) "slicing the whole 3-byte character on its own boundaries still works")
      true))

fn ! testMixedAsciiAndMultibyte -> Bool
  (let [(s (str "a" "é" "b"))]
    (do
      (assert (= (stringLength s) 4) "a + 2-byte accented char + b is 4 bytes")
      (assert (= (stringSliceUtf8 s 0 1) (some "a")) "slicing just the leading ASCII byte works")
      (assert (= (stringSliceUtf8 s 3 4) (some "b")) "slicing just the trailing ASCII byte works")
      (assert (= (stringSliceUtf8 s 0 2) none) "slicing into the middle of the embedded multibyte character: none")
      (assert (= (stringSliceUtf8 s 2 4) none) "slicing starting at the embedded character's continuation byte: none")
      (assert (= (stringSliceUtf8 s 1 3) (some "é")) "slicing exactly the embedded multibyte character on its own boundaries works")
      true))

fn ! testAsciiSliceUnaffected -> Bool
  (let [(s "hello")]
    (do
      (assert (= (stringSliceUtf8 s 1 3) (some "el")) "plain ASCII slicing is unaffected by the boundary check")
      (assert (= (stringSliceUtf8 s 0 5) (some s)) "the whole ASCII string still slices")
      (assert (= (stringSliceUtf8 s 5 5) (some "")) "an empty slice at the very end still works")
      true))

fn ! testOutOfRangeStillNone -> Bool
  (let [(s "hi")]
    (do
      (assert (= (stringSliceUtf8 s -1 1) none) "a negative start is still out of range: none")
      (assert (= (stringSliceUtf8 s 0 3) none) "an end past the length is still out of range: none")
      (assert (= (stringSliceUtf8 s 2 1) none) "a backward range is still invalid: none")
      true))

fn ! testRawStringSliceStaysByteBlind -> Bool
  (let [(s "é")]
    (do
      (assert (= (stringSlice s 0 1) (some "\xc3")) "the raw stringSlice builtin is unchanged: it still returns the partial lead byte mid-codepoint")
      (assert (= (stringSlice s 1 2) (some "\xa9")) "the raw stringSlice builtin is unchanged: it still returns the partial continuation byte mid-codepoint")
      true))

fn ! runTests -> Bool
  (do
    (assert (testMidCodepointTwoByte) "a 2-byte character: valid boundaries slice, mid-codepoint boundaries return none")
    (assert (testMidCodepointThreeByte) "a 3-byte character: every mid-codepoint boundary returns none, the whole character slices")
    (assert (testMixedAsciiAndMultibyte) "ASCII bytes around an embedded multibyte character slice individually; slicing into the multibyte character returns none")
    (assert (testAsciiSliceUnaffected) "pure ASCII slicing is unaffected by the boundary check")
    (assert (testOutOfRangeStillNone) "out-of-range and backward slices still return none as before")
    (assert (testRawStringSliceStaysByteBlind) "the shared stringSlice builtin keeps its byte-blind behaviour; only stringSliceUtf8 adds the boundary check")
    true)
