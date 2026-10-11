(module asl-target-llvm/rtError
  :x [rtErrorDecls rtErrorDefinitions rtErrorDefinitionsWith rtErrorDefinitionsJoin refCloseJoin refKeysJoin rtErrorPieces RefPiece refPieces refClose refKeys refFirstKey refPlain? rtErrorTrapCodes wasmTrapImport wasmRaiseFunction tailOf]
  :i [(asl-target-llvm/rtValue :a valrt)])

fn rtErrorDecls -> (List String)
  (list
    "declare i32 @snprintf(ptr, i64, ptr, ...)"
    "declare i64 @strlen(ptr)"
    "declare i32 @strcmp(ptr, ptr)"
    "declare ptr @memchr(ptr, i32, i64)"
    "declare i64 @write(i32, ptr, i64)"
    "declare i32 @fflush(ptr)"
    "declare void @exit(i32)"
    "declare ptr @getenv(ptr)"
    "declare i32 @atexit(ptr)"
    "declare i32 @unsetenv(ptr)"
    "declare void @longjmp(ptr, i32) noreturn")

fn wasmTrapImport -> String
  "declare void @asl.trap(ptr, ptr, i32) \"wasm-import-module\"=\"asl\" \"wasm-import-name\"=\"trap\""

fn wasmRaiseFunction -> String
  "define internal void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn {\nentry:\n  %len32 = trunc i64 %len to i32\n  call void @asl.trap(ptr %code, ptr %msg, i32 %len32)\n  unreachable\n}"

fn cText sym: String text: String -> String
  (str sym " = private unnamed_addr constant [" (+ (stringLength text) 1) " x i8] c\"" text "\\00\"")

fn codeSym code: String -> String
  (str "@.rterr.c." code)

fn rtErrorTrapCodes -> (List String)
  (list "ERR_ARG" "ERR_ARITY" "ERR_ASSERT" "ERR_ASSERT_AT_INIT" "ERR_DEPTH" "ERR_DIV_ZERO" "ERR_FIELD"
        "ERR_HEAP_CYCLE" "ERR_INT_OVERFLOW" "ERR_IO" "ERR_LIMIT" "ERR_MAIN_FAILED"
        "ERR_MATCH_NONEXHAUSTIVE" "ERR_NO_ENTRY" "ERR_NOT_SERIALIZABLE" "ERR_PARQUET"
        "ERR_RANGE" "ERR_REFUTE" "ERR_SERIALIZE_SIZE" "ERR_SHAPE" "ERR_STACK_DEPTH" "ERR_TEST_FAILED" "ERR_TYPE"
        "ERR_UNKNOWN_SYMBOL" "ERR_UNSUPPORTED" "ERR_WORKER_TRAP")

fn tagNames -> (List String)
  (list "Unit" "Bool" "Int" "Float" "Keyword" "String" "List" "Record" "Variant" "Fn" "Builtin" "Bytes" "F64Array" "I64Array" "I8Array" "Handle")

fn coreMessages -> (List (Pair String String))
  (list (pair "add" "Int + leaves int64") (pair "sub" "Int - leaves int64") (pair "mul" "Int * leaves int64") (pair "div" "Int / leaves int64")
        (pair "divZero" "division by zero") (pair "modZero" "mod by zero")
        (pair "narrow" "Int narrow leaves int32") (pair "floatInt" "Float to Int leaves int64")
        (pair "intKind" "unknown integer trap %lld")
        (pair "wantInt" "compiled code expects Int, got %s") (pair "wantFloat" "compiled code expects Float, got %s")
        (pair "wantBool" "condition must be Bool, got %s") (pair "wantVariant" "match expects a variant, got %s")
        (pair "wantKind" "unknown type trap want %lld")
        (pair "noArm" "no arm matches in %s"))

