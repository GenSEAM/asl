(module asl-target-llvm/rtOps
  :x [rtOpsPieces rtOpsDecls opsEntry? opsEntrySym opsBuiltin? opsBuiltinCall]
  :i [])

fn opsSymbols -> (List (Pair String String))
  (list (pair "+" "add") (pair "-" "sub") (pair "*" "mul") (pair "/" "div") (pair "mod" "mod")
        (pair "<" "lt") (pair "<=" "le") (pair ">" "gt") (pair ">=" "ge") (pair "=" "eq") (pair "!=" "ne") (pair "not" "not"))

fn opsEntry? name: String -> Bool
  (listAny? (fn [(p (Pair String String))] -> Bool (= (pairFirst p) name)) (opsSymbols))

fn opsEntrySym name: String -> String
  (fold (fn [(acc String) (p (Pair String String))] -> String (if (= (pairFirst p) name) (str "@opsrt." (pairSecond p)) acc)) "" (opsSymbols))

fn opsBuiltin? name: String n: Int64 -> Bool
  (and (opsEntry? name) (>= n 0))

fn comparison? suffix: String -> Bool
  (listContains? (list "lt" "le" "gt" "ge" "eq" "ne" "not") suffix)

fn opsBuiltinCall lhs: String p: String name: String args: (List String) -> String
  (let [(n (listLength args))
        (suffix (opsEntrySym name))
        (arg (fn [(i Int64)] -> String (str "%Val " (optionOr (listGet args i) ""))))
        (boxed (fn [(call String)] -> String
                 (str "  " p ".b = " call "\n  " p ".bits = zext i1 " p ".b to i64\n" lhs "insertvalue %Val { i64 1, i64 0 }, i64 " p ".bits, 1\n")))]
    (cond
      ((and (= name "-") (= n 1)) (str lhs "call %Val @opsrt.neg(" (arg 0) ")\n"))
      ((= name "not") (if (= n 1) (boxed (str "call i1 @opsrt.not(" (arg 0) ")")) (str lhs "call %Val @opsrt.notArity()\n")))
      ((and (>= n 2) (or (= name "+") (= name "*")))
        (str (stringJoin (map (fn [(i Int64)] -> String
                                (str "  " p ".f" i " = call %Val " suffix "(%Val " (if (= i 1) (optionOr (listGet args 0) "") (str p ".f" (- i 1))) ", " (arg i) ")\n"))
                              (range 1 (- n 1))) "")
             lhs "call %Val " suffix "(%Val " (if (= n 2) (optionOr (listGet args 0) "") (str p ".f" (- n 2))) ", " (arg (- n 1)) ")\n"))
      ((= n 2) (if (comparison? (stringReplace suffix "@opsrt." ""))
                 (boxed (str "call i1 " suffix "(" (arg 0) ", " (arg 1) ")"))
                 (str lhs "call %Val " suffix "(" (arg 0) ", " (arg 1) ")\n")))
      (else (str lhs "call %Val @opsrt.arity(ptr " (stringReplace suffix "@opsrt." "@.opsrt.who.") ", i64 " n ")\n"))))

fn opsText sym: String text: String -> String
  (str sym " = private unnamed_addr constant [" (+ (stringLength text) 1) " x i8] c\"" text "\\00\"")

fn depthText -> String
  "= on values nested deeper than 10000"

fn opsConstants -> (List (Pair String String))
  (map (fn [(p (Pair String String))] -> (Pair String String) (pair (pairFirst p) (opsText (pairFirst p) (pairSecond p))))
       (listAppend
         (map (fn [(p (Pair String String))] -> (Pair String String) (pair (str "@.opsrt.who." (pairSecond p)) (pairFirst p)))
              (filter (fn [(p (Pair String String))] -> Bool (!= (pairFirst p) "not")) (opsSymbols)))
         (list (pair "@.opsrt.pair" "%s expects two Int or two Float, got %s and %s")
               (pair "@.opsrt.compares" "= compares %s with %s")
               (pair "@.opsrt.depth" (depthText))
               (pair "@.opsrt.neg" "- expects Int or Float, got %s")
               (pair "@.opsrt.not" "not expects Bool, got %s")
               (pair "@.opsrt.arity" "%s takes 2 operands, got %lld")
               (pair "@.opsrt.notArity" "not takes 1 operand"))))

