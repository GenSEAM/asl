(module asl-target-llvm/rtObject
  :x [rtObjectPieces rtObjectDecls]
  :i [])

fn objText sym: String text: String -> String
  (str sym " = private unnamed_addr constant [" (+ (stringLength text) 1) " x i8] c\"" text "\\00\"")

fn partialName -> String
  "partial"

fn partialLimitText -> String
  "partial application with more than 64 arguments"

fn objConstants -> (List (Pair String String))
  (listAppend
    (map (fn [(p (Pair String String))] -> (Pair String String) (pair (pairFirst p) (objText (pairFirst p) (pairSecond p))))
         (list (pair "@.objrt.fieldType" ".-%s expects a record, got %s")
               (pair "@.objrt.noField" "record has no field %s")
               (pair "@.objrt.variantType" "variant field %lld of a %s")
               (pair "@.objrt.variantRange" "variant %s has %d field(s), no field %lld")
               (pair "@.objrt.patternArity" "pattern (%s) binds %u field(s), value has %d")
               (pair "@.objrt.captureType" "closure environment is a %s")
               (pair "@.objrt.captureRange" "capture %lld outside the %d captured value(s)")
               (pair "@.objrt.arity" "%s expects %d argument(s), got %lld")
               (pair "@.objrt.notFn" "cannot call a %s")
               (pair "@.objrt.bytecode" "%s is bytecode, which a native binary cannot run")
               (pair "@.objrt.partialLimit" (partialLimitText))
               (pair "@.objrt.symbol" "symbol %s: the host value model has no symbol type")
               (pair "@.objrt.strLimit" "string constant: count %lld outside 0..2147483647")
               (pair "@.objrt.partial" (partialName))))
    (list (pair "@objrt.partialId" "@objrt.partialId = internal global i32 -1")))

fn formatted p: String code: String format: String args: String -> (List String)
  (list (str "  " p "buf = alloca [4096 x i8]")
        (str "  store i8 0, ptr " p "buf")
        (str "  " p "written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr " p "buf, i64 4096, ptr " format args ")")
        (str "  " p "len = call i64 @strlen(ptr " p "buf)")
        (str "  call void @rterr.raise(ptr @.rterr.c." code ", ptr " p "buf, i64 " p "len)")
        "  unreachable")

fn tagOf v: String -> (List String)
  (list (str "  %tagw = extractvalue %Val " v ", 0")
        "  %tag = trunc i64 %tagw to i32"
        (str "  %objw = extractvalue %Val " v ", 1")
        "  %obj = inttoptr i64 %objw to ptr")

fn defineFn header: String body: (List (List String)) -> String
  (stringJoin (listAppend (list (str "define internal " header " {") "entry:")
                          (listAppend (fold (fn [(acc (List String)) (part (List String))] -> (List String) (listAppend acc part)) (list) body) (list "}")))
              "\n")

fn nameIdFunction -> String
  (defineFn "i32 @objrt.nameId(ptr %cell, ptr %name, i64 %len)"
    (list (list "  %id = load i32, ptr %cell"
                "  %known = icmp sge i32 %id, 0"
                "  br i1 %known, label %done, label %resolve"
                "resolve:"
                "  %fresh = call i32 @valrt.intern(ptr %name, i64 %len)"
                "  store i32 %fresh, ptr %cell"
                "  ret i32 %fresh"
                "done:"
                "  ret i32 %id")))

fn strFunction -> String
  (defineFn "%Val @objrt.str(ptr %cell, ptr %bytes, i64 %len)"
    (list (list "  %cached = load %Val, ptr %cell"
                "  %cachedTag = extractvalue %Val %cached, 0"
                "  %built = icmp ne i64 %cachedTag, 0"
                "  br i1 %built, label %done, label %check"
                "check:"
                "  %fits = icmp ule i64 %len, 2147483647"
                "  br i1 %fits, label %build, label %tooLong"
                "tooLong:"
                "  call void @rterr.raiseNumber(ptr @.rterr.c.ERR_LIMIT, ptr @.objrt.strLimit, i64 %len)"
                "  unreachable"
                "build:"
                "  %size = add i64 %len, 17"
                "  %obj = call ptr @asl_alloc(i32 0, i64 %size)"
                "  %lenp = getelementptr inbounds i8, ptr %obj, i64 8"
                "  store i64 %len, ptr %lenp"
                "  %data = getelementptr inbounds i8, ptr %obj, i64 16"
                "  call void @llvm.memcpy.p0.p0.i64(ptr %data, ptr %bytes, i64 %len, i1 false)"
                "  %end = getelementptr inbounds i8, ptr %data, i64 %len"
                "  store i8 0, ptr %end"
                "  %objw = ptrtoint ptr %obj to i64"
                "  %str = insertvalue %Val { i64 5, i64 0 }, i64 %objw, 1"
                "  store %Val %str, ptr %cell"
                "  call void @asl_rt_global_root(ptr %cell)"
                "  ret %Val %str"
                "done:"
                "  ret %Val %cached")))