fn valueMessages -> (List (Pair String String))
  (list (pair "noArmValue" "no arm matches %s in %s")
        (pair "mainFailed" "main returned %s, not (ok ...)") (pair "mainRange" "main returned (ok %lld), exit codes are 0..255")
        (pair "trapString" "trap expects String, got %s") (pair "trapCode" "trap: unknown error code %s")
        (pair "trapNewline" "trap: message must not contain a newline")
        (pair "assertBool" "assert condition must be Bool, got %s") (pair "refuteBool" "refute condition must be Bool, got %s")
        (pair "assertFailed" "assertion failed: %s") (pair "refuteFailed" "refutation failed: %s")
        (pair "refuteHeld" "refutation failed: predicate held true")
        (pair "reportFailed" "cannot register the assertion report"))

fn messages -> (List (Pair String String))
  (listAppend (coreMessages) (valueMessages))

fn messageText key: String -> String
  (fold (fn [(acc String) (p (Pair String String))] -> String (if (= (pairFirst p) key) (pairSecond p) acc)) "" (messages))

fn reportText -> String
  "%lld assertion(s) executed, %lld refutation(s) executed"

fn msgSym key: String -> String
  (str "@.rterr.m." key)

fn msgLength key: String -> String
  (str (stringLength (messageText key)))

fn raiseFixed code: String key: String -> String
  (str "  call void @rterr.raise(ptr " (codeSym code) ", ptr " (msgSym key) ", i64 " (msgLength key) ")\n  unreachable")

fn raiseText code: String key: String arg: String -> String
  (str "  call void @rterr.raiseText(ptr " (codeSym code) ", ptr " (msgSym key) ", ptr " arg ")\n  unreachable")

fn raiseNumber code: String key: String arg: String -> String
  (str "  call void @rterr.raiseNumber(ptr " (codeSym code) ", ptr " (msgSym key) ", i64 " arg ")\n  unreachable")

fn coreCodes -> (List String)
  (list "ERR_INTERNAL" "ERR_INT_OVERFLOW" "ERR_DIV_ZERO" "ERR_TYPE" "ERR_MATCH_NONEXHAUSTIVE")

fn valueCodes -> (List String)
  (filter (fn [(c String)] -> Bool (not (listContains? (coreCodes) c))) (rtErrorTrapCodes))

fn textConstants codes: (List String) texts: (List (Pair String String)) -> (List String)
  (listAppend (map (fn [(c String)] -> String (cText (codeSym c) c)) codes)
              (map (fn [(p (Pair String String))] -> String (cText (msgSym (pairFirst p)) (pairSecond p))) texts))

fn constants -> (List String)
  (listAppend
    (textConstants (coreCodes) (coreMessages))
    (listAppend
      (map (fn [(i Int64)] -> String (cText (str "@.rterr.tag." i) (optionOr (listGet (tagNames) i) "?"))) (range 0 (listLength (tagNames))))
      (list
        (cText "@.rterr.tag.unknown" "?")
        (str "@.rterr.tags = private unnamed_addr constant [" (listLength (tagNames)) " x ptr] ["
             (stringJoin (map (fn [(i Int64)] -> String (str "ptr @.rterr.tag." i)) (range 0 (listLength (tagNames)))) ", ") "]")
        (cText "@.rterr.line" "%s: %.*s"))))