fn operands -> String
  (stringJoin (list
    "  %a.tagw = extractvalue %Val %a, 0"
    "  %a.tag = trunc i64 %a.tagw to i32"
    "  %a.bits = extractvalue %Val %a, 1"
    "  %b.tagw = extractvalue %Val %b, 0"
    "  %b.tag = trunc i64 %b.tagw to i32"
    "  %b.bits = extractvalue %Val %b, 1"
    "  %a.int = icmp eq i32 %a.tag, 2"
    "  %b.int = icmp eq i32 %b.tag, 2"
    "  %ints = and i1 %a.int, %b.int"
    "  %a.float = icmp eq i32 %a.tag, 3"
    "  %b.float = icmp eq i32 %b.tag, 3"
    "  %floats = and i1 %a.float, %b.float"
    "  br i1 %ints, label %int, label %notInt"
    "notInt:"
    "  br i1 %floats, label %float, label %other"
    "float:"
    "  %x = bitcast i64 %a.bits to double"
    "  %y = bitcast i64 %b.bits to double") "\n")

fn boxInt reg: String -> String
  (str "  " reg ".val = insertvalue %Val { i64 2, i64 0 }, i64 " reg ", 1\n  ret %Val " reg ".val")

fn boxFloat reg: String -> String
  (str "  " reg ".bits = bitcast double " reg " to i64\n  " reg ".val = insertvalue %Val { i64 3, i64 0 }, i64 " reg ".bits, 1\n  ret %Val " reg ".val")

fn trapInt kind: Int64 -> String
  (str "  call void @rterr.int(i32 " kind ")\n  unreachable")

fn typeErr2 suffix: String -> String
  (str "  call void @opsrt.pair(ptr @.opsrt.who." suffix ", i32 %a.tag, i32 %b.tag)\n  unreachable")

fn overflowArith suffix: String intrinsic: String kind: Int64 floatOp: String -> String
  (stringJoin (list
    (str "define internal %Val @opsrt." suffix "(%Val %a, %Val %b) {")
    "entry:"
    (operands)
    (str "  %r = " floatOp " double %x, %y")
    (boxFloat "%r")
    "int:"
    (str "  %wide = call {i64, i1} @llvm." intrinsic ".with.overflow.i64(i64 %a.bits, i64 %b.bits)")
    "  %n = extractvalue {i64, i1} %wide, 0"
    "  %over = extractvalue {i64, i1} %wide, 1"
    "  br i1 %over, label %overflow, label %exact"
    "overflow:"
    (trapInt kind)
    "exact:"
    (boxInt "%n")
    "other:"
    (typeErr2 suffix)
    "}") "\n")

fn divFunction -> String
  (stringJoin (list
    "define internal %Val @opsrt.div(%Val %a, %Val %b) {"
    "entry:"
    (operands)
    "  %r = fdiv double %x, %y"
    (boxFloat "%r")
    "int:"
    "  %zero = icmp eq i64 %b.bits, 0"
    "  br i1 %zero, label %byZero, label %nonZero"
    "byZero:"
    (trapInt 5)
    "nonZero:"
    "  %minusOne = icmp eq i64 %b.bits, -1"
    "  br i1 %minusOne, label %negate, label %divide"
    "negate:"
    "  %isMin = icmp eq i64 %a.bits, -9223372036854775808"
    "  br i1 %isMin, label %overflow, label %negated"
    "overflow:"
    (trapInt 3)
    "negated:"
    "  %neg = sub i64 0, %a.bits"
    (boxInt "%neg")
    "divide:"
    "  %q = sdiv i64 %a.bits, %b.bits"
    "  %rem = srem i64 %a.bits, %b.bits"
    "  %inexact = icmp ne i64 %rem, 0"
    "  %a.neg = icmp slt i64 %a.bits, 0"
    "  %b.neg = icmp slt i64 %b.bits, 0"
    "  %signs = xor i1 %a.neg, %b.neg"
    "  %down = and i1 %inexact, %signs"
    "  %below = sub i64 %q, 1"
    "  %floor = select i1 %down, i64 %below, i64 %q"
    (boxInt "%floor")
    "other:"
    (typeErr2 "div")
    "}") "\n")

