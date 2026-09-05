(module asl-codegen/tests/c-codegen-test
  :d "Unit tests for Embedded C and Arduino code generator."
  :x [test-c-header test-c-type test-gpio-calls test-arduino-sketch run-tests]
  :i [(emit-c :a c)])

(df test-c-header [] -> Bool
  :d "Verifies standard C header generation."
  (let [(hdr (c/emit-c-header))]
    (string-contains? hdr "<stdint.h>")))

(df test-c-type [] -> Bool
  :d "Verifies type mapping to embedded primitives."
  (and (= (c/emit-c-type "I64") "int32_t")
       (and (= (c/emit-c-type "Bool") "bool")
            (= (c/emit-c-type "Unit") "void"))))

(df test-gpio-calls [] -> Bool
  :d "Verifies GPIO calls format into standard Arduino instructions."
  (let [(pm (c/format-gpio-call "pin-mode" 13 1))
        (dw (c/format-gpio-call "digital-write" 13 1))
        (dl (c/format-delay-call 1000))]
    (and (string-contains? pm "pinMode(13, OUTPUT);")
         (and (string-contains? dw "digitalWrite(13, HIGH);")
              (string-contains? dl "delay(1000);")))))

(df test-arduino-sketch [] -> Bool
  :d "Verifies complete Arduino sketch emission."
  (let [(setup-code (c/format-gpio-call "pin-mode" 13 1))
        (loop-code (str (c/format-gpio-call "digital-write" 13 1)
                        (c/format-delay-call 500)))
        (sketch (c/emit-arduino-sketch setup-code loop-code))]
    (and (string-contains? sketch "#include <Arduino.h>")
         (and (string-contains? sketch "void setup()")
              (string-contains? sketch "void loop()")))))

(df run-tests [] -> Bool
  :d "Runs all C codegen unit tests."
  (and (test-c-header)
       (and (test-c-type)
            (and (test-gpio-calls)
                 (test-arduino-sketch)))))
