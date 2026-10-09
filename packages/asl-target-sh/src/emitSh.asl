(module asl-target-sh/emitSh
  :x [formatShScript
      formatShStmt
      formatShExpr
      formatRedirect
      formatTestExpr
      escapeDoubleQuotes
      escapeSingleQuotes
      mangleIdent]
  :i [(asl-target-sh/ast :a ast)])

fn escapeSingleQuotes s: String -> String
  (stringReplace s "'" "'\\''")

fn escapeDoubleQuotes s: String -> String
  (let [(s1 (stringReplace s "\\" "\\\\"))
        (s2 (stringReplace s1 "\"" "\\\""))
        (s3 (stringReplace s2 "$" "\\$"))]
    (stringReplace s3 "`" "\\`"))

fn isReservedWord name: String -> Bool
  (or (or (or (= name "echo") (= name "read")) (or (= name "test") (= name "local")))
      (or (or (= name "set") (= name "path")) (or (= name "IFS") (= name "export"))))

fn mangleIdent name: String -> String
  (let [(cleaned (stringReplace name "-" "_"))]
    (if (isReservedWord cleaned)
      (str "sh_" cleaned)
      cleaned))

fn makeIndent level: Int64 -> String
  (cond
    ((<= level 0) "")
    ((= level 1) "    ")
    ((= level 2) "        ")
    ((= level 3) "            ")
    (else "                "))

fn formatRedirect red: ast/ShRedirect -> String
  (let [(fdStr (mt red.fd ((some f) (stringFromInt64 f)) ((none) "")))]
    (str " " fdStr red.op " " red.target))

fn formatTestExpr expr: ast/ShExpr -> String
  (let [(op expr.op)
        (lOpt expr.left)
        (rOpt expr.right)]
    (let [(leftStr (mt lOpt ((some l) (formatShExpr l)) ((none) "")))
          (rightStr (mt rOpt ((some r) (formatShExpr r)) ((none) "")))]
      (cond
        ((= op "-n") (str "[ -n " leftStr " ]"))
        ((= op "-z") (str "[ -z " leftStr " ]"))
        ((= op "-f") (str "[ -f " leftStr " ]"))
        ((= op "-d") (str "[ -d " leftStr " ]"))
        ((= op "=") (str "[ " leftStr " = " rightStr " ]"))
        ((= op "!=") (str "[ " leftStr " != " rightStr " ]"))
        ((= op "-eq") (str "[ " leftStr " -eq " rightStr " ]"))
        ((= op "-ne") (str "[ " leftStr " -ne " rightStr " ]"))
        (else (str "[ " leftStr " " op " " rightStr " ]")))))

fn formatShExpr expr: ast/ShExpr -> String
  (let [(tag expr.tag)]
    (cond
      ((= tag "litStr")
        (let [(kind expr.quoteKind)
              (rawVal expr.strVal)]
          (if (= kind "single")
            (str "'" (escapeSingleQuotes rawVal) "'")
            (if (= kind "double")
              (str "\"" (escapeDoubleQuotes rawVal) "\"")
              rawVal))))
      ((= tag "litInt")
        (stringFromInt64 expr.intVal))
      ((= tag "var")
        (let [(vName (mangleIdent expr.strVal))]
          (str "\"${" vName ":-}\"")))
      ((= tag "test")
        (formatTestExpr expr))
      ((= tag "binOp")
        (let [(lOpt expr.left)
              (rOpt expr.right)]
          (let [(l (mt lOpt ((some x) (formatShExpr x)) ((none) "")))
                (r (mt rOpt ((some y) (formatShExpr y)) ((none) "")))]
            (str l " " expr.op " " r))))
      (else "")))

fn formatShStmt stmt: ast/ShStmt indent: Int64 -> String
  (let [(ind (makeIndent indent))
        (tag stmt.tag)]
    (cond
      ((= tag "assign")
        (let [(prefix (if stmt.isLocal "local " (if stmt.isExport "export " "")))
              (vName (mangleIdent stmt.name))
              (valStr (formatShExpr stmt.expr))]
          (str ind prefix vName "=" valStr "\n")))
      ((= tag "if")
        (let [(testStr (formatShExpr stmt.expr))
              (thenCode (stringJoin (map (fn [(s ast/ShStmt)] -> String (formatShStmt s (+ indent 1))) stmt.thenStmts) ""))
              (elseList stmt.elseStmts)]
          (if (listEmpty? elseList)
            (str ind "if " testStr "; then\n" thenCode ind "fi\n")
            (let [(elseCode (stringJoin (map (fn [(s ast/ShStmt)] -> String (formatShStmt s (+ indent 1))) elseList) ""))]
              (str ind "if " testStr "; then\n" thenCode ind "else\n" elseCode ind "fi\n")))))
      ((= tag "call")
        (let [(cmdName (mangleIdent stmt.name))
              (argStrs (map (fn [(a ast/ShExpr)] -> String (formatShExpr a)) stmt.args))
              (argsJoined (if (listEmpty? argStrs) "" (str " " (stringJoin argStrs " "))))
              (redStrs (map (fn [(r ast/ShRedirect)] -> String (formatRedirect r)) stmt.redirects))
              (redsJoined (stringJoin redStrs ""))]
          (str ind cmdName argsJoined redsJoined "\n")))
      ((= tag "return")
        (let [(codeStr (formatShExpr stmt.expr))]
          (str ind "return " codeStr "\n")))
      ((= tag "exit")
        (let [(codeStr (formatShExpr stmt.expr))]
          (str ind "exit " codeStr "\n")))
      (else "")))

fn formatShFunction fnDef: ast/ShFunction -> String
  (let [(name (mangleIdent fnDef.name))
        (bodyStrs (map (fn [(s ast/ShStmt)] -> String (formatShStmt s 1)) fnDef.body))
        (bodyJoined (if (listEmpty? bodyStrs) "    :\n" (stringJoin bodyStrs "")))]
    (str name "() {\n" bodyJoined "}\n\n"))

fn formatShScript script: ast/ShScript -> String
  (let [(shebang script.shebang)
        (headerComments (map (fn [(c String)] -> String (str "# " c "\n")) script.comments))
        (commentsJoined (stringJoin headerComments ""))
        (fnStrs (map (fn [(f ast/ShFunction)] -> String (formatShFunction f)) script.functions))
        (fnsJoined (stringJoin fnStrs ""))
        (bodyStrs (map (fn [(s ast/ShStmt)] -> String (formatShStmt s 0)) script.body))
        (bodyJoined (stringJoin bodyStrs ""))]
    (str
      shebang "\n"
      "set -eu\n\n"
      commentsJoined
      (if (= commentsJoined "") "" "\n")
      fnsJoined
      bodyJoined))
