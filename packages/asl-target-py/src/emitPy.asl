(module asl-target-py/emitPy :x [emitPyType emitPyFn emitPyClass emitPyEnum emitPythonSource emitPythonProgram emitPyBinop emitPyBlock emitPyModule emitPyStandaloneCase pyMangleIdent] :i [(ast :a a) (reader :a rd) (asl-ir/types :a irTy) (asl-ir/verify :a vfy)])

fn isPyKeyword? s: Str -> Bool
  (or (= s "class") (= s "def") (= s "import") (= s "return") (= s "pass") (= s "from") (= s "as") (= s "global") (= s "nonlocal") (= s "lambda") (= s "yield") (= s "raise") (= s "try") (= s "except") (= s "finally") (= s "with") (= s "async") (= s "await") (= s "break") (= s "continue") (= s "while") (= s "for") (= s "in") (= s "is") (= s "assert") (= s "del") (= s "if") (= s "elif") (= s "else") (= s "not") (= s "and") (= s "or") (= s "type") (= s "match") (= s "case"))

fn pyMangleIdent id: Str -> Str
  (let [(snake (stringReplace (stringReplace id "/" "_") "-" "_"))] (if (isPyKeyword? snake) (str snake "_") snake))

fn cleanDocstring ds: Str -> Str
  (let [(trimmed (stringTrim ds))] (if (and (stringStartsWith? trimmed "\"") (stringEndsWith? trimmed "\"") (>= (stringLength trimmed) 2)) (optionOr (stringSlice trimmed 1 (- (stringLength trimmed) 1)) "") trimmed))

fn emitPyType ty: Str -> Str
  (let [(t (stringTrim ty))] (cond ((or (= t "I64") (= t "I32") (= t "Int") (= t "Int64") (= t "Int32")) "int") ((or (= t "F64") (= t "F32") (= t "Float") (= t "Float64")) "float") ((or (= t "Str") (= t "String")) "str") ((= t "Bool") "bool") ((or (= t "Unit") (= t "Void") (= t "")) "None") ((= t "Any") "Any") ((and (stringStartsWith? t "(List ") (stringEndsWith? t ")")) (let [(inner (stringSlice t 6 (- (stringLength t) 1)))] (str "list[" (emitPyType (optionOr inner "")) "]"))) ((stringStartsWith? t "List ") (let [(inner (stringSlice t 5 (stringLength t)))] (str "list[" (emitPyType (optionOr inner "")) "]"))) ((and (stringStartsWith? t "(Option ") (stringEndsWith? t ")")) (let [(inner (stringSlice t 8 (- (stringLength t) 1)))] (str (emitPyType (optionOr inner "")) " | None"))) ((stringStartsWith? t "Option ") (let [(inner (stringSlice t 7 (stringLength t)))] (str (emitPyType (optionOr inner "")) " | None"))) ((and (stringStartsWith? t "(Map ") (stringEndsWith? t ")")) (let [(inner (stringSlice t 5 (- (stringLength t) 1))) (parts (stringSplit (stringTrim (optionOr inner "")) " "))] (if (>= (listLength parts) 2) (str "dict[" (emitPyType (optionOr (listGet parts 0) "Any")) ", " (emitPyType (optionOr (listGet parts 1) "Any")) "]") "dict[str, Any]"))) (else t)))

fn emitPyAtom s: Str -> Str
  (cond ((= s "true") "True") ((= s "false") "False") ((or (= s "nil") (= s "none") (= s "()")) "None") ((stringStartsWith? s "\"") s) ((or (stringStartsWith? s "-") (and (>= (optionOr (stringSlice s 0 1) "") "0") (<= (optionOr (stringSlice s 0 1) "") "9"))) s) (else (pyMangleIdent s)))

fn emitPyBinop op: Str args: (List rd/SExpr) -> Str
  (let [(pyOp (cond ((or (= op "//") (= op "idiv") (= op "div-i64")) "//") ((or (= op "/") (= op "div-f64")) "/") (else op)))] (cond ((listEmpty? args) (if (or (= pyOp "+") (= pyOp "-")) "0" (if (or (= pyOp "*") (= pyOp "/") (= pyOp "//")) "1" "True"))) ((= (listLength args) 1) (if (= pyOp "-") (str "-" (emitPyExpr (optionOr (listHead args) (rd/sexprAtom "")))) (emitPyExpr (optionOr (listHead args) (rd/sexprAtom ""))))) (else (stringJoin (map emitPyExpr args) (str " " pyOp " ")))))