fn modFunction -> String
  (stringJoin (list
    "define internal %Val @opsrt.mod(%Val %a, %Val %b) {"
    "entry:"
    (operands)
    "  %fr = frem double %x, %y"
    "  %fr.zero = fcmp oeq double %fr, 0.0"
    "  %fr.signed = call double @llvm.copysign.f64(double 0.0, double %y)"
    "  %fr.neg = fcmp olt double %fr, 0.0"
    "  %y.neg = fcmp olt double %y, 0.0"
    "  %fr.differ = xor i1 %fr.neg, %y.neg"
    "  %fr.moved = fadd double %fr, %y"
    "  %fr.kept = select i1 %fr.differ, double %fr.moved, double %fr"
    "  %r = select i1 %fr.zero, double %fr.signed, double %fr.kept"
    (boxFloat "%r")
    "int:"
    "  %zero = icmp eq i64 %b.bits, 0"
    "  br i1 %zero, label %byZero, label %nonZero"
    "byZero:"
    (trapInt 6)
    "nonZero:"
    "  %minusOne = icmp eq i64 %b.bits, -1"
    "  br i1 %minusOne, label %exact, label %divide"
    "exact:"
    "  ret %Val { i64 2, i64 0 }"
    "divide:"
    "  %rem = srem i64 %a.bits, %b.bits"
    "  %inexact = icmp ne i64 %rem, 0"
    "  %rem.neg = icmp slt i64 %rem, 0"
    "  %b.neg = icmp slt i64 %b.bits, 0"
    "  %signs = xor i1 %rem.neg, %b.neg"
    "  %move = and i1 %inexact, %signs"
    "  %moved = add i64 %rem, %b.bits"
    "  %floor = select i1 %move, i64 %moved, i64 %rem"
    (boxInt "%floor")
    "other:"
    (typeErr2 "mod")
    "}") "\n")

fn ordering suffix: String intCmp: String floatCmp: String -> String
  (stringJoin (list
    (str "define internal i1 @opsrt." suffix "(%Val %a, %Val %b) {")
    "entry:"
    (operands)
    (str "  %fr = fcmp " floatCmp " double %x, %y")
    "  ret i1 %fr"
    "int:"
    (str "  %ir = icmp " intCmp " i64 %a.bits, %b.bits")
    "  ret i1 %ir"
    "other:"
    (str "  %c = call i32 @opsrt.cmp(%Val %a, %Val %b, ptr @.opsrt.who." suffix ")")
    (str "  %cr = icmp " intCmp " i32 %c, 0")
    "  ret i1 %cr"
    "}") "\n")

