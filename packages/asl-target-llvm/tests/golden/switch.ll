source_filename = "switch"

%Val = type { i64, i64 }

@name.circle = private unnamed_addr constant [7 x i8] c"circle\00"
@name.square = private unnamed_addr constant [7 x i8] c"square\00"
@name.empty = private unnamed_addr constant [6 x i8] c"empty\00"
@name.size = private unnamed_addr constant [5 x i8] c"size\00"
@name.isEmpty = private unnamed_addr constant [8 x i8] c"isEmpty\00"
@variants.Shape = private unnamed_addr constant [3 x ptr] [ptr @name.circle, ptr @name.square, ptr @name.empty]
@variantIds.Shape = internal global [3 x i32] zeroinitializer
@variantIdsReady.Shape = internal global i1 false

define tailcc %Val @size(%Val %shape) {
bb.entry:
  %zero = insertvalue %Val { i64 2, i64 0 }, i64 0, 1
  %bb.entry.vtagw = extractvalue %Val %shape, 0
  %bb.entry.vtag = trunc i64 %bb.entry.vtagw to i32
  %bb.entry.isCtor = icmp eq i32 %bb.entry.vtag, 8
  br i1 %bb.entry.isCtor, label %bb.entry.variant, label %bb.entry.miss
bb.entry.variant:
  %bb.entry.objw = extractvalue %Val %shape, 1
  %bb.entry.obj = inttoptr i64 %bb.entry.objw to ptr
  %bb.entry.ctorp = getelementptr inbounds i8, ptr %bb.entry.obj, i64 8
  %bb.entry.ctor = load i32, ptr %bb.entry.ctorp
  %bb.entry.ready = load i1, ptr @variantIdsReady.Shape
  br i1 %bb.entry.ready, label %bb.entry.scan, label %bb.entry.resolve
bb.entry.resolve:
  call void @variantIdsInit.Shape()
  br label %bb.entry.scan
bb.entry.scan:
  %bb.entry.idp0 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 0
  %bb.entry.id0 = load i32, ptr %bb.entry.idp0
  %bb.entry.eq0 = icmp eq i32 %bb.entry.ctor, %bb.entry.id0
  %bb.entry.idp1 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 1
  %bb.entry.id1 = load i32, ptr %bb.entry.idp1
  %bb.entry.eq1 = icmp eq i32 %bb.entry.ctor, %bb.entry.id1
  %bb.entry.idp2 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 2
  %bb.entry.id2 = load i32, ptr %bb.entry.idp2
  %bb.entry.eq2 = icmp eq i32 %bb.entry.ctor, %bb.entry.id2
  %bb.entry.sel2 = select i1 %bb.entry.eq2, i64 2, i64 -1
  %bb.entry.sel1 = select i1 %bb.entry.eq1, i64 1, i64 %bb.entry.sel2
  %bb.entry.tag = select i1 %bb.entry.eq0, i64 0, i64 %bb.entry.sel1
  %bb.entry.found = icmp sge i64 %bb.entry.tag, 0
  %bb.entry.np = getelementptr inbounds i8, ptr %bb.entry.obj, i64 12
  %bb.entry.n = load i32, ptr %bb.entry.np
  %bb.entry.want.is0 = icmp eq i64 %bb.entry.tag, 0
  %bb.entry.want0 = select i1 %bb.entry.want.is0, i32 1, i32 -1
  %bb.entry.want.is1 = icmp eq i64 %bb.entry.tag, 1
  %bb.entry.want1 = select i1 %bb.entry.want.is1, i32 1, i32 %bb.entry.want0
  %bb.entry.armed = icmp sge i32 %bb.entry.want1, 0
  %bb.entry.differs = icmp ne i32 %bb.entry.want1, %bb.entry.n
  %bb.entry.badArity = and i1 %bb.entry.armed, %bb.entry.differs
  br i1 %bb.entry.badArity, label %bb.entry.arity, label %bb.entry.check
bb.entry.arity:
  %bb.entry.pname.is0 = icmp eq i64 %bb.entry.tag, 0
  %bb.entry.pname0 = select i1 %bb.entry.pname.is0, ptr @name.circle, ptr null
  %bb.entry.pname.is1 = icmp eq i64 %bb.entry.tag, 1
  %bb.entry.pname1 = select i1 %bb.entry.pname.is1, ptr @name.square, ptr %bb.entry.pname0
  call void @objrt.patternArity(ptr %bb.entry.pname1, i32 %bb.entry.want1, i32 %bb.entry.n)
  unreachable
bb.entry.check:
  br i1 %bb.entry.found, label %bb.entry.match, label %bb.entry.miss
bb.entry.miss:
  %bb.entry.missIsCtor = icmp eq i32 %bb.entry.vtag, 8
  br i1 %bb.entry.missIsCtor, label %bb.entry.foreign, label %bb.entry.typeFail
bb.entry.foreign:
  call void @rterr.matchValue(%Val %shape, ptr @name.size)
  unreachable
bb.entry.typeFail:
  call void @rterr.type(i32 %bb.entry.vtag, i32 8)
  unreachable
bb.entry.match:
  switch i64 %bb.entry.tag, label %bb.join [
    i64 1, label %bb.onSquare
    i64 0, label %bb.onCircle
  ]
bb.onCircle:
  %r.vtagw = extractvalue %Val %shape, 0
  %r.vtag = trunc i64 %r.vtagw to i32
  %r.isCtor = icmp eq i32 %r.vtag, 8
  br i1 %r.isCtor, label %r.ctor, label %r.slow
r.ctor:
  %r.objw = extractvalue %Val %shape, 1
  %r.obj = inttoptr i64 %r.objw to ptr
  %r.np = getelementptr inbounds i8, ptr %r.obj, i64 12
  %r.n = load i32, ptr %r.np
  %r.n64 = sext i32 %r.n to i64
  %r.inRange = icmp slt i64 0, %r.n64
  br i1 %r.inRange, label %r.fast, label %r.slow
r.fast:
  %r.fp = getelementptr inbounds i8, ptr %r.obj, i64 16
  %r.fastval = load %Val, ptr %r.fp
  br label %r.join
r.slow:
  %r.slowval = call %Val @objrt.variantField(%Val %shape, i64 0)
  br label %r.join
r.join:
  %r = phi %Val [ %r.fastval, %r.fast ], [ %r.slowval, %r.slow ]
  br label %bb.join
bb.onSquare:
  %side.vtagw = extractvalue %Val %shape, 0
  %side.vtag = trunc i64 %side.vtagw to i32
  %side.isCtor = icmp eq i32 %side.vtag, 8
  br i1 %side.isCtor, label %side.ctor, label %side.slow
side.ctor:
  %side.objw = extractvalue %Val %shape, 1
  %side.obj = inttoptr i64 %side.objw to ptr
  %side.np = getelementptr inbounds i8, ptr %side.obj, i64 12
  %side.n = load i32, ptr %side.np
  %side.n64 = sext i32 %side.n to i64
  %side.inRange = icmp slt i64 0, %side.n64
  br i1 %side.inRange, label %side.fast, label %side.slow
side.fast:
  %side.fp = getelementptr inbounds i8, ptr %side.obj, i64 16
  %side.fastval = load %Val, ptr %side.fp
  br label %side.join
side.slow:
  %side.slowval = call %Val @objrt.variantField(%Val %shape, i64 0)
  br label %side.join
side.join:
  %side = phi %Val [ %side.fastval, %side.fast ], [ %side.slowval, %side.slow ]
  br label %bb.join
bb.join:
  %result = phi %Val [ %zero, %bb.entry.match ], [ %r, %r.join ], [ %side, %side.join ]
  ret %Val %result
}

