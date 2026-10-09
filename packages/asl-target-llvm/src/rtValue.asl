(module asl-target-llvm/rtValue
  :x [rtValueLlvm rtValueDecls rtValueDefines? rtValueExportRoots valueShimNames]
  :i [])

fn valText sym: String text: String -> String
  (str sym " = private unnamed_addr constant [" (+ (stringLength text) 1) " x i8] c\"" text "\\00\"")

fn kwSymbols -> (List String)
  (list "@KW_SOME" "@KW_NONE" "@KW_OK" "@KW_ERR" "@KW_PARTIAL")

fn tagNames -> (List String)
  (list "Unit" "Bool" "Int" "Float" "Keyword" "String" "List" "Record" "Variant" "Fn" "Builtin" "Bytes" "F64Array" "I64Array" "I8Array" "Handle")

fn vaMarker -> String
  "6510615555426900570"

fn storage -> (List String)
  (list "@valrt.slots = weak global ptr null"
        "@valrt.capacity = weak global i64 0"
        "@valrt.names = weak global ptr null"
        "@valrt.count = weak global i64 0"
        "@valrt.room = weak global i64 0"
        "@valrt.handler = weak global ptr null"
        "@valrt.errorMsg = weak global [4096 x i8] zeroinitializer")

fn constants -> (List String)
  (listAppend
    (list (valText "@.valrt.unknown" "?"))
    (listAppend
      (map (fn [(i Int64)] -> String (valText (str "@.valrt.tag." i) (optionOr (listGet (tagNames) i) "?"))) (range 0 (listLength (tagNames))))
      (list (str "@.valrt.tags = private unnamed_addr constant [" (listLength (tagNames)) " x ptr] ["
                 (stringJoin (map (fn [(i Int64)] -> String (str "ptr @.valrt.tag." i)) (range 0 (listLength (tagNames)))) ", ") "]"))))

fn hashFunction -> (List String)
  (list "define internal i64 @valrt.hash(ptr %text, i64 %length) {"
        "entry:"
        "  br label %loop"
        "loop:"
        "  %i = phi i64 [ 0, %entry ], [ %next, %step ]"
        "  %h = phi i64 [ 1469598103934665603, %entry ], [ %mixed, %step ]"
        "  %done = icmp uge i64 %i, %length"
        "  br i1 %done, label %out, label %step"
        "step:"
        "  %at = getelementptr inbounds i8, ptr %text, i64 %i"
        "  %byte = load i8, ptr %at"
        "  %wide = zext i8 %byte to i64"
        "  %folded = xor i64 %h, %wide"
        "  %mixed = mul i64 %folded, 1099511628211"
        "  %next = add i64 %i, 1"
        "  br label %loop"
        "out:"
        "  ret i64 %h"
        "}")

fn placeFunction -> (List String)
  (list "define internal void @valrt.place(ptr %slots, i64 %mask, i64 %id) {"
        "entry:"
        "  %names = load ptr, ptr @valrt.names"
        "  %offset = mul i64 %id, 16"
        "  %record = getelementptr inbounds i8, ptr %names, i64 %offset"
        "  %text = load ptr, ptr %record"
        "  %lengthp = getelementptr inbounds i8, ptr %record, i64 8"
        "  %length = load i64, ptr %lengthp"
        "  %h = call i64 @valrt.hash(ptr %text, i64 %length)"
        "  %start = and i64 %h, %mask"
        "  br label %probe"
        "probe:"
        "  %j = phi i64 [ %start, %entry ], [ %after, %taken ]"
        "  %slotp = getelementptr inbounds i32, ptr %slots, i64 %j"
        "  %slot = load i32, ptr %slotp"
        "  %free = icmp eq i32 %slot, 0"
        "  br i1 %free, label %store, label %taken"
        "taken:"
        "  %stepped = add i64 %j, 1"
        "  %after = and i64 %stepped, %mask"
        "  br label %probe"
        "store:"
        "  %id32 = trunc i64 %id to i32"
        "  %mark = add i32 %id32, 1"
        "  store i32 %mark, ptr %slotp"
        "  ret void"
        "}")

