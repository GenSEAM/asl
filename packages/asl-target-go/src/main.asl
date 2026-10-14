(module asl-target-go
  :x [compileEntry! compilePackage! diagText]
  :i [(asl-ir/types :a ty) (asl-ir/link :a lk) (asl-target-go/emit :a em)])

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code ": " d.message)) ds) "\n")

fn compilePackage! pkg: String entryPath: String -> (Result String (List ty/IrDiag))
  (mt (lk/linkEntry! entryPath)
    ((err ds) (err ds))
    ((ok m) (em/emitGoModule pkg m)))

fn compileEntry! entryPath: String -> (Result String (List ty/IrDiag))
  (compilePackage! "main" entryPath)
