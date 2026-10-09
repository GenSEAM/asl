source_filename = "ops/demo"

%Val = type { i64, i64 }

@str.0 = private unnamed_addr constant [12 x i8] c"hi \22there\22\0A\00"
@str.1 = private unnamed_addr constant [1 x i8] c"\00"
@name.Point = private unnamed_addr constant [6 x i8] c"Point\00"
@name.doc = private unnamed_addr constant [4 x i8] c"doc\00"
@name.a$2Db = private unnamed_addr constant [4 x i8] c"a-b\00"
@name.circle = private unnamed_addr constant [7 x i8] c"circle\00"
@name.empty = private unnamed_addr constant [6 x i8] c"empty\00"
@name.x = private unnamed_addr constant [2 x i8] c"x\00"
@name.y = private unnamed_addr constant [2 x i8] c"y\00"
@ctorId.circle = internal global i32 0
@ctorIdReady.circle = internal global i1 false
@ctorId.empty = internal global i32 0
@ctorIdReady.empty = internal global i1 false
@schemaId.Point = internal global i32 0
@schemaIdReady.Point = internal global i1 false
@keyIds.Point = internal global [2 x i32] zeroinitializer
@protoFile.compiled = private unnamed_addr constant [11 x i8] c"<compiled>\00"
@protoName.adder = private unnamed_addr constant [6 x i8] c"adder\00"
@proto.adder = private unnamed_addr constant { ptr, ptr, i32, i32, ptr, i32, i32, ptr, i32, i32, ptr } { ptr @protoName.adder, ptr @protoFile.compiled, i32 1, i32 0, ptr null, i32 0, i32 0, ptr null, i32 0, i32 0, ptr @adder.code }
@nameId.doc = internal global i32 -1
@nameId.x = internal global i32 -1
@strVal.0 = internal global %Val zeroinitializer
@strVal.1 = internal global %Val zeroinitializer
@global.origin = internal global %Val zeroinitializer

define tailcc %Val @adder(%Val %n, %Val %x) {
bb.entry:
  %sum = call %Val @opsrt.add(%Val %n, %Val %x)
  ret %Val %sum
}

define tailcc %Val @makeOrigin() {
bb.entry:
  %zero = insertvalue %Val { i64 2, i64 0 }, i64 0, 1
  %p.ready = load i1, ptr @schemaIdReady.Point
  br i1 %p.ready, label %p.alloc, label %p.resolve
p.resolve:
  call void @schemaIdInit.Point()
  br label %p.alloc
p.alloc:
  %p.schema = load i32, ptr @schemaId.Point
  %p.objp = call ptr @asl_alloc_raw(i32 2, i64 56)
  %p.schemap = getelementptr inbounds i8, ptr %p.objp, i64 8
  store i32 %p.schema, ptr %p.schemap
  %p.np = getelementptr inbounds i8, ptr %p.objp, i64 12
  store i32 2, ptr %p.np
  %p.keysp = getelementptr inbounds i8, ptr %p.objp, i64 16
  store ptr @keyIds.Point, ptr %p.keysp
  %p.f0p = getelementptr inbounds i8, ptr %p.objp, i64 24
  store %Val %zero, ptr %p.f0p
  %p.f1p = getelementptr inbounds i8, ptr %p.objp, i64 40
  store %Val %zero, ptr %p.f1p
  %p.objw = ptrtoint ptr %p.objp to i64
  %p = insertvalue %Val { i64 7, i64 0 }, i64 %p.objw, 1
  ret %Val %p
}