define tailcc i1 @isEmpty(%Val %shape) {
bb.entry:
  %bb.entry.vtagw = extractvalue %Val %shape, 0
  %bb.entry.vtag = trunc i64 %bb.entry.vtagw to i32
  %bb.entry.isCtor = icmp eq i32 %bb.entry.vtag, 8
  br i1 %bb.entry.isCtor, label %bb.entry.variant, label %bb.entry.miss
bb.entry.variant:
  %bb.entry.objw = extractvalue %Val %shape, 1
  %bb.entry.obj = inttoptr i64 %bb.entry.objw to ptr
  %bb.entry.ctorp = getelementptr inbounds i8, ptr %bb.entry.obj, i64 8
  %bb.entry.ctor = load i32, ptr %bb.entry.ctorp
  %bb.entry.ready = load i1, ptr @variantIdsReady.Shape
  br i1 %bb.entry.ready, label %bb.entry.scan, label %bb.entry.resolve
bb.entry.resolve:
  call void @variantIdsInit.Shape()
  br label %bb.entry.scan
bb.entry.scan:
  %bb.entry.idp0 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 0
  %bb.entry.id0 = load i32, ptr %bb.entry.idp0
  %bb.entry.eq0 = icmp eq i32 %bb.entry.ctor, %bb.entry.id0
  %bb.entry.idp1 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 1
  %bb.entry.id1 = load i32, ptr %bb.entry.idp1
  %bb.entry.eq1 = icmp eq i32 %bb.entry.ctor, %bb.entry.id1
  %bb.entry.idp2 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 2
  %bb.entry.id2 = load i32, ptr %bb.entry.idp2
  %bb.entry.eq2 = icmp eq i32 %bb.entry.ctor, %bb.entry.id2
  %bb.entry.sel2 = select i1 %bb.entry.eq2, i64 2, i64 -1
  %bb.entry.sel1 = select i1 %bb.entry.eq1, i64 1, i64 %bb.entry.sel2
  %bb.entry.tag = select i1 %bb.entry.eq0, i64 0, i64 %bb.entry.sel1
  %bb.entry.found = icmp sge i64 %bb.entry.tag, 0
  %bb.entry.np = getelementptr inbounds i8, ptr %bb.entry.obj, i64 12
  %bb.entry.n = load i32, ptr %bb.entry.np
  %bb.entry.want.is0 = icmp eq i64 %bb.entry.tag, 0
  %bb.entry.want0 = select i1 %bb.entry.want.is0, i32 1, i32 -1
  %bb.entry.want.is1 = icmp eq i64 %bb.entry.tag, 1
  %bb.entry.want1 = select i1 %bb.entry.want.is1, i32 1, i32 %bb.entry.want0
  %bb.entry.want.is2 = icmp eq i64 %bb.entry.tag, 2
  %bb.entry.want2 = select i1 %bb.entry.want.is2, i32 0, i32 %bb.entry.want1
  %bb.entry.armed = icmp sge i32 %bb.entry.want2, 0
  %bb.entry.differs = icmp ne i32 %bb.entry.want2, %bb.entry.n
  %bb.entry.badArity = and i1 %bb.entry.armed, %bb.entry.differs
  br i1 %bb.entry.badArity, label %bb.entry.arity, label %bb.entry.check
bb.entry.arity:
  %bb.entry.pname.is0 = icmp eq i64 %bb.entry.tag, 0
  %bb.entry.pname0 = select i1 %bb.entry.pname.is0, ptr @name.circle, ptr null
  %bb.entry.pname.is1 = icmp eq i64 %bb.entry.tag, 1
  %bb.entry.pname1 = select i1 %bb.entry.pname.is1, ptr @name.square, ptr %bb.entry.pname0
  %bb.entry.pname.is2 = icmp eq i64 %bb.entry.tag, 2
  %bb.entry.pname2 = select i1 %bb.entry.pname.is2, ptr @name.empty, ptr %bb.entry.pname1
  call void @objrt.patternArity(ptr %bb.entry.pname2, i32 %bb.entry.want2, i32 %bb.entry.n)
  unreachable
bb.entry.check:
  br i1 %bb.entry.found, label %bb.entry.match, label %bb.entry.miss
bb.entry.miss:
  %bb.entry.missIsCtor = icmp eq i32 %bb.entry.vtag, 8
  br i1 %bb.entry.missIsCtor, label %bb.entry.foreign, label %bb.entry.typeFail
bb.entry.foreign:
  call void @rterr.matchValue(%Val %shape, ptr @name.isEmpty)
  unreachable
bb.entry.typeFail:
  call void @rterr.type(i32 %bb.entry.vtag, i32 8)
  unreachable
bb.entry.match:
  switch i64 %bb.entry.tag, label %bb.entry.nomatch [
    i64 0, label %bb.no
    i64 1, label %bb.no
    i64 2, label %bb.yes
  ]
bb.entry.nomatch:
  unreachable
bb.no:
  %f = bitcast i1 false to i1
  ret i1 %f
bb.yes:
  %t = bitcast i1 true to i1
  ret i1 %t
}

define internal void @variantIdsInit.Shape() {
bb.entry:
  %kw.0.aux = call i32 @valrt.intern(ptr @name.circle, i64 6)
  %slot.0 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 0
  store i32 %kw.0.aux, ptr %slot.0
  %kw.1.aux = call i32 @valrt.intern(ptr @name.square, i64 6)
  %slot.1 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 1
  store i32 %kw.1.aux, ptr %slot.1
  %kw.2.aux = call i32 @valrt.intern(ptr @name.empty, i64 5)
  %slot.2 = getelementptr inbounds [3 x i32], ptr @variantIds.Shape, i64 0, i64 2
  store i32 %kw.2.aux, ptr %slot.2
  store i1 true, ptr @variantIdsReady.Shape
  ret void
}

