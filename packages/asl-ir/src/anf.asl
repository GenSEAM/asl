(module asl-ir/anf :x [toAnf isTerminalAtom? makeFreshVar] :i [(asl-ir/types :a ty)])

fn isTerminalAtom? s: Str -> Bool
  (and (not (stringContains? s "(")) (not (stringContains? s " ")))

fn makeFreshVar prefix: Str index: I64 -> Str
  (str prefix (stringFromInt64 index))

fn toAnf stmts: (List ty/IrStmt) -> (List ty/IrStmt)
  stmts
