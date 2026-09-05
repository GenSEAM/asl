(module asl-codegen/emit-c
  :d "Embedded ANSI C and Arduino Sketch code generator for AgentScript."
  :x [emit-c-header
      emit-arduino-header
      emit-c-type
      emit-c-fn
      emit-arduino-sketch
      format-gpio-call
      format-delay-call]
  :i [])

(df emit-c-header [] -> Str
  :d "Emits standard freestanding C headers."
  "#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n")

(df emit-arduino-header [] -> Str
  :d "Emits standard Arduino platform header."
  "#include <Arduino.h>\n")

(df emit-c-type [(ty Str)] -> Str
  :d "Maps AgentScript type to embedded C/Arduino native type."
  (cond
    ((= ty "I64") "int32_t")
    ((= ty "I32") "int32_t")
    ((= ty "Bool") "bool")
    ((= ty "Str") "const char*")
    ((= ty "F64") "double")
    ((= ty "Unit") "void")
    (:else ty)))

(df emit-c-fn [(name Str) (ret-ty Str) (body Str)] -> Str
  :d "Emits a simple C function definition."
  (str (emit-c-type ret-ty) " " name "(void) {\n" body "\n}\n"))

(df format-gpio-call [(call-kind Str) (pin I64) (state I64)] -> Str
  :d "Formats hardware GPIO call (pinMode or digitalWrite) into Arduino C syntax."
  (cond
    ((= call-kind "pin-mode")
     (let [(mode-str (if (= state 1) "OUTPUT" "INPUT"))]
       (str "  pinMode(" (string-from-int64 pin) ", " mode-str ");\n")))
    ((= call-kind "digital-write")
     (let [(val-str (if (= state 1) "HIGH" "LOW"))]
       (str "  digitalWrite(" (string-from-int64 pin) ", " val-str ");\n")))
    (:else "")))

(df format-delay-call [(ms I64)] -> Str
  :d "Formats millisecond hardware delay."
  (str "  delay(" (string-from-int64 ms) ");\n"))

(df emit-arduino-sketch [(setup-body Str) (loop-body Str)] -> Str
  :d "Generates an Arduino sketch containing setup() and loop() entrypoints."
  (let [(hdr (emit-arduino-header))
        (setup-fn (str "void setup() {\n" setup-body "}\n\n"))
        (loop-fn (str "void loop() {\n" loop-body "}\n"))]
    (str hdr "\n" setup-fn loop-fn)))