@.objrt.variantType = private unnamed_addr constant [27 x i8] c"variant field %lld of a %s\00"
@.objrt.variantRange = private unnamed_addr constant [42 x i8] c"variant %s has %d field(s), no field %lld\00"
@.objrt.patternArity = private unnamed_addr constant [45 x i8] c"pattern (%s) binds %u field(s), value has %d\00"
define internal %Val @objrt.variantField(%Val %v, i64 %i) {
entry:
  %tagw = extractvalue %Val %v, 0
  %tag = trunc i64 %tagw to i32
  %objw = extractvalue %Val %v, 1
  %obj = inttoptr i64 %objw to ptr
  %isCtor = icmp eq i32 %tag, 8
  br i1 %isCtor, label %ctor, label %notCtor
ctor:
  %np = getelementptr inbounds i8, ptr %obj, i64 12
  %n = load i32, ptr %np
  %n64 = sext i32 %n to i64
  %nonNegative = icmp sge i64 %i, 0
  %below = icmp slt i64 %i, %n64
  %inRange = and i1 %nonNegative, %below
  br i1 %inRange, label %found, label %range
found:
  %off = mul i64 %i, 16
  %slot = add i64 %off, 16
  %valp = getelementptr inbounds i8, ptr %obj, i64 %slot
  %value = load %Val, ptr %valp
  ret %Val %value
range:
  %idp = getelementptr inbounds i8, ptr %obj, i64 8
  %id = load i32, ptr %idp
  %vname = call ptr @valrt.symName(i32 %id)
  %range.buf = alloca [4096 x i8]
  store i8 0, ptr %range.buf
  %range.written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %range.buf, i64 4096, ptr @.objrt.variantRange, ptr %vname, i32 %n, i64 %i)
  %range.len = call i64 @strlen(ptr %range.buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_RANGE, ptr %range.buf, i64 %range.len)
  unreachable
notCtor:
  %tname = call ptr @rterr.tagName(i32 %tag)
  %type.buf = alloca [4096 x i8]
  store i8 0, ptr %type.buf
  %type.written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %type.buf, i64 4096, ptr @.objrt.variantType, i64 %i, ptr %tname)
  %type.len = call i64 @strlen(ptr %type.buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_TYPE, ptr %type.buf, i64 %type.len)
  unreachable
}
define internal void @objrt.patternArity(ptr %name, i32 %want, i32 %n) noreturn {
entry:
  %buf = alloca [4096 x i8]
  store i8 0, ptr %buf
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.objrt.patternArity, ptr %name, i32 %want, i32 %n)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_ARITY, ptr %buf, i64 %len)
  unreachable
}
define internal %Val @rtfmt_make_str(ptr %source, i64 %length) {
entry:
  %size0 = add i64 %length, 25
  %object = call ptr @asl_alloc(i32 0, i64 %size0)
  %len.ptr = getelementptr i8, ptr %object, i64 8
  store i64 %length, ptr %len.ptr
  %data = getelementptr i8, ptr %object, i64 16
  call void @llvm.memcpy.p0.p0.i64(ptr %data, ptr %source, i64 %length, i1 false)
  %end = getelementptr i8, ptr %data, i64 %length
  store i8 0, ptr %end
  %word = ptrtoint ptr %object to i64
  %tagged = insertvalue %Val zeroinitializer, i64 5, 0
  %value = insertvalue %Val %tagged, i64 %word, 1
  ret %Val %value
}

define internal %Val @asl_rt_format_i64(i64 %value) {
entry:
  %buffer = alloca i8, i64 32
  %length = call i64 @rtfmt_i64_text(ptr %buffer, i64 %value)
  %text = call %Val @rtfmt_make_str(ptr %buffer, i64 %length)
  ret %Val %text
}

define internal i64 @rtfmt_i64_text(ptr %buffer, i64 %value) {
entry:
  %negative = icmp slt i64 %value, 0
  %start = zext i1 %negative to i64
  %negated = sub i64 0, %value
  %magnitude = select i1 %negative, i64 %negated, i64 %value
  br label %digits
digits:
  %n = phi i64 [ %magnitude, %entry ], [ %next, %digits ]
  %i = phi i64 [ 0, %entry ], [ %i.next, %digits ]
  %q = udiv i64 %n, 10
  %r = urem i64 %n, 10
  %digit = add i64 %r, 48
  %digit.index = add i64 %i, %start
  %slot = getelementptr i8, ptr %buffer, i64 %digit.index
  %char = trunc i64 %digit to i8
  store i8 %char, ptr %slot
  %next = udiv i64 %n, 10
  %i.next = add i64 %i, 1
  %done = icmp eq i64 %next, 0
  br i1 %done, label %finish, label %digits
finish:
  %sign.slot = getelementptr i8, ptr %buffer, i64 0
  br i1 %negative, label %sign, label %reverse.start
sign:
  store i8 45, ptr %sign.slot
  br label %reverse.start
reverse.start:
  %length = add i64 %i.next, %start
  %left = add i64 0, %start
  %right.raw = sub i64 %i.next, 1
  %right = add i64 %right.raw, %start
  br label %reverse
reverse:
  %lo = phi i64 [ %left, %reverse.start ], [ %lo.next, %swap ]
  %hi = phi i64 [ %right, %reverse.start ], [ %hi.next, %swap ]
  %again = icmp ult i64 %lo, %hi
  br i1 %again, label %swap, label %terminate
swap:
  %lp = getelementptr i8, ptr %buffer, i64 %lo
  %hp = getelementptr i8, ptr %buffer, i64 %hi
  %lv = load i8, ptr %lp
  %hv = load i8, ptr %hp
  store i8 %hv, ptr %lp
  store i8 %lv, ptr %hp
  %lo.next = add i64 %lo, 1
  %hi.next = sub i64 %hi, 1
  br label %reverse
terminate:
  %endp = getelementptr i8, ptr %buffer, i64 %length
  store i8 0, ptr %endp
  ret i64 %length
}

define internal %Val @asl_rt_format_float(double %value) {
entry:
  %buffer = alloca i8, i64 64
  %length = call i64 @rtfmt_float_text(ptr %buffer, double %value)
  %text = call %Val @rtfmt_make_str(ptr %buffer, i64 %length)
  ret %Val %text
}

define internal i64 @rtfmt_float_text(ptr %buffer, double %value) {
entry:
  %precision = alloca i32
  %endp = alloca ptr
  %initial.nan = fcmp uno double %value, %value
  br i1 %initial.nan, label %nan.output, label %normal.entry
nan.output:
  %nan.text = getelementptr [4 x i8], ptr @.rtfmt.nan, i64 0, i64 0
  call void @llvm.memcpy.p0.p0.i64(ptr %buffer, ptr %nan.text, i64 4, i1 false)
  ret i64 3
normal.entry:
  store i32 0, ptr %precision
  br label %try
try:
  %p = load i32, ptr %precision
  %spec = getelementptr [5 x i8], ptr @.rtfmt.exp, i64 0, i64 0
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buffer, i64 64, ptr %spec, i32 %p, double %value)
  store ptr null, ptr %endp
  %roundtrip = call double @strtod(ptr %buffer, ptr %endp)
  %same = fcmp oeq double %roundtrip, %value
  %isnan = fcmp uno double %value, %value
  %accepted = or i1 %same, %isnan
  %last = icmp uge i32 %p, 16
  %stop = or i1 %accepted, %last
  br i1 %stop, label %done, label %retry