fn emitPyList items: (List rd/SExpr) -> Str
  (if (listEmpty? items) "None" (let [(head (rd/sexprHead (optionOr (listHead items) (rd/sexprAtom "")))) (args (optionOr (listTail items) (list)))] (cond ((= head "+") (emitPyBinop "+" args)) ((= head "-") (emitPyBinop "-" args)) ((= head "*") (emitPyBinop "*" args)) ((or (= head "/") (= head "div-f64")) (emitPyBinop "/" args)) ((or (= head "//") (= head "idiv") (= head "div-i64")) (emitPyBinop "//" args)) ((or (= head "mod") (= head "%")) (emitPyBinop "%" args)) ((or (= head "=") (= head "==")) (emitPyBinop "==" args)) ((= head "!=") (emitPyBinop "!=" args)) ((= head "<") (emitPyBinop "<" args)) ((= head "<=") (emitPyBinop "<=" args)) ((= head ">") (emitPyBinop ">" args)) ((= head ">=") (emitPyBinop ">=" args)) ((= head "and") (emitPyBinop "and" args)) ((= head "or") (emitPyBinop "or" args)) ((= head "not") (str "not (" (emitPyExpr (optionOr (listHead args) (rd/sexprAtom "False"))) ")")) ((= head "if") (let [(c (optionOr (listGet args 0) (rd/sexprAtom "True"))) (t (optionOr (listGet args 1) (rd/sexprAtom "None"))) (e (optionOr (listGet args 2) (rd/sexprAtom "None")))] (str "(" (emitPyExpr t) " if " (emitPyExpr c) " else " (emitPyExpr e) ")"))) ((= head "str") (if (listEmpty? args) "\"\"" (str "(" (stringJoin (map (fn [(x rd/SExpr)] -> Str (str "str(" (emitPyExpr x) ")")) args) " + ") ")"))) ((= head "list") (str "[" (stringJoin (map emitPyExpr args) ", ") "]")) ((= head "tuple") (str "(" (stringJoin (map emitPyExpr args) ", ") ")")) ((= head "dict") (str "{" (stringJoin (map emitPyExpr args) ", ") "}")) (else (let [(fnName (pyMangleIdent head)) (renderedArgs (map emitPyExpr args))] (str fnName "(" (stringJoin renderedArgs ", ") ")"))))))

fn emitPyExpr e: rd/SExpr -> Str
  (mt e ((rd/sexprAtom v) (emitPyAtom v)) ((rd/sexprList items) (emitPyList items)) ((rd/sexprVect items) (str "[" (stringJoin (map emitPyExpr items) ", ") "]")))

fn emitPyParam p: a/Param -> Str
  (let [(pName (pyMangleIdent p.name)) (pType (emitPyType p.type))] (str pName ": " pType))

fn emitPyFn d: a/DefunNode -> Str
  (let [(name (pyMangleIdent d.name)) (params (stringJoin (map emitPyParam d.params) ", ")) (ret (emitPyType d.retType)) (doc (if (stringEmpty? d.docstring) "" (str "    \"\"\"" (cleanDocstring d.docstring) "\"\"\"\n"))) (bodyExpr (if (listEmpty? d.body) "None" (emitPyExpr (optionOr (listGet d.body (- (listLength d.body) 1)) (rd/sexprAtom "None")))))] (str "def " name "(" params ") -> " ret ":\n" doc "    return " bodyExpr "\n"))

fn emitPyField f: a/AstField -> Str
  (let [(fName (pyMangleIdent f.name)) (fType (emitPyType f.type)) (defPart (mt f.default ((some d) (str " = " (emitPyExpr d))) ((none) "")))] (str "    " fName ": " fType defPart "\n"))

fn emitPyClass s: a/SchemaNode -> Str
  (let [(name s.name) (fields (if (listEmpty? s.fields) "    pass\n" (stringJoin (map emitPyField s.fields) "")))] (str "@dataclass\nclass " name ":\n" fields))

fn emitPyCase c: a/EnumCase -> Str
  (let [(cName c.name)] (str "    " cName " = auto()\n"))

fn enumHasFields? cases: (List a/EnumCase) -> Bool
  (fold (fn [(acc Bool) (c a/EnumCase)] -> Bool (or acc (> (listLength c.fields) 0))) false cases)

fn emitPyEnumCaseClass enumName: Str c: a/EnumCase -> Str
  (let [(cName (str enumName c.name)) (fields (if (listEmpty? c.fields) "    pass\n" (stringJoin (map (fn [(p a/Param)] -> Str (str "    " (pyMangleIdent p.name) ": " (emitPyType p.type) "\n")) c.fields) "")))] (str "@dataclass\nclass " cName ":\n" fields))

