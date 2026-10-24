; (:m :ref UFRT :do "hand-built descriptor-layout record (unboxFieldsDesign :layout): ufrtRawMake copies a Mix twin (boxed, or the compiler's own descriptor layout once the emitter unboxes it: s +24, a +40, f +48, b +56) as {a: Int64, s: String, f: Float64, b: Bool} into nb 1 boxed slot (s at +24) and raw words a +40, f +48, b +56; keys word = descriptor keys address | 1; locs = (tag << 24) | byte offset, 255 boxed")
%Val = type { i64, i64 }

@ufrtDesc.Mix = internal global <{ i32, i32, [4 x i32], [4 x i32] }> <{ i32 4, i32 1, [4 x i32] zeroinitializer, [4 x i32] [i32 33554472, i32 -16777192, i32 50331696, i32 16777272] }>, align 8

declare ptr @asl_alloc(i32, i64)

define %Val @ufrtRawMake(%Val %twin) {
entry:
  %tw = extractvalue %Val %twin, 1
  %t = inttoptr i64 %tw to ptr
  %tkp = getelementptr inbounds i8, ptr %t, i64 16
  %tkw = load i64, ptr %tkp
  %tbit = and i64 %tkw, 1
  %traw = icmp ne i64 %tbit, 0
  %tkw0 = and i64 %tkw, -2
  %tkeys = inttoptr i64 %tkw0 to ptr
  %dkeys = getelementptr inbounds <{ i32, i32, [4 x i32], [4 x i32] }>, ptr @ufrtDesc.Mix, i32 0, i32 2
  call void @llvm.memcpy.p0.p0.i64(ptr %dkeys, ptr %tkeys, i64 16, i1 false)
  %o = call ptr @asl_alloc(i32 2, i64 64)
  %tsp = getelementptr inbounds i8, ptr %t, i64 8
  %schema = load i32, ptr %tsp
  %osp = getelementptr inbounds i8, ptr %o, i64 8
  store i32 %schema, ptr %osp
  %onp = getelementptr inbounds i8, ptr %o, i64 12
  store i32 1, ptr %onp
  %dk = ptrtoint ptr %dkeys to i64
  %dkt = or i64 %dk, 1
  %okp = getelementptr inbounds i8, ptr %o, i64 16
  store i64 %dkt, ptr %okp
  %ts.off = select i1 %traw, i64 24, i64 40
  %ts = getelementptr inbounds i8, ptr %t, i64 %ts.off
  %sv = load %Val, ptr %ts
  %os = getelementptr inbounds i8, ptr %o, i64 24
  store %Val %sv, ptr %os
  %ta.off = select i1 %traw, i64 40, i64 32
  %ta = getelementptr inbounds i8, ptr %t, i64 %ta.off
  %a = load i64, ptr %ta
  %oa = getelementptr inbounds i8, ptr %o, i64 40
  store i64 %a, ptr %oa
  %tf.off = select i1 %traw, i64 48, i64 64
  %tf = getelementptr inbounds i8, ptr %t, i64 %tf.off
  %f = load i64, ptr %tf
  %of = getelementptr inbounds i8, ptr %o, i64 48
  store i64 %f, ptr %of
  %tb.off = select i1 %traw, i64 56, i64 80
  %tb = getelementptr inbounds i8, ptr %t, i64 %tb.off
  %b = load i64, ptr %tb
  %ob = getelementptr inbounds i8, ptr %o, i64 56
  store i64 %b, ptr %ob
  %ow = ptrtoint ptr %o to i64
  %r = insertvalue %Val { i64 7, i64 0 }, i64 %ow, 1
  ret %Val %r
}

declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1 immarg)