retry:
  %p.next = add i32 %p, 1
  store i32 %p.next, ptr %precision
  br label %try
done:
  %ep = call ptr @strchr(ptr %buffer, i32 101)
  %has.exp = icmp ne ptr %ep, null
  br i1 %has.exp, label %exponent.parse, label %formatted
exponent.parse:
  %ep.digits = getelementptr i8, ptr %ep, i64 1
  %exponent = call i32 @atoi(ptr %ep.digits)
  %exp.ge = icmp sge i32 %exponent, -4
  %exp.lt = icmp slt i32 %exponent, 16
  %fixed = and i1 %exp.ge, %exp.lt
  br i1 %fixed, label %fixed.format, label %scientific.format
fixed.format:
  %places.raw = sub i32 %p, %exponent
  %places.positive = icmp sgt i32 %places.raw, 0
  %places = select i1 %places.positive, i32 %places.raw, i32 1
  %fixed.spec = getelementptr [5 x i8], ptr @.rtfmt.fixed, i64 0, i64 0
  %fixed.written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buffer, i64 64, ptr %fixed.spec, i32 %places, double %value)
  br label %formatted
scientific.format:
  %sci.spec = getelementptr [5 x i8], ptr @.rtfmt.exp, i64 0, i64 0
  %sci.written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buffer, i64 64, ptr %sci.spec, i32 %p, double %value)
  br label %formatted
formatted:
  %len = call i64 @strlen(ptr %buffer)
  ret i64 %len
}

define internal i1 @asl_rt_parse_float(ptr %text, i64 %length, ptr %out) {
entry:
  %too.long = icmp uge i64 %length, 512
  %empty = icmp eq i64 %length, 0
  %invalid = or i1 %too.long, %empty
  br i1 %invalid, label %bad, label %copy
copy:
  %buf = alloca i8, i64 512
  call void @llvm.memcpy.p0.p0.i64(ptr %buf, ptr %text, i64 %length, i1 false)
  %nul = getelementptr i8, ptr %buf, i64 %length
  store i8 0, ptr %nul
  %endp = alloca ptr
  store ptr null, ptr %endp
  %nan.text = getelementptr [4 x i8], ptr @.rtfmt.nan, i64 0, i64 0
  %inf.text = getelementptr [4 x i8], ptr @.rtfmt.inf, i64 0, i64 0
  %ninf.text = getelementptr [5 x i8], ptr @.rtfmt.ninf, i64 0, i64 0
  %is.nan = call i32 @strcmp(ptr %buf, ptr %nan.text)
  %nan.ok = icmp eq i32 %is.nan, 0
  br i1 %nan.ok, label %special.nan, label %check.inf
check.inf:
  %is.inf = call i32 @strcmp(ptr %buf, ptr %inf.text)
  %inf.ok = icmp eq i32 %is.inf, 0
  br i1 %inf.ok, label %special.inf, label %check.ninf
check.ninf:
  %is.ninf = call i32 @strcmp(ptr %buf, ptr %ninf.text)
  %ninf.ok = icmp eq i32 %is.ninf, 0
  br i1 %ninf.ok, label %special.ninf, label %normal.parse
special.nan:
  store double 0x7FF8000000000000, ptr %out
  ret i1 true
special.inf:
  store double 0x7FF0000000000000, ptr %out
  ret i1 true
special.ninf:
  store double 0xFFF0000000000000, ptr %out
  ret i1 true
normal.parse:
  %value = call double @strtod(ptr %buf, ptr %endp)
  %end = load ptr, ptr %endp
  %full = icmp eq ptr %end, %nul
  br i1 %full, label %scan.start, label %cleanup.bad
scan.start:
  br label %scan
scan:
  %i = phi i64 [ 0, %scan.start ], [ %i.next, %scan.cont ]
  %scan.done = icmp uge i64 %i, %length
  br i1 %scan.done, label %validate, label %scan.byte
scan.byte:
  %bp = getelementptr i8, ptr %buf, i64 %i
  %bc = load i8, ptr %bp
  %b = zext i8 %bc to i32
  %lower.lo = icmp uge i32 %b, 97
  %lower.hi = icmp ule i32 %b, 122
  %lower = and i1 %lower.lo, %lower.hi
  %upper.lo = icmp uge i32 %b, 65
  %upper.hi = icmp ule i32 %b, 90
  %upper = and i1 %upper.lo, %upper.hi
  %letter = or i1 %lower, %upper
  %e.lower = icmp eq i32 %b, 101
  %e.upper = icmp eq i32 %b, 69
  %is.e = or i1 %e.lower, %e.upper
  %not.e = xor i1 %is.e, true
  %bad.letter = and i1 %letter, %not.e
  br i1 %bad.letter, label %cleanup.bad, label %scan.cont
scan.cont:
  %i.next = add i64 %i, 1
  br label %scan
validate:
  store double %value, ptr %out
  ret i1 true
cleanup.bad:
  br label %bad
bad:
  ret i1 false
}

@.rtfmt.exp = private unnamed_addr constant [5 x i8] c"%.*e\00"
@.rtfmt.fixed = private unnamed_addr constant [5 x i8] c"%.*f\00"
@.rtfmt.nan = private unnamed_addr constant [4 x i8] c"nan\00"
@.rtfmt.inf = private unnamed_addr constant [4 x i8] c"inf\00"
@.rtfmt.ninf = private unnamed_addr constant [5 x i8] c"-inf\00"
%RtFormatBuf = type { ptr, i64, i64 }
@.rtfmt.unit = private unnamed_addr constant [3 x i8] c"()\00"
@.rtfmt.true = private unnamed_addr constant [5 x i8] c"true\00"
@.rtfmt.false = private unnamed_addr constant [6 x i8] c"false\00"
@.rtfmt.openparen = private unnamed_addr constant [2 x i8] c"(\00"
@.rtfmt.closeparen = private unnamed_addr constant [2 x i8] c")\00"
@.rtfmt.openbrace = private unnamed_addr constant [2 x i8] c"{\00"
@.rtfmt.closebrace = private unnamed_addr constant [2 x i8] c"}\00"
@.rtfmt.space = private unnamed_addr constant [2 x i8] c" \00"
@.rtfmt.colon = private unnamed_addr constant [2 x i8] c":\00"
@.rtfmt.quote = private unnamed_addr constant [2 x i8] c"\22\00"
@.rtfmt.slash = private unnamed_addr constant [2 x i8] c"\5c\00"
@.rtfmt.escaped.nl = private unnamed_addr constant [3 x i8] c"\5cn\00"
@.rtfmt.escaped.tab = private unnamed_addr constant [3 x i8] c"\5ct\00"
@.rtfmt.ellipsis = private unnamed_addr constant [4 x i8] c"...\00"
@.rtfmt.fn = private unnamed_addr constant [6 x i8] c"#<fn>\00"
@.rtfmt.bytes = private unnamed_addr constant [9 x i8] c"#<Bytes>\00"
@.rtfmt.f64arr = private unnamed_addr constant [12 x i8] c"#<F64Array>\00"
@.rtfmt.i64arr = private unnamed_addr constant [12 x i8] c"#<I64Array>\00"
@.rtfmt.i8arr = private unnamed_addr constant [11 x i8] c"#<I8Array>\00"
@.rtfmt.handle = private unnamed_addr constant [10 x i8] c"#<Handle>\00"
@.rtfmt.depth = private unnamed_addr constant [53 x i8] c"ERR_DEPTH: printing a value nested deeper than 10000\0A"

