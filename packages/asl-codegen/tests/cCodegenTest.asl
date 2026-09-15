(module asl-codegen/tests/cCodegenTest
  :d "Unit tests for Embedded C and Arduino code generator."
  :x [testCHeader testCType testGpioCalls testArduinoSketch runTests]
  :i [(emitC :a c)])

(df testCHeader [] -> Bool
  :d "Verifies standard C header generation."
  (let [(hdr (c/emitCHeader))]
    (assert (string-contains? hdr "<stdint.h>") "hdr must contain <stdint.h>")
    (assert (not (string-contains? hdr "<stdio.h>")) "hdr must not contain <stdio.h>")
    true))

(df testCType [] -> Bool
  :d "Verifies type mapping to embedded primitives."
  (do
    (assert (= (c/emitCType "I64") "int32_t") "I64 -> int32_t")
    (assert (= (c/emitCType "Bool") "bool") "Bool -> bool")
    (assert (= (c/emitCType "Unit") "void") "Unit -> void")
    true))

(df testGpioCalls [] -> Bool
  :d "Verifies GPIO calls format into standard Arduino instructions."
  (let [(pm (c/formatGpioCall "pin-mode" 13 1))
        (dw (c/formatGpioCall "digital-write" 13 1))
        (dl (c/formatDelayCall 1000))]
    (assert (string-contains? pm "pinMode(13, OUTPUT);") "pm pinMode")
    (assert (string-contains? dw "digitalWrite(13, HIGH);") "dw digitalWrite")
    (assert (string-contains? dl "delay(1000);") "dl delay")
    true))

(df testArduinoSketch [] -> Bool
  :d "Verifies complete Arduino sketch emission."
  (let [(setupCode (c/formatGpioCall "pin-mode" 13 1))
        (loopCode (str (c/formatGpioCall "digital-write" 13 1)
                        (c/formatDelayCall 500)))
        (sketch (c/emitArduinoSketch setupCode loopCode))]
    (assert (string-contains? sketch "#include <Arduino.h>") "sketch Arduino.h")
    (assert (string-contains? sketch "void setup()") "sketch setup")
    (assert (string-contains? sketch "void loop()") "sketch loop")
    true))

(df runTests [] -> Bool
  :d "Runs all C codegen unit tests."
  (do
    (assert (testCHeader) "test-c-header must pass")
    (assert (testCType) "test-c-type must pass")
    (assert (testGpioCalls) "test-gpio-calls must pass")
    (assert (testArduinoSketch) "test-arduino-sketch must pass")
    true))