define tailcc %Val @demo(%Val %url) {
bb.entry:
  %six.argv = alloca [1 x %Val]
  %rawFive = bitcast i64 5 to i64
  %five = insertvalue %Val { i64 2, i64 0 }, i64 %rawFive, 1
  %add5.objp = call ptr @asl_alloc_raw(i32 4, i64 40)
  %add5.pp = getelementptr inbounds i8, ptr %add5.objp, i64 8
  store ptr @proto.adder, ptr %add5.pp
  %add5.np = getelementptr inbounds i8, ptr %add5.objp, i64 16
  store i32 1, ptr %add5.np
  %add5.c0p = getelementptr inbounds i8, ptr %add5.objp, i64 24
  store %Val %five, ptr %add5.c0p
  %add5.objw = ptrtoint ptr %add5.objp to i64
  %add5 = insertvalue %Val { i64 9, i64 0 }, i64 %add5.objw, 1
  %one.bits = bitcast double 1.0 to i64
  %one = insertvalue %Val { i64 3, i64 0 }, i64 %one.bits, 1
  %six.a0 = getelementptr [1 x %Val], ptr %six.argv, i64 0, i64 0
  store %Val %one, ptr %six.a0
  %six = call %Val @objrt.call(%Val %add5, i64 1, ptr %six.argv)
  %half = bitcast double -0.5 to double
  %halfVal.bits = bitcast double %half to i64
  %halfVal = insertvalue %Val { i64 3, i64 0 }, i64 %halfVal.bits, 1
  %greeting = call %Val @objrt.str(ptr @strVal.0, ptr @str.0, i64 11)
  %empty = call %Val @objrt.str(ptr @strVal.1, ptr @str.1, i64 0)
  %unit = insertvalue %Val { i64 0, i64 0 }, i64 0, 1
  %kw.id = call i32 @objrt.nameId(ptr @nameId.doc, ptr @name.doc, i64 3)
  %kw.idw = zext i32 %kw.id to i64
  %kw.idhi = shl i64 %kw.idw, 32
  %kw.word = or i64 %kw.idhi, 4
  %kw = insertvalue %Val { i64 0, i64 0 }, i64 %kw.word, 0
  %sym = call %Val @objrt.symbol(ptr @name.a$2Db)
  %yes = insertvalue %Val { i64 1, i64 0 }, i64 1, 1
  %circle.ready = load i1, ptr @ctorIdReady.circle
  br i1 %circle.ready, label %circle.alloc, label %circle.resolve
circle.resolve:
  call void @ctorIdInit.circle()
  br label %circle.alloc
circle.alloc:
  %circle.ctor = load i32, ptr @ctorId.circle
  %circle.objp = call ptr @asl_alloc_raw(i32 3, i64 32)
  %circle.ctorp = getelementptr inbounds i8, ptr %circle.objp, i64 8
  store i32 %circle.ctor, ptr %circle.ctorp
  %circle.np = getelementptr inbounds i8, ptr %circle.objp, i64 12
  store i32 1, ptr %circle.np
  %circle.f0p = getelementptr inbounds i8, ptr %circle.objp, i64 16
  store %Val %six, ptr %circle.f0p
  %circle.objw = ptrtoint ptr %circle.objp to i64
  %circle = insertvalue %Val { i64 8, i64 0 }, i64 %circle.objw, 1
  %none.ready = load i1, ptr @ctorIdReady.empty
  br i1 %none.ready, label %none.alloc, label %none.resolve
none.resolve:
  call void @ctorIdInit.empty()
  br label %none.alloc
none.alloc:
  %none.ctor = load i32, ptr @ctorId.empty
  %none.objp = call ptr @asl_alloc_raw(i32 3, i64 16)
  %none.ctorp = getelementptr inbounds i8, ptr %none.objp, i64 8
  store i32 %none.ctor, ptr %none.ctorp
  %none.np = getelementptr inbounds i8, ptr %none.objp, i64 12
  store i32 0, ptr %none.np
  %none.objw = ptrtoint ptr %none.objp to i64
  %none = insertvalue %Val { i64 8, i64 0 }, i64 %none.objw, 1
  %origin = load %Val, ptr @global.origin
  %ox = call %Val @objrt.field(%Val %origin, ptr @nameId.x, ptr @name.x, i64 1)
  %body = call %Val @net$2Ffetch(%Val %url, %Val %greeting)
  %rawSix.vtagw = extractvalue %Val %six, 0
  %rawSix.vtag = trunc i64 %rawSix.vtagw to i32
  %rawSix.tagok = icmp eq i32 %rawSix.vtag, 2
  br i1 %rawSix.tagok, label %rawSix.ok, label %rawSix.trap
rawSix.trap:
  call void @rterr.type(i32 %rawSix.vtag, i32 2)
  unreachable
rawSix.ok:
  %rawSix = extractvalue %Val %six, 1
  %ok.vtagw = extractvalue %Val %yes, 0
  %ok.vtag = trunc i64 %ok.vtagw to i32
  %ok.tagok = icmp eq i32 %ok.vtag, 1
  br i1 %ok.tagok, label %ok.ok, label %ok.trap
ok.trap:
  call void @rterr.type(i32 %ok.vtag, i32 1)
  unreachable
ok.ok:
  %ok.w = extractvalue %Val %yes, 1
  %ok = trunc i64 %ok.w to i1
  %all.c8 = call %Val @listrt.cell(%Val %halfVal, %Val { i64 6, i64 0 })
  %all.c7 = call %Val @listrt.cell(%Val %sym, %Val %all.c8)
  %all.c6 = call %Val @listrt.cell(%Val %kw, %Val %all.c7)
  %all.c5 = call %Val @listrt.cell(%Val %unit, %Val %all.c6)
  %all.c4 = call %Val @listrt.cell(%Val %empty, %Val %all.c5)
  %all.c3 = call %Val @listrt.cell(%Val %body, %Val %all.c4)
  %all.c2 = call %Val @listrt.cell(%Val %ox, %Val %all.c3)
  %all.c1 = call %Val @listrt.cell(%Val %none, %Val %all.c2)
  %all.c0 = call %Val @listrt.cell(%Val %circle, %Val %all.c1)
  %all = insertvalue %Val %all.c0, i64 6, 0
  br i1 %ok, label %bb.entry.e0, label %bb.entry.e1
bb.entry.e0:
  br label %bb.done
bb.entry.e1:
  br label %bb.done
bb.done:
  %out = phi %Val [ %all, %bb.entry.e0 ], [ %unit, %bb.entry.e1 ]
  ret %Val %out
}