define internal void @rtfmt_put(ptr %b, ptr %s, i64 %n) {
entry:
  %cap.ptr = getelementptr %RtFormatBuf, ptr %b, i32 0, i32 2
  %len.ptr = getelementptr %RtFormatBuf, ptr %b, i32 0, i32 1
  %data.ptr = getelementptr %RtFormatBuf, ptr %b, i32 0, i32 0
  %len = load i64, ptr %len.ptr
  %cap.word = load i64, ptr %cap.ptr
  %inline = icmp slt i64 %cap.word, 0
  %cap = and i64 %cap.word, 9223372036854775807
  %needed0 = add i64 %len, %n
  %needed = add i64 %needed0, 1
  %enough = icmp uge i64 %cap, %needed
  br i1 %enough, label %copy, label %grow
grow:
  %twice = shl i64 %cap, 1
  %is.zero = icmp eq i64 %cap, 0
  %initial = select i1 %is.zero, i64 64, i64 %twice
  %large.enough = icmp uge i64 %initial, %needed
  %newcap = select i1 %large.enough, i64 %initial, i64 %needed
  %olddata = load ptr, ptr %data.ptr
  br i1 %inline, label %spill, label %resize
spill:
  %spilled = call ptr @malloc(i64 %newcap)
  %spill.failed = icmp eq ptr %spilled, null
  br i1 %spill.failed, label %oom, label %spill.copy
spill.copy:
  call void @llvm.memcpy.p0.p0.i64(ptr %spilled, ptr %olddata, i64 %len, i1 false)
  br label %grown
resize:
  %resized = call ptr @realloc(ptr %olddata, i64 %newcap)
  %failed = icmp eq ptr %resized, null
  br i1 %failed, label %oom, label %grown
oom:
  call void @exit(i32 70)
  unreachable
grown:
  %newdata = phi ptr [ %spilled, %spill.copy ], [ %resized, %resize ]
  store ptr %newdata, ptr %data.ptr
  store i64 %newcap, ptr %cap.ptr
  br label %copy
copy:
  %dest.base = load ptr, ptr %data.ptr
  %dest = getelementptr i8, ptr %dest.base, i64 %len
  call void @llvm.memcpy.p0.p0.i64(ptr %dest, ptr %s, i64 %n, i1 false)
  %newlen = add i64 %len, %n
  %nul = getelementptr i8, ptr %dest.base, i64 %newlen
  store i8 0, ptr %nul
  store i64 %newlen, ptr %len.ptr
  ret void
}

define internal void @rtfmt_text(ptr %b, ptr %s) {
entry:
  %n = call i64 @strlen(ptr %s)
  call void @rtfmt_put(ptr %b, ptr %s, i64 %n)
  ret void
}

define internal void @rtfmt_strval(ptr %b, %Val %v) {
entry:
  %objword = extractvalue %Val %v, 1
  %obj = inttoptr i64 %objword to ptr
  %len = getelementptr i8, ptr %obj, i64 8
  %n = load i64, ptr %len
  %data = getelementptr i8, ptr %obj, i64 16
  call void @rtfmt_put(ptr %b, ptr %data, i64 %n)
  ret void
}

define internal void @rtfmt_put_i64(ptr %b, i64 %value) {
entry:
  %digits = alloca i8, i64 32
  %n = call i64 @rtfmt_i64_text(ptr %digits, i64 %value)
  call void @rtfmt_put(ptr %b, ptr %digits, i64 %n)
  ret void
}

define internal void @rtfmt_put_float(ptr %b, double %value) {
entry:
  %digits = alloca i8, i64 64
  %n = call i64 @rtfmt_float_text(ptr %digits, double %value)
  call void @rtfmt_put(ptr %b, ptr %digits, i64 %n)
  ret void
}

define internal void @rtfmt_render(ptr %b, %Val %v, i32 %repr, i32 %depth, i32 %limit) {
entry:
  %limited = icmp sge i32 %limit, 0
  %over.limit = icmp sgt i32 %depth, %limit
  %ellipsis = and i1 %limited, %over.limit
  br i1 %ellipsis, label %emit.ellipsis, label %check.depth
emit.ellipsis:
  %dots = getelementptr [4 x i8], ptr @.rtfmt.ellipsis, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %dots)
  ret void
check.depth:
  %too.deep = icmp sgt i32 %depth, 10000
  br i1 %too.deep, label %depth.error, label %dispatch
depth.error:
  %depth.written = call i64 @write(i32 2, ptr @.rtfmt.depth, i64 53)
  call void @exit(i32 1)
  unreachable
dispatch:
  %tagword = extractvalue %Val %v, 0
  %tag = trunc i64 %tagword to i32
  switch i32 %tag, label %other [ i32 0, label %unit i32 1, label %boolean i32 2, label %integer i32 3, label %float i32 4, label %keyword i32 5, label %string i32 6, label %list i32 7, label %record i32 8, label %ctor i32 9, label %function i32 10, label %function ]
unit:
  %unit.s = getelementptr [3 x i8], ptr @.rtfmt.unit, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %unit.s)
  ret void
boolean:
  %payload = extractvalue %Val %v, 1
  %truth = icmp ne i64 %payload, 0
  br i1 %truth, label %true.text, label %false.text
true.text:
  %true.s = getelementptr [5 x i8], ptr @.rtfmt.true, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %true.s)
  ret void
false.text:
  %false.s = getelementptr [6 x i8], ptr @.rtfmt.false, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %false.s)
  ret void
integer:
  %iv = extractvalue %Val %v, 1
  call void @rtfmt_put_i64(ptr %b, i64 %iv)
  ret void
float:
  %fv.bits = extractvalue %Val %v, 1
  %fv = bitcast i64 %fv.bits to double
  call void @rtfmt_put_float(ptr %b, double %fv)
  ret void
keyword:
  %aux = lshr i64 %tagword, 32
  %aux32 = trunc i64 %aux to i32
  %kw.name = call ptr @valrt.symName(i32 %aux32)

  %colon.s = getelementptr [2 x i8], ptr @.rtfmt.colon, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %colon.s)
  call void @rtfmt_text(ptr %b, ptr %kw.name)
  ret void
string:
  %repr.on = icmp ne i32 %repr, 0
  br i1 %repr.on, label %string.quoted, label %string.raw
string.raw:
  call void @rtfmt_strval(ptr %b, %Val %v)
  ret void