fn growFunction -> (List String)
  (list "define internal void @valrt.grow(i64 %capacity) {"
        "entry:"
        "  %fresh = call ptr @calloc(i64 %capacity, i64 4)"
        "  %failed = icmp eq ptr %fresh, null"
        "  br i1 %failed, label %oom, label %fill"
        "oom:"
        "  call void @exit(i32 70)"
        "  unreachable"
        "fill:"
        "  %mask = sub i64 %capacity, 1"
        "  %count = load i64, ptr @valrt.count"
        "  br label %loop"
        "loop:"
        "  %id = phi i64 [ 0, %fill ], [ %next, %body ]"
        "  %more = icmp ult i64 %id, %count"
        "  br i1 %more, label %body, label %done"
        "body:"
        "  call void @valrt.place(ptr %fresh, i64 %mask, i64 %id)"
        "  %next = add i64 %id, 1"
        "  br label %loop"
        "done:"
        "  %old = load ptr, ptr @valrt.slots"
        "  call void @free(ptr %old)"
        "  store ptr %fresh, ptr @valrt.slots"
        "  store i64 %capacity, ptr @valrt.capacity"
        "  ret void"
        "}")

fn addFunction -> (List String)
  (list "define internal i32 @valrt.add(ptr %text, i64 %length, ptr %slotp) {"
        "entry:"
        "  %count = load i64, ptr @valrt.count"
        "  %full = icmp uge i64 %count, 2147483646"
        "  br i1 %full, label %oom, label %copy"
        "copy:"
        "  %size = add i64 %length, 1"
        "  %bytes = call ptr @malloc(i64 %size)"
        "  %noBytes = icmp eq ptr %bytes, null"
        "  br i1 %noBytes, label %oom, label %fill"
        "fill:"
        "  call void @llvm.memcpy.p0.p0.i64(ptr %bytes, ptr %text, i64 %length, i1 false)"
        "  %end = getelementptr inbounds i8, ptr %bytes, i64 %length"
        "  store i8 0, ptr %end"
        "  %room = load i64, ptr @valrt.room"
        "  %fits = icmp ult i64 %count, %room"
        "  br i1 %fits, label %record, label %widen"
        "widen:"
        "  %none = icmp eq i64 %room, 0"
        "  %doubled = shl i64 %room, 1"
        "  %wider = select i1 %none, i64 1024, i64 %doubled"
        "  %wideBytes = mul i64 %wider, 16"
        "  %old = load ptr, ptr @valrt.names"
        "  %grown = call ptr @realloc(ptr %old, i64 %wideBytes)"
        "  %noRoom = icmp eq ptr %grown, null"
        "  br i1 %noRoom, label %oom, label %widened"
        "widened:"
        "  store ptr %grown, ptr @valrt.names"
        "  store i64 %wider, ptr @valrt.room"
        "  br label %record"
        "record:"
        "  %names = load ptr, ptr @valrt.names"
        "  %offset = mul i64 %count, 16"
        "  %entry.record = getelementptr inbounds i8, ptr %names, i64 %offset"
        "  store ptr %bytes, ptr %entry.record"
        "  %lengthp = getelementptr inbounds i8, ptr %entry.record, i64 8"
        "  store i64 %length, ptr %lengthp"
        "  %id = trunc i64 %count to i32"
        "  %mark = add i32 %id, 1"
        "  store i32 %mark, ptr %slotp"
        "  %next = add i64 %count, 1"
        "  store i64 %next, ptr @valrt.count"
        "  ret i32 %id"
        "oom:"
        "  call void @exit(i32 70)"
        "  unreachable"
        "}")