define internal %Val @adder.code(%Val %env, i64 %argc, ptr %argv) {
bb.entry:
  %cap0.tagw = extractvalue %Val %env, 0
  %cap0.tag = trunc i64 %cap0.tagw to i32
  %cap0.isFn = icmp eq i32 %cap0.tag, 9
  br i1 %cap0.isFn, label %cap0.fn, label %cap0.slow
cap0.fn:
  %cap0.objw = extractvalue %Val %env, 1
  %cap0.obj = inttoptr i64 %cap0.objw to ptr
  %cap0.np = getelementptr inbounds i8, ptr %cap0.obj, i64 16
  %cap0.n = load i32, ptr %cap0.np
  %cap0.n64 = sext i32 %cap0.n to i64
  %cap0.inRange = icmp slt i64 0, %cap0.n64
  br i1 %cap0.inRange, label %cap0.fast, label %cap0.slow
cap0.fast:
  %cap0.fp = getelementptr inbounds i8, ptr %cap0.obj, i64 24
  %cap0.fastval = load %Val, ptr %cap0.fp
  br label %cap0.join
cap0.slow:
  %cap0.slowval = call %Val @objrt.capture(%Val %env, i64 0)
  br label %cap0.join
cap0.join:
  %cap0 = phi %Val [ %cap0.fastval, %cap0.fast ], [ %cap0.slowval, %cap0.slow ]
  %arg0.slot = getelementptr %Val, ptr %argv, i64 0
  %arg0 = load %Val, ptr %arg0.slot
  %result = call tailcc %Val @adder(%Val %cap0, %Val %arg0)
  ret %Val %result
}

define internal void @ctorIdInit.circle() {
bb.entry:
  %kw.aux = call i32 @valrt.intern(ptr @name.circle, i64 6)
  store i32 %kw.aux, ptr @ctorId.circle
  store i1 true, ptr @ctorIdReady.circle
  ret void
}

define internal void @ctorIdInit.empty() {
bb.entry:
  %kw.aux = call i32 @valrt.intern(ptr @name.empty, i64 5)
  store i32 %kw.aux, ptr @ctorId.empty
  store i1 true, ptr @ctorIdReady.empty
  ret void
}

define internal void @schemaIdInit.Point() {
bb.entry:
  %kw.aux = call i32 @valrt.intern(ptr @name.Point, i64 5)
  store i32 %kw.aux, ptr @schemaId.Point
  %fkw.0.aux = call i32 @valrt.intern(ptr @name.x, i64 1)
  %fslot.0 = getelementptr inbounds [2 x i32], ptr @keyIds.Point, i64 0, i64 0
  store i32 %fkw.0.aux, ptr %fslot.0
  %fkw.1.aux = call i32 @valrt.intern(ptr @name.y, i64 1)
  %fslot.1 = getelementptr inbounds [2 x i32], ptr @keyIds.Point, i64 0, i64 1
  store i32 %fkw.1.aux, ptr %fslot.1
  store i1 true, ptr @schemaIdReady.Point
  ret void
}

define void @init.ops$2Fdemo() {
bb.entry:
  call void @asl_rt_global_root(ptr @global.origin)
  %g.0 = call tailcc %Val @makeOrigin()
  store %Val %g.0, ptr @global.origin
  ret void
}

define internal %Val @listrt.cell(%Val %car, %Val %cdr) {
entry:
  %obj = call ptr @asl_alloc(i32 1, i64 40)
  %carp = getelementptr inbounds i8, ptr %obj, i64 8
  store %Val %car, ptr %carp
  %cdrp = getelementptr inbounds i8, ptr %obj, i64 24
  store %Val %cdr, ptr %cdrp
  %objw = ptrtoint ptr %obj to i64
  %r = insertvalue %Val { i64 6, i64 0 }, i64 %objw, 1
  ret %Val %r
}
@.opsrt.who.add = private unnamed_addr constant [2 x i8] c"+\00"
@.opsrt.pair = private unnamed_addr constant [47 x i8] c"%s expects two Int or two Float, got %s and %s\00"
define internal void @opsrt.pair(ptr %who, i32 %a, i32 %b) noreturn {
entry:
  %buf = alloca [4096 x i8]
  store i8 0, ptr %buf
  %aName = call ptr @rterr.tagName(i32 %a)
  %bName = call ptr @rterr.tagName(i32 %b)
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.opsrt.pair, ptr %who, ptr %aName, ptr %bName)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_TYPE, ptr %buf, i64 %len)
  unreachable
}
define internal %Val @opsrt.add(%Val %a, %Val %b) {
entry:
  %a.tagw = extractvalue %Val %a, 0
  %a.tag = trunc i64 %a.tagw to i32
  %a.bits = extractvalue %Val %a, 1
  %b.tagw = extractvalue %Val %b, 0
  %b.tag = trunc i64 %b.tagw to i32
  %b.bits = extractvalue %Val %b, 1
  %a.int = icmp eq i32 %a.tag, 2
  %b.int = icmp eq i32 %b.tag, 2
  %ints = and i1 %a.int, %b.int
  %a.float = icmp eq i32 %a.tag, 3
  %b.float = icmp eq i32 %b.tag, 3
  %floats = and i1 %a.float, %b.float
  br i1 %ints, label %int, label %notInt
notInt:
  br i1 %floats, label %float, label %other
float:
  %x = bitcast i64 %a.bits to double
  %y = bitcast i64 %b.bits to double
  %r = fadd double %x, %y
  %r.bits = bitcast double %r to i64
  %r.val = insertvalue %Val { i64 3, i64 0 }, i64 %r.bits, 1
  ret %Val %r.val
int:
  %wide = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %a.bits, i64 %b.bits)
  %n = extractvalue {i64, i1} %wide, 0
  %over = extractvalue {i64, i1} %wide, 1
  br i1 %over, label %overflow, label %exact