fn rtErrorCoreLlvm -> (List String)
  (listAppend
    (constants)
    (list
      ""
      "define internal void @rterr.writeAll(i32 %fd, ptr %data, i64 %length) {"
      "entry:"
      "  br label %loop"
      "loop:"
      "  %offset = phi i64 [ 0, %entry ], [ %next, %more ]"
      "  %done = icmp uge i64 %offset, %length"
      "  br i1 %done, label %finish, label %once"
      "once:"
      "  %at = getelementptr i8, ptr %data, i64 %offset"
      "  %rest = sub i64 %length, %offset"
      "  %wrote = call i64 @write(i32 %fd, ptr %at, i64 %rest)"
      "  %progress = icmp sgt i64 %wrote, 0"
      "  br i1 %progress, label %more, label %finish"
      "more:"
      "  %next = add i64 %offset, %wrote"
      "  br label %loop"
      "finish:"
      "  ret void"
      "}"
      ""
      "define internal void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn {"
      "entry:"
      "  %buf = alloca [4097 x i8]"
      "  %big = icmp ugt i64 %len, 4096"
      "  %clamped = select i1 %big, i64 4096, i64 %len"
      "  %prec = trunc i64 %clamped to i32"
      "  %slot = call ptr @aslHandlerSlot()"
      "  %handler = load ptr, ptr %slot"
      "  %nested = icmp ne ptr %handler, null"
      "  br i1 %nested, label %rethrow, label %report"
      "rethrow:"
      "  %text = call ptr @aslErrorText()"
      "  %kept = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %text, i64 4096, ptr @.rterr.line, ptr %code, i32 %prec, ptr %msg)"
      "  call void @longjmp(ptr %handler, i32 1)"
      "  unreachable"
      "report:"
      "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.rterr.line, ptr %code, i32 %prec, ptr %msg)"
      "  %negative = icmp slt i32 %written, 0"
      "  %wide = sext i32 %written to i64"
      "  %over = icmp ugt i64 %wide, 4095"
      "  %cut = select i1 %over, i64 4095, i64 %wide"
      "  %count = select i1 %negative, i64 0, i64 %cut"
      "  %end = getelementptr i8, ptr %buf, i64 %count"
      "  store i8 10, ptr %end"
      "  %total = add i64 %count, 1"
      "  %flushed = call i32 @fflush(ptr null)"
      "  call void @rterr.writeAll(i32 2, ptr %buf, i64 %total)"
      "  call void @exit(i32 1)"
      "  unreachable"
      "}"
      ""
      "define internal void @rterr.raiseText(ptr %code, ptr %format, ptr %arg) noreturn {"
      "entry:"
      "  %buf = alloca [4096 x i8]"
      "  store i8 0, ptr %buf"
      "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr %format, ptr %arg)"
      "  %len = call i64 @strlen(ptr %buf)"
      "  call void @rterr.raise(ptr %code, ptr %buf, i64 %len)"
      "  unreachable"
      "}"
      ""
      "define internal void @rterr.raiseNumber(ptr %code, ptr %format, i64 %arg) noreturn {"
      "entry:"
      "  %buf = alloca [4096 x i8]"
      "  store i8 0, ptr %buf"
      "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr %format, i64 %arg)"
      "  %len = call i64 @strlen(ptr %buf)"
      "  call void @rterr.raise(ptr %code, ptr %buf, i64 %len)"
      "  unreachable"
      "}"
      ""
      "define internal ptr @rterr.tagName(i32 %tag) {"
      "entry:"
      (str "  %known = icmp ult i32 %tag, " (listLength (tagNames)))
      "  br i1 %known, label %named, label %unnamed"
      "named:"
      "  %index = zext i32 %tag to i64"
      (str "  %slot = getelementptr [" (listLength (tagNames)) " x ptr], ptr @.rterr.tags, i64 0, i64 %index")
      "  %name = load ptr, ptr %slot"
      "  ret ptr %name"
      "unnamed:"
      "  ret ptr @.rterr.tag.unknown"
      "}"
      ""
      "define internal void @rterr.int(i32 %kind) noreturn {"
      "entry:"
      "  switch i32 %kind, label %unknown [ i32 0, label %add i32 1, label %sub i32 2, label %mul i32 3, label %div i32 5, label %divZero i32 6, label %modZero i32 7, label %narrow i32 8, label %floatInt ]"
      "add:" (raiseFixed "ERR_INT_OVERFLOW" "add")
      "sub:" (raiseFixed "ERR_INT_OVERFLOW" "sub")
      "mul:" (raiseFixed "ERR_INT_OVERFLOW" "mul")
      "div:" (raiseFixed "ERR_INT_OVERFLOW" "div")
      "divZero:" (raiseFixed "ERR_DIV_ZERO" "divZero")
      "modZero:" (raiseFixed "ERR_DIV_ZERO" "modZero")
      "narrow:" (raiseFixed "ERR_INT_OVERFLOW" "narrow")
      "floatInt:" (raiseFixed "ERR_INT_OVERFLOW" "floatInt")
      "unknown:"
      "  %wide = sext i32 %kind to i64"
      (raiseNumber "ERR_INTERNAL" "intKind" "%wide")
      "}"
      ""
      "define internal void @rterr.type(i32 %got, i32 %want) noreturn {"
      "entry:"
      "  %name = call ptr @rterr.tagName(i32 %got)"
      "  switch i32 %want, label %unknown [ i32 2, label %int i32 3, label %float i32 1, label %bool i32 8, label %variant ]"
      "int:" (raiseText "ERR_TYPE" "wantInt" "%name")
      "float:" (raiseText "ERR_TYPE" "wantFloat" "%name")
      "bool:" (raiseText "ERR_TYPE" "wantBool" "%name")
      "variant:" (raiseText "ERR_TYPE" "wantVariant" "%name")
      "unknown:"
      "  %wide = sext i32 %want to i64"
      (raiseNumber "ERR_INTERNAL" "wantKind" "%wide")
      "}"
      ""
      "define internal void @rterr.match(ptr %fn) noreturn {"
      "entry:"
      (raiseText "ERR_MATCH_NONEXHAUSTIVE" "noArm" "%fn")
      "}"))

