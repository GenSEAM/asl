(module asl-codegen/tests/c-codegen-test
  :d "Unit tests for Embedded C and Arduino code generator."
  :x [test-c-header test-c-type test-gpio-calls test-arduino-sketch run-tests]
  :i [(emit-c :a c)])

(df test-c-header [] -> Bool
  :d "Verifies standard C header generation."
  (let [(hdr (c/emit-c-header))]
    (assert (string-contains? hdr "<stdint.h>") "hdr must contain <stdint.h>")
    (assert (not (string-contains? hdr "<stdio.h>")) "hdr must not contain <stdio.h>")
    true))

(df test-c-type [] -> Bool
  :d "Verifies type mapping to embedded primitives."
  (do
    (assert (= (c/emit-c-type "I64") "int32_t") "I64 -> int32_t")
    (assert (= (c/emit-c-type "Bool") "bool") "Bool -> bool")
    (assert (= (c/emit-c-type "Unit") "void") "Unit -> void")
    true))

(df test-gpio-calls [] -> Bool
  :d "Verifies GPIO calls format into standard Arduino instructions."
  (let [(pm (c/format-gpio-call "pin-mode" 13 1))
        (dw (c/format-gpio-call "digital-write" 13 1))
        (dl (c/format-delay-call 1000))]
    (assert (string-contains? pm "pinMode(13, OUTPUT);") "pm pinMode")
    (assert (string-contains? dw "digitalWrite(13, HIGH);") "dw digitalWrite")
    (assert (string-contains? dl "delay(1000);") "dl delay")
    true))

(df test-arduino-sketch [] -> Bool
  :d "Verifies complete Arduino sketch emission."
  (let [(setup-code (c/format-gpio-call "pin-mode" 13 1))
        (loop-code (str (c/format-gpio-call "digital-write" 13 1)
                        (c/format-delay-call 500)))
        (sketch (c/emit-arduino-sketch setup-code loop-code))]
    (assert (string-contains? sketch "#include <Arduino.h>") "sketch Arduino.h")
    (assert (string-contains? sketch "void setup()") "sketch setup")
    (assert (string-contains? sketch "void loop()") "sketch loop")
    true))

(df run-tests [] -> Bool
  :d "Runs all C codegen unit tests."
  (do
    (assert (test-c-header) "test-c-header must pass")
    (assert (test-c-type) "test-c-type must pass")
    (assert (test-gpio-calls) "test-gpio-calls must pass")
    (assert (test-arduino-sketch) "test-arduino-sketch must pass")
    true))
