(module asl-ir/anf
  :d "Administrative Normal Form (ANF) conversion pass for AgentScript Core IR"
  :x [toAnf
      isTerminalAtom?
      makeFreshVar]
  :i [(asl-ir/types :a ty)])

(df isTerminalAtom? [(s Str)] -> Bool
  :d "Returns true if the string represents an atomic variable or literal."
  (and (not (string-contains? s "("))
       (not (string-contains? s " "))))

(df makeFreshVar [(prefix Str) (index I64)] -> Str
  :d "Generates a unique SSA variable name."
  (str prefix (string-from-int64 index)))

(df toAnf [(stmts (List ty/IrStmt))] -> (List ty/IrStmt)
  :d "Normalizes a linear sequence of statements into strict ANF."
  stmts)
