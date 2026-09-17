(module asl-target-c
  :d "Standalone C11 backend consuming verified asl-ir with Address/Undefined Sanitizers"
  :x [emitC11Module
      emitC11Type
      emitC11Block
      emitC11Closure
      emitC11Panic
      emitC11StandaloneCase
      emitC11Source]
  :i [(asl-ir/types :a irTy)
      (asl-target-c/types :a ty)
      (asl-target-c/emit :a em)])

(df emitC11Type [(t irTy/IrType)] -> Str
  :d "Maps an IrType node to its corresponding C11 type signature."
  (ty/emitC11Type t))

(df emitC11Closure [(name Str) (envFields (List Str))] -> Str
  :d "Synthesizes a C11 closure environment struct definition."
  (ty/emitC11Closure name envFields))

(df emitC11Panic [(code Int64) (msg Str)] -> Str
  :d "Emits a C11 panic invocation terminating execution with fixed exit code."
  (ty/emitC11Panic code msg))

(df emitC11Block [(stmts (List irTy/IrStmt))] -> Str
  :d "Emits a block of C11 statements."
  (em/emitC11Block stmts))

(df emitC11Module [(m irTy/IrModule)] -> (Result Str (List irTy/IrDiag))
  :d "Emits verified C11 source file from IrModule or returns typed diagnostics if unverified."
  (em/emitC11Module m))

(df emitC11StandaloneCase [(caseId Str)] -> Str
  :d "Emits compliant C11 source code for a conformance test case."
  (em/emitC11StandaloneCase caseId))

(df emitC11Source [(src Str) (path Str)] -> (Result Str Str)
  :d "Parses and compiles a source string to standalone C11."
  (em/emitC11Source src path))
