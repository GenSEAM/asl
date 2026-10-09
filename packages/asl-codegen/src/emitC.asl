(module asl-codegen/emitC :x [emitCHeader emitArduinoHeader emitCType emitCFn emitArduinoSketch formatGpioCall formatDelayCall emitCStandalone emitCHeaderFile emitCSourceFile c99TypeStr] :i [(ast :a a) (c99Emit :a ce) (c99Type :a ct)])

fn emitCHeader -> Str
  "#include <stdint.h>\n#include <stdbool.h>\n#include <stddef.h>\n"

fn emitArduinoHeader -> Str
  "#include <Arduino.h>\n"

fn emitCType ty: Str -> Str
  (cond ((= ty "I64") "int32_t") ((= ty "I32") "int32_t") ((= ty "Bool") "bool") ((= ty "Str") "const char*") ((= ty "F64") "double") ((= ty "Unit") "void") (else ty))

fn emitCFn name: Str retTy: Str body: Str -> Str
  (str (emitCType retTy) " " name "(void) {\n" body "\n}\n")

fn formatGpioCall callKind: Str pin: I64 state: I64 -> Str
  (cond ((= callKind "pin-mode") (let [(modeStr (if (= state 1) "OUTPUT" "INPUT"))] (str "  pinMode(" (stringFromInt64 pin) ", " modeStr ");\n"))) ((= callKind "digital-write") (let [(valStr (if (= state 1) "HIGH" "LOW"))] (str "  digitalWrite(" (stringFromInt64 pin) ", " valStr ");\n"))) (else ""))

fn formatDelayCall ms: I64 -> Str
  (str "  delay(" (stringFromInt64 ms) ");\n")

fn emitArduinoSketch setupBody: Str loopBody: Str -> Str
  (let [(hdr (emitArduinoHeader)) (setupFn (str "void setup() {\n" setupBody "}\n\n")) (loopFn (str "void loop() {\n" loopBody "}\n"))] (str hdr "\n" setupFn loopFn))

fn emitCStandalone forms: (List a/TopForm) entryFn: Str isFreestanding: Bool -> Str
  (ce/emitCStandalone forms entryFn isFreestanding)

fn emitCHeaderFile mod: a/ModuleNode -> Str
  (ce/emitCHeaderFile mod)

fn emitCSourceFile mod: a/ModuleNode -> Str
  (ce/emitCSourceFile mod)

fn c99TypeStr ty: Str -> Str
  (ct/c99TypeStr ty)
