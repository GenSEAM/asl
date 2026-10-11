(module asl-target-llvm/rtFloor
  :x [floorText entryNames main]
  :i [(asl-target-llvm/libc :a libc)
      (asl-target-llvm/gcRoute :a gr)])

fn entryNames -> (List String)
  (list "gcFloorFail" "gcFloorGuard" "gcFloorRaise")

fn codeMax -> Int64
  125

fn messageMax -> Int64
  1023

fn lineBytes -> Int64
  (+ (codeMax) (+ (messageMax) 4))

fn writeAllText errno: String eintr: Int64 -> String
  (stringJoin
    (list "define internal void @rtFloor.writeAll(ptr %p, i64 %n) {"
          "entry:"
          "  br label %loop"
          "loop:"
          "  %at = phi ptr [ %p, %entry ], [ %at, %interrupted ], [ %next, %advance ]"
          "  %left = phi i64 [ %n, %entry ], [ %left, %interrupted ], [ %rest, %advance ]"
          "  %done = icmp sle i64 %left, 0"
          "  br i1 %done, label %out, label %write"
          "write:"
          "  %w = call i64 @write(i32 2, ptr %at, i64 %left)"
          "  %failed = icmp slt i64 %w, 0"
          "  br i1 %failed, label %error, label %wrote"
          "error:"
          (str "  %ep = call ptr @" errno "()")
          "  %e = load i32, ptr %ep"
          (str "  %intr = icmp eq i32 %e, " eintr)
          "  br i1 %intr, label %interrupted, label %out"
          "interrupted:"
          "  br label %loop"
          "wrote:"
          "  %none = icmp eq i64 %w, 0"
          "  br i1 %none, label %out, label %advance"
          "advance:"
          "  %next = getelementptr inbounds i8, ptr %at, i64 %w"
          "  %rest = sub i64 %left, %w"
          "  br label %loop"
          "out:"
          "  ret void"
          "}")
    "\n")

fn failText -> String
  (stringJoin
    (list "define weak void @gcFloorFail(ptr %code, ptr %msg, ...) noreturn {"
          "entry:"
          (str "  %line = alloca [" (lineBytes) " x i8], align 1")
          "  %raise = load ptr, ptr @gcFloorRaise"
          "  %hasRaise = icmp ne ptr %raise, null"
          "  br i1 %hasRaise, label %raising, label %print"
          "raising:"
          "  call void %raise(ptr %code, ptr %msg)"
          "  br label %print"
          "print:"
          "  %codeLen = call i64 @strlen(ptr %code)"
          (str "  %cl = call i64 @llvm.umin.i64(i64 %codeLen, i64 " (codeMax) ")")
          "  %msgLen = call i64 @strlen(ptr %msg)"
          (str "  %ml = call i64 @llvm.umin.i64(i64 %msgLen, i64 " (messageMax) ")")
          "  call void @llvm.memcpy.p0.p0.i64(ptr %line, ptr %code, i64 %cl, i1 false)"
          "  %sep = getelementptr inbounds i8, ptr %line, i64 %cl"
          "  store i8 58, ptr %sep"
          "  %space = getelementptr inbounds i8, ptr %sep, i64 1"
          "  store i8 32, ptr %space"
          "  %text = getelementptr inbounds i8, ptr %sep, i64 2"
          "  call void @llvm.memcpy.p0.p0.i64(ptr %text, ptr %msg, i64 %ml, i1 false)"
          "  %nl = getelementptr inbounds i8, ptr %text, i64 %ml"
          "  store i8 10, ptr %nl"
          "  %head = add i64 %cl, %ml"
          "  %len = add i64 %head, 3"
          "  call void @rtFloor.writeAll(ptr %line, i64 %len)"
          "  call void @exit(i32 1)"
          "  unreachable"
          "}")
    "\n")

fn declLines errno: String -> (List String)
  (list "declare i64 @write(i32, ptr, i64)" "declare i64 @strlen(ptr)" (str "declare ptr @" errno "()") "declare void @exit(i32) noreturn"
        "declare i64 @llvm.umin.i64(i64, i64)" "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)")

fn floorText facts: libc/TripleFacts -> (Result String String)
  (mt (libc/libcConst facts "EINTR")
    ((none) (err (str "ERR_LLVM_RTFLOOR: libc.asl has no EINTR for " facts.triple)))
    ((some eintr)
      (if (stringEmpty? facts.errnoAccessor)
        (err (str "ERR_LLVM_RTFLOOR: libc.asl names no errno accessor for " facts.triple))
        (ok (str "source_filename = \"aslRtFloor\"\n\n"
                 (stringJoin (list "@gcFloorGuard = weak global ptr null, align 8" "@gcFloorRaise = weak global ptr null, align 8" "" (failText) "" (writeAllText facts.errnoAccessor eintr) ""
                                   (stringJoin (declLines facts.errnoAccessor) "\n"))
                             "\n")
                 "\n")))))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(out (processRun "uname -s -m"))
        (triple (if (= out.exitCode 0) (gr/hostTriple out.stdout) ""))]
    (mt (libc/libcFacts triple)
      ((none) (err (str "ERR_LLVM_RTFLOOR: libc.asl covers no host printing '" out.stdout "' for uname -s -m")))
      ((some facts)
        (mt (floorText facts)
          ((err e) (err e))
          ((ok text)
            (mt (listHead args)
              ((none) (do (print text) (ok 0)))
              ((some path) (mt (fileWrite path text)
                             ((ok _) (ok 0))
                             ((err e) (err (str "ERR_LLVM_RTFLOOR: cannot write " path ": " e)))))))))))
