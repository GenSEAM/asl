source_filename = "fibRaw"

define tailcc i64 @fib(i64 %n) {
bb.entry:
  %two = bitcast i64 2 to i64
  %small = icmp slt i64 %n, %two
  br i1 %small, label %bb.base, label %bb.recur
bb.base:
  ret i64 %n
bb.recur:
  %one = bitcast i64 1 to i64
  %n1.p.pair = call {i64, i1} @llvm.ssub.with.overflow.i64(i64 %n, i64 %one)
  %n1 = extractvalue {i64, i1} %n1.p.pair, 0
  %n1.p.bad = extractvalue {i64, i1} %n1.p.pair, 1
  br i1 %n1.p.bad, label %n1.p.trap, label %n1.p.ok
n1.p.trap:
  call void @llvm.trap()
  unreachable
n1.p.ok:
  %f1 = call tailcc i64 @fib(i64 %n1)
  %n2.p.pair = call {i64, i1} @llvm.ssub.with.overflow.i64(i64 %n, i64 %two)
  %n2 = extractvalue {i64, i1} %n2.p.pair, 0
  %n2.p.bad = extractvalue {i64, i1} %n2.p.pair, 1
  br i1 %n2.p.bad, label %n2.p.trap, label %n2.p.ok
n2.p.trap:
  call void @llvm.trap()
  unreachable
n2.p.ok:
  %f2 = call tailcc i64 @fib(i64 %n2)
  %sum.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %f1, i64 %f2)
  %sum = extractvalue {i64, i1} %sum.p.pair, 0
  %sum.p.bad = extractvalue {i64, i1} %sum.p.pair, 1
  br i1 %sum.p.bad, label %sum.p.trap, label %sum.p.ok
sum.p.trap:
  call void @llvm.trap()
  unreachable
sum.p.ok:
  ret i64 %sum
}

define tailcc i64 @fibMain() {
bb.entry:
  %ten = bitcast i64 10 to i64
  %result = musttail call tailcc i64 @fib(i64 %ten)
  ret i64 %result
}

@.rterr.c.ERR_INTERNAL = private unnamed_addr constant [13 x i8] c"ERR_INTERNAL\00"
@.rterr.line = private unnamed_addr constant [9 x i8] c"%s: %.*s\00"

define internal void @rterr.writeAll(i32 %fd, ptr %data, i64 %length) {
entry:
  br label %loop
loop:
  %offset = phi i64 [ 0, %entry ], [ %next, %more ]
  %done = icmp uge i64 %offset, %length
  br i1 %done, label %finish, label %once
once:
  %at = getelementptr i8, ptr %data, i64 %offset
  %rest = sub i64 %length, %offset
  %wrote = call i64 @write(i32 %fd, ptr %at, i64 %rest)
  %progress = icmp sgt i64 %wrote, 0
  br i1 %progress, label %more, label %finish
more:
  %next = add i64 %offset, %wrote
  br label %loop
finish:
  ret void
}

define internal void @rterr.raise(ptr %code, ptr %msg, i64 %len) noreturn {
entry:
  %buf = alloca [4097 x i8]
  %big = icmp ugt i64 %len, 4096
  %clamped = select i1 %big, i64 4096, i64 %len
  %prec = trunc i64 %clamped to i32
  %slot = call ptr @aslHandlerSlot()
  %handler = load ptr, ptr %slot
  %nested = icmp ne ptr %handler, null
  br i1 %nested, label %rethrow, label %report
rethrow:
  %text = call ptr @aslErrorText()
  %kept = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %text, i64 4096, ptr @.rterr.line, ptr %code, i32 %prec, ptr %msg)
  call void @longjmp(ptr %handler, i32 1)
  unreachable
report:
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.rterr.line, ptr %code, i32 %prec, ptr %msg)
  %negative = icmp slt i32 %written, 0
  %wide = sext i32 %written to i64
  %over = icmp ugt i64 %wide, 4095
  %cut = select i1 %over, i64 4095, i64 %wide
  %count = select i1 %negative, i64 0, i64 %cut
  %end = getelementptr i8, ptr %buf, i64 %count
  store i8 10, ptr %end
  %total = add i64 %count, 1
  %flushed = call i32 @fflush(ptr null)
  call void @rterr.writeAll(i32 2, ptr %buf, i64 %total)
  call void @exit(i32 1)
  unreachable
}
@.rterr.m.reportFailed = private unnamed_addr constant [37 x i8] c"cannot register the assertion report\00"
@rterr.assertCount = weak global i64 0
@rterr.refuteCount = weak global i64 0
@.rterr.reportEnv = private unnamed_addr constant [18 x i8] c"ASL_ASSERT_REPORT\00"
@.rterr.reportLine = private unnamed_addr constant [57 x i8] c"%lld assertion(s) executed, %lld refutation(s) executed\0A\00"

define internal void @rterr.report() {
entry:
  %buf = alloca [128 x i8]
  store i8 0, ptr %buf
  %asserts = load i64, ptr @rterr.assertCount
  %refutes = load i64, ptr @rterr.refuteCount
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 128, ptr @.rterr.reportLine, i64 %asserts, i64 %refutes)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.writeAll(i32 2, ptr %buf, i64 %len)
  ret void
}

define internal void @rterr.reportInit() {
entry:
  %env = call ptr @getenv(ptr @.rterr.reportEnv)
  %set = icmp ne ptr %env, null
  br i1 %set, label %check, label %done
check:
  %first = load i8, ptr %env
  %one = icmp eq i8 %first, 49
  br i1 %one, label %install, label %done
install:
  %rc = call i32 @atexit(ptr @rterr.report)
  %uc = call i32 @unsetenv(ptr @.rterr.reportEnv)
  %failed = icmp ne i32 %rc, 0
  br i1 %failed, label %fail, label %done
fail:
  call void @rterr.raise(ptr @.rterr.c.ERR_INTERNAL, ptr @.rterr.m.reportFailed, i64 36)
  unreachable
done:
  ret void
}
@valrt.handler = weak global ptr null
@valrt.errorMsg = weak global [4096 x i8] zeroinitializer

define weak ptr @aslHandlerSlot() {
entry:
  ret ptr @valrt.handler
}

define weak ptr @aslErrorText() {
entry:
  ret ptr @valrt.errorMsg
}
define i32 @main() {
bb.entry:
  call void @rterr.reportInit()
  %result = call tailcc i64 @fibMain()
  %code = trunc i64 %result to i32
  ret i32 %code
}

declare void @llvm.trap()
declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)
declare {i64, i1} @llvm.ssub.with.overflow.i64(i64, i64)
declare i64 @strlen(ptr)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i64 @write(i32, ptr, i64)
declare void @exit(i32)
declare i32 @fflush(ptr)
declare ptr @getenv(ptr)
declare i32 @atexit(ptr)
declare i32 @unsetenv(ptr)
declare void @longjmp(ptr, i32) noreturn