fn cmpFunction -> String
  (stringJoin (list
    "define internal i32 @opsrt.cmp(%Val %a, %Val %b, ptr %who) {"
    "entry:"
    "  %a.tagw = extractvalue %Val %a, 0"
    "  %a.tag = trunc i64 %a.tagw to i32"
    "  %b.tagw = extractvalue %Val %b, 0"
    "  %b.tag = trunc i64 %b.tagw to i32"
    "  %same = icmp eq i32 %a.tag, %b.tag"
    "  br i1 %same, label %kind, label %bad"
    "kind:"
    "  switch i32 %a.tag, label %bad [ i32 5, label %string i32 4, label %keyword ]"
    "string:"
    "  %a.objw = extractvalue %Val %a, 1"
    "  %a.obj = inttoptr i64 %a.objw to ptr"
    "  %b.objw = extractvalue %Val %b, 1"
    "  %b.obj = inttoptr i64 %b.objw to ptr"
    "  %a.lenp = getelementptr inbounds i8, ptr %a.obj, i64 8"
    "  %a.len = load i64, ptr %a.lenp"
    "  %b.lenp = getelementptr inbounds i8, ptr %b.obj, i64 8"
    "  %b.len = load i64, ptr %b.lenp"
    "  %a.text = getelementptr inbounds i8, ptr %a.obj, i64 16"
    "  %b.text = getelementptr inbounds i8, ptr %b.obj, i64 16"
    "  %shorter = icmp ult i64 %a.len, %b.len"
    "  %common = select i1 %shorter, i64 %a.len, i64 %b.len"
    "  %bytes = call i32 @memcmp(ptr %a.text, ptr %b.text, i64 %common)"
    "  %differ = icmp ne i32 %bytes, 0"
    "  br i1 %differ, label %byBytes, label %byLength"
    "byBytes:"
    "  ret i32 %bytes"
    "byLength:"
    "  %longer = icmp ugt i64 %a.len, %b.len"
    "  %after = zext i1 %longer to i32"
    "  %before = select i1 %shorter, i32 -1, i32 %after"
    "  ret i32 %before"
    "keyword:"
    "  %a.auxw = lshr i64 %a.tagw, 32"
    "  %a.aux = trunc i64 %a.auxw to i32"
    "  %b.auxw = lshr i64 %b.tagw, 32"
    "  %b.aux = trunc i64 %b.auxw to i32"
    "  %a.name = call ptr @valrt.symName(i32 %a.aux)"
    "  %b.name = call ptr @valrt.symName(i32 %b.aux)"
    "  %names = call i32 @strcmp(ptr %a.name, ptr %b.name)"
    "  ret i32 %names"
    "bad:"
    "  call void @opsrt.pair(ptr %who, i32 %a.tag, i32 %b.tag)"
    "  unreachable"
    "}") "\n")

fn equality suffix: String intCmp: String floatCmp: String negate: Bool -> String
  (stringJoin (list
    (str "define internal i1 @opsrt." suffix "(%Val %a, %Val %b) {")
    "entry:"
    (operands)
    (str "  %fr = fcmp " floatCmp " double %x, %y")
    "  ret i1 %fr"
    "int:"
    (str "  %ir = icmp " intCmp " i64 %a.bits, %b.bits")
    "  ret i1 %ir"
    "other:"
    "  %same = call i1 @opsrt.valEq(%Val %a, %Val %b, i32 0)"
    (if negate "  %r = xor i1 %same, true\n  ret i1 %r" "  ret i1 %same")
    "}") "\n")

fn objOf v: String -> String
  (str "  %" v ".obj = inttoptr i64 %" v ".bits to ptr")

fn fieldAt v: String off: Int64 ty: String into: String -> String
  (str "  %" into "p = getelementptr inbounds i8, ptr %" v ".obj, i64 " off "\n  %" into " = load " ty ", ptr %" into "p")

