(module asl-target-llvm/ffiRt
  :x [ffiRtNames ffiRtPieces handleTag]
  :i [])

; (:m :ref FFI2 :do "a Handle is the collector's Handle object (type 7, a large object: C pointer at 16, finaliser at 24) behind a Val of tag 15; the sweep calls fin(p) on an unreachable open handle, and a close clears both words so it never runs twice")
fn handleTag -> Int64
  15

fn ffiRtNames -> (List String)
  (list "ffiMkHandle" "ffiHandlePtr" "ffiHandleFin" "ffiHandleClear")

fn objOf -> (List String)
  (list "  %tagw = extractvalue %Val %h, 0"
        "  %tag = trunc i64 %tagw to i32"
        (str "  %isHandle = icmp eq i32 %tag, " (handleTag))
        "  br i1 %isHandle, label %open, label %none"
        "open:"
        "  %objw = extractvalue %Val %h, 1"
        "  %obj = inttoptr i64 %objw to ptr")

fn mkHandleText -> String
  (stringJoin (list
    "define internal %Val @ffiMkHandle(ptr %p, ptr %fin) {"
    "entry:"
    "  %obj = call ptr @asl_alloc(i32 7, i64 32)"
    "  %pp = getelementptr inbounds i8, ptr %obj, i64 16"
    "  store ptr %p, ptr %pp"
    "  %fp = getelementptr inbounds i8, ptr %obj, i64 24"
    "  store ptr %fin, ptr %fp"
    "  %objw = ptrtoint ptr %obj to i64"
    (str "  %v = insertvalue %Val { i64 " (handleTag) ", i64 0 }, i64 %objw, 1")
    "  ret %Val %v"
    "}") "\n")

fn loadText name: String offset: Int64 -> String
  (stringJoin (listAppend (cons (str "define internal ptr @" name "(%Val %h) {") (cons "entry:" (objOf)))
                          (list (str "  %at = getelementptr inbounds i8, ptr %obj, i64 " offset)
                                "  %p = load ptr, ptr %at"
                                "  ret ptr %p"
                                "none:"
                                "  ret ptr null"
                                "}")) "\n")

fn clearText -> String
  (stringJoin (listAppend (cons "define internal i64 @ffiHandleClear(%Val %h) {" (cons "entry:" (objOf)))
                          (list "  %pp = getelementptr inbounds i8, ptr %obj, i64 16"
                                "  store ptr null, ptr %pp"
                                "  %fp = getelementptr inbounds i8, ptr %obj, i64 24"
                                "  store ptr null, ptr %fp"
                                "  ret i64 0"
                                "none:"
                                "  ret i64 0"
                                "}")) "\n")

fn ffiRtPieces -> (List (Pair String String))
  (list (pair "@ffiMkHandle" (mkHandleText))
        (pair "@ffiHandlePtr" (loadText "ffiHandlePtr" 16))
        (pair "@ffiHandleFin" (loadText "ffiHandleFin" 24))
        (pair "@ffiHandleClear" (clearText)))
