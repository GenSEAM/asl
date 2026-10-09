(module asl-target-c :x [emitC11Module emitC11Type emitC11Block emitC11Closure emitC11Panic emitC11StandaloneCase emitC11Source emitC11SourceWith] :i [(asl-ir/types :a irTy) (asl-target-c/types :a ty) (asl-target-c/emit :a em)])

fn emitC11Type t: irTy/IrType -> Str
  (ty/emitC11Type t)

fn emitC11Closure name: Str envFields: (List Str) -> Str
  (ty/emitC11Closure name envFields)

fn emitC11Panic code: Int64 msg: Str -> Str
  (ty/emitC11Panic code msg)

fn emitC11Block stmts: (List irTy/IrStmt) -> Str
  (em/emitC11Block stmts)

fn emitC11Module m: irTy/IrModule -> (Result Str (List irTy/IrDiag))
  (em/emitC11Module m)

fn emitC11StandaloneCase caseId: Str -> Str
  (em/emitC11StandaloneCase caseId)

fn emitC11Source src: Str path: Str -> (Result Str Str)
  (em/emitC11Source src path)

fn emitC11SourceWith src: Str preludeSrc: Str path: Str -> (Result Str Str)
  (em/emitC11SourceWith src preludeSrc path)