fn valEqFunction -> String
  (stringJoin (list
    "define internal i1 @opsrt.valEq(%Val %a, %Val %b, i32 %depth) {"
    "entry:"
    "  %deep = icmp sge i32 %depth, 10000"
    "  br i1 %deep, label %tooDeep, label %enter"
    "tooDeep:"
    (str "  call void @rterr.raise(ptr @.rterr.c.ERR_DEPTH, ptr @.opsrt.depth, i64 " (stringLength (depthText)) ")")
    "  unreachable"
    "enter:"
    "  %a.tagw = extractvalue %Val %a, 0"
    "  %a.tag = trunc i64 %a.tagw to i32"
    "  %a.bits = extractvalue %Val %a, 1"
    "  %b.tagw = extractvalue %Val %b, 0"
    "  %b.tag = trunc i64 %b.tagw to i32"
    "  %b.bits = extractvalue %Val %b, 1"
    "  %same = icmp eq i32 %a.tag, %b.tag"
    "  br i1 %same, label %dispatch, label %mismatch"
    "mismatch:"
    "  call void @opsrt.compares(i32 %a.tag, i32 %b.tag)"
    "  unreachable"
    "dispatch:"
    "  %next = add i32 %depth, 1"
    "  %bitsEq = icmp eq i64 %a.bits, %b.bits"
    "  switch i32 %a.tag, label %payload [ i32 0, label %yes i32 3, label %float i32 4, label %keyword i32 5, label %string i32 6, label %list i32 7, label %record i32 8, label %ctor i32 11, label %bytes ]"
    "yes:"
    "  ret i1 true"
    "no:"
    "  ret i1 false"
    "payload:"
    "  ret i1 %bitsEq"
    "float:"
    "  %x = bitcast i64 %a.bits to double"
    "  %y = bitcast i64 %b.bits to double"
    "  %floatEq = fcmp oeq double %x, %y"
    "  ret i1 %floatEq"
    "keyword:"
    "  %a.aux = lshr i64 %a.tagw, 32"
    "  %b.aux = lshr i64 %b.tagw, 32"
    "  %auxEq = icmp eq i64 %a.aux, %b.aux"
    "  ret i1 %auxEq"
    "string:"
    (objOf "a") (objOf "b")
    (fieldAt "a" 8 "i64" "s.alen") (fieldAt "b" 8 "i64" "s.blen")
    "  %s.lenEq = icmp eq i64 %s.alen, %s.blen"
    "  br i1 %s.lenEq, label %s.bytes, label %no"
    "s.bytes:"
    "  %s.atext = getelementptr inbounds i8, ptr %a.obj, i64 16"
    "  %s.btext = getelementptr inbounds i8, ptr %b.obj, i64 16"
    "  %s.cmp = call i32 @memcmp(ptr %s.atext, ptr %s.btext, i64 %s.alen)"
    "  %s.eq = icmp eq i32 %s.cmp, 0"
    "  ret i1 %s.eq"
    "bytes:"
    "  %y.aobj = inttoptr i64 %a.bits to ptr"
    "  %y.bobj = inttoptr i64 %b.bits to ptr"
    "  %y.alenp = getelementptr inbounds i8, ptr %y.aobj, i64 8"
    "  %y.alen = load i64, ptr %y.alenp"
    "  %y.blenp = getelementptr inbounds i8, ptr %y.bobj, i64 8"
    "  %y.blen = load i64, ptr %y.blenp"
    "  %y.lenEq = icmp eq i64 %y.alen, %y.blen"
    "  br i1 %y.lenEq, label %y.some, label %no"
    "y.some:"
    "  %y.empty = icmp eq i64 %y.alen, 0"
    "  br i1 %y.empty, label %yes, label %y.data"
    "y.data:"
    "  %y.adatap = getelementptr inbounds i8, ptr %y.aobj, i64 24"
    "  %y.adata = load ptr, ptr %y.adatap"
    "  %y.bdatap = getelementptr inbounds i8, ptr %y.bobj, i64 24"
    "  %y.bdata = load ptr, ptr %y.bdatap"
    "  %y.cmp = call i32 @memcmp(ptr %y.adata, ptr %y.bdata, i64 %y.alen)"
    "  %y.eq = icmp eq i32 %y.cmp, 0"
    "  ret i1 %y.eq"
    "list:"
    "  br label %l.loop"
    "l.loop:"
    "  %l.x = phi i64 [ %a.bits, %list ], [ %l.xNext, %l.next ]"
    "  %l.y = phi i64 [ %b.bits, %list ], [ %l.yNext, %l.next ]"
    "  %l.xLive = icmp ne i64 %l.x, 0"
    "  %l.yLive = icmp ne i64 %l.y, 0"
    "  %l.both = and i1 %l.xLive, %l.yLive"
    "  br i1 %l.both, label %l.cell, label %l.end"
    "l.cell:"
    "  %l.xobj = inttoptr i64 %l.x to ptr"
    "  %l.yobj = inttoptr i64 %l.y to ptr"
    "  %l.xcarp = getelementptr inbounds i8, ptr %l.xobj, i64 8"
    "  %l.xcar = load %Val, ptr %l.xcarp"
    "  %l.ycarp = getelementptr inbounds i8, ptr %l.yobj, i64 8"
    "  %l.ycar = load %Val, ptr %l.ycarp"
    "  %l.carEq = call i1 @opsrt.valEq(%Val %l.xcar, %Val %l.ycar, i32 %next)"
    "  br i1 %l.carEq, label %l.next, label %no"
    "l.next:"
    "  %l.xcdrp = getelementptr inbounds i8, ptr %l.xobj, i64 24"
    "  %l.xcdr = load %Val, ptr %l.xcdrp"
    "  %l.xNext = extractvalue %Val %l.xcdr, 1"
    "  %l.ycdrp = getelementptr inbounds i8, ptr %l.yobj, i64 24"
    "  %l.ycdr = load %Val, ptr %l.ycdrp"
    "  %l.yNext = extractvalue %Val %l.ycdr, 1"
    "  br label %l.loop"
    "l.end:"
    "  %l.same = icmp eq i64 %l.x, %l.y"
    "  ret i1 %l.same"
    "ctor:"
    "  %c.aobj = inttoptr i64 %a.bits to ptr"
    "  %c.bobj = inttoptr i64 %b.bits to ptr"
    "  %c.aidp = getelementptr inbounds i8, ptr %c.aobj, i64 8"
    "  %c.aid = load i32, ptr %c.aidp"
    "  %c.bidp = getelementptr inbounds i8, ptr %c.bobj, i64 8"
    "  %c.bid = load i32, ptr %c.bidp"
    "  %c.anp = getelementptr inbounds i8, ptr %c.aobj, i64 12"
    "  %c.an = load i32, ptr %c.anp"
    "  %c.bnp = getelementptr inbounds i8, ptr %c.bobj, i64 12"
    "  %c.bn = load i32, ptr %c.bnp"
    "  %c.idEq = icmp eq i32 %c.aid, %c.bid"
    "  %c.nEq = icmp eq i32 %c.an, %c.bn"
    "  %c.shape = and i1 %c.idEq, %c.nEq"
    "  br i1 %c.shape, label %c.loop, label %no"
    "c.loop:"
    "  %c.i = phi i32 [ 0, %ctor ], [ %c.inext, %c.field ]"
    "  %c.more = icmp slt i32 %c.i, %c.an"
    "  br i1 %c.more, label %c.field, label %yes"
    "c.field:"
    "  %c.iw = sext i32 %c.i to i64"
    "  %c.off0 = mul i64 %c.iw, 16"
    "  %c.off = add i64 %c.off0, 16"
    "  %c.afp = getelementptr inbounds i8, ptr %c.aobj, i64 %c.off"
    "  %c.af = load %Val, ptr %c.afp"
    "  %c.bfp = getelementptr inbounds i8, ptr %c.bobj, i64 %c.off"
    "  %c.bf = load %Val, ptr %c.bfp"
    "  %c.fieldEq = call i1 @opsrt.valEq(%Val %c.af, %Val %c.bf, i32 %next)"
    "  %c.inext = add i32 %c.i, 1"
    "  br i1 %c.fieldEq, label %c.loop, label %no"
    "record:"
    "  %r.aobj = inttoptr i64 %a.bits to ptr"
    "  %r.bobj = inttoptr i64 %b.bits to ptr"
    "  %r.aschemap = getelementptr inbounds i8, ptr %r.aobj, i64 8"
    "  %r.aschema = load i32, ptr %r.aschemap"
    "  %r.bschemap = getelementptr inbounds i8, ptr %r.bobj, i64 8"
    "  %r.bschema = load i32, ptr %r.bschemap"
    "  %r.anp = getelementptr inbounds i8, ptr %r.aobj, i64 12"
    "  %r.an = load i32, ptr %r.anp"
    "  %r.bnp = getelementptr inbounds i8, ptr %r.bobj, i64 12"
    "  %r.bn = load i32, ptr %r.bnp"
    "  %r.nEq = icmp eq i32 %r.an, %r.bn"
    "  %r.schemaEq = icmp eq i32 %r.aschema, %r.bschema"
    "  %r.shape = and i1 %r.nEq, %r.schemaEq"
    "  br i1 %r.shape, label %r.keys, label %no"
    "r.keys:"
    "  %r.akeysp = getelementptr inbounds i8, ptr %r.aobj, i64 16"
    "  %r.akeys = load ptr, ptr %r.akeysp"
    "  %r.bkeysp = getelementptr inbounds i8, ptr %r.bobj, i64 16"
    "  %r.bkeys = load ptr, ptr %r.bkeysp"
    "  br label %r.loop"
    "r.loop:"
    "  %r.i = phi i32 [ 0, %r.keys ], [ %r.inext, %r.found ]"
    "  %r.more = icmp slt i32 %r.i, %r.an"
    "  br i1 %r.more, label %r.key, label %yes"
    "r.key:"
    "  %r.iw = sext i32 %r.i to i64"
    "  %r.akeyp = getelementptr inbounds i32, ptr %r.akeys, i64 %r.iw"
    "  %r.akey = load i32, ptr %r.akeyp"
    "  br label %r.search"
    "r.search:"
    "  %r.k = phi i32 [ 0, %r.key ], [ %r.knext, %r.miss ]"
    "  %r.left = icmp slt i32 %r.k, %r.bn"
    "  br i1 %r.left, label %r.probe, label %no"
    "r.probe:"
    "  %r.kw = sext i32 %r.k to i64"
    "  %r.bkeyp = getelementptr inbounds i32, ptr %r.bkeys, i64 %r.kw"
    "  %r.bkey = load i32, ptr %r.bkeyp"
    "  %r.hit = icmp eq i32 %r.bkey, %r.akey"
    "  br i1 %r.hit, label %r.compare, label %r.miss"
    "r.miss:"
    "  %r.knext = add i32 %r.k, 1"
    "  br label %r.search"
    "r.compare:"
    "  %r.aoff0 = mul i64 %r.iw, 16"
    "  %r.aoff = add i64 %r.aoff0, 24"
    "  %r.boff0 = mul i64 %r.kw, 16"
    "  %r.boff = add i64 %r.boff0, 24"
    "  %r.avp = getelementptr inbounds i8, ptr %r.aobj, i64 %r.aoff"
    "  %r.av = load %Val, ptr %r.avp"
    "  %r.bvp = getelementptr inbounds i8, ptr %r.bobj, i64 %r.boff"
    "  %r.bv = load %Val, ptr %r.bvp"
    "  %r.valueEq = call i1 @opsrt.valEq(%Val %r.av, %Val %r.bv, i32 %next)"
    "  br i1 %r.valueEq, label %r.found, label %no"
    "r.found:"
    "  %r.inext = add i32 %r.i, 1"
    "  br label %r.loop"
    "}") "\n")