string.quoted:
  %quote.s = getelementptr [2 x i8], ptr @.rtfmt.quote, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %quote.s)
  %sword = extractvalue %Val %v, 1
  %sobj = inttoptr i64 %sword to ptr
  %slen.ptr = getelementptr i8, ptr %sobj, i64 8
  %slen = load i64, ptr %slen.ptr
  %sdata = getelementptr i8, ptr %sobj, i64 16
  br label %string.loop
string.loop:
  %si = phi i64 [ 0, %string.quoted ], [ %si.next, %string.more ]
  %sdone = icmp uge i64 %si, %slen
  br i1 %sdone, label %string.end, label %string.byte
string.byte:
  %sp = getelementptr i8, ptr %sdata, i64 %si
  %sc = load i8, ptr %sp
  %sc32 = zext i8 %sc to i32
  switch i32 %sc32, label %string.literal [ i32 34, label %string.escaped i32 92, label %string.escaped i32 10, label %string.nl i32 9, label %string.tab ]
string.escaped:
  %slash.s = getelementptr [2 x i8], ptr @.rtfmt.slash, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %slash.s)
  call void @rtfmt_put(ptr %b, ptr %sp, i64 1)
  br label %string.more
string.nl:
  %nl.s = getelementptr [3 x i8], ptr @.rtfmt.escaped.nl, i64 0, i64 0
  call void @rtfmt_put(ptr %b, ptr %nl.s, i64 2)
  br label %string.more
string.tab:
  %tab.s = getelementptr [3 x i8], ptr @.rtfmt.escaped.tab, i64 0, i64 0
  call void @rtfmt_put(ptr %b, ptr %tab.s, i64 2)
  br label %string.more
string.literal:
  call void @rtfmt_put(ptr %b, ptr %sp, i64 1)
  br label %string.more
string.more:
  %si.next = add i64 %si, 1
  br label %string.loop
string.end:
  call void @rtfmt_text(ptr %b, ptr %quote.s)
  ret void
function:
  %fn.s = getelementptr [6 x i8], ptr @.rtfmt.fn, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %fn.s)
  ret void
other:
  %other.tag = icmp eq i32 %tag, 11
  br i1 %other.tag, label %bytes.text, label %other.array1
bytes.text:
  %bytes.s = getelementptr [9 x i8], ptr @.rtfmt.bytes, i64 0, i64 0
  call void @rtfmt_put(ptr %b, ptr %bytes.s, i64 8)
  ret void
other.array1:
  %f64.tag = icmp eq i32 %tag, 12
  br i1 %f64.tag, label %f64.text, label %other.array2
f64.text:
  %f64.s = getelementptr [12 x i8], ptr @.rtfmt.f64arr, i64 0, i64 0
  call void @rtfmt_put(ptr %b, ptr %f64.s, i64 11)
  ret void
other.array2:
  %i64.tag = icmp eq i32 %tag, 13
  br i1 %i64.tag, label %i64.text, label %other.array3
i64.text:
  %i64.s = getelementptr [12 x i8], ptr @.rtfmt.i64arr, i64 0, i64 0
  call void @rtfmt_put(ptr %b, ptr %i64.s, i64 11)
  ret void
other.array3:
  %i8.tag = icmp eq i32 %tag, 14
  br i1 %i8.tag, label %i8.text, label %handle.text
i8.text:
  %i8.s = getelementptr [11 x i8], ptr @.rtfmt.i8arr, i64 0, i64 0
  call void @rtfmt_put(ptr %b, ptr %i8.s, i64 10)
  ret void
handle.text:
  %handle.s = getelementptr [10 x i8], ptr @.rtfmt.handle, i64 0, i64 0
  call void @rtfmt_put(ptr %b, ptr %handle.s, i64 9)
  ret void
list:
  %open.p = getelementptr [2 x i8], ptr @.rtfmt.openparen, i64 0, i64 0
  %close.p = getelementptr [2 x i8], ptr @.rtfmt.closeparen, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %open.p)
  %lword = extractvalue %Val %v, 1
  %lobj = inttoptr i64 %lword to ptr
  br label %list.loop
list.loop:
  %node = phi ptr [ %lobj, %list ], [ %next.node, %list.next ]
  %node.null = icmp eq ptr %node, null
  br i1 %node.null, label %list.end, label %list.item
list.item:
  %car.ptr = getelementptr i8, ptr %node, i64 8
  %car = load %Val, ptr %car.ptr
  %depth.next = add i32 %depth, 1
  call void @rtfmt_render(ptr %b, %Val %car, i32 1, i32 %depth.next, i32 %limit)
  %cdr.word.ptr = getelementptr i8, ptr %node, i64 32
  %cdr.word = load i64, ptr %cdr.word.ptr
  %next.node = inttoptr i64 %cdr.word to ptr
  %more.nodes = icmp ne ptr %next.node, null
  br i1 %more.nodes, label %list.space, label %list.next
list.space:
  %space.s = getelementptr [2 x i8], ptr @.rtfmt.space, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %space.s)
  br label %list.next
list.next:
  br label %list.loop
list.end:
  call void @rtfmt_text(ptr %b, ptr %close.p)
  ret void
record:
  %ro = getelementptr [2 x i8], ptr @.rtfmt.openbrace, i64 0, i64 0
  %rc = getelementptr [2 x i8], ptr @.rtfmt.closebrace, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %ro)
  %rword = extractvalue %Val %v, 1
  %robj = inttoptr i64 %rword to ptr
  %rn.ptr = getelementptr i8, ptr %robj, i64 12
  %rn.i32 = load i32, ptr %rn.ptr
  %rn = zext i32 %rn.i32 to i64
  %rkeys.ptr = getelementptr i8, ptr %robj, i64 16
  %rkeys = load ptr, ptr %rkeys.ptr
  %rvalues = getelementptr i8, ptr %robj, i64 24
  br label %record.loop
record.loop:
  %ri = phi i64 [ 0, %record ], [ %ri.next, %record.next ]
  %r.done = icmp uge i64 %ri, %rn
  br i1 %r.done, label %record.end, label %record.item
record.item:
  %rfirst = icmp eq i64 %ri, 0
  br i1 %rfirst, label %record.key, label %record.space
record.space:
  %rs = getelementptr [2 x i8], ptr @.rtfmt.space, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %rs)
  br label %record.key
record.key:
  %rkey.ptr = getelementptr i32, ptr %rkeys, i64 %ri
  %rkey = load i32, ptr %rkey.ptr
  %rkey.name = call ptr @valrt.symName(i32 %rkey)

  %rcolon = getelementptr [2 x i8], ptr @.rtfmt.colon, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %rcolon)
  call void @rtfmt_text(ptr %b, ptr %rkey.name)
  %rspace = getelementptr [2 x i8], ptr @.rtfmt.space, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %rspace)
  %rvalue.ptr = getelementptr %Val, ptr %rvalues, i64 %ri
  %rvalue = load %Val, ptr %rvalue.ptr
  %rdepth = add i32 %depth, 1
  call void @rtfmt_render(ptr %b, %Val %rvalue, i32 1, i32 %rdepth, i32 %limit)
  br label %record.next