fn fieldFunction -> String
  (defineFn "%Val @objrt.field(%Val %v, ptr %cell, ptr %name, i64 %len)"
    (list (tagOf "%v")
          (list "  %isRec = icmp eq i32 %tag, 7"
                "  br i1 %isRec, label %rec, label %notRec"
                "rec:"
                "  %key = call i32 @objrt.nameId(ptr %cell, ptr %name, i64 %len)"
                "  %np = getelementptr inbounds i8, ptr %obj, i64 12"
                "  %n = load i32, ptr %np"
                "  %keysp = getelementptr inbounds i8, ptr %obj, i64 16"
                "  %keys = load ptr, ptr %keysp"
                "  br label %loop"
                "loop:"
                "  %i = phi i32 [ 0, %rec ], [ %next, %body ]"
                "  %inRange = icmp slt i32 %i, %n"
                "  br i1 %inRange, label %body, label %missing"
                "body:"
                "  %keyp = getelementptr inbounds i32, ptr %keys, i32 %i"
                "  %k = load i32, ptr %keyp"
                "  %next = add i32 %i, 1"
                "  %match = icmp eq i32 %k, %key"
                "  br i1 %match, label %found, label %loop"
                "found:"
                "  %i64 = sext i32 %i to i64"
                "  %off = mul i64 %i64, 16"
                "  %slot = add i64 %off, 24"
                "  %valp = getelementptr inbounds i8, ptr %obj, i64 %slot"
                "  %value = load %Val, ptr %valp"
                "  ret %Val %value"
                "missing:"
                "  call void @rterr.raiseText(ptr @.rterr.c.ERR_FIELD, ptr @.objrt.noField, ptr %name)"
                "  unreachable"
                "notRec:"
                "  %tname = call ptr @rterr.tagName(i32 %tag)")
          (formatted "%type." "ERR_TYPE" "@.objrt.fieldType" ", ptr %name, ptr %tname")))

fn variantFieldFunction -> String
  (defineFn "%Val @objrt.variantField(%Val %v, i64 %i)"
    (list (tagOf "%v")
          (list "  %isCtor = icmp eq i32 %tag, 8"
                "  br i1 %isCtor, label %ctor, label %notCtor"
                "ctor:"
                "  %np = getelementptr inbounds i8, ptr %obj, i64 12"
                "  %n = load i32, ptr %np"
                "  %n64 = sext i32 %n to i64"
                "  %nonNegative = icmp sge i64 %i, 0"
                "  %below = icmp slt i64 %i, %n64"
                "  %inRange = and i1 %nonNegative, %below"
                "  br i1 %inRange, label %found, label %range"
                "found:"
                "  %off = mul i64 %i, 16"
                "  %slot = add i64 %off, 16"
                "  %valp = getelementptr inbounds i8, ptr %obj, i64 %slot"
                "  %value = load %Val, ptr %valp"
                "  ret %Val %value"
                "range:"
                "  %idp = getelementptr inbounds i8, ptr %obj, i64 8"
                "  %id = load i32, ptr %idp"
                "  %vname = call ptr @valrt.symName(i32 %id)")
          (formatted "%range." "ERR_RANGE" "@.objrt.variantRange" ", ptr %vname, i32 %n, i64 %i")
          (list "notCtor:"
                "  %tname = call ptr @rterr.tagName(i32 %tag)")
          (formatted "%type." "ERR_TYPE" "@.objrt.variantType" ", i64 %i, ptr %tname")))

fn patternArityFunction -> String
  (defineFn "void @objrt.patternArity(ptr %name, i32 %want, i32 %n) noreturn"
    (list (formatted "%" "ERR_ARITY" "@.objrt.patternArity" ", ptr %name, i32 %want, i32 %n")))

fn captureFunction -> String
  (defineFn "%Val @objrt.capture(%Val %env, i64 %i)"
    (list (tagOf "%env")
          (list "  %isFn = icmp eq i32 %tag, 9"
                "  br i1 %isFn, label %closure, label %notFn"
                "closure:"
                "  %np = getelementptr inbounds i8, ptr %obj, i64 16"
                "  %n = load i32, ptr %np"
                "  %n64 = sext i32 %n to i64"
                "  %nonNegative = icmp sge i64 %i, 0"
                "  %below = icmp slt i64 %i, %n64"
                "  %inRange = and i1 %nonNegative, %below"
                "  br i1 %inRange, label %found, label %range"
                "found:"
                "  %off = mul i64 %i, 16"
                "  %slot = add i64 %off, 24"
                "  %valp = getelementptr inbounds i8, ptr %obj, i64 %slot"
                "  %value = load %Val, ptr %valp"
                "  ret %Val %value"
                "range:")
          (formatted "%" "ERR_RANGE" "@.objrt.captureRange" ", i64 %i, i32 %n")
          (list "notFn:"
                "  %tname = call ptr @rterr.tagName(i32 %tag)"
                "  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.objrt.captureType, ptr %tname)"
                "  unreachable")))