fn rtErrorValueLlvm -> (List String)
  (listAppend (textConstants (valueCodes) (valueMessages)) (list
    "@rterr.assertCount = weak global i64 0"
    "@rterr.refuteCount = weak global i64 0"
    (cText "@.rterr.ok" "ok")
    (cText "@.rterr.reportEnv" "ASL_ASSERT_REPORT")
    (str "@.rterr.reportLine = private unnamed_addr constant [" (+ (stringLength (reportText)) 2) " x i8] c\"" (reportText) "\\0A\\00\"")
    (str "@.rterr.trapCodes = private unnamed_addr constant [" (listLength (rtErrorTrapCodes)) " x ptr] ["
         (stringJoin (map (fn [(c String)] -> String (str "ptr " (codeSym c))) (rtErrorTrapCodes)) ", ") "]")
    ""
    "define internal ptr @rterr.text(%Val %s) {"
    "entry:"
    "  %word = extractvalue %Val %s, 1"
    "  %obj = inttoptr i64 %word to ptr"
    "  %data = getelementptr i8, ptr %obj, i64 16"
    "  ret ptr %data"
    "}"
    ""
    "define internal void @rterr.matchValue(%Val %v, ptr %fn) noreturn {"
    "entry:"
    "  %buf = alloca [4096 x i8]"
    "  store i8 0, ptr %buf"
    "  %shown = call %Val @asl_rt_format_val(%Val %v, i32 1, i32 8)"
    "  %shownText = call ptr @rterr.text(%Val %shown)"
    (str "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr " (msgSym "noArmValue") ", ptr %shownText, ptr %fn)")
    "  %len = call i64 @strlen(ptr %buf)"
    (str "  call void @rterr.raise(ptr " (codeSym "ERR_MATCH_NONEXHAUSTIVE") ", ptr %buf, i64 %len)")
    "  unreachable"
    "}"
    ""
    "define internal i32 @rterr.exit(%Val %r) {"
    "entry:"
    "  %word = extractvalue %Val %r, 0"
    "  %tag = trunc i64 %word to i32"
    "  %isCtor = icmp eq i32 %tag, 8"
    "  br i1 %isCtor, label %ctor, label %fail"
    "ctor:"
    "  %objword = extractvalue %Val %r, 1"
    "  %obj = inttoptr i64 %objword to ptr"
    "  %idp = getelementptr i8, ptr %obj, i64 8"
    "  %id = load i32, ptr %idp"
    "  %okId = call i32 @valrt.intern(ptr @.rterr.ok, i64 2)"
    "  %isOk = icmp eq i32 %id, %okId"
    "  br i1 %isOk, label %ok, label %fail"
    "fail:"
    "  %shown = call %Val @asl_rt_format_val(%Val %r, i32 1, i32 8)"
    "  %shownText = call ptr @rterr.text(%Val %shown)"
    (raiseText "ERR_MAIN_FAILED" "mainFailed" "%shownText")
    "ok:"
    "  %np = getelementptr i8, ptr %obj, i64 12"
    "  %n = load i32, ptr %np"
    "  %single = icmp eq i32 %n, 1"
    "  br i1 %single, label %field, label %zero"
    "field:"
    "  %fieldp = getelementptr i8, ptr %obj, i64 16"
    "  %fieldword = load i64, ptr %fieldp"
    "  %fieldtag = trunc i64 %fieldword to i32"
    "  %isInt = icmp eq i32 %fieldtag, 2"
    "  br i1 %isInt, label %int, label %zero"
    "int:"
    "  %valuep = getelementptr i8, ptr %obj, i64 24"
    "  %code = load i64, ptr %valuep"
    "  %inRange = icmp ule i64 %code, 255"
    "  br i1 %inRange, label %exit, label %range"
    "range:"
    (raiseNumber "ERR_RANGE" "mainRange" "%code")
    "exit:"
    "  %code32 = trunc i64 %code to i32"
    "  ret i32 %code32"
    "zero:"
    "  ret i32 0"
    "}"
    ""
    "define internal %Val @rterr.trap(%Val %code, %Val %msg) {"
    "entry:"
    "  %cword = extractvalue %Val %code, 0"
    "  %ctag = trunc i64 %cword to i32"
    "  %cstr = icmp eq i32 %ctag, 5"
    "  br i1 %cstr, label %codeString, label %codeType"
    "codeType:"
    "  %cname = call ptr @rterr.tagName(i32 %ctag)"
    (raiseText "ERR_TYPE" "trapString" "%cname")
    "codeString:"
    "  %mword = extractvalue %Val %msg, 0"
    "  %mtag = trunc i64 %mword to i32"
    "  %mstr = icmp eq i32 %mtag, 5"
    "  br i1 %mstr, label %msgString, label %msgType"
    "msgType:"
    "  %mname = call ptr @rterr.tagName(i32 %mtag)"
    (raiseText "ERR_TYPE" "trapString" "%mname")
    "msgString:"
    "  %ctext = call ptr @rterr.text(%Val %code)"
    "  br label %scan"
    "scan:"
    "  %i = phi i64 [ 0, %msgString ], [ %inext, %next ]"
    (str "  %exhausted = icmp uge i64 %i, " (listLength (rtErrorTrapCodes)))
    "  br i1 %exhausted, label %unknown, label %probe"
    "probe:"
    (str "  %slot = getelementptr [" (listLength (rtErrorTrapCodes)) " x ptr], ptr @.rterr.trapCodes, i64 0, i64 %i")
    "  %known = load ptr, ptr %slot"
    "  %cmp = call i32 @strcmp(ptr %ctext, ptr %known)"
    "  %same = icmp eq i32 %cmp, 0"
    "  br i1 %same, label %checkMsg, label %next"
    "next:"
    "  %inext = add i64 %i, 1"
    "  br label %scan"
    "unknown:"
    (raiseText "ERR_TYPE" "trapCode" "%ctext")
    "checkMsg:"
    "  %mobjword = extractvalue %Val %msg, 1"
    "  %mobj = inttoptr i64 %mobjword to ptr"
    "  %mlenp = getelementptr i8, ptr %mobj, i64 8"
    "  %mlen = load i64, ptr %mlenp"
    "  %mtext = getelementptr i8, ptr %mobj, i64 16"
    "  %newline = call ptr @memchr(ptr %mtext, i32 10, i64 %mlen)"
    "  %hasNewline = icmp ne ptr %newline, null"
    "  br i1 %hasNewline, label %badMsg, label %raise"
    "badMsg:"
    (raiseFixed "ERR_TYPE" "trapNewline")
    "raise:"
    "  call void @rterr.raise(ptr %ctext, ptr %mtext, i64 %mlen)"
    "  unreachable"
    "}"
    ""
    "define internal void @rterr.assert(%Val %c, %Val %m) {"
    "entry:"
    "  %word = extractvalue %Val %c, 0"
    "  %tag = trunc i64 %word to i32"
    "  %isBool = icmp eq i32 %tag, 1"
    "  br i1 %isBool, label %count, label %type"
    "type:"
    "  %name = call ptr @rterr.tagName(i32 %tag)"
    (raiseText "ERR_TYPE" "assertBool" "%name")
    "count:"
    "  %before = load i64, ptr @rterr.assertCount"
    "  %after = add i64 %before, 1"
    "  store i64 %after, ptr @rterr.assertCount"
    "  %bits = extractvalue %Val %c, 1"
    "  %held = icmp ne i64 %bits, 0"
    "  br i1 %held, label %pass, label %fail"
    "pass:"
    "  ret void"
    "fail:"
    "  %shown = call %Val @asl_rt_format_val(%Val %m, i32 0, i32 8)"
    "  %shownText = call ptr @rterr.text(%Val %shown)"
    (raiseText "ERR_ASSERT" "assertFailed" "%shownText")
    "}"
    ""
    "define internal void @rterr.refute(%Val %c, %Val %m) {"
    "entry:"
    "  %word = extractvalue %Val %c, 0"
    "  %tag = trunc i64 %word to i32"
    "  %isBool = icmp eq i32 %tag, 1"
    "  br i1 %isBool, label %count, label %type"
    "type:"
    "  %name = call ptr @rterr.tagName(i32 %tag)"
    (raiseText "ERR_TYPE" "refuteBool" "%name")
    "count:"
    "  %before = load i64, ptr @rterr.refuteCount"
    "  %after = add i64 %before, 1"
    "  store i64 %after, ptr @rterr.refuteCount"
    "  %bits = extractvalue %Val %c, 1"
    "  %held = icmp ne i64 %bits, 0"
    "  br i1 %held, label %fail, label %pass"
    "pass:"
    "  ret void"
    "fail:"
    "  %mword = extractvalue %Val %m, 0"
    "  %mtag = trunc i64 %mword to i32"
    "  %bare = icmp eq i32 %mtag, 0"
    "  br i1 %bare, label %held.bare, label %held.message"
    "held.bare:"
    (raiseFixed "ERR_REFUTE" "refuteHeld")
    "held.message:"
    "  %shown = call %Val @asl_rt_format_val(%Val %m, i32 0, i32 8)"
    "  %shownText = call ptr @rterr.text(%Val %shown)"
    (raiseText "ERR_REFUTE" "refuteFailed" "%shownText")
    "}"
    ""
    "define internal void @rterr.report() {"
    "entry:"
    "  %buf = alloca [128 x i8]"
    "  store i8 0, ptr %buf"
    "  %asserts = load i64, ptr @rterr.assertCount"
    "  %refutes = load i64, ptr @rterr.refuteCount"
    "  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 128, ptr @.rterr.reportLine, i64 %asserts, i64 %refutes)"
    "  %len = call i64 @strlen(ptr %buf)"
    "  call void @rterr.writeAll(i32 2, ptr %buf, i64 %len)"
    "  ret void"
    "}"
    ""
    "define internal void @rterr.reportInit() {"
    "entry:"
    "  %env = call ptr @getenv(ptr @.rterr.reportEnv)"
    "  %set = icmp ne ptr %env, null"
    "  br i1 %set, label %check, label %done"
    "check:"
    "  %first = load i8, ptr %env"
    "  %one = icmp eq i8 %first, 49"
    "  br i1 %one, label %install, label %done"
    "install:"
    "  %rc = call i32 @atexit(ptr @rterr.report)"
    "  %uc = call i32 @unsetenv(ptr @.rterr.reportEnv)"
    "  %failed = icmp ne i32 %rc, 0"
    "  br i1 %failed, label %fail, label %done"
    "fail:"
    (raiseFixed "ERR_INTERNAL" "reportFailed")
    "done:"
    "  ret void"
    "}"))