overflow:
  call void @rterr.int(i32 0)
  unreachable
exact:
  %n.val = insertvalue %Val { i64 2, i64 0 }, i64 %n, 1
  ret %Val %n.val
other:
  call void @opsrt.pair(ptr @.opsrt.who.add, i32 %a.tag, i32 %b.tag)
  unreachable
}
@.objrt.fieldType = private unnamed_addr constant [30 x i8] c".-%s expects a record, got %s\00"
@.objrt.noField = private unnamed_addr constant [23 x i8] c"record has no field %s\00"
@.objrt.captureType = private unnamed_addr constant [28 x i8] c"closure environment is a %s\00"
@.objrt.captureRange = private unnamed_addr constant [46 x i8] c"capture %lld outside the %d captured value(s)\00"
@.objrt.arity = private unnamed_addr constant [36 x i8] c"%s expects %d argument(s), got %lld\00"
@.objrt.notFn = private unnamed_addr constant [17 x i8] c"cannot call a %s\00"
@.objrt.bytecode = private unnamed_addr constant [49 x i8] c"%s is bytecode, which a native binary cannot run\00"
@.objrt.partialLimit = private unnamed_addr constant [48 x i8] c"partial application with more than 64 arguments\00"
@.objrt.symbol = private unnamed_addr constant [51 x i8] c"symbol %s: the host value model has no symbol type\00"
@.objrt.strLimit = private unnamed_addr constant [50 x i8] c"string constant: count %lld outside 0..2147483647\00"
@.objrt.partial = private unnamed_addr constant [8 x i8] c"partial\00"
@objrt.partialId = internal global i32 -1
define internal i32 @objrt.nameId(ptr %cell, ptr %name, i64 %len) {
entry:
  %id = load i32, ptr %cell
  %known = icmp sge i32 %id, 0
  br i1 %known, label %done, label %resolve
resolve:
  %fresh = call i32 @valrt.intern(ptr %name, i64 %len)
  store i32 %fresh, ptr %cell
  ret i32 %fresh
done:
  ret i32 %id
}
define internal %Val @objrt.str(ptr %cell, ptr %bytes, i64 %len) {
entry:
  %cached = load %Val, ptr %cell
  %cachedTag = extractvalue %Val %cached, 0
  %built = icmp ne i64 %cachedTag, 0
  br i1 %built, label %done, label %check
check:
  %fits = icmp ule i64 %len, 2147483647
  br i1 %fits, label %build, label %tooLong
tooLong:
  call void @rterr.raiseNumber(ptr @.rterr.c.ERR_LIMIT, ptr @.objrt.strLimit, i64 %len)
  unreachable
build:
  %size = add i64 %len, 17
  %obj = call ptr @asl_alloc(i32 0, i64 %size)
  %lenp = getelementptr inbounds i8, ptr %obj, i64 8
  store i64 %len, ptr %lenp
  %data = getelementptr inbounds i8, ptr %obj, i64 16
  call void @llvm.memcpy.p0.p0.i64(ptr %data, ptr %bytes, i64 %len, i1 false)
  %end = getelementptr inbounds i8, ptr %data, i64 %len
  store i8 0, ptr %end
  %objw = ptrtoint ptr %obj to i64
  %str = insertvalue %Val { i64 5, i64 0 }, i64 %objw, 1
  store %Val %str, ptr %cell
  call void @asl_rt_global_root(ptr %cell)
  ret %Val %str
done:
  ret %Val %cached
}
define internal %Val @objrt.field(%Val %v, ptr %cell, ptr %name, i64 %len) {
entry:
  %tagw = extractvalue %Val %v, 0
  %tag = trunc i64 %tagw to i32
  %objw = extractvalue %Val %v, 1
  %obj = inttoptr i64 %objw to ptr
  %isRec = icmp eq i32 %tag, 7
  br i1 %isRec, label %rec, label %notRec
rec:
  %key = call i32 @objrt.nameId(ptr %cell, ptr %name, i64 %len)
  %np = getelementptr inbounds i8, ptr %obj, i64 12
  %n = load i32, ptr %np
  %keysp = getelementptr inbounds i8, ptr %obj, i64 16
  %keys = load ptr, ptr %keysp
  br label %loop
loop:
  %i = phi i32 [ 0, %rec ], [ %next, %body ]
  %inRange = icmp slt i32 %i, %n
  br i1 %inRange, label %body, label %missing
body:
  %keyp = getelementptr inbounds i32, ptr %keys, i32 %i
  %k = load i32, ptr %keyp
  %next = add i32 %i, 1
  %match = icmp eq i32 %k, %key
  br i1 %match, label %found, label %loop
found:
  %i64 = sext i32 %i to i64
  %off = mul i64 %i64, 16
  %slot = add i64 %off, 24
  %valp = getelementptr inbounds i8, ptr %obj, i64 %slot
  %value = load %Val, ptr %valp
  ret %Val %value
missing:
  call void @rterr.raiseText(ptr @.rterr.c.ERR_FIELD, ptr @.objrt.noField, ptr %name)
  unreachable
notRec:
  %tname = call ptr @rterr.tagName(i32 %tag)
  %type.buf = alloca [4096 x i8]
  store i8 0, ptr %type.buf
  %type.written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %type.buf, i64 4096, ptr @.objrt.fieldType, ptr %name, ptr %tname)
  %type.len = call i64 @strlen(ptr %type.buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_TYPE, ptr %type.buf, i64 %type.len)
  unreachable
}
define internal %Val @objrt.capture(%Val %env, i64 %i) {
entry:
  %tagw = extractvalue %Val %env, 0
  %tag = trunc i64 %tagw to i32
  %objw = extractvalue %Val %env, 1
  %obj = inttoptr i64 %objw to ptr
  %isFn = icmp eq i32 %tag, 9
  br i1 %isFn, label %closure, label %notFn
closure:
  %np = getelementptr inbounds i8, ptr %obj, i64 16
  %n = load i32, ptr %np
  %n64 = sext i32 %n to i64
  %nonNegative = icmp sge i64 %i, 0
  %below = icmp slt i64 %i, %n64
  %inRange = and i1 %nonNegative, %below
  br i1 %inRange, label %found, label %range
found:
  %off = mul i64 %i, 16
  %slot = add i64 %off, 24
  %valp = getelementptr inbounds i8, ptr %obj, i64 %slot
  %value = load %Val, ptr %valp
  ret %Val %value
range:
  %buf = alloca [4096 x i8]
  store i8 0, ptr %buf
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.objrt.captureRange, i64 %i, i32 %n)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_RANGE, ptr %buf, i64 %len)
  unreachable