fn callFunction -> String
  (defineFn "%Val @objrt.call(%Val %fn, i64 %argc, ptr %argv)"
    (list (list "  %all = alloca [64 x %Val]")
          (tagOf "%fn")
          (list "  %isFn = icmp eq i32 %tag, 9"
                "  br i1 %isFn, label %closure, label %notFn"
                "closure:"
                "  %protop = getelementptr inbounds i8, ptr %obj, i64 8"
                "  %proto = load ptr, ptr %protop"
                "  %codep = getelementptr inbounds i8, ptr %proto, i64 56"
                "  %code = load ptr, ptr %codep"
                "  %native = icmp ne ptr %code, null"
                "  br i1 %native, label %arity, label %bytecode"
                "arity:"
                "  %np = getelementptr inbounds i8, ptr %proto, i64 16"
                "  %n = load i32, ptr %np"
                "  %n64 = sext i32 %n to i64"
                "  %fits = icmp eq i64 %argc, %n64"
                "  br i1 %fits, label %direct, label %wrongArity"
                "direct:"
                "  %result = call %Val %code(%Val %fn, i64 %argc, ptr %argv)"
                "  ret %Val %result"
                "wrongArity:"
                "  %pname = load ptr, ptr %proto")
          (formatted "%" "ERR_ARITY" "@.objrt.arity" ", ptr %pname, i32 %n, i64 %argc")
          (list "notFn:"
                "  %isCtor = icmp eq i32 %tag, 8"
                "  br i1 %isCtor, label %ctor, label %bad"
                "ctor:"
                "  %idp = getelementptr inbounds i8, ptr %obj, i64 8"
                "  %id = load i32, ptr %idp"
                (str "  %partialId = call i32 @objrt.nameId(ptr @objrt.partialId, ptr @.objrt.partial, i64 " (stringLength (partialName)) ")")
                "  %isPartial = icmp eq i32 %id, %partialId"
                "  %cnp = getelementptr inbounds i8, ptr %obj, i64 12"
                "  %cn = load i32, ptr %cnp"
                "  %hasHead = icmp sgt i32 %cn, 0"
                "  %callable = and i1 %isPartial, %hasHead"
                "  br i1 %callable, label %partial, label %bad"
                "partial:"
                "  %cn64 = sext i32 %cn to i64"
                "  %bound = sub i64 %cn64, 1"
                "  %total = add i64 %bound, %argc"
                "  %over = icmp sgt i64 %total, 64"
                "  br i1 %over, label %tooMany, label %splice"
                "tooMany:"
                (str "  call void @rterr.raise(ptr @.rterr.c.ERR_LIMIT, ptr @.objrt.partialLimit, i64 " (stringLength (partialLimitText)) ")")
                "  unreachable"
                "splice:"
                "  %boundBytes = mul i64 %bound, 16"
                "  %boundp = getelementptr inbounds i8, ptr %obj, i64 32"
                "  call void @llvm.memcpy.p0.p0.i64(ptr %all, ptr %boundp, i64 %boundBytes, i1 false)"
                "  %argBytes = mul i64 %argc, 16"
                "  %rest = getelementptr inbounds i8, ptr %all, i64 %boundBytes"
                "  call void @llvm.memcpy.p0.p0.i64(ptr %rest, ptr %argv, i64 %argBytes, i1 false)"
                "  %headp = getelementptr inbounds i8, ptr %obj, i64 16"
                "  %head = load %Val, ptr %headp"
                "  %spliced = call %Val @objrt.call(%Val %head, i64 %total, ptr %all)"
                "  ret %Val %spliced"
                "bytecode:"
                "  %bname = load ptr, ptr %proto")
          (formatted "%b." "ERR_INTERNAL" "@.objrt.bytecode" ", ptr %bname")
          (list "bad:"
                "  %tname = call ptr @rterr.tagName(i32 %tag)"
                "  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.objrt.notFn, ptr %tname)"
                "  unreachable")))

fn aslCallFunction -> String
  (stringJoin (list "define %Val @aslCall(%Val %fn, i32 %argc, ptr %argv) {"
                    "entry:"
                    "  %n = sext i32 %argc to i64"
                    "  %result = call %Val @objrt.call(%Val %fn, i64 %n, ptr %argv)"
                    "  ret %Val %result"
                    "}")
              "\n")

fn symbolFunction -> String
  (defineFn "%Val @objrt.symbol(ptr %name) noreturn"
    (list (list "  call void @rterr.raiseText(ptr @.rterr.c.ERR_UNSUPPORTED, ptr @.objrt.symbol, ptr %name)"
                "  unreachable")))

fn rtObjectPieces -> (List (Pair String String))
  (listAppend (objConstants)
              (list (pair "@objrt.nameId" (nameIdFunction))
                    (pair "@objrt.str" (strFunction))
                    (pair "@objrt.field" (fieldFunction))
                    (pair "@objrt.variantField" (variantFieldFunction))
                    (pair "@objrt.patternArity" (patternArityFunction))
                    (pair "@objrt.capture" (captureFunction))
                    (pair "@objrt.call" (callFunction))
                    (pair "@aslCall" (aslCallFunction))
                    (pair "@objrt.symbol" (symbolFunction))))

fn rtObjectDecls -> (List String)
  (list "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)")