(schema PieceScan (:f done (List (Pair String String))) (:f name String) (:f body (List String)))

(schema RefPiece (:f name String) (:f body String) (:f keys (List String)) (:f plain Bool))

fn pieceName line: String -> String
  (let [(at (optionOr (stringIndexOf line "@") 0))
        (rest (optionOr (stringSlice line at (stringLength line)) ""))
        (stop (if (stringStartsWith? line "@")
                (optionOr (stringIndexOf rest " = ") (stringLength rest))
                (optionOr (stringIndexOf rest "(") (stringLength rest))))]
    (optionOr (stringSlice rest 0 stop) rest))

fn scanLine acc: PieceScan line: String -> PieceScan
  (cond
    ((not (stringEmpty? acc.name))
      (if (= line "}")
        (PieceScan :done (cons (pair acc.name (stringJoin (listReverse (cons line acc.body)) "\n")) acc.done) :name "" :body (list))
        (with acc :body (cons line acc.body))))
    ((stringStartsWith? line "define ") (with acc :name (pieceName line) :body (list line)))
    ((stringStartsWith? line "@") (PieceScan :done (cons (pair (pieceName line) line) acc.done) :name "" :body (list)))
    (else acc))

fn piecesOf lines: (List String) -> (List (Pair String String))
  (listReverse (fold scanLine (PieceScan :done (list) :name "" :body (list)) (stringSplit (stringJoin lines "\n") "\n")).done)