record.next:
  %ri.next = add i64 %ri, 1
  br label %record.loop
record.end:
  call void @rtfmt_text(ptr %b, ptr %rc)
  ret void
ctor:
  %co = getelementptr [2 x i8], ptr @.rtfmt.openparen, i64 0, i64 0
  %cc = getelementptr [2 x i8], ptr @.rtfmt.closeparen, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %co)
  %cword = extractvalue %Val %v, 1
  %cobj = inttoptr i64 %cword to ptr
  %cid.ptr = getelementptr i8, ptr %cobj, i64 8
  %cid = load i32, ptr %cid.ptr
  %cname = call ptr @valrt.symName(i32 %cid)

  call void @rtfmt_text(ptr %b, ptr %cname)
  %cn.ptr = getelementptr i8, ptr %cobj, i64 12
  %cn.i32 = load i32, ptr %cn.ptr
  %cn = zext i32 %cn.i32 to i64
  %cfields = getelementptr i8, ptr %cobj, i64 16
  br label %ctor.loop
ctor.loop:
  %ci = phi i64 [ 0, %ctor ], [ %ci.next, %ctor.next ]
  %c.done = icmp uge i64 %ci, %cn
  br i1 %c.done, label %ctor.end, label %ctor.item
ctor.item:
  %cs = getelementptr [2 x i8], ptr @.rtfmt.space, i64 0, i64 0
  call void @rtfmt_text(ptr %b, ptr %cs)
  %cvalue.ptr = getelementptr %Val, ptr %cfields, i64 %ci
  %cvalue = load %Val, ptr %cvalue.ptr
  %cdepth = add i32 %depth, 1
  call void @rtfmt_render(ptr %b, %Val %cvalue, i32 1, i32 %cdepth, i32 %limit)
  br label %ctor.next
ctor.next:
  %ci.next = add i64 %ci, 1
  br label %ctor.loop
ctor.end:
  call void @rtfmt_text(ptr %b, ptr %cc)
  ret void
}
define internal %Val @asl_rt_format_val(%Val %v, i32 %repr, i32 %limit) {
entry:
  %buf = alloca %RtFormatBuf
  %inline = alloca i8, i64 256
  %ptr.slot = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 0
  %len.slot = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 1
  %cap.slot = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 2
  store ptr %inline, ptr %ptr.slot
  store i64 0, ptr %len.slot
  store i64 -9223372036854775552, ptr %cap.slot
  call void @rtfmt_render(ptr %buf, %Val %v, i32 %repr, i32 0, i32 %limit)
  %data = load ptr, ptr %ptr.slot
  %length = load i64, ptr %len.slot
  %result = call %Val @rtfmt_make_str(ptr %data, i64 %length)
  %cap.word = load i64, ptr %cap.slot
  %spilled = icmp sge i64 %cap.word, 0
  br i1 %spilled, label %release, label %finished
release:
  call void @free(ptr %data)
  br label %finished
finished:
  ret %Val %result
}
define internal %Val @asl_rt_format_many(ptr %args, i64 %count, i32 %mode) {
entry:
  %buf = alloca %RtFormatBuf
  %inline = alloca i8, i64 256
  %ptr.slot = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 0
  %len.slot = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 1
  %cap.slot = getelementptr %RtFormatBuf, ptr %buf, i32 0, i32 2
  store ptr %inline, ptr %ptr.slot
  store i64 0, ptr %len.slot
  store i64 -9223372036854775552, ptr %cap.slot
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %next, %after.item ]
  %done = icmp uge i64 %i, %count
  br i1 %done, label %suffix, label %item
item:
  %str.mode = icmp eq i32 %mode, 0
  %first = icmp eq i64 %i, 0
  %not.str.mode = xor i1 %str.mode, true
  %not.first = xor i1 %first, true
  %separator = and i1 %not.str.mode, %not.first
  br i1 %separator, label %space, label %load.item
space:
  %sp = getelementptr [2 x i8], ptr @.rtfmt.space, i64 0, i64 0
  call void @rtfmt_text(ptr %buf, ptr %sp)
  br label %load.item
load.item:
  %item.ptr = getelementptr %Val, ptr %args, i64 %i
  %item.val = load %Val, ptr %item.ptr
  %word = extractvalue %Val %item.val, 0
  %tag = trunc i64 %word to i32
  %is.string = icmp eq i32 %tag, 5
  %is.str.mode = and i1 %str.mode, %is.string
  %render.repr = select i1 %str.mode, i32 1, i32 0
  %raw.str = select i1 %is.str.mode, i32 0, i32 %render.repr
  call void @rtfmt_render(ptr %buf, %Val %item.val, i32 %raw.str, i32 0, i32 -1)
  br label %after.item
after.item:
  %next = add i64 %i, 1
  br label %loop
suffix:
  %line.mode = icmp uge i32 %mode, 2
  br i1 %line.mode, label %newline, label %finish
newline:
  %nl = alloca i8
  store i8 10, ptr %nl
  call void @rtfmt_put(ptr %buf, ptr %nl, i64 1)
  br label %finish
finish:
  %data = load ptr, ptr %ptr.slot
  %length = load i64, ptr %len.slot
  %result = call %Val @rtfmt_make_str(ptr %data, i64 %length)
  %cap.word = load i64, ptr %cap.slot
  %spilled = icmp sge i64 %cap.word, 0
  br i1 %spilled, label %release, label %finished
release:
  call void @free(ptr %data)
  br label %finished
finished:
  ret %Val %result
}
@.rtfmt.option = private unnamed_addr constant [7 x i8] c"Option\00"
@.rtfmt.some = private unnamed_addr constant [5 x i8] c"some\00"
@.rtfmt.none = private unnamed_addr constant [5 x i8] c"none\00"

define internal %Val @asl_rt_format_float_value(%Val %input) {
entry:
  %word = extractvalue %Val %input, 0
  %tag = trunc i64 %word to i32
  %is.float = icmp eq i32 %tag, 3
  br i1 %is.float, label %format, label %type.error
type.error:
  call void @rterr.type(i32 %tag, i32 3)
  unreachable
format:
  %bits = extractvalue %Val %input, 1
  %number = bitcast i64 %bits to double
  %text = call %Val @asl_rt_format_float(double %number)
  ret %Val %text
}