notFn:
  %tname = call ptr @rterr.tagName(i32 %tag)
  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.objrt.captureType, ptr %tname)
  unreachable
}
define internal %Val @objrt.call(%Val %fn, i64 %argc, ptr %argv) {
entry:
  %all = alloca [64 x %Val]
  %tagw = extractvalue %Val %fn, 0
  %tag = trunc i64 %tagw to i32
  %objw = extractvalue %Val %fn, 1
  %obj = inttoptr i64 %objw to ptr
  %isFn = icmp eq i32 %tag, 9
  br i1 %isFn, label %closure, label %notFn
closure:
  %protop = getelementptr inbounds i8, ptr %obj, i64 8
  %proto = load ptr, ptr %protop
  %codep = getelementptr inbounds i8, ptr %proto, i64 56
  %code = load ptr, ptr %codep
  %native = icmp ne ptr %code, null
  br i1 %native, label %arity, label %bytecode
arity:
  %np = getelementptr inbounds i8, ptr %proto, i64 16
  %n = load i32, ptr %np
  %n64 = sext i32 %n to i64
  %fits = icmp eq i64 %argc, %n64
  br i1 %fits, label %direct, label %wrongArity
direct:
  %result = call %Val %code(%Val %fn, i64 %argc, ptr %argv)
  ret %Val %result
wrongArity:
  %pname = load ptr, ptr %proto
  %buf = alloca [4096 x i8]
  store i8 0, ptr %buf
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.objrt.arity, ptr %pname, i32 %n, i64 %argc)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_ARITY, ptr %buf, i64 %len)
  unreachable
notFn:
  %isCtor = icmp eq i32 %tag, 8
  br i1 %isCtor, label %ctor, label %bad
ctor:
  %idp = getelementptr inbounds i8, ptr %obj, i64 8
  %id = load i32, ptr %idp
  %partialId = call i32 @objrt.nameId(ptr @objrt.partialId, ptr @.objrt.partial, i64 7)
  %isPartial = icmp eq i32 %id, %partialId
  %cnp = getelementptr inbounds i8, ptr %obj, i64 12
  %cn = load i32, ptr %cnp
  %hasHead = icmp sgt i32 %cn, 0
  %callable = and i1 %isPartial, %hasHead
  br i1 %callable, label %partial, label %bad
partial:
  %cn64 = sext i32 %cn to i64
  %bound = sub i64 %cn64, 1
  %total = add i64 %bound, %argc
  %over = icmp sgt i64 %total, 64
  br i1 %over, label %tooMany, label %splice
tooMany:
  call void @rterr.raise(ptr @.rterr.c.ERR_LIMIT, ptr @.objrt.partialLimit, i64 47)
  unreachable
splice:
  %boundBytes = mul i64 %bound, 16
  %boundp = getelementptr inbounds i8, ptr %obj, i64 32
  call void @llvm.memcpy.p0.p0.i64(ptr %all, ptr %boundp, i64 %boundBytes, i1 false)
  %argBytes = mul i64 %argc, 16
  %rest = getelementptr inbounds i8, ptr %all, i64 %boundBytes
  call void @llvm.memcpy.p0.p0.i64(ptr %rest, ptr %argv, i64 %argBytes, i1 false)
  %headp = getelementptr inbounds i8, ptr %obj, i64 16
  %head = load %Val, ptr %headp
  %spliced = call %Val @objrt.call(%Val %head, i64 %total, ptr %all)
  ret %Val %spliced
