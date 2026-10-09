@good = private unnamed_addr constant [17 x i8] c"1000000 1000000\0A\00"
@bad = private unnamed_addr constant [14 x i8] c"tail failure\0A\00"

declare i64 @write(i32, ptr, i64) "wasm-import-module"="asl" "wasm-import-name"="write"

define i64 @selfLoop(i64 %remaining, i64 %total) {
entry:
  %done = icmp eq i64 %remaining, 0
  br i1 %done, label %return, label %again
again:
  %next = sub i64 %remaining, 1
  %sum = add i64 %total, 1
  %result = musttail call i64 @selfLoop(i64 %next, i64 %sum)
  ret i64 %result
return:
  ret i64 %total
}

define i64 @evenLoop(i64 %remaining, i64 %total) {
entry:
  %done = icmp eq i64 %remaining, 0
  br i1 %done, label %return, label %again
again:
  %next = sub i64 %remaining, 1
  %sum = add i64 %total, 1
  %result = musttail call i64 @oddLoop(i64 %next, i64 %sum)
  ret i64 %result
return:
  ret i64 %total
}

define i64 @oddLoop(i64 %remaining, i64 %total) {
entry:
  %done = icmp eq i64 %remaining, 0
  br i1 %done, label %return, label %again
again:
  %next = sub i64 %remaining, 1
  %sum = add i64 %total, 1
  %result = musttail call i64 @evenLoop(i64 %next, i64 %sum)
  ret i64 %result
return:
  ret i64 %total
}

define i32 @main() {
entry:
  %self = call i64 @selfLoop(i64 1000000, i64 0)
  %mutual = call i64 @evenLoop(i64 1000000, i64 0)
  %selfOk = icmp eq i64 %self, 1000000
  %mutualOk = icmp eq i64 %mutual, 1000000
  %ok = and i1 %selfOk, %mutualOk
  %okPtr = getelementptr inbounds [17 x i8], ptr @good, i64 0, i64 0
  %badPtr = getelementptr inbounds [14 x i8], ptr @bad, i64 0, i64 0
  %ptr = select i1 %ok, ptr %okPtr, ptr %badPtr
  %len = select i1 %ok, i64 16, i64 13
  %written = call i64 @write(i32 1, ptr %ptr, i64 %len)
  %code = select i1 %ok, i32 0, i32 1
  ret i32 %code
}

define void @_start() {
entry:
  %code = call i32 @main()
  %failed = icmp ne i32 %code, 0
  br i1 %failed, label %trap, label %done
trap:
  unreachable
done:
  ret void
}