define internal %Val @asl_rt_format_parse_value(%Val %input) {
entry:
  %word = extractvalue %Val %input, 0
  %tag = trunc i64 %word to i32
  %is.str = icmp eq i32 %tag, 5
  br i1 %is.str, label %parse, label %type.error
type.error:
  call void @rterr.type(i32 %tag, i32 5)
  unreachable
parse:
  %objword = extractvalue %Val %input, 1
  %obj = inttoptr i64 %objword to ptr
  %length.ptr = getelementptr i8, ptr %obj, i64 8
  %length = load i64, ptr %length.ptr
  %text = getelementptr i8, ptr %obj, i64 16
  %raw = alloca double
  %ok = call i1 @asl_rt_parse_float(ptr %text, i64 %length, ptr %raw)
  br i1 %ok, label %some, label %none
some:
  %number = load double, ptr %raw
  %bits = bitcast double %number to i64
  %float.tagged = insertvalue %Val zeroinitializer, i64 3, 0
  %float.value = insertvalue %Val %float.tagged, i64 %bits, 1
  %items = alloca %Val
  store %Val %float.value, ptr %items
  %some.name = getelementptr [5 x i8], ptr @.rtfmt.some, i64 0, i64 0
  %some.id = call i32 @valrt.intern(ptr %some.name, i64 4)
  %some.object = call ptr @asl_alloc(i32 3, i64 32)
  %some.ctor.ptr = getelementptr i8, ptr %some.object, i64 8
  store i32 %some.id, ptr %some.ctor.ptr
  %some.n.ptr = getelementptr i8, ptr %some.object, i64 12
  store i32 1, ptr %some.n.ptr
  %some.fields = getelementptr i8, ptr %some.object, i64 16
  call void @llvm.memcpy.p0.p0.i64(ptr %some.fields, ptr %items, i64 16, i1 false)
  %some.objword = ptrtoint ptr %some.object to i64
  %some.tagged = insertvalue %Val zeroinitializer, i64 8, 0
  %wrapped = insertvalue %Val %some.tagged, i64 %some.objword, 1
  ret %Val %wrapped
none:
  %none.name = getelementptr [5 x i8], ptr @.rtfmt.none, i64 0, i64 0
  %none.id = call i32 @valrt.intern(ptr %none.name, i64 4)
  %none.object = call ptr @asl_alloc(i32 3, i64 16)
  %none.ctor.ptr = getelementptr i8, ptr %none.object, i64 8
  store i32 %none.id, ptr %none.ctor.ptr
  %none.n.ptr = getelementptr i8, ptr %none.object, i64 12
  store i32 0, ptr %none.n.ptr
  %none.objword = ptrtoint ptr %none.object to i64
  %none.tagged = insertvalue %Val zeroinitializer, i64 8, 0
  %empty.option = insertvalue %Val %none.tagged, i64 %none.objword, 1
  ret %Val %empty.option
}

define internal void @asl_rt_format_write(%Val %text.val, i32 %fd) {
entry:
  %word = extractvalue %Val %text.val, 0
  %tag = trunc i64 %word to i32
  %is.str = icmp eq i32 %tag, 5
  br i1 %is.str, label %start, label %type.error
type.error:
  call void @rterr.type(i32 %tag, i32 5)
  unreachable
start:
  %objword = extractvalue %Val %text.val, 1
  %obj = inttoptr i64 %objword to ptr
  %length.ptr = getelementptr i8, ptr %obj, i64 8
  %length = load i64, ptr %length.ptr
  %data = getelementptr i8, ptr %obj, i64 16
  br label %write.loop
write.loop:
  %offset = phi i64 [ 0, %start ], [ %offset.next, %write.more ]
  %remaining = sub i64 %length, %offset
  %finished = icmp uge i64 %offset, %length
  br i1 %finished, label %done, label %write.once
write.once:
  %current = getelementptr i8, ptr %data, i64 %offset
  %written = call i64 @write(i32 %fd, ptr %current, i64 %remaining)
  %positive = icmp sgt i64 %written, 0
  br i1 %positive, label %write.more, label %done
write.more:
  %offset.next = add i64 %offset, %written
  br label %write.loop
done:
  ret void
}
@.rterr.c.ERR_INTERNAL = private unnamed_addr constant [13 x i8] c"ERR_INTERNAL\00"
@.rterr.c.ERR_TYPE = private unnamed_addr constant [9 x i8] c"ERR_TYPE\00"
@.rterr.c.ERR_MATCH_NONEXHAUSTIVE = private unnamed_addr constant [24 x i8] c"ERR_MATCH_NONEXHAUSTIVE\00"
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
@.rterr.c.ERR_RANGE = private unnamed_addr constant [10 x i8] c"ERR_RANGE\00"
@.rterr.m.noArmValue = private unnamed_addr constant [24 x i8] c"no arm matches %s in %s\00"

define internal ptr @rterr.text(%Val %s) {
entry:
  %word = extractvalue %Val %s, 1
  %obj = inttoptr i64 %word to ptr
  %data = getelementptr i8, ptr %obj, i64 16
  ret ptr %data
}

define internal void @rterr.matchValue(%Val %v, ptr %fn) noreturn {
entry:
  %buf = alloca [4096 x i8]
  store i8 0, ptr %buf
  %shown = call %Val @asl_rt_format_val(%Val %v, i32 1, i32 8)
  %shownText = call ptr @rterr.text(%Val %shown)
  %written = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 4096, ptr @.rterr.m.noArmValue, ptr %shownText, ptr %fn)
  %len = call i64 @strlen(ptr %buf)
  call void @rterr.raise(ptr @.rterr.c.ERR_MATCH_NONEXHAUSTIVE, ptr %buf, i64 %len)
  unreachable
}
@valrt.slots = weak global ptr null
@valrt.capacity = weak global i64 0
@valrt.names = weak global ptr null
@valrt.count = weak global i64 0
@valrt.room = weak global i64 0
@valrt.handler = weak global ptr null
@valrt.errorMsg = weak global [4096 x i8] zeroinitializer
@.valrt.unknown = private unnamed_addr constant [2 x i8] c"?\00"

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

define weak ptr @aslSymNameShared(i32 %id) {
entry:
  %count = load i64, ptr @valrt.count
  %wide = sext i32 %id to i64
  %nonNegative = icmp sge i64 %wide, 0
  %below = icmp slt i64 %wide, %count
  %known = and i1 %nonNegative, %below
  br i1 %known, label %named, label %unknown
named:
  %names = load ptr, ptr @valrt.names
  %offset = mul i64 %wide, 16
  %record = getelementptr inbounds i8, ptr %names, i64 %offset
  %text = load ptr, ptr %record
  ret ptr %text
unknown:
  ret ptr @.valrt.unknown
}

define internal ptr @valrt.symName(i32 %id) {
entry:
  %text = call ptr @aslSymNameShared(i32 %id)
  ret ptr %text
}

define weak ptr @aslHandlerSlot() {
entry:
  ret ptr @valrt.handler
}

define weak ptr @aslErrorText() {
entry:
  ret ptr @valrt.errorMsg
}
declare ptr @asl_alloc(i32, i64)
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare i64 @strlen(ptr)
declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare double @strtod(ptr, ptr)
declare i32 @strcmp(ptr, ptr)
declare ptr @strchr(ptr, i32)
declare i32 @atoi(ptr)
declare i64 @write(i32, ptr, i64)
declare void @exit(i32)
declare i32 @fflush(ptr)
declare void @longjmp(ptr, i32) noreturn
declare ptr @calloc(i64, i64)
declare i32 @memcmp(ptr, ptr, i64)