fn findFunction -> (List String)
  (list "define internal i32 @valrt.find(ptr %text, i64 %length) {"
        "entry:"
        "  %count = load i64, ptr @valrt.count"
        "  %capacity = load i64, ptr @valrt.capacity"
        "  %twice = shl i64 %count, 1"
        "  %crowded = icmp uge i64 %twice, %capacity"
        "  br i1 %crowded, label %grow, label %ready"
        "grow:"
        "  %empty = icmp eq i64 %capacity, 0"
        "  %doubled = shl i64 %capacity, 1"
        "  %bigger = select i1 %empty, i64 1024, i64 %doubled"
        "  call void @valrt.grow(i64 %bigger)"
        "  br label %ready"
        "ready:"
        "  %slots = load ptr, ptr @valrt.slots"
        "  %size = load i64, ptr @valrt.capacity"
        "  %mask = sub i64 %size, 1"
        "  %names = load ptr, ptr @valrt.names"
        "  %h = call i64 @valrt.hash(ptr %text, i64 %length)"
        "  %start = and i64 %h, %mask"
        "  br label %probe"
        "probe:"
        "  %j = phi i64 [ %start, %ready ], [ %after, %differ ]"
        "  %slotp = getelementptr inbounds i32, ptr %slots, i64 %j"
        "  %slot = load i32, ptr %slotp"
        "  %free = icmp eq i32 %slot, 0"
        "  br i1 %free, label %add, label %compare"
        "compare:"
        "  %id = sub i32 %slot, 1"
        "  %wide = zext i32 %id to i64"
        "  %offset = mul i64 %wide, 16"
        "  %record = getelementptr inbounds i8, ptr %names, i64 %offset"
        "  %lengthp = getelementptr inbounds i8, ptr %record, i64 8"
        "  %known = load i64, ptr %lengthp"
        "  %sameLength = icmp eq i64 %known, %length"
        "  br i1 %sameLength, label %bytes, label %differ"
        "bytes:"
        "  %name = load ptr, ptr %record"
        "  %order = call i32 @memcmp(ptr %name, ptr %text, i64 %length)"
        "  %same = icmp eq i32 %order, 0"
        "  br i1 %same, label %found, label %differ"
        "found:"
        "  ret i32 %id"
        "differ:"
        "  %stepped = add i64 %j, 1"
        "  %after = and i64 %stepped, %mask"
        "  br label %probe"
        "add:"
        "  %fresh = call i32 @valrt.add(ptr %text, i64 %length, ptr %slotp)"
        "  ret i32 %fresh"
        "}")

fn internFunction -> (List String)
  (list "define weak i32 @aslInternShared(ptr %text, i64 %length) {"
        "entry:"
        "  %id = call i32 @valrt.find(ptr %text, i64 %length)"
        "  ret i32 %id"
        "}"
        ""
        "define internal i32 @valrt.intern(ptr %text, i64 %length) {"
        "entry:"
        "  %id = call i32 @aslInternShared(ptr %text, i64 %length)"
        "  ret i32 %id"
        "}")

fn symNameFunction -> (List String)
  (list "define weak ptr @aslSymNameShared(i32 %id) {"
        "entry:"
        "  %count = load i64, ptr @valrt.count"
        "  %wide = sext i32 %id to i64"
        "  %nonNegative = icmp sge i64 %wide, 0"
        "  %below = icmp slt i64 %wide, %count"
        "  %known = and i1 %nonNegative, %below"
        "  br i1 %known, label %named, label %unknown"
        "named:"
        "  %names = load ptr, ptr @valrt.names"
        "  %offset = mul i64 %wide, 16"
        "  %record = getelementptr inbounds i8, ptr %names, i64 %offset"
        "  %text = load ptr, ptr %record"
        "  ret ptr %text"
        "unknown:"
        "  ret ptr @.valrt.unknown"
        "}"
        ""
        "define internal ptr @valrt.symName(i32 %id) {"
        "entry:"
        "  %text = call ptr @aslSymNameShared(i32 %id)"
        "  ret ptr %text"
        "}")

fn raiseStateFunctions -> (List String)
  (list "define weak ptr @aslHandlerSlot() {"
        "entry:"
        "  ret ptr @valrt.handler"
        "}"
        ""
        "define weak ptr @aslErrorText() {"
        "entry:"
        "  ret ptr @valrt.errorMsg"
        "}")

fn failBody -> (List String)
  (list "  %list = alloca [4 x i64], align 16"
        "  %markp = getelementptr inbounds i64, ptr %list, i64 1"
        (str "  store i64 " (vaMarker) ", ptr %markp")
        "  call void @llvm.va_start(ptr %list)"
        "  %mark = load i64, ptr %markp"
        (str "  %pointerOnly = icmp eq i64 %mark, " (vaMarker))
        "  %pointer = load ptr, ptr %list"
        "  %passed = select i1 %pointerOnly, ptr %pointer, ptr %list"
        "  %buf = alloca [4096 x i8]"
        "  store i8 0, ptr %buf"
        "  %written = call i32 @vsnprintf(ptr %buf, i64 4096, ptr %format, ptr %passed)"
        "  call void @llvm.va_end(ptr %list)"
        "  %length = call i64 @strlen(ptr %buf)"
        "  call void @rterr.raise(ptr %code, ptr %buf, i64 %length)"
        "  unreachable")