fn refDelimiters -> (List String)
  (list "(" ")" "," " " "]" "\n")

fn refStop? c: Int64 -> Bool
  (or (= c 64) (or (= c 40) (or (= c 41) (or (= c 44) (or (= c 32) (or (= c 93) (= c 10)))))))

fn refEnd b: Bytes n: Int64 j: Int64 -> Int64
  (cond
    ((>= j n) n)
    ((refStop? (bytesGet b j)) j)
    (else (refEnd b n (+ j 1))))

fn refAdd acc: (Map String Bool) k: String -> (Map String Bool)
  (if (mapHas? acc k) acc (mapSet acc k true))

fn refKeysFrom text: String b: Bytes n: Int64 endNl: Bool i: Int64 acc: (Map String Bool) -> (Map String Bool)
  (cond
    ((>= i n) acc)
    ((!= (bytesGet b i) 64) (refKeysFrom text b n endNl (+ i 1) acc))
    (else (let [(j (refEnd b n (+ i 1)))]
            (cond
              ((and (< j n) (!= (bytesGet b j) 64)) (refKeysFrom text b n endNl (+ j 1) (refAdd acc (optionOr (stringSlice text i (+ j 1)) ""))))
              ((and (>= j n) endNl) (refAdd acc (str (optionOr (stringSlice text i n) "") "\n")))
              (else (refKeysFrom text b n endNl j acc))))))