fn formatTwoTags sym: String withWho: Bool format: String -> String
  (let [(who (if withWho "ptr %who, " ""))]
    (stringJoin (list
      (str "define internal void " sym "(" who "i32 %a, i32 %b) noreturn {")
      "entry:"
      "  %buf = alloca [4096 x i8]"
      "  store i8 0, ptr %buf"
      "  %aName = call ptr @rterr.tagName(i32 %a)"
      "  %bName = call ptr @rterr.tagName(i32 %b)"
      (str "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr " format ", " who "ptr %aName, ptr %bName)")
      "  %len = call i64 @strlen(ptr %buf)"
      "  call void @rterr.raise(ptr @.rterr.c.ERR_TYPE, ptr %buf, i64 %len)"
      "  unreachable"
      "}") "\n"))

fn unaryFunction sym: String message: String wantTag: String body: (List String) -> String
  (stringJoin (listAppend
    (list
      (str "define internal " sym " {")
      "entry:"
      "  %v.tagw = extractvalue %Val %v, 0"
      "  %v.tag = trunc i64 %v.tagw to i32"
      "  %v.bits = extractvalue %Val %v, 1"
      wantTag
      "bad:"
      "  %name = call ptr @rterr.tagName(i32 %v.tag)"
      (str "  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr " message ", ptr %name)")
      "  unreachable")
    (listAppend body (list "}"))) "\n")

