(module asl-target-js
  :x [compileEntry! diagText]
  :i [(asl-ir/types :a ty) (asl-ir/link :a lk) (asl-target-js/emit :a em)])

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code ": " d.message)) ds) "\n")

fn compileEntry! entryPath: String -> (Result String (List ty/IrDiag))
  (mt (lk/linkEntry! entryPath)
    ((err ds) (err ds))
    ((ok m) (em/emitJsModule m)))
