source_filename = "traps"

define tailcc i64 @add(i64 %a, i64 %b) {
bb.entry:
  %r.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %a, i64 %b)
  %r = extractvalue {i64, i1} %r.p.pair, 0
  %r.p.bad = extractvalue {i64, i1} %r.p.pair, 1
  br i1 %r.p.bad, label %r.p.trap, label %r.p.ok
r.p.trap:
  call void @llvm.trap()
  unreachable
r.p.ok:
  ret i64 %r
}

define tailcc i64 @sub(i64 %a, i64 %b) {
bb.entry:
  %r.p.pair = call {i64, i1} @llvm.ssub.with.overflow.i64(i64 %a, i64 %b)
  %r = extractvalue {i64, i1} %r.p.pair, 0
  %r.p.bad = extractvalue {i64, i1} %r.p.pair, 1
  br i1 %r.p.bad, label %r.p.trap, label %r.p.ok
r.p.trap:
  call void @llvm.trap()
  unreachable
r.p.ok:
  ret i64 %r
}

define tailcc i64 @mul(i64 %a, i64 %b) {
bb.entry:
  %r.p.pair = call {i64, i1} @llvm.smul.with.overflow.i64(i64 %a, i64 %b)
  %r = extractvalue {i64, i1} %r.p.pair, 0
  %r.p.bad = extractvalue {i64, i1} %r.p.pair, 1
  br i1 %r.p.bad, label %r.p.trap, label %r.p.ok
r.p.trap:
  call void @llvm.trap()
  unreachable
r.p.ok:
  ret i64 %r
}

define tailcc i64 @quot(i64 %a, i64 %b) {
bb.entry:
  %r.p.zero = icmp eq i64 %b, 0
  %r.p.min = icmp eq i64 %a, -9223372036854775808
  %r.p.neg = icmp eq i64 %b, -1
  %r.p.over = and i1 %r.p.min, %r.p.neg
  %r.p.bad = or i1 %r.p.zero, %r.p.over
  br i1 %r.p.bad, label %r.p.trap, label %r.p.ok
r.p.trap:
  call void @llvm.trap()
  unreachable
r.p.ok:
  %r = sdiv i64 %a, %b
  ret i64 %r
}

define tailcc i64 @rem(i64 %a, i64 %b) {
bb.entry:
  %r.p.bad = icmp eq i64 %b, 0
  br i1 %r.p.bad, label %r.p.trap, label %r.p.ok
r.p.trap:
  call void @llvm.trap()
  unreachable
r.p.ok:
  %r.p.neg = icmp eq i64 %b, -1
  %r.p.divisor = select i1 %r.p.neg, i64 1, i64 %b
  %r = srem i64 %a, %r.p.divisor
  ret i64 %r
}

define tailcc i64 @toInt(double %x) {
bb.entry:
  %r.p.low = fcmp oge double %x, 0xC3E0000000000000
  %r.p.high = fcmp olt double %x, 0x43E0000000000000
  %r.p.fits = and i1 %r.p.low, %r.p.high
  %r.p.bad = xor i1 %r.p.fits, true
  br i1 %r.p.bad, label %r.p.trap, label %r.p.ok
r.p.trap:
  call void @rterr.int(i32 8)
  unreachable
r.p.ok:
  %r = fptosi double %x to i64
  ret i64 %r
}

define tailcc i64 @control() {
bb.entry:
  %a = bitcast i64 7 to i64
  %b = bitcast i64 2 to i64
  %r = musttail call tailcc i64 @quot(i64 %a, i64 %b)
  ret i64 %r
}

define tailcc i64 @quotZero() {
bb.entry:
  %a = bitcast i64 7 to i64
  %b = bitcast i64 0 to i64
  %r = musttail call tailcc i64 @quot(i64 %a, i64 %b)
  ret i64 %r
}

define tailcc i64 @quotMin() {
bb.entry:
  %a = bitcast i64 -9223372036854775808 to i64
  %b = bitcast i64 -1 to i64
  %r = musttail call tailcc i64 @quot(i64 %a, i64 %b)
  ret i64 %r
}

define tailcc i64 @remZero() {
bb.entry:
  %a = bitcast i64 7 to i64
  %b = bitcast i64 0 to i64
  %r = musttail call tailcc i64 @rem(i64 %a, i64 %b)
  ret i64 %r
}

define tailcc i64 @addOver() {
bb.entry:
  %a = bitcast i64 9223372036854775807 to i64
  %b = bitcast i64 1 to i64
  %r = musttail call tailcc i64 @add(i64 %a, i64 %b)
  ret i64 %r
}

define tailcc i64 @subOver() {
bb.entry:
  %a = bitcast i64 -9223372036854775807 to i64
  %b = bitcast i64 2 to i64
  %r = musttail call tailcc i64 @sub(i64 %a, i64 %b)
  ret i64 %r
}

define tailcc i64 @mulOver() {
bb.entry:
  %a = bitcast i64 4611686018427387904 to i64
  %b = bitcast i64 2 to i64
  %r = musttail call tailcc i64 @mul(i64 %a, i64 %b)
  ret i64 %r
}

define tailcc i64 @floatControl() {
bb.entry:
  %x = bitcast double -7.0 to double
  %y = bitcast double 2.0 to double
  %q = fdiv double %x, %y
  %r = musttail call tailcc i64 @toInt(double %q)
  ret i64 %r
}

