(module asl-utils/tests/checksumsTest :x [runTests] :i [(asl-utils/checksums :a ck)])

fn bs s: String -> Bytes
  (stringToBytes s)

fn testAdler -> Bool
  (do (assert (= (ck/adler32 (bs "")) 1) "adler32 empty is 1")
      (assert (= (ck/adler32 (bs "a")) 6422626) "adler32 a")
      (assert (= (ck/adler32 (bs "abc")) 38600999) "adler32 abc")
      (assert (= (ck/adler32 (bs "123456789")) 152961502) "adler32 check vector 123456789")
      (assert (= (ck/adler32 (bs "Wikipedia")) 300286872) "adler32 Wikipedia")
      (assert (= (ck/adler32 (bs "The quick brown fox jumps over the lazy dog")) 1541148634) "adler32 fox")
      true)

fn testFnv32 -> Bool
  (do (assert (= (ck/fnv1a32 (bs "")) 2166136261) "fnv1a32 empty is offset basis")
      (assert (= (ck/fnv1a32 (bs "a")) 3826002220) "fnv1a32 a")
      (assert (= (ck/fnv1a32 (bs "foobar")) 3214735720) "fnv1a32 foobar")
      (assert (= (ck/fnv1a32 (bs "hello")) 1335831723) "fnv1a32 hello")
      (assert (= (ck/fnv1a32 (bs "123456789")) 3146166556) "fnv1a32 123456789")
      (assert (= (ck/fnv1a32 (bs "The quick brown fox jumps over the lazy dog")) 76545936) "fnv1a32 fox")
      true)

fn testFnv64 -> Bool
  (do (assert (= (ck/fnv1a64 (bs "")) -3750763034362895579) "fnv1a64 empty is offset basis")
      (assert (= (ck/fnv1a64 (bs "a")) -5808556873153909620) "fnv1a64 a")
      (assert (= (ck/fnv1a64 (bs "foobar")) -8821353812377114648) "fnv1a64 foobar")
      (assert (= (ck/fnv1a64 (bs "hello")) -6615550055289275125) "fnv1a64 hello")
      (assert (= (ck/fnv1a64 (bs "123456789")) 492395637191921148) "fnv1a64 123456789")
      (assert (= (ck/fnv1a64 (bs "The quick brown fox jumps over the lazy dog")) -866459186506731248) "fnv1a64 fox")
      true)

fn testCrc -> Bool
  (do (assert (= (ck/crc32 (bs "")) 0) "crc32 empty is 0")
      (assert (= (ck/crc32 (bs "a")) 3904355907) "crc32 a")
      (assert (= (ck/crc32 (bs "123456789")) 3421780262) "crc32 check vector 123456789 is 0xCBF43926")
      (assert (= (ck/crc32 (bs "Wikipedia")) 2913648686) "crc32 Wikipedia")
      (assert (= (ck/crc32 (bs "The quick brown fox jumps over the lazy dog")) 1095738169) "crc32 fox is 0x414FA339")
      true)

fn runTests -> Bool
  (and (testAdler) (testFnv32) (testFnv64) (testCrc))