fn strFunction -> (List String)
  (list "define internal %Val @valrt.str(ptr %text, i64 %length) {"
        "entry:"
        "  %size = add i64 %length, 17"
        "  %object = call ptr @asl_alloc(i32 0, i64 %size)"
        "  %lengthp = getelementptr inbounds i8, ptr %object, i64 8"
        "  store i64 %length, ptr %lengthp"
        "  %data = getelementptr inbounds i8, ptr %object, i64 16"
        "  call void @llvm.memcpy.p0.p0.i64(ptr %data, ptr %text, i64 %length, i1 false)"
        "  %end = getelementptr inbounds i8, ptr %data, i64 %length"
        "  store i8 0, ptr %end"
        "  %word = ptrtoint ptr %object to i64"
        "  %value = insertvalue %Val { i64 5, i64 0 }, i64 %word, 1"
        "  ret %Val %value"
        "}")

fn argsFunction -> (List String)
  (list "define internal %Val @valrt.args(i32 %argc, ptr %argv) {"
        "entry:"
        "  %last = sext i32 %argc to i64"
        "  br label %loop"
        "loop:"
        "  %i = phi i64 [ %last, %entry ], [ %prior, %body ]"
        "  %list = phi %Val [ { i64 6, i64 0 }, %entry ], [ %cell, %body ]"
        "  %prior = sub i64 %i, 1"
        "  %more = icmp sge i64 %prior, 1"
        "  br i1 %more, label %body, label %done"
        "body:"
        "  %slot = getelementptr inbounds ptr, ptr %argv, i64 %prior"
        "  %arg = load ptr, ptr %slot"
        "  %length = call i64 @strlen(ptr %arg)"
        "  %text = call %Val @valrt.str(ptr %arg, i64 %length)"
        "  %object = call ptr @asl_alloc(i32 1, i64 40)"
        "  %carp = getelementptr inbounds i8, ptr %object, i64 8"
        "  store %Val %text, ptr %carp"
        "  %cdrp = getelementptr inbounds i8, ptr %object, i64 24"
        "  store %Val %list, ptr %cdrp"
        "  %word = ptrtoint ptr %object to i64"
        "  %cell = insertvalue %Val { i64 6, i64 0 }, i64 %word, 1"
        "  br label %loop"
        "done:"
        "  ret %Val %list"
        "}")

fn shimHeaders -> (List (Pair String String))
  (list (pair "intern" "define internal i32 @intern(ptr %text, i64 %length) {")
        (pair "symName" "define internal ptr @symName(i32 %id) {")
        (pair "mkStr" "define internal %Val @mkStr(ptr %text, i64 %length) {")
        (pair "valToCStrN" "define internal ptr @valToCStrN(%Val %v, i32 %repr, ptr %lengthp) {")
        (pair "valToCStr" "define internal ptr @valToCStr(%Val %v, i32 %repr) {")
        (pair "aslError" "define internal i64 @aslError(ptr %code, ptr %format, ...) noreturn {")
        (pair "aslErrorHandlerGet" "define internal ptr @aslErrorHandlerGet() {")
        (pair "aslErrorHandlerSet" "define internal i64 @aslErrorHandlerSet(ptr %handler) {")
        (pair "tagName" "define weak ptr @tagName(i32 %tag) {")
        (pair "mkCtor" "define weak %Val @mkCtor(i32 %id, i32 %count) {"))

fn valueShimNames -> (List String)
  (map (fn [(p (Pair String String))] -> String (pairFirst p)) (shimHeaders))

fn header name: String -> String
  (fold (fn [(acc String) (p (Pair String String))] -> String (if (= (pairFirst p) name) (pairSecond p) acc)) "" (shimHeaders))

fn shim name: String body: (List String) -> (List String)
  (listAppend (list (header name) "entry:") (listAppend body (list "}")))