define tailcc i64 @floatNan() {
bb.entry:
  %x = bitcast double 0.0 to double
  %y = bitcast double 0.0 to double
  %q = fdiv double %x, %y
  %r = musttail call tailcc i64 @toInt(double %q)
  ret i64 %r
}

define tailcc i64 @floatHuge() {
bb.entry:
  %x = bitcast double 1.0e+19 to double
  %y = bitcast double 1.0 to double
  %q = fdiv double %x, %y
  %r = musttail call tailcc i64 @toInt(double %q)
  ret i64 %r
}

define tailcc i64 @narrowControl() {
bb.entry:
  %x = bitcast i64 42 to i64
  %n.p.low = icmp sge i64 %x, -2147483648
  %n.p.high = icmp sle i64 %x, 2147483647
  %n.p.fits = and i1 %n.p.low, %n.p.high
  %n.p.bad = xor i1 %n.p.fits, true
  br i1 %n.p.bad, label %n.p.trap, label %n.p.ok
n.p.trap:
  call void @rterr.int(i32 7)
  unreachable
n.p.ok:
  %n = trunc i64 %x to i32
  %w = sext i32 %n to i64
  ret i64 %w
}

define tailcc i64 @narrowOver() {
bb.entry:
  %x = bitcast i64 9223372036854775807 to i64
  %n.p.low = icmp sge i64 %x, -2147483648
  %n.p.high = icmp sle i64 %x, 2147483647
  %n.p.fits = and i1 %n.p.low, %n.p.high
  %n.p.bad = xor i1 %n.p.fits, true
  br i1 %n.p.bad, label %n.p.trap, label %n.p.ok
n.p.trap:
  call void @rterr.int(i32 7)
  unreachable
n.p.ok:
  %n = trunc i64 %x to i32
  %w = sext i32 %n to i64
  ret i64 %w
}

@.rterr.c.ERR_INTERNAL = private unnamed_addr constant [13 x i8] c"ERR_INTERNAL\00"
@.rterr.c.ERR_INT_OVERFLOW = private unnamed_addr constant [17 x i8] c"ERR_INT_OVERFLOW\00"
@.rterr.c.ERR_DIV_ZERO = private unnamed_addr constant [13 x i8] c"ERR_DIV_ZERO\00"
@.rterr.m.add = private unnamed_addr constant [19 x i8] c"Int + leaves int64\00"
@.rterr.m.sub = private unnamed_addr constant [19 x i8] c"Int - leaves int64\00"
@.rterr.m.mul = private unnamed_addr constant [19 x i8] c"Int * leaves int64\00"
@.rterr.m.div = private unnamed_addr constant [19 x i8] c"Int / leaves int64\00"
@.rterr.m.divZero = private unnamed_addr constant [17 x i8] c"division by zero\00"
@.rterr.m.modZero = private unnamed_addr constant [12 x i8] c"mod by zero\00"
@.rterr.m.narrow = private unnamed_addr constant [24 x i8] c"Int narrow leaves int32\00"
@.rterr.m.floatInt = private unnamed_addr constant [26 x i8] c"Float to Int leaves int64\00"
@.rterr.m.intKind = private unnamed_addr constant [26 x i8] c"unknown integer trap %lld\00"
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

define internal void @rterr.raiseNumber(ptr %code, ptr %format, i64 %arg) noreturn {
entry:
  %buf = alloca [4096 x i8]
  store i8 0, ptr %buf
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr %format, i64 %arg)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.raise(ptr %code, ptr %buf, i64 %len)
  unreachable
}

define internal void @rterr.int(i32 %kind) noreturn {
entry:
  switch i32 %kind, label %unknown [ i32 0, label %add i32 1, label %sub i32 2, label %mul i32 3, label %div i32 5, label %divZero i32 6, label %modZero i32 7, label %narrow i32 8, label %floatInt ]
add:
  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.add, i64 18)
  unreachable
sub:
  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.sub, i64 18)
  unreachable
mul:
  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.mul, i64 18)
  unreachable
div:
  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.div, i64 18)
  unreachable
divZero:
  call void @rterr.raise(ptr @.rterr.c.ERR_DIV_ZERO, ptr @.rterr.m.divZero, i64 16)
  unreachable
modZero:
  call void @rterr.raise(ptr @.rterr.c.ERR_DIV_ZERO, ptr @.rterr.m.modZero, i64 11)
  unreachable
narrow:
  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.narrow, i64 23)
  unreachable
floatInt:
  call void @rterr.raise(ptr @.rterr.c.ERR_INT_OVERFLOW, ptr @.rterr.m.floatInt, i64 25)
  unreachable
unknown:
  %wide = sext i32 %kind to i64
  call void @rterr.raiseNumber(ptr @.rterr.c.ERR_INTERNAL, ptr @.rterr.m.intKind, i64 %wide)
  unreachable
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
declare void @llvm.trap()
declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)
declare {i64, i1} @llvm.ssub.with.overflow.i64(i64, i64)
declare {i64, i1} @llvm.smul.with.overflow.i64(i64, i64)
declare i64 @strlen(ptr)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i64 @write(i32, ptr, i64)
declare void @exit(i32)
declare i32 @fflush(ptr)
declare void @longjmp(ptr, i32) noreturn