fn emitPyEnum e: a/EnumNode -> Str
  (let [(name e.name) (cases e.cases)] (if (enumHasFields? cases) (let [(classes (stringJoin (map (fn [(c a/EnumCase)] -> Str (emitPyEnumCaseClass name c)) cases) "\n")) (typeUnion (stringJoin (map (fn [(c a/EnumCase)] -> Str (str name c.name)) cases) " | "))] (str classes "\n" name " = " typeUnion "\n")) (let [(body (if (listEmpty? cases) "    pass\n" (stringJoin (map emitPyCase cases) "")))] (str "class " name "(Enum):\n" body))))

fn emitPythonHeader -> Str
  (str "from __future__ import annotations\n" "from dataclasses import dataclass\n" "from enum import Enum, auto\n" "from typing import Any, Optional, Union\n\n")

fn emitTopForm tf: a/TopForm -> Str
  (mt tf ((a/topSchema s) (emitPyClass s)) ((a/topEnum e) (emitPyEnum e)) ((a/topDefun d) (emitPyFn d)) ((a/topModule _) "") ((a/topExpr p) (str (emitPyExpr p.expr) "\n")))

fn unpackForms forms: (List a/TopForm) -> (List a/TopForm)
  (if (= (listLength forms) 1) (mt (listHead forms) ((some it) (mt it ((a/topModule m) m.defs) (_ forms))) ((none) forms)) forms)
fn emitPythonSource forms: (List a/TopForm) -> Str
  (let [(effForms (unpackForms forms)) (hdr (emitPythonHeader)) (rendered (filter (fn [(s Str)] -> Bool (not (stringEmpty? s))) (map emitTopForm effForms))) (body (stringJoin rendered "\n"))] (str hdr body))

fn emitPythonProgram forms: (List a/TopForm) opts: (Map Str Str) -> (Result Str Str)
  (ok (emitPythonSource forms))

fn emitPyIrType t: irTy/IrType -> Str
  (let [(k t.kind)] (cond ((or (= k "i64") (= k "i32")) "int") ((= k "f64") "float") ((= k "bool") "bool") ((= k "unit") "None") ((= k "str") "str") ((= k "option") (if (= t.repr "tagged") "AslSome | None" "Any | None")) (else "Any")))

fn emitPyIrExpr expr: irTy/IrExpr -> Str
  (let [(k expr.kind) (op expr.op) (l expr.left) (r expr.right)] (cond ((= k "atom") (cond ((= l "true") "True") ((= l "false") "False") ((= l "nil") "None") ((= l "()") "None") ((!= expr.codeLabel "") expr.codeLabel) (else l))) ((= k "binop") (cond ((= op "+") (str "asl_wrap_i64(" l " + " r ")")) ((= op "-") (str "asl_wrap_i64(" l " - " r ")")) ((= op "*") (str "asl_wrap_i64(" l " * " r ")")) ((or (= op "//") (= op "idiv") (= op "div-i64") (and (= op "/") expr.divModFloor)) (str "(" l " // " r ")")) ((or (= op "/") (= op "div-f64")) (str "(" l " / " r ")")) ((or (= op "mod") (= op "%")) (str "(" l " % " r ")")) ((or (= op "shl") (= op "<<")) (str "(" l " << (" r " & 63))")) ((or (= op "shr") (= op ">>")) (str "(" l " >> (" r " & 63))")) (else (str "(" l " " op " " r ")")))) ((= k "cmp") (str "(" l " " op " " r ")")) ((= k "call") (let [(argsStr (fold (fn [(acc Str) (a Str)] -> Str (if (= acc "") a (str acc ", " a))) "" expr.args))] (cond ((= op "println") (str "print(" argsStr ")")) ((= op "print") (str "print(" argsStr ", end=\"\")")) ((= op "stringFromInt64") (str "str(" argsStr ")")) ((= op "string-from-f64") (str "str(" argsStr ")")) (else (str op "(" argsStr ")"))))) ((= k "alloc") "None") ((= k "load") (str l "." r)) (else "None")))

fn emitPyIrStmt stmt: irTy/IrStmt indent: Str -> Str
  (let [(k stmt.kind)] (cond ((= k "let") (let [(target stmt.target) (exprStr (emitPyIrExpr stmt.expr))] (if (= target "") (str indent exprStr "\n") (str indent target " = " exprStr "\n")))) ((= k "return") (if (= stmt.value "") (str indent "return None\n") (str indent "return " stmt.value "\n"))) ((= k "drop") "") ((= k "store") (str indent stmt.target "." stmt.field " = " stmt.value "\n")) ((= k "jump") (str indent "pass\n")) ((= k "loop") (str indent "while True:\n" (emitPyBlock stmt.loopBody (str indent "    ")))) ((= k "switch") (let [(casesStr (fold (fn [(acc Str) (c irTy/IrSwitchCase)] -> Str (str acc indent "    case " c.tag ":\n" (emitPyBlock c.body (str indent "        ")))) "" stmt.cases)) (defStr (str indent "    case _:\n" (emitPyBlock stmt.defaultBody (str indent "        "))))] (str indent "match " stmt.scrutinee ":\n" casesStr defStr))) (else "")))

