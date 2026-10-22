(module asl-target-js
  :x [compileEntry! compileWithTypes! diagText]
  :i [(asl-ir/types :a ty) (asl-ir/link :a lk) (asl-target-js/emit :a em) (asl-target-js/dts :a dts)])

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code ": " d.message)) ds) "\n")

fn compileEntry! entryPath: String -> (Result String (List ty/IrDiag))
  (match (lk/linkEntry! entryPath)
    ((err ds) (err ds))
    ((ok m) (em/emitJsModule m)))

fn compileWithTypes! entryPath: String -> (Result (Pair String String) (List ty/IrDiag))
  (match (compileEntry! entryPath)
    ((err ds) (err ds))
    ((ok js)
      (match (fileReadString entryPath)
        ((err e) (err [(ty/makeIrDiag "ERR_LINK_READ" (str "cannot read " entryPath) entryPath)]))
        ((ok src) (match (dts/emitDts src) ((ok types) (ok (pair js types))) ((err e) (err [(ty/makeIrDiag "ERR_DTS" e entryPath)])))))))