bytecode:
  %bname = load ptr, ptr %proto
  %b.buf = alloca [4096 x i8]
  store i8 0, ptr %b.buf
  %b.written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %b.buf, i64 4096, ptr @.objrt.bytecode, ptr %bname)
  %b.len = call i64 @strlen(ptr %b.buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_INTERNAL, ptr %b.buf, i64 %b.len)
  unreachable
bad:
  %tname = call ptr @rterr.tagName(i32 %tag)
  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.objrt.notFn, ptr %tname)
  unreachable
}
define internal %Val @objrt.symbol(ptr %name) noreturn {
entry:
  call void @rterr.raiseText(ptr @.rterr.c.ERR_UNSUPPORTED, ptr @.objrt.symbol, ptr %name)
  unreachable
}
@.rterr.c.ERR_INTERNAL = private unnamed_addr constant [13 x i8] c"ERR_INTERNAL\00"
@.rterr.c.ERR_INT_OVERFLOW = private unnamed_addr constant [17 x i8] c"ERR_INT_OVERFLOW\00"
@.rterr.c.ERR_DIV_ZERO = private unnamed_addr constant [13 x i8] c"ERR_DIV_ZERO\00"
@.rterr.c.ERR_TYPE = private unnamed_addr constant [9 x i8] c"ERR_TYPE\00"
@.rterr.m.add = private unnamed_addr constant [19 x i8] c"Int + leaves int64\00"
@.rterr.m.sub = private unnamed_addr constant [19 x i8] c"Int - leaves int64\00"
@.rterr.m.mul = private unnamed_addr constant [19 x i8] c"Int * leaves int64\00"
@.rterr.m.div = private unnamed_addr constant [19 x i8] c"Int / leaves int64\00"
@.rterr.m.divZero = private unnamed_addr constant [17 x i8] c"division by zero\00"
@.rterr.m.modZero = private unnamed_addr constant [12 x i8] c"mod by zero\00"
@.rterr.m.narrow = private unnamed_addr constant [24 x i8] c"Int narrow leaves int32\00"
@.rterr.m.floatInt = private unnamed_addr constant [26 x i8] c"Float to Int leaves int64\00"
@.rterr.m.intKind = private unnamed_addr constant [26 x i8] c"unknown integer trap %lld\00"
@.rterr.m.wantInt = private unnamed_addr constant [34 x i8] c"compiled code expects Int, got %s\00"
@.rterr.m.wantFloat = private unnamed_addr constant [36 x i8] c"compiled code expects Float, got %s\00"
@.rterr.m.wantBool = private unnamed_addr constant [31 x i8] c"condition must be Bool, got %s\00"
@.rterr.m.wantVariant = private unnamed_addr constant [32 x i8] c"match expects a variant, got %s\00"
@.rterr.m.wantKind = private unnamed_addr constant [28 x i8] c"unknown type trap want %lld\00"
@.rterr.tag.0 = private unnamed_addr constant [5 x i8] c"Unit\00"
@.rterr.tag.1 = private unnamed_addr constant [5 x i8] c"Bool\00"
@.rterr.tag.2 = private unnamed_addr constant [4 x i8] c"Int\00"
@.rterr.tag.3 = private unnamed_addr constant [6 x i8] c"Float\00"
@.rterr.tag.4 = private unnamed_addr constant [8 x i8] c"Keyword\00"
@.rterr.tag.5 = private unnamed_addr constant [7 x i8] c"String\00"
@.rterr.tag.6 = private unnamed_addr constant [5 x i8] c"List\00"
@.rterr.tag.7 = private unnamed_addr constant [7 x i8] c"Record\00"
@.rterr.tag.8 = private unnamed_addr constant [8 x i8] c"Variant\00"
@.rterr.tag.9 = private unnamed_addr constant [3 x i8] c"Fn\00"
@.rterr.tag.10 = private unnamed_addr constant [8 x i8] c"Builtin\00"
@.rterr.tag.11 = private unnamed_addr constant [6 x i8] c"Bytes\00"
@.rterr.tag.12 = private unnamed_addr constant [9 x i8] c"F64Array\00"
@.rterr.tag.13 = private unnamed_addr constant [9 x i8] c"I64Array\00"
@.rterr.tag.14 = private unnamed_addr constant [8 x i8] c"I8Array\00"
@.rterr.tag.15 = private unnamed_addr constant [7 x i8] c"Handle\00"
@.rterr.tag.unknown = private unnamed_addr constant [2 x i8] c"?\00"
@.rterr.tags = private unnamed_addr constant [16 x ptr] [ptr @.rterr.tag.0, ptr @.rterr.tag.1, ptr @.rterr.tag.2, ptr @.rterr.tag.3, ptr @.rterr.tag.4, ptr @.rterr.tag.5, ptr @.rterr.tag.6, ptr @.rterr.tag.7, ptr @.rterr.tag.8, ptr @.rterr.tag.9, ptr @.rterr.tag.10, ptr @.rterr.tag.11, ptr @.rterr.tag.12, ptr @.rterr.tag.13, ptr @.rterr.tag.14, ptr @.rterr.tag.15]
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