fn refKeysInto acc: (Map String Bool) text: String endNl: Bool -> (Map String Bool)
  (let [(b (stringToBytes text))]
    (refKeysFrom text b (bytesLength b) endNl 0 acc))

fn refKeys text: String -> (Map String Bool)
  (refKeysInto (mapEmpty) text false)

fn refKeysJoin acc: (Map String Bool) chunks: (List String) -> (Map String Bool)
  (mt (listHead chunks)
    ((none) acc)
    ((some c) (let [(rest (optionOr (listTail chunks) (list)))]
                (refKeysJoin (refKeysInto acc c (not (listEmpty? rest))) rest))))

fn tailSuffix rev: (List String) acc: (List String) size: Int64 -> (List String)
  (mt (listHead rev)
    ((none) acc)
    ((some c) (if (>= size 256)
                acc
                (tailSuffix (optionOr (listTail rev) (list)) (cons c acc) (+ size (+ (stringLength c) 1))))))

fn tailOfJoin chunks: (List String) -> String
  (tailOf (stringJoin (tailSuffix (listReverse chunks) (list) 0) "\n"))

fn refFirstFrom text: String b: Bytes n: Int64 i: Int64 -> (Option String)
  (cond
    ((>= i n) (none))
    ((!= (bytesGet b i) 64) (refFirstFrom text b n (+ i 1)))
    (else (let [(j (refEnd b n (+ i 1)))]
            (if (and (< j n) (!= (bytesGet b j) 64))
              (stringSlice text i (+ j 1))
              (refFirstFrom text b n j)))))

