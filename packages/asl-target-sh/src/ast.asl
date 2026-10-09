(module asl-target-sh/ast
  :x [ShScript
      ShFunction
      ShRedirect
      ShStmt
      ShExpr
      makeShScript
      makeShFunction
      makeShRedirect
      makeShAssign
      makeShIf
      makeShCall
      makeShReturn
      makeShExit
      makeShLitStr
      makeShLitInt
      makeShVar
      makeShTestExpr
      makeShBinOp]
  :i [])

(schema ShScript
  (:f shebang String)
  (:f comments (List String))
  (:f functions (List ShFunction))
  (:f body (List ShStmt)))

(schema ShFunction
  (:f name String)
  (:f body (List ShStmt)))

(schema ShRedirect
  (:f fd (Option Int64))
  (:f op String)
  (:f target String))

(schema ShStmt
  (:f tag String)
  (:f name String)
  (:f isLocal Bool)
  (:f isExport Bool)
  (:f expr ShExpr)
  (:f thenStmts (List ShStmt))
  (:f elseStmts (List ShStmt))
  (:f args (List ShExpr))
  (:f redirects (List ShRedirect)))

(schema ShExpr
  (:f tag String)
  (:f strVal String)
  (:f intVal Int64)
  (:f quoteKind String)
  (:f left (Option ShExpr))
  (:f right (Option ShExpr))
  (:f op String))

fn makeShScript shebang: String comments: (List String) functions: (List ShFunction) body: (List ShStmt) -> ShScript
  (ShScript
    :shebang (if (= shebang "") "#!/bin/sh" shebang)
    :comments comments
    :functions functions
    :body body)

fn makeShFunction name: String body: (List ShStmt) -> ShFunction
  (ShFunction :name name :body body)

fn makeShRedirect fd: (Option Int64) op: String target: String -> ShRedirect
  (ShRedirect :fd fd :op op :target target)

fn makeEmptyExpr -> ShExpr
  (ShExpr :tag "none" :strVal "" :intVal 0 :quoteKind "none" :left none :right none :op "")

fn makeShAssign name: String value: ShExpr isLocal: Bool isExport: Bool -> ShStmt
  (ShStmt
    :tag "assign"
    :name name
    :isLocal isLocal
    :isExport isExport
    :expr value
    :thenStmts (list)
    :elseStmts (list)
    :args (list)
    :redirects (list))

fn makeShIf test: ShExpr thenStmts: (List ShStmt) elseStmts: (List ShStmt) -> ShStmt
  (ShStmt
    :tag "if"
    :name ""
    :isLocal false
    :isExport false
    :expr test
    :thenStmts thenStmts
    :elseStmts elseStmts
    :args (list)
    :redirects (list))

fn makeShCall cmd: String args: (List ShExpr) redirects: (List ShRedirect) -> ShStmt
  (ShStmt
    :tag "call"
    :name cmd
    :isLocal false
    :isExport false
    :expr (makeEmptyExpr)
    :thenStmts (list)
    :elseStmts (list)
    :args args
    :redirects redirects)

fn makeShReturn code: ShExpr -> ShStmt
  (ShStmt
    :tag "return"
    :name ""
    :isLocal false
    :isExport false
    :expr code
    :thenStmts (list)
    :elseStmts (list)
    :args (list)
    :redirects (list))

fn makeShExit code: ShExpr -> ShStmt
  (ShStmt
    :tag "exit"
    :name ""
    :isLocal false
    :isExport false
    :expr code
    :thenStmts (list)
    :elseStmts (list)
    :args (list)
    :redirects (list))

fn makeShLitStr val: String -> ShExpr
  (ShExpr :tag "litStr" :strVal val :intVal 0 :quoteKind "single" :left none :right none :op "")

fn makeShLitInt val: Int64 -> ShExpr
  (ShExpr :tag "litInt" :strVal (stringFromInt64 val) :intVal val :quoteKind "raw" :left none :right none :op "")

fn makeShVar name: String -> ShExpr
  (ShExpr :tag "var" :strVal name :intVal 0 :quoteKind "double" :left none :right none :op "")

fn makeShTestExpr op: String left: ShExpr right: ShExpr -> ShExpr
  (ShExpr :tag "test" :strVal "" :intVal 0 :quoteKind "raw" :left (some left) :right (some right) :op op)

fn makeShBinOp op: String left: ShExpr right: ShExpr -> ShExpr
  (ShExpr :tag "binOp" :strVal "" :intVal 0 :quoteKind "raw" :left (some left) :right (some right) :op op)