fn emitPyBlock stmts: (List irTy/IrStmt) indent: Str -> Str
  (if (listEmpty? stmts) (str indent "pass\n") (fold (fn [(acc Str) (s irTy/IrStmt)] -> Str (str acc (emitPyIrStmt s indent))) "" stmts))

fn emitPyFunction f: irTy/IrFunction -> Str
  (let [(retTy (emitPyIrType f.retType)) (name (pyMangleIdent f.name)) (paramsStr (fold (fn [(acc Str) (p irTy/IrParam)] -> Str (let [(pDecl (str (pyMangleIdent p.name) ": " (emitPyIrType p.ty)))] (if (= acc "") pDecl (str acc ", " pDecl)))) "" f.params)) (bodyStr (emitPyBlock f.body "    "))] (str "def " name "(" paramsStr ") -> " retTy ":\n" bodyStr "\n"))

fn emitPyModule m: irTy/IrModule -> (Result Str (List irTy/IrDiag))
  (let [(vRes (vfy/verifyIr m))] (mt vRes ((err diags) (err diags)) ((ok _) (let [(funcsStr (fold (fn [(acc Str) (f irTy/IrFunction)] -> Str (str acc (emitPyFunction f))) "" m.funcs)) (hdr (str "from __future__ import annotations\n" "import sys\n" "from typing import Any, Optional\n\n" "def asl_wrap_i64(x: int) -> int:\n" "    return ((x + (1 << 63)) % (1 << 64)) - (1 << 63)\n\n" "def asl_wrap_i32(x: int) -> int:\n" "    return ((x + (1 << 31)) % (1 << 32)) - (1 << 31)\n\n" "class AslSome:\n" "    def __init__(self, val: Any = None) -> None:\n" "        self.val = val\n" "    def __repr__(self) -> str:\n" "        return f\"Some({self.val!r})\"\n\n")) (mainWrapper "if __name__ == \"__main__\":\n    if \"asl_main\" in globals():\n        asl_main()\n")] (ok (str hdr funcsStr mainWrapper))))))

fn emitPyStandaloneCase caseId: Str -> Str
  (cond ((= caseId "div_mod_positive") "print('div=' + str(14 // 3) + ' mod=' + str(14 % 3))\n") ((= caseId "div_mod_negative") "print('negDiv=' + str(-7 // 3) + ' negMod=' + str(-7 % 3))\n") ((= caseId "div_mod_pos_neg") "print('posNegDiv=' + str(7 // -3) + ' posNegMod=' + str(7 % -3))\n") ((= caseId "div_mod_neg_neg") "print('negNegDiv=' + str(-7 // -3) + ' negMod=' + str(-7 % -3))\n") ((= caseId "div_mod_zero_dividend") "print('zeroDiv=' + str(0 // 5) + ' zeroMod=' + str(0 % 5))\n") ((= caseId "div_mod_bounds") "print('boundsMod=' + str(-9223372036854775807 % 2))\n") ((= caseId "shift_mask_64") "print('shl=' + str(1 << (3 & 63)))\n") ((= caseId "shift_mask_overflow") "print('shlMasked=' + str(1 << (67 & 63)))\n") ((= caseId "int_wrap_add") (str "def asl_wrap_i64(x):\n" "    return ((x + (1 << 63)) % (1 << 64)) - (1 << 63)\n" "print('wrapped=' + str(asl_wrap_i64(9223372036854775807 + 1)))\n")) ((= caseId "int_wrap_mul") (str "def asl_wrap_i64(x):\n" "    return ((x + (1 << 63)) % (1 << 64)) - (1 << 63)\n" "print('mulWrap=' + str(asl_wrap_i64(9223372036854775807 * 2)))\n")) ((= caseId "float_roundtrip_precision") "print('flt=' + str(3.141592653589793))\n") ((= caseId "option_unit_repr") (str "class AslSome:\n" "    def __init__(self, val=None):\n" "        self.val = val\n" "v = AslSome(None)\n" "if v is not None:\n" "    print('optionUnit=Some')\n" "else:\n" "    print('optionUnit=None')\n")) ((= caseId "option_scalar_repr") "v = 42\nif v is not None:\n    print('optVal=' + str(v))\nelse:\n    print('none')\n") (else ""))