define internal void @rterr.raiseText(ptr %code, ptr %format, ptr %arg) noreturn {
entry:
  %buf = alloca [4096 x i8]
  store i8 0, ptr %buf
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr %format, ptr %arg)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.raise(ptr %code, ptr %buf, i64 %len)
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

define internal ptr @rterr.tagName(i32 %tag) {
entry:
  %known = icmp ult i32 %tag, 16
  br i1 %known, label %named, label %unnamed
named:
  %index = zext i32 %tag to i64
  %slot = getelementptr [16 x ptr], ptr @.rterr.tags, i64 0, i64 %index
  %name = load ptr, ptr %slot
  ret ptr %name
unnamed:
  ret ptr @.rterr.tag.unknown
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

define internal void @rterr.type(i32 %got, i32 %want) noreturn {
entry:
  %name = call ptr @rterr.tagName(i32 %got)
  switch i32 %want, label %unknown [ i32 2, label %int i32 3, label %float i32 1, label %bool i32 8, label %variant ]
int:
  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.rterr.m.wantInt, ptr %name)
  unreachable
float:
  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.rterr.m.wantFloat, ptr %name)
  unreachable
bool:
  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.rterr.m.wantBool, ptr %name)
  unreachable
variant:
  call void @rterr.raiseText(ptr @.rterr.c.ERR_TYPE, ptr @.rterr.m.wantVariant, ptr %name)
  unreachable
unknown:
  %wide = sext i32 %want to i64
  call void @rterr.raiseNumber(ptr @.rterr.c.ERR_INTERNAL, ptr @.rterr.m.wantKind, i64 %wide)
  unreachable
}
@.rterr.c.ERR_ARITY = private unnamed_addr constant [10 x i8] c"ERR_ARITY\00"
@.rterr.c.ERR_FIELD = private unnamed_addr constant [10 x i8] c"ERR_FIELD\00"
@.rterr.c.ERR_LIMIT = private unnamed_addr constant [10 x i8] c"ERR_LIMIT\00"
@.rterr.c.ERR_RANGE = private unnamed_addr constant [10 x i8] c"ERR_RANGE\00"
@.rterr.c.ERR_UNSUPPORTED = private unnamed_addr constant [16 x i8] c"ERR_UNSUPPORTED\00"
@valrt.slots = weak global ptr null
@valrt.capacity = weak global i64 0
@valrt.names = weak global ptr null
@valrt.count = weak global i64 0
@valrt.room = weak global i64 0
@valrt.handler = weak global ptr null
@valrt.errorMsg = weak global [4096 x i8] zeroinitializer

define internal i64 @valrt.hash(ptr %text, i64 %length) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %next, %step ]
  %h = phi i64 [ 1469598103934665603, %entry ], [ %mixed, %step ]
  %done = icmp uge i64 %i, %length
  br i1 %done, label %out, label %step
step:
  %at = getelementptr inbounds i8, ptr %text, i64 %i
  %byte = load i8, ptr %at
  %wide = zext i8 %byte to i64
  %folded = xor i64 %h, %wide
  %mixed = mul i64 %folded, 1099511628211
  %next = add i64 %i, 1
  br label %loop
out:
  ret i64 %h
}

define internal void @valrt.place(ptr %slots, i64 %mask, i64 %id) {
entry:
  %names = load ptr, ptr @valrt.names
  %offset = mul i64 %id, 16
  %record = getelementptr inbounds i8, ptr %names, i64 %offset
  %text = load ptr, ptr %record
  %lengthp = getelementptr inbounds i8, ptr %record, i64 8
  %length = load i64, ptr %lengthp
  %h = call i64 @valrt.hash(ptr %text, i64 %length)
  %start = and i64 %h, %mask
  br label %probe
probe:
  %j = phi i64 [ %start, %entry ], [ %after, %taken ]
  %slotp = getelementptr inbounds i32, ptr %slots, i64 %j
  %slot = load i32, ptr %slotp
  %free = icmp eq i32 %slot, 0
  br i1 %free, label %store, label %taken
taken:
  %stepped = add i64 %j, 1
  %after = and i64 %stepped, %mask
  br label %probe
store:
  %id32 = trunc i64 %id to i32
  %mark = add i32 %id32, 1
  store i32 %mark, ptr %slotp
  ret void
}

define internal void @valrt.grow(i64 %capacity) {
entry:
  %fresh = call ptr @calloc(i64 %capacity, i64 4)
  %failed = icmp eq ptr %fresh, null
  br i1 %failed, label %oom, label %fill
oom:
  call void @exit(i32 70)
  unreachable
fill:
  %mask = sub i64 %capacity, 1
  %count = load i64, ptr @valrt.count
  br label %loop
loop:
  %id = phi i64 [ 0, %fill ], [ %next, %body ]
  %more = icmp ult i64 %id, %count
  br i1 %more, label %body, label %done
body:
  call void @valrt.place(ptr %fresh, i64 %mask, i64 %id)
  %next = add i64 %id, 1
  br label %loop
done:
  %old = load ptr, ptr @valrt.slots
  call void @free(ptr %old)
  store ptr %fresh, ptr @valrt.slots
  store i64 %capacity, ptr @valrt.capacity
  ret void
}