fn opsFunctions -> (List (Pair String String))
  (list
    (pair "@opsrt.pair" (formatTwoTags "@opsrt.pair" true "@.opsrt.pair"))
    (pair "@opsrt.compares" (formatTwoTags "@opsrt.compares" false "@.opsrt.compares"))
    (pair "@opsrt.arity"
      (stringJoin (list
        "define internal %Val @opsrt.arity(ptr %who, i64 %n) noreturn {"
        "entry:"
        "  %buf = alloca [4096 x i8]"
        "  store i8 0, ptr %buf"
        "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.opsrt.arity, ptr %who, i64 %n)"
        "  %len = call i64 @strlen(ptr %buf)"
        "  call void @rterr.raise(ptr @.rterr.c.ERR_ARITY, ptr %buf, i64 %len)"
        "  unreachable"
        "}") "\n"))
    (pair "@opsrt.notArity"
      (stringJoin (list
        "define internal %Val @opsrt.notArity() noreturn {"
        "entry:"
        "  call void @rterr.raise(ptr @.rterr.c.ERR_ARITY, ptr @.opsrt.notArity, i64 19)"
        "  unreachable"
        "}") "\n"))
    (pair "@opsrt.add" (overflowArith "add" "sadd" 0 "fadd"))
    (pair "@opsrt.sub" (overflowArith "sub" "ssub" 1 "fsub"))
    (pair "@opsrt.mul" (overflowArith "mul" "smul" 2 "fmul"))
    (pair "@opsrt.div" (divFunction))
    (pair "@opsrt.mod" (modFunction))
    (pair "@opsrt.cmp" (cmpFunction))
    (pair "@opsrt.lt" (ordering "lt" "slt" "olt"))
    (pair "@opsrt.le" (ordering "le" "sle" "ole"))
    (pair "@opsrt.gt" (ordering "gt" "sgt" "ogt"))
    (pair "@opsrt.ge" (ordering "ge" "sge" "oge"))
    (pair "@opsrt.valEq" (valEqFunction))
    (pair "@opsrt.eq" (equality "eq" "eq" "oeq" false))
    (pair "@opsrt.ne" (equality "ne" "ne" "une" true))
    (pair "@opsrt.neg"
      (unaryFunction "%Val @opsrt.neg(%Val %v)" "@.opsrt.neg"
        "  %v.int = icmp eq i32 %v.tag, 2\n  br i1 %v.int, label %int, label %notInt\nnotInt:\n  %v.float = icmp eq i32 %v.tag, 3\n  br i1 %v.float, label %float, label %bad"
        (list "int:"
              "  %isMin = icmp eq i64 %v.bits, -9223372036854775808"
              "  br i1 %isMin, label %overflow, label %negated"
              "overflow:"
              (trapInt 1)
              "negated:"
              "  %n = sub i64 0, %v.bits"
              (boxInt "%n")
              "float:"
              "  %x = bitcast i64 %v.bits to double"
              "  %r = fneg double %x"
              (boxFloat "%r"))))
    (pair "@opsrt.not"
      (unaryFunction "i1 @opsrt.not(%Val %v)" "@.opsrt.not"
        "  %v.bool = icmp eq i32 %v.tag, 1\n  br i1 %v.bool, label %bool, label %bad"
        (list "bool:"
              "  %r = icmp eq i64 %v.bits, 0"
              "  ret i1 %r"))))

fn rtOpsPieces -> (List (Pair String String))
  (listAppend (opsConstants) (opsFunctions))

fn rtOpsDecls -> (List String)
  (list "declare i32 @memcmp(ptr, ptr, i64)"
        "declare i32 @strcmp(ptr, ptr)"
        "declare double @llvm.copysign.f64(double, double)"
        "declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)"
        "declare {i64, i1} @llvm.ssub.with.overflow.i64(i64, i64)"
        "declare {i64, i1} @llvm.smul.with.overflow.i64(i64, i64)")
