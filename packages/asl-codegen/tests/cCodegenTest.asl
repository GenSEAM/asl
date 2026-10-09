(module asl-codegen/tests/cCodegenTest :x [testCHeader testCType testGpioCalls testArduinoSketch runTests] :i [(emitC :a c)])

fn testCHeader -> Bool
  (let [(hdr (c/emitCHeader))] (assert (stringContains? hdr "<stdint.h>") "hdr must contain <stdint.h>") (assert (not (stringContains? hdr "<stdio.h>")) "hdr must not contain <stdio.h>") true)

fn testCType -> Bool
  (do (assert (= (c/emitCType "I64") "int32_t") "I64 -> int32_t") (assert (= (c/emitCType "Bool") "bool") "Bool -> bool") (assert (= (c/emitCType "Unit") "void") "Unit -> void") true)

fn testGpioCalls -> Bool
  (let [(pm (c/formatGpioCall "pin-mode" 13 1)) (dw (c/formatGpioCall "digital-write" 13 1)) (dl (c/formatDelayCall 1000))] (assert (stringContains? pm "pinMode(13, OUTPUT);") "pm pinMode") (assert (stringContains? dw "digitalWrite(13, HIGH);") "dw digitalWrite") (assert (stringContains? dl "delay(1000);") "dl delay") true)

fn testArduinoSketch -> Bool
  (let [(setupCode (c/formatGpioCall "pin-mode" 13 1)) (loopCode (str (c/formatGpioCall "digital-write" 13 1) (c/formatDelayCall 500))) (sketch (c/emitArduinoSketch setupCode loopCode))] (assert (stringContains? sketch "#include <Arduino.h>") "sketch Arduino.h") (assert (stringContains? sketch "void setup()") "sketch setup") (assert (stringContains? sketch "void loop()") "sketch loop") true)

fn runTests -> Bool
  (do (assert (testCHeader) "test-c-header must pass") (assert (testCType) "test-c-type must pass") (assert (testGpioCalls) "test-gpio-calls must pass") (assert (testArduinoSketch) "test-arduino-sketch must pass") true)