define internal i32 @valrt.add(ptr %text, i64 %length, ptr %slotp) {
entry:
  %count = load i64, ptr @valrt.count
  %full = icmp uge i64 %count, 2147483646
  br i1 %full, label %oom, label %copy
copy:
  %size = add i64 %length, 1
  %bytes = call ptr @malloc(i64 %size)
  %noBytes = icmp eq ptr %bytes, null
  br i1 %noBytes, label %oom, label %fill
fill:
  call void @llvm.memcpy.p0.p0.i64(ptr %bytes, ptr %text, i64 %length, i1 false)
  %end = getelementptr inbounds i8, ptr %bytes, i64 %length
  store i8 0, ptr %end
  %room = load i64, ptr @valrt.room
  %fits = icmp ult i64 %count, %room
  br i1 %fits, label %record, label %widen
widen:
  %none = icmp eq i64 %room, 0
  %doubled = shl i64 %room, 1
  %wider = select i1 %none, i64 1024, i64 %doubled
  %wideBytes = mul i64 %wider, 16
  %old = load ptr, ptr @valrt.names
  %grown = call ptr @realloc(ptr %old, i64 %wideBytes)
  %noRoom = icmp eq ptr %grown, null
  br i1 %noRoom, label %oom, label %widened
widened:
  store ptr %grown, ptr @valrt.names
  store i64 %wider, ptr @valrt.room
  br label %record
record:
  %names = load ptr, ptr @valrt.names
  %offset = mul i64 %count, 16
  %entry.record = getelementptr inbounds i8, ptr %names, i64 %offset
  store ptr %bytes, ptr %entry.record
  %lengthp = getelementptr inbounds i8, ptr %entry.record, i64 8
  store i64 %length, ptr %lengthp
  %id = trunc i64 %count to i32
  %mark = add i32 %id, 1
  store i32 %mark, ptr %slotp
  %next = add i64 %count, 1
  store i64 %next, ptr @valrt.count
  ret i32 %id
oom:
  call void @exit(i32 70)
  unreachable
}

define internal i32 @valrt.find(ptr %text, i64 %length) {
entry:
  %count = load i64, ptr @valrt.count
  %capacity = load i64, ptr @valrt.capacity
  %twice = shl i64 %count, 1
  %crowded = icmp uge i64 %twice, %capacity
  br i1 %crowded, label %grow, label %ready
grow:
  %empty = icmp eq i64 %capacity, 0
  %doubled = shl i64 %capacity, 1
  %bigger = select i1 %empty, i64 1024, i64 %doubled
  call void @valrt.grow(i64 %bigger)
  br label %ready
ready:
  %slots = load ptr, ptr @valrt.slots
  %size = load i64, ptr @valrt.capacity
  %mask = sub i64 %size, 1
  %names = load ptr, ptr @valrt.names
  %h = call i64 @valrt.hash(ptr %text, i64 %length)
  %start = and i64 %h, %mask
  br label %probe
probe:
  %j = phi i64 [ %start, %ready ], [ %after, %differ ]
  %slotp = getelementptr inbounds i32, ptr %slots, i64 %j
  %slot = load i32, ptr %slotp
  %free = icmp eq i32 %slot, 0
  br i1 %free, label %add, label %compare
compare:
  %id = sub i32 %slot, 1
  %wide = zext i32 %id to i64
  %offset = mul i64 %wide, 16
  %record = getelementptr inbounds i8, ptr %names, i64 %offset
  %lengthp = getelementptr inbounds i8, ptr %record, i64 8
  %known = load i64, ptr %lengthp
  %sameLength = icmp eq i64 %known, %length
  br i1 %sameLength, label %bytes, label %differ
bytes:
  %name = load ptr, ptr %record
  %order = call i32 @memcmp(ptr %name, ptr %text, i64 %length)
  %same = icmp eq i32 %order, 0
  br i1 %same, label %found, label %differ
found:
  ret i32 %id
differ:
  %stepped = add i64 %j, 1
  %after = and i64 %stepped, %mask
  br label %probe
add:
  %fresh = call i32 @valrt.add(ptr %text, i64 %length, ptr %slotp)
  ret i32 %fresh
}

define weak i32 @aslInternShared(ptr %text, i64 %length) {
entry:
  %id = call i32 @valrt.find(ptr %text, i64 %length)
  ret i32 %id
}

define internal i32 @valrt.intern(ptr %text, i64 %length) {
entry:
  %id = call i32 @aslInternShared(ptr %text, i64 %length)
  ret i32 %id
}

define weak ptr @aslHandlerSlot() {
entry:
  ret ptr @valrt.handler
}

define weak ptr @aslErrorText() {
entry:
  ret ptr @valrt.errorMsg
}
declare %Val @net$2Ffetch(%Val, %Val)
declare ptr @asl_alloc(i32, i64)
declare ptr @asl_alloc_raw(i32, i64)
declare void @asl_rt_global_root(ptr)
declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare i64 @strlen(ptr)
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i64 @write(i32, ptr, i64)
declare void @exit(i32)
declare i32 @fflush(ptr)
declare void @longjmp(ptr, i32) noreturn
declare ptr @calloc(i64, i64)
declare i32 @memcmp(ptr, ptr, i64)