fn shimFunctions -> (List String)
  (listAppend (listAppend (listAppend (listAppend
    (shim "intern" (list "  %id = call i32 @valrt.intern(ptr %text, i64 %length)" "  ret i32 %id"))
    (shim "symName" (list "  %text = call ptr @valrt.symName(i32 %id)" "  ret ptr %text")))
    (listAppend
      (shim "mkStr" (list "  %value = call %Val @valrt.str(ptr %text, i64 %length)" "  ret %Val %value"))
      (shim "valToCStrN"
        (list "  %buf = alloca %RtFormatBuf"
              "  %datap = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 0"
              "  %usedp = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 1"
              "  %roomp = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 2"
              "  store ptr null, ptr %datap"
              "  store i64 0, ptr %usedp"
              "  store i64 0, ptr %roomp"
              "  call void @rtfmt_render(ptr %buf, %Val %v, i32 %repr, i32 0, i32 -1)"
              "  %data = load ptr, ptr %datap"
              "  %used = load i64, ptr %usedp"
              "  %empty = icmp eq ptr %data, null"
              "  br i1 %empty, label %blank, label %done"
              "blank:"
              "  %one = call ptr @malloc(i64 1)"
              "  %lost = icmp eq ptr %one, null"
              "  br i1 %lost, label %oom, label %terminated"
              "terminated:"
              "  store i8 0, ptr %one"
              "  br label %done"
              "oom:"
              "  call void @exit(i32 70)"
              "  unreachable"
              "done:"
              "  %text = phi ptr [ %data, %entry ], [ %one, %terminated ]"
              "  store i64 %used, ptr %lengthp"
              "  ret ptr %text"))))
    (listAppend
      (shim "valToCStr" (list "  %lengthp = alloca i64" "  %text = call ptr @valToCStrN(%Val %v, i32 %repr, ptr %lengthp)" "  ret ptr %text"))
      (shim "aslError" (failBody))))
    (listAppend
      (listAppend
        (shim "aslErrorHandlerGet" (list "  %slot = call ptr @aslHandlerSlot()" "  %handler = load ptr, ptr %slot" "  ret ptr %handler"))
        (shim "aslErrorHandlerSet" (list "  %slot = call ptr @aslHandlerSlot()" "  store ptr %handler, ptr %slot" "  ret i64 0")))
      (listAppend
        (shim "tagName"
          (list (str "  %known = icmp ult i32 %tag, " (listLength (tagNames)))
                "  br i1 %known, label %named, label %unnamed"
                "named:"
                "  %index = zext i32 %tag to i64"
                (str "  %slot = getelementptr [" (listLength (tagNames)) " x ptr], ptr @.valrt.tags, i64 0, i64 %index")
                "  %name = load ptr, ptr %slot"
                "  ret ptr %name"
                "unnamed:"
                "  ret ptr @.valrt.unknown"))
        (shim "mkCtor"
          (list "  %wide = zext i32 %count to i64"
                "  %fields = mul i64 %wide, 16"
                "  %size = add i64 %fields, 16"
                "  %object = call ptr @asl_alloc(i32 3, i64 %size)"
                "  %idp = getelementptr inbounds i8, ptr %object, i64 8"
                "  store i32 %id, ptr %idp"
                "  %countp = getelementptr inbounds i8, ptr %object, i64 12"
                "  store i32 %count, ptr %countp"
                "  %word = ptrtoint ptr %object to i64"
                "  %value = insertvalue %Val { i64 8, i64 0 }, i64 %word, 1"
                "  ret %Val %value")))))

fn kwGlobals -> (List String)
  (map (fn [(k String)] -> String (str k " = weak global i32 0")) (kwSymbols))

fn rtValueLlvm -> (List String)
  (listAppend (listAppend (listAppend (storage) (constants)) (kwGlobals))
    (listAppend
      (fold (fn [(acc (List String)) (f (List String))] -> (List String) (listAppend acc (listAppend f (list ""))))
            (list)
            (list (hashFunction) (placeFunction) (growFunction) (addFunction) (findFunction) (internFunction)
                  (symNameFunction) (raiseStateFunctions) (strFunction) (argsFunction)))
      (shimFunctions)))

fn rtValueExportRoots -> String
  (str (stringJoin (kwSymbols) " ") " @tagName( @mkCtor( @aslInternShared(")

fn rtValueDecls -> (List String)
  (list "declare ptr @calloc(i64, i64)"
        "declare ptr @malloc(i64)"
        "declare ptr @realloc(ptr, i64)"
        "declare void @free(ptr)"
        "declare i32 @memcmp(ptr, ptr, i64)"
        "declare i64 @strlen(ptr)"
        "declare void @exit(i32)"
        "declare i32 @vsnprintf(ptr, i64, ptr, ptr)"
        "declare void @llvm.va_start(ptr)"
        "declare void @llvm.va_end(ptr)"
        "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)"
        "declare void @longjmp(ptr, i32) noreturn")

fn rtValueDefines? text: String name: String -> Bool
  (let [(h (header name))]
    (and (not (stringEmpty? h)) (stringContains? text h)))