fn refFirstKey text: String -> (Option String)
  (let [(b (stringToBytes text))]
    (refFirstFrom text b (bytesLength b) 0))

fn refPlain? name: String -> Bool
  (and (stringStartsWith? name "@")
       (let [(b (stringToBytes name))]
         (= (refEnd b (bytesLength b) 1) (bytesLength b))))

fn refPiece delims: (List String) p: (Pair String String) -> RefPiece
  (RefPiece :name (pairFirst p) :body (pairSecond p) :keys (map (fn [(d String)] -> String (str (pairFirst p) d)) delims) :plain (refPlain? (pairFirst p)))

fn refPieces delims: (List String) pieces: (List (Pair String String)) -> (List RefPiece)
  (map (fn [(p (Pair String String))] -> RefPiece (refPiece delims p)) pieces)

fn refersVia? keys: (Map String Bool) text: String p: RefPiece -> Bool
  (if p.plain
    (listAny? (fn [(k String)] -> Bool (mapHas? keys k)) p.keys)
    (listAny? (fn [(k String)] -> Bool (stringContains? text k)) p.keys))

fn tailOf text: String -> String
  (optionOr (stringSlice text (if (> (stringLength text) 256) (- (stringLength text) 256) 0) (stringLength text)) text)

fn refClose text: String chosen: (Map String Bool) pieces: (List RefPiece) -> (Map String Bool)
  (refCloseStep (refKeys text) text (tailOf text) chosen pieces)

fn refCloseStep keys: (Map String Bool) text: String tail: String chosen: (Map String Bool) pieces: (List RefPiece) -> (Map String Bool)
  (let [(fresh (filter (fn [(p RefPiece)] -> Bool (and (not (mapHas? chosen p.name)) (refersVia? keys text p))) pieces))]
    (if (listEmpty? fresh)
      chosen
      (refClose (str tail "\n" (stringJoin (map (fn [(p RefPiece)] -> String p.body) fresh) "\n"))
                (fold (fn [(m (Map String Bool)) (p RefPiece)] -> (Map String Bool) (mapSet m p.name true)) chosen fresh)
                pieces)))

fn refCloseJoin chunks: (List String) pieces: (List RefPiece) -> (Map String Bool)
  (refCloseStep (refKeysJoin (mapEmpty) chunks)
                (if (listAll? (fn [(p RefPiece)] -> Bool p.plain) pieces) "" (stringJoin chunks "\n"))
                (tailOfJoin chunks) (mapEmpty) pieces)

fn rtErrorPieces -> (List RefPiece)
  (refPieces (refDelimiters) (piecesOf (listAppend (listAppend (rtErrorCoreLlvm) (rtErrorValueLlvm)) (valrt/rtValueLlvm))))

fn rtErrorChosen pieces: (List RefPiece) chosen: (Map String Bool) -> (List String)
  (map (fn [(p RefPiece)] -> String (if (stringStartsWith? p.body "@") p.body (str "\n" p.body)))
       (filter (fn [(p RefPiece)] -> Bool (mapHas? chosen p.name)) pieces))

fn rtErrorDefinitionsJoin pieces: (List RefPiece) chunks: (List String) -> (List String)
  (rtErrorChosen pieces (refCloseJoin chunks pieces))

fn rtErrorDefinitionsWith pieces: (List RefPiece) text: String -> (List String)
  (let [(chosen (refClose text (mapEmpty) pieces))]
    (map (fn [(p RefPiece)] -> String (if (stringStartsWith? p.body "@") p.body (str "\n" p.body)))
         (filter (fn [(p RefPiece)] -> Bool (mapHas? chosen p.name)) pieces)))

fn rtErrorDefinitions text: String -> (List String)
  (rtErrorDefinitionsWith (rtErrorPieces) text)
