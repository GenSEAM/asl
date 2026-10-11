source_filename = "primCheck"

define tailcc i64 @primCheck() {
bb.entry:
  %zero = bitcast i64 0 to i64
  %one = bitcast i64 1 to i64
  br label %bb.check0
bb.check0:
  %count0 = phi i64 [ %zero, %bb.entry ]
  %adda = bitcast i64 40 to i64
  %addb = bitcast i64 2 to i64
  %addwant = bitcast i64 42 to i64
  %addgot.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %adda, i64 %addb)
  %addgot = extractvalue {i64, i1} %addgot.p.pair, 0
  %addgot.p.bad = extractvalue {i64, i1} %addgot.p.pair, 1
  br i1 %addgot.p.bad, label %addgot.p.trap, label %addgot.p.ok
addgot.p.trap:
  call void @llvm.trap()
  unreachable
addgot.p.ok:
  %add = icmp eq i64 %addgot, %addwant
  %next0.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count0, i64 %one)
  %next0 = extractvalue {i64, i1} %next0.p.pair, 0
  %next0.p.bad = extractvalue {i64, i1} %next0.p.pair, 1
  br i1 %next0.p.bad, label %next0.p.trap, label %next0.p.ok
next0.p.trap:
  call void @llvm.trap()
  unreachable
next0.p.ok:
  br i1 %add, label %bb.check1, label %bb.fail0
bb.fail0:
  %code0 = bitcast i64 1 to i64
  ret i64 %code0
bb.check1:
  %count1 = phi i64 [ %next0, %next0.p.ok ]
  %suba = bitcast i64 5 to i64
  %subb = bitcast i64 7 to i64
  %subwant = bitcast i64 -2 to i64
  %subgot.p.pair = call {i64, i1} @llvm.ssub.with.overflow.i64(i64 %suba, i64 %subb)
  %subgot = extractvalue {i64, i1} %subgot.p.pair, 0
  %subgot.p.bad = extractvalue {i64, i1} %subgot.p.pair, 1
  br i1 %subgot.p.bad, label %subgot.p.trap, label %subgot.p.ok
subgot.p.trap:
  call void @llvm.trap()
  unreachable
subgot.p.ok:
  %sub = icmp eq i64 %subgot, %subwant
  %next1.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count1, i64 %one)
  %next1 = extractvalue {i64, i1} %next1.p.pair, 0
  %next1.p.bad = extractvalue {i64, i1} %next1.p.pair, 1
  br i1 %next1.p.bad, label %next1.p.trap, label %next1.p.ok
next1.p.trap:
  call void @llvm.trap()
  unreachable
next1.p.ok:
  br i1 %sub, label %bb.check2, label %bb.fail1
bb.fail1:
  %code1 = bitcast i64 2 to i64
  ret i64 %code1
bb.check2:
  %count2 = phi i64 [ %next1, %next1.p.ok ]
  %mula = bitcast i64 -6 to i64
  %mulb = bitcast i64 7 to i64
  %mulwant = bitcast i64 -42 to i64
  %mulgot.p.pair = call {i64, i1} @llvm.smul.with.overflow.i64(i64 %mula, i64 %mulb)
  %mulgot = extractvalue {i64, i1} %mulgot.p.pair, 0
  %mulgot.p.bad = extractvalue {i64, i1} %mulgot.p.pair, 1
  br i1 %mulgot.p.bad, label %mulgot.p.trap, label %mulgot.p.ok
mulgot.p.trap:
  call void @llvm.trap()
  unreachable
mulgot.p.ok:
  %mul = icmp eq i64 %mulgot, %mulwant
  %next2.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count2, i64 %one)
  %next2 = extractvalue {i64, i1} %next2.p.pair, 0
  %next2.p.bad = extractvalue {i64, i1} %next2.p.pair, 1
  br i1 %next2.p.bad, label %next2.p.trap, label %next2.p.ok
next2.p.trap:
  call void @llvm.trap()
  unreachable
next2.p.ok:
  br i1 %mul, label %bb.check3, label %bb.fail2
bb.fail2:
  %code2 = bitcast i64 3 to i64
  ret i64 %code2
bb.check3:
  %count3 = phi i64 [ %next2, %next2.p.ok ]
  %quota = bitcast i64 -7 to i64
  %quotb = bitcast i64 2 to i64
  %quotwant = bitcast i64 -3 to i64
  %quotgot.p.zero = icmp eq i64 %quotb, 0
  %quotgot.p.min = icmp eq i64 %quota, -9223372036854775808
  %quotgot.p.neg = icmp eq i64 %quotb, -1
  %quotgot.p.over = and i1 %quotgot.p.min, %quotgot.p.neg
  %quotgot.p.bad = or i1 %quotgot.p.zero, %quotgot.p.over
  br i1 %quotgot.p.bad, label %quotgot.p.trap, label %quotgot.p.ok
quotgot.p.trap:
  call void @llvm.trap()
  unreachable
quotgot.p.ok:
  %quotgot = sdiv i64 %quota, %quotb
  %quot = icmp eq i64 %quotgot, %quotwant
  %next3.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count3, i64 %one)
  %next3 = extractvalue {i64, i1} %next3.p.pair, 0
  %next3.p.bad = extractvalue {i64, i1} %next3.p.pair, 1
  br i1 %next3.p.bad, label %next3.p.trap, label %next3.p.ok
next3.p.trap:
  call void @llvm.trap()
  unreachable
next3.p.ok:
  br i1 %quot, label %bb.check4, label %bb.fail3
bb.fail3:
  %code3 = bitcast i64 4 to i64
  ret i64 %code3
bb.check4:
  %count4 = phi i64 [ %next3, %next3.p.ok ]
  %rema = bitcast i64 -7 to i64
  %remb = bitcast i64 2 to i64
  %remwant = bitcast i64 -1 to i64
  %remgot.p.bad = icmp eq i64 %remb, 0
  br i1 %remgot.p.bad, label %remgot.p.trap, label %remgot.p.ok
remgot.p.trap:
  call void @llvm.trap()
  unreachable
remgot.p.ok:
  %remgot.p.neg = icmp eq i64 %remb, -1
  %remgot.p.divisor = select i1 %remgot.p.neg, i64 1, i64 %remb
  %remgot = srem i64 %rema, %remgot.p.divisor
  %rem = icmp eq i64 %remgot, %remwant
  %next4.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count4, i64 %one)
  %next4 = extractvalue {i64, i1} %next4.p.pair, 0
  %next4.p.bad = extractvalue {i64, i1} %next4.p.pair, 1
  br i1 %next4.p.bad, label %next4.p.trap, label %next4.p.ok
next4.p.trap:
  call void @llvm.trap()
  unreachable
next4.p.ok:
  br i1 %rem, label %bb.check5, label %bb.fail4
bb.fail4:
  %code4 = bitcast i64 5 to i64
  ret i64 %code4
bb.check5:
  %count5 = phi i64 [ %next4, %next4.p.ok ]
  %remNega = bitcast i64 7 to i64
  %remNegb = bitcast i64 -1 to i64
  %remNegwant = bitcast i64 0 to i64
  %remNeggot.p.bad = icmp eq i64 %remNegb, 0
  br i1 %remNeggot.p.bad, label %remNeggot.p.trap, label %remNeggot.p.ok
remNeggot.p.trap:
  call void @llvm.trap()
  unreachable
remNeggot.p.ok:
  %remNeggot.p.neg = icmp eq i64 %remNegb, -1
  %remNeggot.p.divisor = select i1 %remNeggot.p.neg, i64 1, i64 %remNegb
  %remNeggot = srem i64 %remNega, %remNeggot.p.divisor
  %remNeg = icmp eq i64 %remNeggot, %remNegwant
  %next5.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count5, i64 %one)
  %next5 = extractvalue {i64, i1} %next5.p.pair, 0
  %next5.p.bad = extractvalue {i64, i1} %next5.p.pair, 1
  br i1 %next5.p.bad, label %next5.p.trap, label %next5.p.ok
next5.p.trap:
  call void @llvm.trap()
  unreachable
next5.p.ok:
  br i1 %remNeg, label %bb.check6, label %bb.fail5
bb.fail5:
  %code5 = bitcast i64 6 to i64
  ret i64 %code5
bb.check6:
  %count6 = phi i64 [ %next5, %next5.p.ok ]
  %addMaxa = bitcast i64 9223372036854775806 to i64
  %addMaxb = bitcast i64 1 to i64
  %addMaxwant = bitcast i64 9223372036854775807 to i64
  %addMaxgot.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %addMaxa, i64 %addMaxb)
  %addMaxgot = extractvalue {i64, i1} %addMaxgot.p.pair, 0
  %addMaxgot.p.bad = extractvalue {i64, i1} %addMaxgot.p.pair, 1
  br i1 %addMaxgot.p.bad, label %addMaxgot.p.trap, label %addMaxgot.p.ok
addMaxgot.p.trap:
  call void @llvm.trap()
  unreachable
addMaxgot.p.ok:
  %addMax = icmp eq i64 %addMaxgot, %addMaxwant
  %next6.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count6, i64 %one)
  %next6 = extractvalue {i64, i1} %next6.p.pair, 0
  %next6.p.bad = extractvalue {i64, i1} %next6.p.pair, 1
  br i1 %next6.p.bad, label %next6.p.trap, label %next6.p.ok
next6.p.trap:
  call void @llvm.trap()
  unreachable
next6.p.ok:
  br i1 %addMax, label %bb.check7, label %bb.fail6
bb.fail6:
  %code6 = bitcast i64 7 to i64
  ret i64 %code6
bb.check7:
  %count7 = phi i64 [ %next6, %next6.p.ok ]
  %min = bitcast i64 -9223372036854775808 to i64
  %minNeg = bitcast i64 -1 to i64
  %minRem.p.bad = icmp eq i64 %minNeg, 0
  br i1 %minRem.p.bad, label %minRem.p.trap, label %minRem.p.ok
minRem.p.trap:
  call void @llvm.trap()
  unreachable
minRem.p.ok:
  %minRem.p.neg = icmp eq i64 %minNeg, -1
  %minRem.p.divisor = select i1 %minRem.p.neg, i64 1, i64 %minNeg
  %minRem = srem i64 %min, %minRem.p.divisor
  %minZero = bitcast i64 0 to i64
  %minRemOk = icmp eq i64 %minRem, %minZero
  %next7.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count7, i64 %one)
  %next7 = extractvalue {i64, i1} %next7.p.pair, 0
  %next7.p.bad = extractvalue {i64, i1} %next7.p.pair, 1
  br i1 %next7.p.bad, label %next7.p.trap, label %next7.p.ok
next7.p.trap:
  call void @llvm.trap()
  unreachable
next7.p.ok:
  br i1 %minRemOk, label %bb.check8, label %bb.fail7
bb.fail7:
  %code7 = bitcast i64 8 to i64
  ret i64 %code7
bb.check8:
  %count8 = phi i64 [ %next7, %next7.p.ok ]
  %eqa = bitcast i64 3 to i64
  %eqb = bitcast i64 3 to i64
  %eqgot = icmp eq i64 %eqa, %eqb
  %eq = and i1 %eqgot, %eqgot
  %next8.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count8, i64 %one)
  %next8 = extractvalue {i64, i1} %next8.p.pair, 0
  %next8.p.bad = extractvalue {i64, i1} %next8.p.pair, 1
  br i1 %next8.p.bad, label %next8.p.trap, label %next8.p.ok
next8.p.trap:
  call void @llvm.trap()
  unreachable
next8.p.ok:
  br i1 %eq, label %bb.check9, label %bb.fail8
bb.fail8:
  %code8 = bitcast i64 9 to i64
  ret i64 %code8
bb.check9:
  %count9 = phi i64 [ %next8, %next8.p.ok ]
  %eqNota = bitcast i64 3 to i64
  %eqNotb = bitcast i64 4 to i64
  %eqNotgot = icmp eq i64 %eqNota, %eqNotb
  %eqNot = xor i1 %eqNotgot, true
  %next9.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count9, i64 %one)
  %next9 = extractvalue {i64, i1} %next9.p.pair, 0
  %next9.p.bad = extractvalue {i64, i1} %next9.p.pair, 1
  br i1 %next9.p.bad, label %next9.p.trap, label %next9.p.ok
next9.p.trap:
  call void @llvm.trap()
  unreachable
next9.p.ok:
  br i1 %eqNot, label %bb.check10, label %bb.fail9
bb.fail9:
  %code9 = bitcast i64 10 to i64
  ret i64 %code9
bb.check10:
  %count10 = phi i64 [ %next9, %next9.p.ok ]
  %nea = bitcast i64 3 to i64
  %neb = bitcast i64 4 to i64
  %negot = icmp ne i64 %nea, %neb
  %ne = and i1 %negot, %negot
  %next10.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count10, i64 %one)
  %next10 = extractvalue {i64, i1} %next10.p.pair, 0
  %next10.p.bad = extractvalue {i64, i1} %next10.p.pair, 1
  br i1 %next10.p.bad, label %next10.p.trap, label %next10.p.ok
next10.p.trap:
  call void @llvm.trap()
  unreachable
next10.p.ok:
  br i1 %ne, label %bb.check11, label %bb.fail10
bb.fail10:
  %code10 = bitcast i64 11 to i64
  ret i64 %code10
bb.check11:
  %count11 = phi i64 [ %next10, %next10.p.ok ]
  %neNota = bitcast i64 3 to i64
  %neNotb = bitcast i64 3 to i64
  %neNotgot = icmp ne i64 %neNota, %neNotb
  %neNot = xor i1 %neNotgot, true
  %next11.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count11, i64 %one)
  %next11 = extractvalue {i64, i1} %next11.p.pair, 0
  %next11.p.bad = extractvalue {i64, i1} %next11.p.pair, 1
  br i1 %next11.p.bad, label %next11.p.trap, label %next11.p.ok
next11.p.trap:
  call void @llvm.trap()
  unreachable
next11.p.ok:
  br i1 %neNot, label %bb.check12, label %bb.fail11
bb.fail11:
  %code11 = bitcast i64 12 to i64
  ret i64 %code11
bb.check12:
  %count12 = phi i64 [ %next11, %next11.p.ok ]
  %lta = bitcast i64 -1 to i64
  %ltb = bitcast i64 0 to i64
  %ltgot = icmp slt i64 %lta, %ltb
  %lt = and i1 %ltgot, %ltgot
  %next12.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count12, i64 %one)
  %next12 = extractvalue {i64, i1} %next12.p.pair, 0
  %next12.p.bad = extractvalue {i64, i1} %next12.p.pair, 1
  br i1 %next12.p.bad, label %next12.p.trap, label %next12.p.ok
next12.p.trap:
  call void @llvm.trap()
  unreachable
next12.p.ok:
  br i1 %lt, label %bb.check13, label %bb.fail12
bb.fail12:
  %code12 = bitcast i64 13 to i64
  ret i64 %code12
bb.check13:
  %count13 = phi i64 [ %next12, %next12.p.ok ]
  %ltNota = bitcast i64 0 to i64
  %ltNotb = bitcast i64 0 to i64
  %ltNotgot = icmp slt i64 %ltNota, %ltNotb
  %ltNot = xor i1 %ltNotgot, true
  %next13.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count13, i64 %one)
  %next13 = extractvalue {i64, i1} %next13.p.pair, 0
  %next13.p.bad = extractvalue {i64, i1} %next13.p.pair, 1
  br i1 %next13.p.bad, label %next13.p.trap, label %next13.p.ok
next13.p.trap:
  call void @llvm.trap()
  unreachable
next13.p.ok:
  br i1 %ltNot, label %bb.check14, label %bb.fail13
bb.fail13:
  %code13 = bitcast i64 14 to i64
  ret i64 %code13
bb.check14:
  %count14 = phi i64 [ %next13, %next13.p.ok ]
  %lea = bitcast i64 0 to i64
  %leb = bitcast i64 0 to i64
  %legot = icmp sle i64 %lea, %leb
  %le = and i1 %legot, %legot
  %next14.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count14, i64 %one)
  %next14 = extractvalue {i64, i1} %next14.p.pair, 0
  %next14.p.bad = extractvalue {i64, i1} %next14.p.pair, 1
  br i1 %next14.p.bad, label %next14.p.trap, label %next14.p.ok
next14.p.trap:
  call void @llvm.trap()
  unreachable
next14.p.ok:
  br i1 %le, label %bb.check15, label %bb.fail14
bb.fail14:
  %code14 = bitcast i64 15 to i64
  ret i64 %code14
bb.check15:
  %count15 = phi i64 [ %next14, %next14.p.ok ]
  %leNota = bitcast i64 1 to i64
  %leNotb = bitcast i64 0 to i64
  %leNotgot = icmp sle i64 %leNota, %leNotb
  %leNot = xor i1 %leNotgot, true
  %next15.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count15, i64 %one)
  %next15 = extractvalue {i64, i1} %next15.p.pair, 0
  %next15.p.bad = extractvalue {i64, i1} %next15.p.pair, 1
  br i1 %next15.p.bad, label %next15.p.trap, label %next15.p.ok
next15.p.trap:
  call void @llvm.trap()
  unreachable
next15.p.ok:
  br i1 %leNot, label %bb.check16, label %bb.fail15
bb.fail15:
  %code15 = bitcast i64 16 to i64
  ret i64 %code15
bb.check16:
  %count16 = phi i64 [ %next15, %next15.p.ok ]
  %gta = bitcast i64 0 to i64
  %gtb = bitcast i64 -1 to i64
  %gtgot = icmp sgt i64 %gta, %gtb
  %gt = and i1 %gtgot, %gtgot
  %next16.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count16, i64 %one)
  %next16 = extractvalue {i64, i1} %next16.p.pair, 0
  %next16.p.bad = extractvalue {i64, i1} %next16.p.pair, 1
  br i1 %next16.p.bad, label %next16.p.trap, label %next16.p.ok
next16.p.trap:
  call void @llvm.trap()
  unreachable
next16.p.ok:
  br i1 %gt, label %bb.check17, label %bb.fail16
bb.fail16:
  %code16 = bitcast i64 17 to i64
  ret i64 %code16
bb.check17:
  %count17 = phi i64 [ %next16, %next16.p.ok ]
  %gtNota = bitcast i64 0 to i64
  %gtNotb = bitcast i64 0 to i64
  %gtNotgot = icmp sgt i64 %gtNota, %gtNotb
  %gtNot = xor i1 %gtNotgot, true
  %next17.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count17, i64 %one)
  %next17 = extractvalue {i64, i1} %next17.p.pair, 0
  %next17.p.bad = extractvalue {i64, i1} %next17.p.pair, 1
  br i1 %next17.p.bad, label %next17.p.trap, label %next17.p.ok
next17.p.trap:
  call void @llvm.trap()
  unreachable
next17.p.ok:
  br i1 %gtNot, label %bb.check18, label %bb.fail17
bb.fail17:
  %code17 = bitcast i64 18 to i64
  ret i64 %code17
bb.check18:
  %count18 = phi i64 [ %next17, %next17.p.ok ]
  %gea = bitcast i64 0 to i64
  %geb = bitcast i64 0 to i64
  %gegot = icmp sge i64 %gea, %geb
  %ge = and i1 %gegot, %gegot
  %next18.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count18, i64 %one)
  %next18 = extractvalue {i64, i1} %next18.p.pair, 0
  %next18.p.bad = extractvalue {i64, i1} %next18.p.pair, 1
  br i1 %next18.p.bad, label %next18.p.trap, label %next18.p.ok
next18.p.trap:
  call void @llvm.trap()
  unreachable
next18.p.ok:
  br i1 %ge, label %bb.check19, label %bb.fail18
bb.fail18:
  %code18 = bitcast i64 19 to i64
  ret i64 %code18
bb.check19:
  %count19 = phi i64 [ %next18, %next18.p.ok ]
  %geNota = bitcast i64 -1 to i64
  %geNotb = bitcast i64 0 to i64
  %geNotgot = icmp sge i64 %geNota, %geNotb
  %geNot = xor i1 %geNotgot, true
  %next19.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count19, i64 %one)
  %next19 = extractvalue {i64, i1} %next19.p.pair, 0
  %next19.p.bad = extractvalue {i64, i1} %next19.p.pair, 1
  br i1 %next19.p.bad, label %next19.p.trap, label %next19.p.ok
next19.p.trap:
  call void @llvm.trap()
  unreachable
next19.p.ok:
  br i1 %geNot, label %bb.check20, label %bb.fail19
bb.fail19:
  %code19 = bitcast i64 20 to i64
  ret i64 %code19
bb.check20:
  %count20 = phi i64 [ %next19, %next19.p.ok ]
  %fadda = bitcast double 1.5 to double
  %faddb = bitcast double 2.25 to double
  %faddwant = bitcast double 3.75 to double
  %faddgot = fadd double %fadda, %faddb
  %fadd = fcmp oeq double %faddgot, %faddwant
  %next20.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count20, i64 %one)
  %next20 = extractvalue {i64, i1} %next20.p.pair, 0
  %next20.p.bad = extractvalue {i64, i1} %next20.p.pair, 1
  br i1 %next20.p.bad, label %next20.p.trap, label %next20.p.ok
next20.p.trap:
  call void @llvm.trap()
  unreachable
next20.p.ok:
  br i1 %fadd, label %bb.check21, label %bb.fail20
bb.fail20:
  %code20 = bitcast i64 21 to i64
  ret i64 %code20
bb.check21:
  %count21 = phi i64 [ %next20, %next20.p.ok ]
  %fsuba = bitcast double 1.5 to double
  %fsubb = bitcast double 2.25 to double
  %fsubwant = bitcast double -0.75 to double
  %fsubgot = fsub double %fsuba, %fsubb
  %fsub = fcmp oeq double %fsubgot, %fsubwant
  %next21.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count21, i64 %one)
  %next21 = extractvalue {i64, i1} %next21.p.pair, 0
  %next21.p.bad = extractvalue {i64, i1} %next21.p.pair, 1
  br i1 %next21.p.bad, label %next21.p.trap, label %next21.p.ok
next21.p.trap:
  call void @llvm.trap()
  unreachable
next21.p.ok:
  br i1 %fsub, label %bb.check22, label %bb.fail21
bb.fail21:
  %code21 = bitcast i64 22 to i64
  ret i64 %code21
bb.check22:
  %count22 = phi i64 [ %next21, %next21.p.ok ]
  %fmula = bitcast double 1.5 to double
  %fmulb = bitcast double -2.0 to double
  %fmulwant = bitcast double -3.0 to double
  %fmulgot = fmul double %fmula, %fmulb
  %fmul = fcmp oeq double %fmulgot, %fmulwant
  %next22.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count22, i64 %one)
  %next22 = extractvalue {i64, i1} %next22.p.pair, 0
  %next22.p.bad = extractvalue {i64, i1} %next22.p.pair, 1
  br i1 %next22.p.bad, label %next22.p.trap, label %next22.p.ok
next22.p.trap:
  call void @llvm.trap()
  unreachable
next22.p.ok:
  br i1 %fmul, label %bb.check23, label %bb.fail22
bb.fail22:
  %code22 = bitcast i64 23 to i64
  ret i64 %code22
bb.check23:
  %count23 = phi i64 [ %next22, %next22.p.ok ]
  %fdiva = bitcast double 3.0 to double
  %fdivb = bitcast double 4.0 to double
  %fdivwant = bitcast double 0.75 to double
  %fdivgot = fdiv double %fdiva, %fdivb
  %fdiv = fcmp oeq double %fdivgot, %fdivwant
  %next23.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count23, i64 %one)
  %next23 = extractvalue {i64, i1} %next23.p.pair, 0
  %next23.p.bad = extractvalue {i64, i1} %next23.p.pair, 1
  br i1 %next23.p.bad, label %next23.p.trap, label %next23.p.ok
next23.p.trap:
  call void @llvm.trap()
  unreachable
next23.p.ok:
  br i1 %fdiv, label %bb.check24, label %bb.fail23
bb.fail23:
  %code23 = bitcast i64 24 to i64
  ret i64 %code23
bb.check24:
  %count24 = phi i64 [ %next23, %next23.p.ok ]
  %feqa = bitcast double 0.5 to double
  %feqb = bitcast double 0.5 to double
  %feqgot = fcmp oeq double %feqa, %feqb
  %feq = and i1 %feqgot, %feqgot
  %next24.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count24, i64 %one)
  %next24 = extractvalue {i64, i1} %next24.p.pair, 0
  %next24.p.bad = extractvalue {i64, i1} %next24.p.pair, 1
  br i1 %next24.p.bad, label %next24.p.trap, label %next24.p.ok
next24.p.trap:
  call void @llvm.trap()
  unreachable
next24.p.ok:
  br i1 %feq, label %bb.check25, label %bb.fail24
bb.fail24:
  %code24 = bitcast i64 25 to i64
  ret i64 %code24
bb.check25:
  %count25 = phi i64 [ %next24, %next24.p.ok ]
  %fnea = bitcast double 0.5 to double
  %fneb = bitcast double 0.25 to double
  %fnegot = fcmp une double %fnea, %fneb
  %fne = and i1 %fnegot, %fnegot
  %next25.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count25, i64 %one)
  %next25 = extractvalue {i64, i1} %next25.p.pair, 0
  %next25.p.bad = extractvalue {i64, i1} %next25.p.pair, 1
  br i1 %next25.p.bad, label %next25.p.trap, label %next25.p.ok
next25.p.trap:
  call void @llvm.trap()
  unreachable
next25.p.ok:
  br i1 %fne, label %bb.check26, label %bb.fail25
bb.fail25:
  %code25 = bitcast i64 26 to i64
  ret i64 %code25
bb.check26:
  %count26 = phi i64 [ %next25, %next25.p.ok ]
  %flta = bitcast double 0.25 to double
  %fltb = bitcast double 0.5 to double
  %fltgot = fcmp olt double %flta, %fltb
  %flt = and i1 %fltgot, %fltgot
  %next26.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count26, i64 %one)
  %next26 = extractvalue {i64, i1} %next26.p.pair, 0
  %next26.p.bad = extractvalue {i64, i1} %next26.p.pair, 1
  br i1 %next26.p.bad, label %next26.p.trap, label %next26.p.ok
next26.p.trap:
  call void @llvm.trap()
  unreachable
next26.p.ok:
  br i1 %flt, label %bb.check27, label %bb.fail26
bb.fail26:
  %code26 = bitcast i64 27 to i64
  ret i64 %code26
bb.check27:
  %count27 = phi i64 [ %next26, %next26.p.ok ]
  %fltNota = bitcast double 0.5 to double
  %fltNotb = bitcast double 0.5 to double
  %fltNotgot = fcmp olt double %fltNota, %fltNotb
  %fltNot = xor i1 %fltNotgot, true
  %next27.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count27, i64 %one)
  %next27 = extractvalue {i64, i1} %next27.p.pair, 0
  %next27.p.bad = extractvalue {i64, i1} %next27.p.pair, 1
  br i1 %next27.p.bad, label %next27.p.trap, label %next27.p.ok
next27.p.trap:
  call void @llvm.trap()
  unreachable
next27.p.ok:
  br i1 %fltNot, label %bb.check28, label %bb.fail27
bb.fail27:
  %code27 = bitcast i64 28 to i64
  ret i64 %code27
bb.check28:
  %count28 = phi i64 [ %next27, %next27.p.ok ]
  %flea = bitcast double 0.5 to double
  %fleb = bitcast double 0.5 to double
  %flegot = fcmp ole double %flea, %fleb
  %fle = and i1 %flegot, %flegot
  %next28.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count28, i64 %one)
  %next28 = extractvalue {i64, i1} %next28.p.pair, 0
  %next28.p.bad = extractvalue {i64, i1} %next28.p.pair, 1
  br i1 %next28.p.bad, label %next28.p.trap, label %next28.p.ok
next28.p.trap:
  call void @llvm.trap()
  unreachable
next28.p.ok:
  br i1 %fle, label %bb.check29, label %bb.fail28
bb.fail28:
  %code28 = bitcast i64 29 to i64
  ret i64 %code28
bb.check29:
  %count29 = phi i64 [ %next28, %next28.p.ok ]
  %fgta = bitcast double 0.5 to double
  %fgtb = bitcast double 0.25 to double
  %fgtgot = fcmp ogt double %fgta, %fgtb
  %fgt = and i1 %fgtgot, %fgtgot
  %next29.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count29, i64 %one)
  %next29 = extractvalue {i64, i1} %next29.p.pair, 0
  %next29.p.bad = extractvalue {i64, i1} %next29.p.pair, 1
  br i1 %next29.p.bad, label %next29.p.trap, label %next29.p.ok
next29.p.trap:
  call void @llvm.trap()
  unreachable
next29.p.ok:
  br i1 %fgt, label %bb.check30, label %bb.fail29
bb.fail29:
  %code29 = bitcast i64 30 to i64
  ret i64 %code29
bb.check30:
  %count30 = phi i64 [ %next29, %next29.p.ok ]
  %fgea = bitcast double 0.5 to double
  %fgeb = bitcast double 0.5 to double
  %fgegot = fcmp oge double %fgea, %fgeb
  %fge = and i1 %fgegot, %fgegot
  %next30.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count30, i64 %one)
  %next30 = extractvalue {i64, i1} %next30.p.pair, 0
  %next30.p.bad = extractvalue {i64, i1} %next30.p.pair, 1
  br i1 %next30.p.bad, label %next30.p.trap, label %next30.p.ok
next30.p.trap:
  call void @llvm.trap()
  unreachable
next30.p.ok:
  br i1 %fge, label %bb.check31, label %bb.fail30
bb.fail30:
  %code30 = bitcast i64 31 to i64
  ret i64 %code30
bb.check31:
  %count31 = phi i64 [ %next30, %next30.p.ok ]
  %fgeNota = bitcast double 0.25 to double
  %fgeNotb = bitcast double 0.5 to double
  %fgeNotgot = fcmp oge double %fgeNota, %fgeNotb
  %fgeNot = xor i1 %fgeNotgot, true
  %next31.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count31, i64 %one)
  %next31 = extractvalue {i64, i1} %next31.p.pair, 0
  %next31.p.bad = extractvalue {i64, i1} %next31.p.pair, 1
  br i1 %next31.p.bad, label %next31.p.trap, label %next31.p.ok
next31.p.trap:
  call void @llvm.trap()
  unreachable
next31.p.ok:
  br i1 %fgeNot, label %bb.check32, label %bb.fail31
bb.fail31:
  %code31 = bitcast i64 32 to i64
  ret i64 %code31
bb.check32:
  %count32 = phi i64 [ %next31, %next31.p.ok ]
  %nanZero = bitcast double 0.0 to double
  %nan = fdiv double %nanZero, %nanZero
  %nanNe = fcmp une double %nan, %nan
  %nanEq = fcmp oeq double %nan, %nan
  %nanLe = fcmp ole double %nan, %nan
  %nanOrdered = or i1 %nanEq, %nanLe
  %nanUnordered = xor i1 %nanOrdered, true
  %nanOk = and i1 %nanNe, %nanUnordered
  %next32.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count32, i64 %one)
  %next32 = extractvalue {i64, i1} %next32.p.pair, 0
  %next32.p.bad = extractvalue {i64, i1} %next32.p.pair, 1
  br i1 %next32.p.bad, label %next32.p.trap, label %next32.p.ok
next32.p.trap:
  call void @llvm.trap()
  unreachable
next32.p.ok:
  br i1 %nanOk, label %bb.check33, label %bb.fail32
bb.fail32:
  %code32 = bitcast i64 33 to i64
  ret i64 %code32
bb.check33:
  %count33 = phi i64 [ %next32, %next32.p.ok ]
  %yes = bitcast i1 true to i1
  %no = bitcast i1 false to i1
  %andNo = and i1 %yes, %no
  %orYes = or i1 %no, %yes
  %andNoNot = xor i1 %andNo, true
  %logicOk = and i1 %andNoNot, %orYes
  %next33.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count33, i64 %one)
  %next33 = extractvalue {i64, i1} %next33.p.pair, 0
  %next33.p.bad = extractvalue {i64, i1} %next33.p.pair, 1
  br i1 %next33.p.bad, label %next33.p.trap, label %next33.p.ok
next33.p.trap:
  call void @llvm.trap()
  unreachable
next33.p.ok:
  br i1 %logicOk, label %bb.check34, label %bb.fail33
bb.fail33:
  %code33 = bitcast i64 34 to i64
  ret i64 %code33
bb.check34:
  %count34 = phi i64 [ %next33, %next33.p.ok ]
  %three = bitcast i64 3 to i64
  %threeF = sitofp i64 %three to double
  %threeWant = bitcast double 3.0 to double
  %toFloatOk = fcmp oeq double %threeF, %threeWant
  %next34.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count34, i64 %one)
  %next34 = extractvalue {i64, i1} %next34.p.pair, 0
  %next34.p.bad = extractvalue {i64, i1} %next34.p.pair, 1
  br i1 %next34.p.bad, label %next34.p.trap, label %next34.p.ok
next34.p.trap:
  call void @llvm.trap()
  unreachable
next34.p.ok:
  br i1 %toFloatOk, label %bb.check35, label %bb.fail34
bb.fail34:
  %code34 = bitcast i64 35 to i64
  ret i64 %code34
bb.check35:
  %count35 = phi i64 [ %next34, %next34.p.ok ]
  %negFrac = bitcast double -2.75 to double
  %negTrunc.p.low = fcmp oge double %negFrac, 0xC3E0000000000000
  %negTrunc.p.high = fcmp olt double %negFrac, 0x43E0000000000000
  %negTrunc.p.fits = and i1 %negTrunc.p.low, %negTrunc.p.high
  %negTrunc.p.bad = xor i1 %negTrunc.p.fits, true
  br i1 %negTrunc.p.bad, label %negTrunc.p.trap, label %negTrunc.p.ok
negTrunc.p.trap:
  call void @rterr.int(i32 8)
  unreachable
negTrunc.p.ok:
  %negTrunc = fptosi double %negFrac to i64
  %negWant = bitcast i64 -2 to i64
  %toIntOk = icmp eq i64 %negTrunc, %negWant
  %next35.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count35, i64 %one)
  %next35 = extractvalue {i64, i1} %next35.p.pair, 0
  %next35.p.bad = extractvalue {i64, i1} %next35.p.pair, 1
  br i1 %next35.p.bad, label %next35.p.trap, label %next35.p.ok
next35.p.trap:
  call void @llvm.trap()
  unreachable
next35.p.ok:
  br i1 %toIntOk, label %bb.check36, label %bb.fail35
bb.fail35:
  %code35 = bitcast i64 36 to i64
  ret i64 %code35
bb.check36:
  %count36 = phi i64 [ %next35, %next35.p.ok ]
  %lowInt = bitcast i64 -9223372036854775808 to i64
  %lowF = sitofp i64 %lowInt to double
  %lowBack.p.low = fcmp oge double %lowF, 0xC3E0000000000000
  %lowBack.p.high = fcmp olt double %lowF, 0x43E0000000000000
  %lowBack.p.fits = and i1 %lowBack.p.low, %lowBack.p.high
  %lowBack.p.bad = xor i1 %lowBack.p.fits, true
  br i1 %lowBack.p.bad, label %lowBack.p.trap, label %lowBack.p.ok
lowBack.p.trap:
  call void @rterr.int(i32 8)
  unreachable
lowBack.p.ok:
  %lowBack = fptosi double %lowF to i64
  %lowOk = icmp eq i64 %lowBack, %lowInt
  %next36.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count36, i64 %one)
  %next36 = extractvalue {i64, i1} %next36.p.pair, 0
  %next36.p.bad = extractvalue {i64, i1} %next36.p.pair, 1
  br i1 %next36.p.bad, label %next36.p.trap, label %next36.p.ok
next36.p.trap:
  call void @llvm.trap()
  unreachable
next36.p.ok:
  br i1 %lowOk, label %bb.check37, label %bb.fail36
bb.fail36:
  %code36 = bitcast i64 37 to i64
  ret i64 %code36
bb.check37:
  %count37 = phi i64 [ %next36, %next36.p.ok ]
  %floorPosa = bitcast double 2.7 to double
  %floorPosr = call double @llvm.floor.f64(double %floorPosa)
  %floorPoswant = bitcast double 2.0 to double
  %floorPoseq = fcmp oeq double %floorPosr, %floorPoswant
  %floorPosaOrdered = fcmp oeq double %floorPosr, %floorPosr
  %floorPosbOrdered = fcmp oeq double %floorPoswant, %floorPoswant
  %floorPosaIsNan = xor i1 %floorPosaOrdered, true
  %floorPosbIsNan = xor i1 %floorPosbOrdered, true
  %floorPosbothNan = and i1 %floorPosaIsNan, %floorPosbIsNan
  %floorPosone = bitcast double 1.0 to double
  %floorPosra = fdiv double %floorPosone, %floorPosr
  %floorPosrb = fdiv double %floorPosone, %floorPoswant
  %floorPossameSign = fcmp oeq double %floorPosra, %floorPosrb
  %floorPoseqAndSign = and i1 %floorPoseq, %floorPossameSign
  %floorPos = or i1 %floorPosbothNan, %floorPoseqAndSign
  %next37.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count37, i64 %one)
  %next37 = extractvalue {i64, i1} %next37.p.pair, 0
  %next37.p.bad = extractvalue {i64, i1} %next37.p.pair, 1
  br i1 %next37.p.bad, label %next37.p.trap, label %next37.p.ok
next37.p.trap:
  call void @llvm.trap()
  unreachable
next37.p.ok:
  br i1 %floorPos, label %bb.check38, label %bb.fail37
bb.fail37:
  %code37 = bitcast i64 38 to i64
  ret i64 %code37
bb.check38:
  %count38 = phi i64 [ %next37, %next37.p.ok ]
  %floorNega = bitcast double -2.5 to double
  %floorNegr = call double @llvm.floor.f64(double %floorNega)
  %floorNegwant = bitcast double -3.0 to double
  %floorNegeq = fcmp oeq double %floorNegr, %floorNegwant
  %floorNegaOrdered = fcmp oeq double %floorNegr, %floorNegr
  %floorNegbOrdered = fcmp oeq double %floorNegwant, %floorNegwant
  %floorNegaIsNan = xor i1 %floorNegaOrdered, true
  %floorNegbIsNan = xor i1 %floorNegbOrdered, true
  %floorNegbothNan = and i1 %floorNegaIsNan, %floorNegbIsNan
  %floorNegone = bitcast double 1.0 to double
  %floorNegra = fdiv double %floorNegone, %floorNegr
  %floorNegrb = fdiv double %floorNegone, %floorNegwant
  %floorNegsameSign = fcmp oeq double %floorNegra, %floorNegrb
  %floorNegeqAndSign = and i1 %floorNegeq, %floorNegsameSign
  %floorNeg = or i1 %floorNegbothNan, %floorNegeqAndSign
  %next38.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count38, i64 %one)
  %next38 = extractvalue {i64, i1} %next38.p.pair, 0
  %next38.p.bad = extractvalue {i64, i1} %next38.p.pair, 1
  br i1 %next38.p.bad, label %next38.p.trap, label %next38.p.ok
next38.p.trap:
  call void @llvm.trap()
  unreachable
next38.p.ok:
  br i1 %floorNeg, label %bb.check39, label %bb.fail38
bb.fail38:
  %code38 = bitcast i64 39 to i64
  ret i64 %code38
bb.check39:
  %count39 = phi i64 [ %next38, %next38.p.ok ]
  %floorNegHalfa = bitcast double -0.5 to double
  %floorNegHalfr = call double @llvm.floor.f64(double %floorNegHalfa)
  %floorNegHalfwant = bitcast double -1.0 to double
  %floorNegHalfeq = fcmp oeq double %floorNegHalfr, %floorNegHalfwant
  %floorNegHalfaOrdered = fcmp oeq double %floorNegHalfr, %floorNegHalfr
  %floorNegHalfbOrdered = fcmp oeq double %floorNegHalfwant, %floorNegHalfwant
  %floorNegHalfaIsNan = xor i1 %floorNegHalfaOrdered, true
  %floorNegHalfbIsNan = xor i1 %floorNegHalfbOrdered, true
  %floorNegHalfbothNan = and i1 %floorNegHalfaIsNan, %floorNegHalfbIsNan
  %floorNegHalfone = bitcast double 1.0 to double
  %floorNegHalfra = fdiv double %floorNegHalfone, %floorNegHalfr
  %floorNegHalfrb = fdiv double %floorNegHalfone, %floorNegHalfwant
  %floorNegHalfsameSign = fcmp oeq double %floorNegHalfra, %floorNegHalfrb
  %floorNegHalfeqAndSign = and i1 %floorNegHalfeq, %floorNegHalfsameSign
  %floorNegHalf = or i1 %floorNegHalfbothNan, %floorNegHalfeqAndSign
  %next39.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count39, i64 %one)
  %next39 = extractvalue {i64, i1} %next39.p.pair, 0
  %next39.p.bad = extractvalue {i64, i1} %next39.p.pair, 1
  br i1 %next39.p.bad, label %next39.p.trap, label %next39.p.ok
next39.p.trap:
  call void @llvm.trap()
  unreachable
next39.p.ok:
  br i1 %floorNegHalf, label %bb.check40, label %bb.fail39
bb.fail39:
  %code39 = bitcast i64 40 to i64
  ret i64 %code39
bb.check40:
  %count40 = phi i64 [ %next39, %next39.p.ok ]
  %floorNegZeroa = bitcast double -0.0 to double
  %floorNegZeror = call double @llvm.floor.f64(double %floorNegZeroa)
  %floorNegZerowant = bitcast double -0.0 to double
  %floorNegZeroeq = fcmp oeq double %floorNegZeror, %floorNegZerowant
  %floorNegZeroaOrdered = fcmp oeq double %floorNegZeror, %floorNegZeror
  %floorNegZerobOrdered = fcmp oeq double %floorNegZerowant, %floorNegZerowant
  %floorNegZeroaIsNan = xor i1 %floorNegZeroaOrdered, true
  %floorNegZerobIsNan = xor i1 %floorNegZerobOrdered, true
  %floorNegZerobothNan = and i1 %floorNegZeroaIsNan, %floorNegZerobIsNan
  %floorNegZeroone = bitcast double 1.0 to double
  %floorNegZerora = fdiv double %floorNegZeroone, %floorNegZeror
  %floorNegZerorb = fdiv double %floorNegZeroone, %floorNegZerowant
  %floorNegZerosameSign = fcmp oeq double %floorNegZerora, %floorNegZerorb
  %floorNegZeroeqAndSign = and i1 %floorNegZeroeq, %floorNegZerosameSign
  %floorNegZero = or i1 %floorNegZerobothNan, %floorNegZeroeqAndSign
  %next40.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count40, i64 %one)
  %next40 = extractvalue {i64, i1} %next40.p.pair, 0
  %next40.p.bad = extractvalue {i64, i1} %next40.p.pair, 1
  br i1 %next40.p.bad, label %next40.p.trap, label %next40.p.ok
next40.p.trap:
  call void @llvm.trap()
  unreachable
next40.p.ok:
  br i1 %floorNegZero, label %bb.check41, label %bb.fail40
bb.fail40:
  %code40 = bitcast i64 41 to i64
  ret i64 %code40
bb.check41:
  %count41 = phi i64 [ %next40, %next40.p.ok ]
  %floorInfa = bitcast double 0x7FF0000000000000 to double
  %floorInfr = call double @llvm.floor.f64(double %floorInfa)
  %floorInfwant = bitcast double 0x7FF0000000000000 to double
  %floorInfeq = fcmp oeq double %floorInfr, %floorInfwant
  %floorInfaOrdered = fcmp oeq double %floorInfr, %floorInfr
  %floorInfbOrdered = fcmp oeq double %floorInfwant, %floorInfwant
  %floorInfaIsNan = xor i1 %floorInfaOrdered, true
  %floorInfbIsNan = xor i1 %floorInfbOrdered, true
  %floorInfbothNan = and i1 %floorInfaIsNan, %floorInfbIsNan
  %floorInfone = bitcast double 1.0 to double
  %floorInfra = fdiv double %floorInfone, %floorInfr
  %floorInfrb = fdiv double %floorInfone, %floorInfwant
  %floorInfsameSign = fcmp oeq double %floorInfra, %floorInfrb
  %floorInfeqAndSign = and i1 %floorInfeq, %floorInfsameSign
  %floorInf = or i1 %floorInfbothNan, %floorInfeqAndSign
  %next41.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count41, i64 %one)
  %next41 = extractvalue {i64, i1} %next41.p.pair, 0
  %next41.p.bad = extractvalue {i64, i1} %next41.p.pair, 1
  br i1 %next41.p.bad, label %next41.p.trap, label %next41.p.ok
next41.p.trap:
  call void @llvm.trap()
  unreachable
next41.p.ok:
  br i1 %floorInf, label %bb.check42, label %bb.fail41
bb.fail41:
  %code41 = bitcast i64 42 to i64
  ret i64 %code41
bb.check42:
  %count42 = phi i64 [ %next41, %next41.p.ok ]
  %floorNana = bitcast double 0x7FF8000000000000 to double
  %floorNanr = call double @llvm.floor.f64(double %floorNana)
  %floorNanwant = bitcast double 0x7FF8000000000000 to double
  %floorNaneq = fcmp oeq double %floorNanr, %floorNanwant
  %floorNanaOrdered = fcmp oeq double %floorNanr, %floorNanr
  %floorNanbOrdered = fcmp oeq double %floorNanwant, %floorNanwant
  %floorNanaIsNan = xor i1 %floorNanaOrdered, true
  %floorNanbIsNan = xor i1 %floorNanbOrdered, true
  %floorNanbothNan = and i1 %floorNanaIsNan, %floorNanbIsNan
  %floorNanone = bitcast double 1.0 to double
  %floorNanra = fdiv double %floorNanone, %floorNanr
  %floorNanrb = fdiv double %floorNanone, %floorNanwant
  %floorNansameSign = fcmp oeq double %floorNanra, %floorNanrb
  %floorNaneqAndSign = and i1 %floorNaneq, %floorNansameSign
  %floorNan = or i1 %floorNanbothNan, %floorNaneqAndSign
  %next42.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count42, i64 %one)
  %next42 = extractvalue {i64, i1} %next42.p.pair, 0
  %next42.p.bad = extractvalue {i64, i1} %next42.p.pair, 1
  br i1 %next42.p.bad, label %next42.p.trap, label %next42.p.ok
next42.p.trap:
  call void @llvm.trap()
  unreachable
next42.p.ok:
  br i1 %floorNan, label %bb.check43, label %bb.fail42
bb.fail42:
  %code42 = bitcast i64 43 to i64
  ret i64 %code42
bb.check43:
  %count43 = phi i64 [ %next42, %next42.p.ok ]
  %ceilPosa = bitcast double 2.3 to double
  %ceilPosr = call double @llvm.ceil.f64(double %ceilPosa)
  %ceilPoswant = bitcast double 3.0 to double
  %ceilPoseq = fcmp oeq double %ceilPosr, %ceilPoswant
  %ceilPosaOrdered = fcmp oeq double %ceilPosr, %ceilPosr
  %ceilPosbOrdered = fcmp oeq double %ceilPoswant, %ceilPoswant
  %ceilPosaIsNan = xor i1 %ceilPosaOrdered, true
  %ceilPosbIsNan = xor i1 %ceilPosbOrdered, true
  %ceilPosbothNan = and i1 %ceilPosaIsNan, %ceilPosbIsNan
  %ceilPosone = bitcast double 1.0 to double
  %ceilPosra = fdiv double %ceilPosone, %ceilPosr
  %ceilPosrb = fdiv double %ceilPosone, %ceilPoswant
  %ceilPossameSign = fcmp oeq double %ceilPosra, %ceilPosrb
  %ceilPoseqAndSign = and i1 %ceilPoseq, %ceilPossameSign
  %ceilPos = or i1 %ceilPosbothNan, %ceilPoseqAndSign
  %next43.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count43, i64 %one)
  %next43 = extractvalue {i64, i1} %next43.p.pair, 0
  %next43.p.bad = extractvalue {i64, i1} %next43.p.pair, 1
  br i1 %next43.p.bad, label %next43.p.trap, label %next43.p.ok
next43.p.trap:
  call void @llvm.trap()
  unreachable
next43.p.ok:
  br i1 %ceilPos, label %bb.check44, label %bb.fail43
bb.fail43:
  %code43 = bitcast i64 44 to i64
  ret i64 %code43
bb.check44:
  %count44 = phi i64 [ %next43, %next43.p.ok ]
  %ceilNega = bitcast double -2.5 to double
  %ceilNegr = call double @llvm.ceil.f64(double %ceilNega)
  %ceilNegwant = bitcast double -2.0 to double
  %ceilNegeq = fcmp oeq double %ceilNegr, %ceilNegwant
  %ceilNegaOrdered = fcmp oeq double %ceilNegr, %ceilNegr
  %ceilNegbOrdered = fcmp oeq double %ceilNegwant, %ceilNegwant
  %ceilNegaIsNan = xor i1 %ceilNegaOrdered, true
  %ceilNegbIsNan = xor i1 %ceilNegbOrdered, true
  %ceilNegbothNan = and i1 %ceilNegaIsNan, %ceilNegbIsNan
  %ceilNegone = bitcast double 1.0 to double
  %ceilNegra = fdiv double %ceilNegone, %ceilNegr
  %ceilNegrb = fdiv double %ceilNegone, %ceilNegwant
  %ceilNegsameSign = fcmp oeq double %ceilNegra, %ceilNegrb
  %ceilNegeqAndSign = and i1 %ceilNegeq, %ceilNegsameSign
  %ceilNeg = or i1 %ceilNegbothNan, %ceilNegeqAndSign
  %next44.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count44, i64 %one)
  %next44 = extractvalue {i64, i1} %next44.p.pair, 0
  %next44.p.bad = extractvalue {i64, i1} %next44.p.pair, 1
  br i1 %next44.p.bad, label %next44.p.trap, label %next44.p.ok
next44.p.trap:
  call void @llvm.trap()
  unreachable
next44.p.ok:
  br i1 %ceilNeg, label %bb.check45, label %bb.fail44
bb.fail44:
  %code44 = bitcast i64 45 to i64
  ret i64 %code44
bb.check45:
  %count45 = phi i64 [ %next44, %next44.p.ok ]
  %ceilNegZeroa = bitcast double -0.0 to double
  %ceilNegZeror = call double @llvm.ceil.f64(double %ceilNegZeroa)
  %ceilNegZerowant = bitcast double -0.0 to double
  %ceilNegZeroeq = fcmp oeq double %ceilNegZeror, %ceilNegZerowant
  %ceilNegZeroaOrdered = fcmp oeq double %ceilNegZeror, %ceilNegZeror
  %ceilNegZerobOrdered = fcmp oeq double %ceilNegZerowant, %ceilNegZerowant
  %ceilNegZeroaIsNan = xor i1 %ceilNegZeroaOrdered, true
  %ceilNegZerobIsNan = xor i1 %ceilNegZerobOrdered, true
  %ceilNegZerobothNan = and i1 %ceilNegZeroaIsNan, %ceilNegZerobIsNan
  %ceilNegZeroone = bitcast double 1.0 to double
  %ceilNegZerora = fdiv double %ceilNegZeroone, %ceilNegZeror
  %ceilNegZerorb = fdiv double %ceilNegZeroone, %ceilNegZerowant
  %ceilNegZerosameSign = fcmp oeq double %ceilNegZerora, %ceilNegZerorb
  %ceilNegZeroeqAndSign = and i1 %ceilNegZeroeq, %ceilNegZerosameSign
  %ceilNegZero = or i1 %ceilNegZerobothNan, %ceilNegZeroeqAndSign
  %next45.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count45, i64 %one)
  %next45 = extractvalue {i64, i1} %next45.p.pair, 0
  %next45.p.bad = extractvalue {i64, i1} %next45.p.pair, 1
  br i1 %next45.p.bad, label %next45.p.trap, label %next45.p.ok
next45.p.trap:
  call void @llvm.trap()
  unreachable
next45.p.ok:
  br i1 %ceilNegZero, label %bb.check46, label %bb.fail45
bb.fail45:
  %code45 = bitcast i64 46 to i64
  ret i64 %code45
bb.check46:
  %count46 = phi i64 [ %next45, %next45.p.ok ]
  %ceilNegInfa = bitcast double 0xFFF0000000000000 to double
  %ceilNegInfr = call double @llvm.ceil.f64(double %ceilNegInfa)
  %ceilNegInfwant = bitcast double 0xFFF0000000000000 to double
  %ceilNegInfeq = fcmp oeq double %ceilNegInfr, %ceilNegInfwant
  %ceilNegInfaOrdered = fcmp oeq double %ceilNegInfr, %ceilNegInfr
  %ceilNegInfbOrdered = fcmp oeq double %ceilNegInfwant, %ceilNegInfwant
  %ceilNegInfaIsNan = xor i1 %ceilNegInfaOrdered, true
  %ceilNegInfbIsNan = xor i1 %ceilNegInfbOrdered, true
  %ceilNegInfbothNan = and i1 %ceilNegInfaIsNan, %ceilNegInfbIsNan
  %ceilNegInfone = bitcast double 1.0 to double
  %ceilNegInfra = fdiv double %ceilNegInfone, %ceilNegInfr
  %ceilNegInfrb = fdiv double %ceilNegInfone, %ceilNegInfwant
  %ceilNegInfsameSign = fcmp oeq double %ceilNegInfra, %ceilNegInfrb
  %ceilNegInfeqAndSign = and i1 %ceilNegInfeq, %ceilNegInfsameSign
  %ceilNegInf = or i1 %ceilNegInfbothNan, %ceilNegInfeqAndSign
  %next46.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count46, i64 %one)
  %next46 = extractvalue {i64, i1} %next46.p.pair, 0
  %next46.p.bad = extractvalue {i64, i1} %next46.p.pair, 1
  br i1 %next46.p.bad, label %next46.p.trap, label %next46.p.ok
next46.p.trap:
  call void @llvm.trap()
  unreachable
next46.p.ok:
  br i1 %ceilNegInf, label %bb.check47, label %bb.fail46
bb.fail46:
  %code46 = bitcast i64 47 to i64
  ret i64 %code46
bb.check47:
  %count47 = phi i64 [ %next46, %next46.p.ok ]
  %roundHalfa = bitcast double 2.5 to double
  %roundHalfr = call double @llvm.round.f64(double %roundHalfa)
  %roundHalfwant = bitcast double 3.0 to double
  %roundHalfeq = fcmp oeq double %roundHalfr, %roundHalfwant
  %roundHalfaOrdered = fcmp oeq double %roundHalfr, %roundHalfr
  %roundHalfbOrdered = fcmp oeq double %roundHalfwant, %roundHalfwant
  %roundHalfaIsNan = xor i1 %roundHalfaOrdered, true
  %roundHalfbIsNan = xor i1 %roundHalfbOrdered, true
  %roundHalfbothNan = and i1 %roundHalfaIsNan, %roundHalfbIsNan
  %roundHalfone = bitcast double 1.0 to double
  %roundHalfra = fdiv double %roundHalfone, %roundHalfr
  %roundHalfrb = fdiv double %roundHalfone, %roundHalfwant
  %roundHalfsameSign = fcmp oeq double %roundHalfra, %roundHalfrb
  %roundHalfeqAndSign = and i1 %roundHalfeq, %roundHalfsameSign
  %roundHalf = or i1 %roundHalfbothNan, %roundHalfeqAndSign
  %next47.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count47, i64 %one)
  %next47 = extractvalue {i64, i1} %next47.p.pair, 0
  %next47.p.bad = extractvalue {i64, i1} %next47.p.pair, 1
  br i1 %next47.p.bad, label %next47.p.trap, label %next47.p.ok
next47.p.trap:
  call void @llvm.trap()
  unreachable
next47.p.ok:
  br i1 %roundHalf, label %bb.check48, label %bb.fail47
bb.fail47:
  %code47 = bitcast i64 48 to i64
  ret i64 %code47
bb.check48:
  %count48 = phi i64 [ %next47, %next47.p.ok ]
  %roundNegHalfa = bitcast double -2.5 to double
  %roundNegHalfr = call double @llvm.round.f64(double %roundNegHalfa)
  %roundNegHalfwant = bitcast double -3.0 to double
  %roundNegHalfeq = fcmp oeq double %roundNegHalfr, %roundNegHalfwant
  %roundNegHalfaOrdered = fcmp oeq double %roundNegHalfr, %roundNegHalfr
  %roundNegHalfbOrdered = fcmp oeq double %roundNegHalfwant, %roundNegHalfwant
  %roundNegHalfaIsNan = xor i1 %roundNegHalfaOrdered, true
  %roundNegHalfbIsNan = xor i1 %roundNegHalfbOrdered, true
  %roundNegHalfbothNan = and i1 %roundNegHalfaIsNan, %roundNegHalfbIsNan
  %roundNegHalfone = bitcast double 1.0 to double
  %roundNegHalfra = fdiv double %roundNegHalfone, %roundNegHalfr
  %roundNegHalfrb = fdiv double %roundNegHalfone, %roundNegHalfwant
  %roundNegHalfsameSign = fcmp oeq double %roundNegHalfra, %roundNegHalfrb
  %roundNegHalfeqAndSign = and i1 %roundNegHalfeq, %roundNegHalfsameSign
  %roundNegHalf = or i1 %roundNegHalfbothNan, %roundNegHalfeqAndSign
  %next48.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count48, i64 %one)
  %next48 = extractvalue {i64, i1} %next48.p.pair, 0
  %next48.p.bad = extractvalue {i64, i1} %next48.p.pair, 1
  br i1 %next48.p.bad, label %next48.p.trap, label %next48.p.ok
next48.p.trap:
  call void @llvm.trap()
  unreachable
next48.p.ok:
  br i1 %roundNegHalf, label %bb.check49, label %bb.fail48
bb.fail48:
  %code48 = bitcast i64 49 to i64
  ret i64 %code48
bb.check49:
  %count49 = phi i64 [ %next48, %next48.p.ok ]
  %roundUpa = bitcast double 2.6 to double
  %roundUpr = call double @llvm.round.f64(double %roundUpa)
  %roundUpwant = bitcast double 3.0 to double
  %roundUpeq = fcmp oeq double %roundUpr, %roundUpwant
  %roundUpaOrdered = fcmp oeq double %roundUpr, %roundUpr
  %roundUpbOrdered = fcmp oeq double %roundUpwant, %roundUpwant
  %roundUpaIsNan = xor i1 %roundUpaOrdered, true
  %roundUpbIsNan = xor i1 %roundUpbOrdered, true
  %roundUpbothNan = and i1 %roundUpaIsNan, %roundUpbIsNan
  %roundUpone = bitcast double 1.0 to double
  %roundUpra = fdiv double %roundUpone, %roundUpr
  %roundUprb = fdiv double %roundUpone, %roundUpwant
  %roundUpsameSign = fcmp oeq double %roundUpra, %roundUprb
  %roundUpeqAndSign = and i1 %roundUpeq, %roundUpsameSign
  %roundUp = or i1 %roundUpbothNan, %roundUpeqAndSign
  %next49.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count49, i64 %one)
  %next49 = extractvalue {i64, i1} %next49.p.pair, 0
  %next49.p.bad = extractvalue {i64, i1} %next49.p.pair, 1
  br i1 %next49.p.bad, label %next49.p.trap, label %next49.p.ok
next49.p.trap:
  call void @llvm.trap()
  unreachable
next49.p.ok:
  br i1 %roundUp, label %bb.check50, label %bb.fail49
bb.fail49:
  %code49 = bitcast i64 50 to i64
  ret i64 %code49
bb.check50:
  %count50 = phi i64 [ %next49, %next49.p.ok ]
  %roundDowna = bitcast double 2.4 to double
  %roundDownr = call double @llvm.round.f64(double %roundDowna)
  %roundDownwant = bitcast double 2.0 to double
  %roundDowneq = fcmp oeq double %roundDownr, %roundDownwant
  %roundDownaOrdered = fcmp oeq double %roundDownr, %roundDownr
  %roundDownbOrdered = fcmp oeq double %roundDownwant, %roundDownwant
  %roundDownaIsNan = xor i1 %roundDownaOrdered, true
  %roundDownbIsNan = xor i1 %roundDownbOrdered, true
  %roundDownbothNan = and i1 %roundDownaIsNan, %roundDownbIsNan
  %roundDownone = bitcast double 1.0 to double
  %roundDownra = fdiv double %roundDownone, %roundDownr
  %roundDownrb = fdiv double %roundDownone, %roundDownwant
  %roundDownsameSign = fcmp oeq double %roundDownra, %roundDownrb
  %roundDowneqAndSign = and i1 %roundDowneq, %roundDownsameSign
  %roundDown = or i1 %roundDownbothNan, %roundDowneqAndSign
  %next50.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count50, i64 %one)
  %next50 = extractvalue {i64, i1} %next50.p.pair, 0
  %next50.p.bad = extractvalue {i64, i1} %next50.p.pair, 1
  br i1 %next50.p.bad, label %next50.p.trap, label %next50.p.ok
next50.p.trap:
  call void @llvm.trap()
  unreachable
next50.p.ok:
  br i1 %roundDown, label %bb.check51, label %bb.fail50
bb.fail50:
  %code50 = bitcast i64 51 to i64
  ret i64 %code50
bb.check51:
  %count51 = phi i64 [ %next50, %next50.p.ok ]
  %roundNana = bitcast double 0x7FF8000000000000 to double
  %roundNanr = call double @llvm.round.f64(double %roundNana)
  %roundNanwant = bitcast double 0x7FF8000000000000 to double
  %roundNaneq = fcmp oeq double %roundNanr, %roundNanwant
  %roundNanaOrdered = fcmp oeq double %roundNanr, %roundNanr
  %roundNanbOrdered = fcmp oeq double %roundNanwant, %roundNanwant
  %roundNanaIsNan = xor i1 %roundNanaOrdered, true
  %roundNanbIsNan = xor i1 %roundNanbOrdered, true
  %roundNanbothNan = and i1 %roundNanaIsNan, %roundNanbIsNan
  %roundNanone = bitcast double 1.0 to double
  %roundNanra = fdiv double %roundNanone, %roundNanr
  %roundNanrb = fdiv double %roundNanone, %roundNanwant
  %roundNansameSign = fcmp oeq double %roundNanra, %roundNanrb
  %roundNaneqAndSign = and i1 %roundNaneq, %roundNansameSign
  %roundNan = or i1 %roundNanbothNan, %roundNaneqAndSign
  %next51.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count51, i64 %one)
  %next51 = extractvalue {i64, i1} %next51.p.pair, 0
  %next51.p.bad = extractvalue {i64, i1} %next51.p.pair, 1
  br i1 %next51.p.bad, label %next51.p.trap, label %next51.p.ok
next51.p.trap:
  call void @llvm.trap()
  unreachable
next51.p.ok:
  br i1 %roundNan, label %bb.check52, label %bb.fail51
bb.fail51:
  %code51 = bitcast i64 52 to i64
  ret i64 %code51
bb.check52:
  %count52 = phi i64 [ %next51, %next51.p.ok ]
  %roundInfa = bitcast double 0x7FF0000000000000 to double
  %roundInfr = call double @llvm.round.f64(double %roundInfa)
  %roundInfwant = bitcast double 0x7FF0000000000000 to double
  %roundInfeq = fcmp oeq double %roundInfr, %roundInfwant
  %roundInfaOrdered = fcmp oeq double %roundInfr, %roundInfr
  %roundInfbOrdered = fcmp oeq double %roundInfwant, %roundInfwant
  %roundInfaIsNan = xor i1 %roundInfaOrdered, true
  %roundInfbIsNan = xor i1 %roundInfbOrdered, true
  %roundInfbothNan = and i1 %roundInfaIsNan, %roundInfbIsNan
  %roundInfone = bitcast double 1.0 to double
  %roundInfra = fdiv double %roundInfone, %roundInfr
  %roundInfrb = fdiv double %roundInfone, %roundInfwant
  %roundInfsameSign = fcmp oeq double %roundInfra, %roundInfrb
  %roundInfeqAndSign = and i1 %roundInfeq, %roundInfsameSign
  %roundInf = or i1 %roundInfbothNan, %roundInfeqAndSign
  %next52.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count52, i64 %one)
  %next52 = extractvalue {i64, i1} %next52.p.pair, 0
  %next52.p.bad = extractvalue {i64, i1} %next52.p.pair, 1
  br i1 %next52.p.bad, label %next52.p.trap, label %next52.p.ok
next52.p.trap:
  call void @llvm.trap()
  unreachable
next52.p.ok:
  br i1 %roundInf, label %bb.check53, label %bb.fail52
bb.fail52:
  %code52 = bitcast i64 53 to i64
  ret i64 %code52
bb.check53:
  %count53 = phi i64 [ %next52, %next52.p.ok ]
  %sqrtPosa = bitcast double 2.0 to double
  %sqrtPosr = call double @llvm.sqrt.f64(double %sqrtPosa)
  %sqrtPoswant = bitcast double 1.4142135623730951 to double
  %sqrtPoseq = fcmp oeq double %sqrtPosr, %sqrtPoswant
  %sqrtPosaOrdered = fcmp oeq double %sqrtPosr, %sqrtPosr
  %sqrtPosbOrdered = fcmp oeq double %sqrtPoswant, %sqrtPoswant
  %sqrtPosaIsNan = xor i1 %sqrtPosaOrdered, true
  %sqrtPosbIsNan = xor i1 %sqrtPosbOrdered, true
  %sqrtPosbothNan = and i1 %sqrtPosaIsNan, %sqrtPosbIsNan
  %sqrtPosone = bitcast double 1.0 to double
  %sqrtPosra = fdiv double %sqrtPosone, %sqrtPosr
  %sqrtPosrb = fdiv double %sqrtPosone, %sqrtPoswant
  %sqrtPossameSign = fcmp oeq double %sqrtPosra, %sqrtPosrb
  %sqrtPoseqAndSign = and i1 %sqrtPoseq, %sqrtPossameSign
  %sqrtPos = or i1 %sqrtPosbothNan, %sqrtPoseqAndSign
  %next53.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count53, i64 %one)
  %next53 = extractvalue {i64, i1} %next53.p.pair, 0
  %next53.p.bad = extractvalue {i64, i1} %next53.p.pair, 1
  br i1 %next53.p.bad, label %next53.p.trap, label %next53.p.ok
next53.p.trap:
  call void @llvm.trap()
  unreachable
next53.p.ok:
  br i1 %sqrtPos, label %bb.check54, label %bb.fail53
bb.fail53:
  %code53 = bitcast i64 54 to i64
  ret i64 %code53
bb.check54:
  %count54 = phi i64 [ %next53, %next53.p.ok ]
  %sqrtZeroa = bitcast double 0.0 to double
  %sqrtZeror = call double @llvm.sqrt.f64(double %sqrtZeroa)
  %sqrtZerowant = bitcast double 0.0 to double
  %sqrtZeroeq = fcmp oeq double %sqrtZeror, %sqrtZerowant
  %sqrtZeroaOrdered = fcmp oeq double %sqrtZeror, %sqrtZeror
  %sqrtZerobOrdered = fcmp oeq double %sqrtZerowant, %sqrtZerowant
  %sqrtZeroaIsNan = xor i1 %sqrtZeroaOrdered, true
  %sqrtZerobIsNan = xor i1 %sqrtZerobOrdered, true
  %sqrtZerobothNan = and i1 %sqrtZeroaIsNan, %sqrtZerobIsNan
  %sqrtZeroone = bitcast double 1.0 to double
  %sqrtZerora = fdiv double %sqrtZeroone, %sqrtZeror
  %sqrtZerorb = fdiv double %sqrtZeroone, %sqrtZerowant
  %sqrtZerosameSign = fcmp oeq double %sqrtZerora, %sqrtZerorb
  %sqrtZeroeqAndSign = and i1 %sqrtZeroeq, %sqrtZerosameSign
  %sqrtZero = or i1 %sqrtZerobothNan, %sqrtZeroeqAndSign
  %next54.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count54, i64 %one)
  %next54 = extractvalue {i64, i1} %next54.p.pair, 0
  %next54.p.bad = extractvalue {i64, i1} %next54.p.pair, 1
  br i1 %next54.p.bad, label %next54.p.trap, label %next54.p.ok
next54.p.trap:
  call void @llvm.trap()
  unreachable
next54.p.ok:
  br i1 %sqrtZero, label %bb.check55, label %bb.fail54
bb.fail54:
  %code54 = bitcast i64 55 to i64
  ret i64 %code54
bb.check55:
  %count55 = phi i64 [ %next54, %next54.p.ok ]
  %sqrtNegZeroa = bitcast double -0.0 to double
  %sqrtNegZeror = call double @llvm.sqrt.f64(double %sqrtNegZeroa)
  %sqrtNegZerowant = bitcast double -0.0 to double
  %sqrtNegZeroeq = fcmp oeq double %sqrtNegZeror, %sqrtNegZerowant
  %sqrtNegZeroaOrdered = fcmp oeq double %sqrtNegZeror, %sqrtNegZeror
  %sqrtNegZerobOrdered = fcmp oeq double %sqrtNegZerowant, %sqrtNegZerowant
  %sqrtNegZeroaIsNan = xor i1 %sqrtNegZeroaOrdered, true
  %sqrtNegZerobIsNan = xor i1 %sqrtNegZerobOrdered, true
  %sqrtNegZerobothNan = and i1 %sqrtNegZeroaIsNan, %sqrtNegZerobIsNan
  %sqrtNegZeroone = bitcast double 1.0 to double
  %sqrtNegZerora = fdiv double %sqrtNegZeroone, %sqrtNegZeror
  %sqrtNegZerorb = fdiv double %sqrtNegZeroone, %sqrtNegZerowant
  %sqrtNegZerosameSign = fcmp oeq double %sqrtNegZerora, %sqrtNegZerorb
  %sqrtNegZeroeqAndSign = and i1 %sqrtNegZeroeq, %sqrtNegZerosameSign
  %sqrtNegZero = or i1 %sqrtNegZerobothNan, %sqrtNegZeroeqAndSign
  %next55.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count55, i64 %one)
  %next55 = extractvalue {i64, i1} %next55.p.pair, 0
  %next55.p.bad = extractvalue {i64, i1} %next55.p.pair, 1
  br i1 %next55.p.bad, label %next55.p.trap, label %next55.p.ok
next55.p.trap:
  call void @llvm.trap()
  unreachable
next55.p.ok:
  br i1 %sqrtNegZero, label %bb.check56, label %bb.fail55
bb.fail55:
  %code55 = bitcast i64 56 to i64
  ret i64 %code55
bb.check56:
  %count56 = phi i64 [ %next55, %next55.p.ok ]
  %sqrtNega = bitcast double -1.0 to double
  %sqrtNegr = call double @llvm.sqrt.f64(double %sqrtNega)
  %sqrtNegwant = bitcast double 0x7FF8000000000000 to double
  %sqrtNegeq = fcmp oeq double %sqrtNegr, %sqrtNegwant
  %sqrtNegaOrdered = fcmp oeq double %sqrtNegr, %sqrtNegr
  %sqrtNegbOrdered = fcmp oeq double %sqrtNegwant, %sqrtNegwant
  %sqrtNegaIsNan = xor i1 %sqrtNegaOrdered, true
  %sqrtNegbIsNan = xor i1 %sqrtNegbOrdered, true
  %sqrtNegbothNan = and i1 %sqrtNegaIsNan, %sqrtNegbIsNan
  %sqrtNegone = bitcast double 1.0 to double
  %sqrtNegra = fdiv double %sqrtNegone, %sqrtNegr
  %sqrtNegrb = fdiv double %sqrtNegone, %sqrtNegwant
  %sqrtNegsameSign = fcmp oeq double %sqrtNegra, %sqrtNegrb
  %sqrtNegeqAndSign = and i1 %sqrtNegeq, %sqrtNegsameSign
  %sqrtNeg = or i1 %sqrtNegbothNan, %sqrtNegeqAndSign
  %next56.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count56, i64 %one)
  %next56 = extractvalue {i64, i1} %next56.p.pair, 0
  %next56.p.bad = extractvalue {i64, i1} %next56.p.pair, 1
  br i1 %next56.p.bad, label %next56.p.trap, label %next56.p.ok
next56.p.trap:
  call void @llvm.trap()
  unreachable
next56.p.ok:
  br i1 %sqrtNeg, label %bb.check57, label %bb.fail56
bb.fail56:
  %code56 = bitcast i64 57 to i64
  ret i64 %code56
bb.check57:
  %count57 = phi i64 [ %next56, %next56.p.ok ]
  %sqrtInfa = bitcast double 0x7FF0000000000000 to double
  %sqrtInfr = call double @llvm.sqrt.f64(double %sqrtInfa)
  %sqrtInfwant = bitcast double 0x7FF0000000000000 to double
  %sqrtInfeq = fcmp oeq double %sqrtInfr, %sqrtInfwant
  %sqrtInfaOrdered = fcmp oeq double %sqrtInfr, %sqrtInfr
  %sqrtInfbOrdered = fcmp oeq double %sqrtInfwant, %sqrtInfwant
  %sqrtInfaIsNan = xor i1 %sqrtInfaOrdered, true
  %sqrtInfbIsNan = xor i1 %sqrtInfbOrdered, true
  %sqrtInfbothNan = and i1 %sqrtInfaIsNan, %sqrtInfbIsNan
  %sqrtInfone = bitcast double 1.0 to double
  %sqrtInfra = fdiv double %sqrtInfone, %sqrtInfr
  %sqrtInfrb = fdiv double %sqrtInfone, %sqrtInfwant
  %sqrtInfsameSign = fcmp oeq double %sqrtInfra, %sqrtInfrb
  %sqrtInfeqAndSign = and i1 %sqrtInfeq, %sqrtInfsameSign
  %sqrtInf = or i1 %sqrtInfbothNan, %sqrtInfeqAndSign
  %next57.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count57, i64 %one)
  %next57 = extractvalue {i64, i1} %next57.p.pair, 0
  %next57.p.bad = extractvalue {i64, i1} %next57.p.pair, 1
  br i1 %next57.p.bad, label %next57.p.trap, label %next57.p.ok
next57.p.trap:
  call void @llvm.trap()
  unreachable
next57.p.ok:
  br i1 %sqrtInf, label %bb.check58, label %bb.fail57
bb.fail57:
  %code57 = bitcast i64 58 to i64
  ret i64 %code57
bb.check58:
  %count58 = phi i64 [ %next57, %next57.p.ok ]
  %powBasica = bitcast double 2.0 to double
  %powBasicb = bitcast double 10.0 to double
  %powBasicr = call double @pow(double %powBasica, double %powBasicb)
  %powBasicwant = bitcast double 1024.0 to double
  %powBasiceq = fcmp oeq double %powBasicr, %powBasicwant
  %powBasicaOrdered = fcmp oeq double %powBasicr, %powBasicr
  %powBasicbOrdered = fcmp oeq double %powBasicwant, %powBasicwant
  %powBasicaIsNan = xor i1 %powBasicaOrdered, true
  %powBasicbIsNan = xor i1 %powBasicbOrdered, true
  %powBasicbothNan = and i1 %powBasicaIsNan, %powBasicbIsNan
  %powBasicone = bitcast double 1.0 to double
  %powBasicra = fdiv double %powBasicone, %powBasicr
  %powBasicrb = fdiv double %powBasicone, %powBasicwant
  %powBasicsameSign = fcmp oeq double %powBasicra, %powBasicrb
  %powBasiceqAndSign = and i1 %powBasiceq, %powBasicsameSign
  %powBasic = or i1 %powBasicbothNan, %powBasiceqAndSign
  %next58.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count58, i64 %one)
  %next58 = extractvalue {i64, i1} %next58.p.pair, 0
  %next58.p.bad = extractvalue {i64, i1} %next58.p.pair, 1
  br i1 %next58.p.bad, label %next58.p.trap, label %next58.p.ok
next58.p.trap:
  call void @llvm.trap()
  unreachable
next58.p.ok:
  br i1 %powBasic, label %bb.check59, label %bb.fail58
bb.fail58:
  %code58 = bitcast i64 59 to i64
  ret i64 %code58
bb.check59:
  %count59 = phi i64 [ %next58, %next58.p.ok ]
  %powLargea = bitcast double 2.0 to double
  %powLargeb = bitcast double 62.0 to double
  %powLarger = call double @pow(double %powLargea, double %powLargeb)
  %powLargewant = bitcast double 4.611686018427388e+18 to double
  %powLargeeq = fcmp oeq double %powLarger, %powLargewant
  %powLargeaOrdered = fcmp oeq double %powLarger, %powLarger
  %powLargebOrdered = fcmp oeq double %powLargewant, %powLargewant
  %powLargeaIsNan = xor i1 %powLargeaOrdered, true
  %powLargebIsNan = xor i1 %powLargebOrdered, true
  %powLargebothNan = and i1 %powLargeaIsNan, %powLargebIsNan
  %powLargeone = bitcast double 1.0 to double
  %powLargera = fdiv double %powLargeone, %powLarger
  %powLargerb = fdiv double %powLargeone, %powLargewant
  %powLargesameSign = fcmp oeq double %powLargera, %powLargerb
  %powLargeeqAndSign = and i1 %powLargeeq, %powLargesameSign
  %powLarge = or i1 %powLargebothNan, %powLargeeqAndSign
  %next59.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count59, i64 %one)
  %next59 = extractvalue {i64, i1} %next59.p.pair, 0
  %next59.p.bad = extractvalue {i64, i1} %next59.p.pair, 1
  br i1 %next59.p.bad, label %next59.p.trap, label %next59.p.ok
next59.p.trap:
  call void @llvm.trap()
  unreachable
next59.p.ok:
  br i1 %powLarge, label %bb.check60, label %bb.fail59
bb.fail59:
  %code59 = bitcast i64 60 to i64
  ret i64 %code59
bb.check60:
  %count60 = phi i64 [ %next59, %next59.p.ok ]
  %powZeroNega = bitcast double 0.0 to double
  %powZeroNegb = bitcast double -1.0 to double
  %powZeroNegr = call double @pow(double %powZeroNega, double %powZeroNegb)
  %powZeroNegwant = bitcast double 0x7FF0000000000000 to double
  %powZeroNegeq = fcmp oeq double %powZeroNegr, %powZeroNegwant
  %powZeroNegaOrdered = fcmp oeq double %powZeroNegr, %powZeroNegr
  %powZeroNegbOrdered = fcmp oeq double %powZeroNegwant, %powZeroNegwant
  %powZeroNegaIsNan = xor i1 %powZeroNegaOrdered, true
  %powZeroNegbIsNan = xor i1 %powZeroNegbOrdered, true
  %powZeroNegbothNan = and i1 %powZeroNegaIsNan, %powZeroNegbIsNan
  %powZeroNegone = bitcast double 1.0 to double
  %powZeroNegra = fdiv double %powZeroNegone, %powZeroNegr
  %powZeroNegrb = fdiv double %powZeroNegone, %powZeroNegwant
  %powZeroNegsameSign = fcmp oeq double %powZeroNegra, %powZeroNegrb
  %powZeroNegeqAndSign = and i1 %powZeroNegeq, %powZeroNegsameSign
  %powZeroNeg = or i1 %powZeroNegbothNan, %powZeroNegeqAndSign
  %next60.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count60, i64 %one)
  %next60 = extractvalue {i64, i1} %next60.p.pair, 0
  %next60.p.bad = extractvalue {i64, i1} %next60.p.pair, 1
  br i1 %next60.p.bad, label %next60.p.trap, label %next60.p.ok
next60.p.trap:
  call void @llvm.trap()
  unreachable
next60.p.ok:
  br i1 %powZeroNeg, label %bb.check61, label %bb.fail60
bb.fail60:
  %code60 = bitcast i64 61 to i64
  ret i64 %code60
bb.check61:
  %count61 = phi i64 [ %next60, %next60.p.ok ]
  %powNegFraca = bitcast double -1.0 to double
  %powNegFracb = bitcast double 0.5 to double
  %powNegFracr = call double @pow(double %powNegFraca, double %powNegFracb)
  %powNegFracwant = bitcast double 0x7FF8000000000000 to double
  %powNegFraceq = fcmp oeq double %powNegFracr, %powNegFracwant
  %powNegFracaOrdered = fcmp oeq double %powNegFracr, %powNegFracr
  %powNegFracbOrdered = fcmp oeq double %powNegFracwant, %powNegFracwant
  %powNegFracaIsNan = xor i1 %powNegFracaOrdered, true
  %powNegFracbIsNan = xor i1 %powNegFracbOrdered, true
  %powNegFracbothNan = and i1 %powNegFracaIsNan, %powNegFracbIsNan
  %powNegFracone = bitcast double 1.0 to double
  %powNegFracra = fdiv double %powNegFracone, %powNegFracr
  %powNegFracrb = fdiv double %powNegFracone, %powNegFracwant
  %powNegFracsameSign = fcmp oeq double %powNegFracra, %powNegFracrb
  %powNegFraceqAndSign = and i1 %powNegFraceq, %powNegFracsameSign
  %powNegFrac = or i1 %powNegFracbothNan, %powNegFraceqAndSign
  %next61.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count61, i64 %one)
  %next61 = extractvalue {i64, i1} %next61.p.pair, 0
  %next61.p.bad = extractvalue {i64, i1} %next61.p.pair, 1
  br i1 %next61.p.bad, label %next61.p.trap, label %next61.p.ok
next61.p.trap:
  call void @llvm.trap()
  unreachable
next61.p.ok:
  br i1 %powNegFrac, label %bb.check62, label %bb.fail61
bb.fail61:
  %code61 = bitcast i64 62 to i64
  ret i64 %code61
bb.check62:
  %count62 = phi i64 [ %next61, %next61.p.ok ]
  %powNana = bitcast double 0x7FF8000000000000 to double
  %powNanb = bitcast double 2.0 to double
  %powNanr = call double @pow(double %powNana, double %powNanb)
  %powNanwant = bitcast double 0x7FF8000000000000 to double
  %powNaneq = fcmp oeq double %powNanr, %powNanwant
  %powNanaOrdered = fcmp oeq double %powNanr, %powNanr
  %powNanbOrdered = fcmp oeq double %powNanwant, %powNanwant
  %powNanaIsNan = xor i1 %powNanaOrdered, true
  %powNanbIsNan = xor i1 %powNanbOrdered, true
  %powNanbothNan = and i1 %powNanaIsNan, %powNanbIsNan
  %powNanone = bitcast double 1.0 to double
  %powNanra = fdiv double %powNanone, %powNanr
  %powNanrb = fdiv double %powNanone, %powNanwant
  %powNansameSign = fcmp oeq double %powNanra, %powNanrb
  %powNaneqAndSign = and i1 %powNaneq, %powNansameSign
  %powNan = or i1 %powNanbothNan, %powNaneqAndSign
  %next62.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count62, i64 %one)
  %next62 = extractvalue {i64, i1} %next62.p.pair, 0
  %next62.p.bad = extractvalue {i64, i1} %next62.p.pair, 1
  br i1 %next62.p.bad, label %next62.p.trap, label %next62.p.ok
next62.p.trap:
  call void @llvm.trap()
  unreachable
next62.p.ok:
  br i1 %powNan, label %bb.check63, label %bb.fail62
bb.fail62:
  %code62 = bitcast i64 63 to i64
  ret i64 %code62
bb.check63:
  %count63 = phi i64 [ %next62, %next62.p.ok ]
  %expOnea = bitcast double 1.0 to double
  %expOner = call double @exp(double %expOnea)
  %expOnewant = bitcast double 2.718281828459045 to double
  %expOneeq = fcmp oeq double %expOner, %expOnewant
  %expOneaOrdered = fcmp oeq double %expOner, %expOner
  %expOnebOrdered = fcmp oeq double %expOnewant, %expOnewant
  %expOneaIsNan = xor i1 %expOneaOrdered, true
  %expOnebIsNan = xor i1 %expOnebOrdered, true
  %expOnebothNan = and i1 %expOneaIsNan, %expOnebIsNan
  %expOneone = bitcast double 1.0 to double
  %expOnera = fdiv double %expOneone, %expOner
  %expOnerb = fdiv double %expOneone, %expOnewant
  %expOnesameSign = fcmp oeq double %expOnera, %expOnerb
  %expOneeqAndSign = and i1 %expOneeq, %expOnesameSign
  %expOne = or i1 %expOnebothNan, %expOneeqAndSign
  %next63.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count63, i64 %one)
  %next63 = extractvalue {i64, i1} %next63.p.pair, 0
  %next63.p.bad = extractvalue {i64, i1} %next63.p.pair, 1
  br i1 %next63.p.bad, label %next63.p.trap, label %next63.p.ok
next63.p.trap:
  call void @llvm.trap()
  unreachable
next63.p.ok:
  br i1 %expOne, label %bb.check64, label %bb.fail63
bb.fail63:
  %code63 = bitcast i64 64 to i64
  ret i64 %code63
bb.check64:
  %count64 = phi i64 [ %next63, %next63.p.ok ]
  %expLargea = bitcast double 700.0 to double
  %expLarger = call double @exp(double %expLargea)
  %expLargewant = bitcast double 1.0142320547350045e+304 to double
  %expLargeeq = fcmp oeq double %expLarger, %expLargewant
  %expLargeaOrdered = fcmp oeq double %expLarger, %expLarger
  %expLargebOrdered = fcmp oeq double %expLargewant, %expLargewant
  %expLargeaIsNan = xor i1 %expLargeaOrdered, true
  %expLargebIsNan = xor i1 %expLargebOrdered, true
  %expLargebothNan = and i1 %expLargeaIsNan, %expLargebIsNan
  %expLargeone = bitcast double 1.0 to double
  %expLargera = fdiv double %expLargeone, %expLarger
  %expLargerb = fdiv double %expLargeone, %expLargewant
  %expLargesameSign = fcmp oeq double %expLargera, %expLargerb
  %expLargeeqAndSign = and i1 %expLargeeq, %expLargesameSign
  %expLarge = or i1 %expLargebothNan, %expLargeeqAndSign
  %next64.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count64, i64 %one)
  %next64 = extractvalue {i64, i1} %next64.p.pair, 0
  %next64.p.bad = extractvalue {i64, i1} %next64.p.pair, 1
  br i1 %next64.p.bad, label %next64.p.trap, label %next64.p.ok
next64.p.trap:
  call void @llvm.trap()
  unreachable
next64.p.ok:
  br i1 %expLarge, label %bb.check65, label %bb.fail64
bb.fail64:
  %code64 = bitcast i64 65 to i64
  ret i64 %code64
bb.check65:
  %count65 = phi i64 [ %next64, %next64.p.ok ]
  %expOverflowa = bitcast double 710.0 to double
  %expOverflowr = call double @exp(double %expOverflowa)
  %expOverflowwant = bitcast double 0x7FF0000000000000 to double
  %expOverfloweq = fcmp oeq double %expOverflowr, %expOverflowwant
  %expOverflowaOrdered = fcmp oeq double %expOverflowr, %expOverflowr
  %expOverflowbOrdered = fcmp oeq double %expOverflowwant, %expOverflowwant
  %expOverflowaIsNan = xor i1 %expOverflowaOrdered, true
  %expOverflowbIsNan = xor i1 %expOverflowbOrdered, true
  %expOverflowbothNan = and i1 %expOverflowaIsNan, %expOverflowbIsNan
  %expOverflowone = bitcast double 1.0 to double
  %expOverflowra = fdiv double %expOverflowone, %expOverflowr
  %expOverflowrb = fdiv double %expOverflowone, %expOverflowwant
  %expOverflowsameSign = fcmp oeq double %expOverflowra, %expOverflowrb
  %expOverfloweqAndSign = and i1 %expOverfloweq, %expOverflowsameSign
  %expOverflow = or i1 %expOverflowbothNan, %expOverfloweqAndSign
  %next65.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count65, i64 %one)
  %next65 = extractvalue {i64, i1} %next65.p.pair, 0
  %next65.p.bad = extractvalue {i64, i1} %next65.p.pair, 1
  br i1 %next65.p.bad, label %next65.p.trap, label %next65.p.ok
next65.p.trap:
  call void @llvm.trap()
  unreachable
next65.p.ok:
  br i1 %expOverflow, label %bb.check66, label %bb.fail65
bb.fail65:
  %code65 = bitcast i64 66 to i64
  ret i64 %code65
bb.check66:
  %count66 = phi i64 [ %next65, %next65.p.ok ]
  %expNana = bitcast double 0x7FF8000000000000 to double
  %expNanr = call double @exp(double %expNana)
  %expNanwant = bitcast double 0x7FF8000000000000 to double
  %expNaneq = fcmp oeq double %expNanr, %expNanwant
  %expNanaOrdered = fcmp oeq double %expNanr, %expNanr
  %expNanbOrdered = fcmp oeq double %expNanwant, %expNanwant
  %expNanaIsNan = xor i1 %expNanaOrdered, true
  %expNanbIsNan = xor i1 %expNanbOrdered, true
  %expNanbothNan = and i1 %expNanaIsNan, %expNanbIsNan
  %expNanone = bitcast double 1.0 to double
  %expNanra = fdiv double %expNanone, %expNanr
  %expNanrb = fdiv double %expNanone, %expNanwant
  %expNansameSign = fcmp oeq double %expNanra, %expNanrb
  %expNaneqAndSign = and i1 %expNaneq, %expNansameSign
  %expNan = or i1 %expNanbothNan, %expNaneqAndSign
  %next66.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count66, i64 %one)
  %next66 = extractvalue {i64, i1} %next66.p.pair, 0
  %next66.p.bad = extractvalue {i64, i1} %next66.p.pair, 1
  br i1 %next66.p.bad, label %next66.p.trap, label %next66.p.ok
next66.p.trap:
  call void @llvm.trap()
  unreachable
next66.p.ok:
  br i1 %expNan, label %bb.check67, label %bb.fail66
bb.fail66:
  %code66 = bitcast i64 67 to i64
  ret i64 %code66
bb.check67:
  %count67 = phi i64 [ %next66, %next66.p.ok ]
  %logNormala = bitcast double 2.718281828459045 to double
  %logNormalr = call double @log(double %logNormala)
  %logNormalwant = bitcast double 1.0 to double
  %logNormaleq = fcmp oeq double %logNormalr, %logNormalwant
  %logNormalaOrdered = fcmp oeq double %logNormalr, %logNormalr
  %logNormalbOrdered = fcmp oeq double %logNormalwant, %logNormalwant
  %logNormalaIsNan = xor i1 %logNormalaOrdered, true
  %logNormalbIsNan = xor i1 %logNormalbOrdered, true
  %logNormalbothNan = and i1 %logNormalaIsNan, %logNormalbIsNan
  %logNormalone = bitcast double 1.0 to double
  %logNormalra = fdiv double %logNormalone, %logNormalr
  %logNormalrb = fdiv double %logNormalone, %logNormalwant
  %logNormalsameSign = fcmp oeq double %logNormalra, %logNormalrb
  %logNormaleqAndSign = and i1 %logNormaleq, %logNormalsameSign
  %logNormal = or i1 %logNormalbothNan, %logNormaleqAndSign
  %next67.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count67, i64 %one)
  %next67 = extractvalue {i64, i1} %next67.p.pair, 0
  %next67.p.bad = extractvalue {i64, i1} %next67.p.pair, 1
  br i1 %next67.p.bad, label %next67.p.trap, label %next67.p.ok
next67.p.trap:
  call void @llvm.trap()
  unreachable
next67.p.ok:
  br i1 %logNormal, label %bb.check68, label %bb.fail67
bb.fail67:
  %code67 = bitcast i64 68 to i64
  ret i64 %code67
bb.check68:
  %count68 = phi i64 [ %next67, %next67.p.ok ]
  %logZeroa = bitcast double 0.0 to double
  %logZeror = call double @log(double %logZeroa)
  %logZerowant = bitcast double 0xFFF0000000000000 to double
  %logZeroeq = fcmp oeq double %logZeror, %logZerowant
  %logZeroaOrdered = fcmp oeq double %logZeror, %logZeror
  %logZerobOrdered = fcmp oeq double %logZerowant, %logZerowant
  %logZeroaIsNan = xor i1 %logZeroaOrdered, true
  %logZerobIsNan = xor i1 %logZerobOrdered, true
  %logZerobothNan = and i1 %logZeroaIsNan, %logZerobIsNan
  %logZeroone = bitcast double 1.0 to double
  %logZerora = fdiv double %logZeroone, %logZeror
  %logZerorb = fdiv double %logZeroone, %logZerowant
  %logZerosameSign = fcmp oeq double %logZerora, %logZerorb
  %logZeroeqAndSign = and i1 %logZeroeq, %logZerosameSign
  %logZero = or i1 %logZerobothNan, %logZeroeqAndSign
  %next68.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count68, i64 %one)
  %next68 = extractvalue {i64, i1} %next68.p.pair, 0
  %next68.p.bad = extractvalue {i64, i1} %next68.p.pair, 1
  br i1 %next68.p.bad, label %next68.p.trap, label %next68.p.ok
next68.p.trap:
  call void @llvm.trap()
  unreachable
next68.p.ok:
  br i1 %logZero, label %bb.check69, label %bb.fail68
bb.fail68:
  %code68 = bitcast i64 69 to i64
  ret i64 %code68
bb.check69:
  %count69 = phi i64 [ %next68, %next68.p.ok ]
  %logNega = bitcast double -1.0 to double
  %logNegr = call double @log(double %logNega)
  %logNegwant = bitcast double 0x7FF8000000000000 to double
  %logNegeq = fcmp oeq double %logNegr, %logNegwant
  %logNegaOrdered = fcmp oeq double %logNegr, %logNegr
  %logNegbOrdered = fcmp oeq double %logNegwant, %logNegwant
  %logNegaIsNan = xor i1 %logNegaOrdered, true
  %logNegbIsNan = xor i1 %logNegbOrdered, true
  %logNegbothNan = and i1 %logNegaIsNan, %logNegbIsNan
  %logNegone = bitcast double 1.0 to double
  %logNegra = fdiv double %logNegone, %logNegr
  %logNegrb = fdiv double %logNegone, %logNegwant
  %logNegsameSign = fcmp oeq double %logNegra, %logNegrb
  %logNegeqAndSign = and i1 %logNegeq, %logNegsameSign
  %logNeg = or i1 %logNegbothNan, %logNegeqAndSign
  %next69.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count69, i64 %one)
  %next69 = extractvalue {i64, i1} %next69.p.pair, 0
  %next69.p.bad = extractvalue {i64, i1} %next69.p.pair, 1
  br i1 %next69.p.bad, label %next69.p.trap, label %next69.p.ok
next69.p.trap:
  call void @llvm.trap()
  unreachable
next69.p.ok:
  br i1 %logNeg, label %bb.check70, label %bb.fail69
bb.fail69:
  %code69 = bitcast i64 70 to i64
  ret i64 %code69
bb.check70:
  %count70 = phi i64 [ %next69, %next69.p.ok ]
  %logInfa = bitcast double 0x7FF0000000000000 to double
  %logInfr = call double @log(double %logInfa)
  %logInfwant = bitcast double 0x7FF0000000000000 to double
  %logInfeq = fcmp oeq double %logInfr, %logInfwant
  %logInfaOrdered = fcmp oeq double %logInfr, %logInfr
  %logInfbOrdered = fcmp oeq double %logInfwant, %logInfwant
  %logInfaIsNan = xor i1 %logInfaOrdered, true
  %logInfbIsNan = xor i1 %logInfbOrdered, true
  %logInfbothNan = and i1 %logInfaIsNan, %logInfbIsNan
  %logInfone = bitcast double 1.0 to double
  %logInfra = fdiv double %logInfone, %logInfr
  %logInfrb = fdiv double %logInfone, %logInfwant
  %logInfsameSign = fcmp oeq double %logInfra, %logInfrb
  %logInfeqAndSign = and i1 %logInfeq, %logInfsameSign
  %logInf = or i1 %logInfbothNan, %logInfeqAndSign
  %next70.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count70, i64 %one)
  %next70 = extractvalue {i64, i1} %next70.p.pair, 0
  %next70.p.bad = extractvalue {i64, i1} %next70.p.pair, 1
  br i1 %next70.p.bad, label %next70.p.trap, label %next70.p.ok
next70.p.trap:
  call void @llvm.trap()
  unreachable
next70.p.ok:
  br i1 %logInf, label %bb.check71, label %bb.fail70
bb.fail70:
  %code70 = bitcast i64 71 to i64
  ret i64 %code70
bb.check71:
  %count71 = phi i64 [ %next70, %next70.p.ok ]
  %log2Basica = bitcast double 8.0 to double
  %log2Basicr = call double @log2(double %log2Basica)
  %log2Basicwant = bitcast double 3.0 to double
  %log2Basiceq = fcmp oeq double %log2Basicr, %log2Basicwant
  %log2BasicaOrdered = fcmp oeq double %log2Basicr, %log2Basicr
  %log2BasicbOrdered = fcmp oeq double %log2Basicwant, %log2Basicwant
  %log2BasicaIsNan = xor i1 %log2BasicaOrdered, true
  %log2BasicbIsNan = xor i1 %log2BasicbOrdered, true
  %log2BasicbothNan = and i1 %log2BasicaIsNan, %log2BasicbIsNan
  %log2Basicone = bitcast double 1.0 to double
  %log2Basicra = fdiv double %log2Basicone, %log2Basicr
  %log2Basicrb = fdiv double %log2Basicone, %log2Basicwant
  %log2BasicsameSign = fcmp oeq double %log2Basicra, %log2Basicrb
  %log2BasiceqAndSign = and i1 %log2Basiceq, %log2BasicsameSign
  %log2Basic = or i1 %log2BasicbothNan, %log2BasiceqAndSign
  %next71.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count71, i64 %one)
  %next71 = extractvalue {i64, i1} %next71.p.pair, 0
  %next71.p.bad = extractvalue {i64, i1} %next71.p.pair, 1
  br i1 %next71.p.bad, label %next71.p.trap, label %next71.p.ok
next71.p.trap:
  call void @llvm.trap()
  unreachable
next71.p.ok:
  br i1 %log2Basic, label %bb.check72, label %bb.fail71
bb.fail71:
  %code71 = bitcast i64 72 to i64
  ret i64 %code71
bb.check72:
  %count72 = phi i64 [ %next71, %next71.p.ok ]
  %log2Zeroa = bitcast double 0.0 to double
  %log2Zeror = call double @log2(double %log2Zeroa)
  %log2Zerowant = bitcast double 0xFFF0000000000000 to double
  %log2Zeroeq = fcmp oeq double %log2Zeror, %log2Zerowant
  %log2ZeroaOrdered = fcmp oeq double %log2Zeror, %log2Zeror
  %log2ZerobOrdered = fcmp oeq double %log2Zerowant, %log2Zerowant
  %log2ZeroaIsNan = xor i1 %log2ZeroaOrdered, true
  %log2ZerobIsNan = xor i1 %log2ZerobOrdered, true
  %log2ZerobothNan = and i1 %log2ZeroaIsNan, %log2ZerobIsNan
  %log2Zeroone = bitcast double 1.0 to double
  %log2Zerora = fdiv double %log2Zeroone, %log2Zeror
  %log2Zerorb = fdiv double %log2Zeroone, %log2Zerowant
  %log2ZerosameSign = fcmp oeq double %log2Zerora, %log2Zerorb
  %log2ZeroeqAndSign = and i1 %log2Zeroeq, %log2ZerosameSign
  %log2Zero = or i1 %log2ZerobothNan, %log2ZeroeqAndSign
  %next72.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count72, i64 %one)
  %next72 = extractvalue {i64, i1} %next72.p.pair, 0
  %next72.p.bad = extractvalue {i64, i1} %next72.p.pair, 1
  br i1 %next72.p.bad, label %next72.p.trap, label %next72.p.ok
next72.p.trap:
  call void @llvm.trap()
  unreachable
next72.p.ok:
  br i1 %log2Zero, label %bb.check73, label %bb.fail72
bb.fail72:
  %code72 = bitcast i64 73 to i64
  ret i64 %code72
bb.check73:
  %count73 = phi i64 [ %next72, %next72.p.ok ]
  %log10Basica = bitcast double 1000.0 to double
  %log10Basicr = call double @log10(double %log10Basica)
  %log10Basicwant = bitcast double 3.0 to double
  %log10Basiceq = fcmp oeq double %log10Basicr, %log10Basicwant
  %log10BasicaOrdered = fcmp oeq double %log10Basicr, %log10Basicr
  %log10BasicbOrdered = fcmp oeq double %log10Basicwant, %log10Basicwant
  %log10BasicaIsNan = xor i1 %log10BasicaOrdered, true
  %log10BasicbIsNan = xor i1 %log10BasicbOrdered, true
  %log10BasicbothNan = and i1 %log10BasicaIsNan, %log10BasicbIsNan
  %log10Basicone = bitcast double 1.0 to double
  %log10Basicra = fdiv double %log10Basicone, %log10Basicr
  %log10Basicrb = fdiv double %log10Basicone, %log10Basicwant
  %log10BasicsameSign = fcmp oeq double %log10Basicra, %log10Basicrb
  %log10BasiceqAndSign = and i1 %log10Basiceq, %log10BasicsameSign
  %log10Basic = or i1 %log10BasicbothNan, %log10BasiceqAndSign
  %next73.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count73, i64 %one)
  %next73 = extractvalue {i64, i1} %next73.p.pair, 0
  %next73.p.bad = extractvalue {i64, i1} %next73.p.pair, 1
  br i1 %next73.p.bad, label %next73.p.trap, label %next73.p.ok
next73.p.trap:
  call void @llvm.trap()
  unreachable
next73.p.ok:
  br i1 %log10Basic, label %bb.check74, label %bb.fail73
bb.fail73:
  %code73 = bitcast i64 74 to i64
  ret i64 %code73
bb.check74:
  %count74 = phi i64 [ %next73, %next73.p.ok ]
  %log10Nega = bitcast double -5.0 to double
  %log10Negr = call double @log10(double %log10Nega)
  %log10Negwant = bitcast double 0x7FF8000000000000 to double
  %log10Negeq = fcmp oeq double %log10Negr, %log10Negwant
  %log10NegaOrdered = fcmp oeq double %log10Negr, %log10Negr
  %log10NegbOrdered = fcmp oeq double %log10Negwant, %log10Negwant
  %log10NegaIsNan = xor i1 %log10NegaOrdered, true
  %log10NegbIsNan = xor i1 %log10NegbOrdered, true
  %log10NegbothNan = and i1 %log10NegaIsNan, %log10NegbIsNan
  %log10Negone = bitcast double 1.0 to double
  %log10Negra = fdiv double %log10Negone, %log10Negr
  %log10Negrb = fdiv double %log10Negone, %log10Negwant
  %log10NegsameSign = fcmp oeq double %log10Negra, %log10Negrb
  %log10NegeqAndSign = and i1 %log10Negeq, %log10NegsameSign
  %log10Neg = or i1 %log10NegbothNan, %log10NegeqAndSign
  %next74.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count74, i64 %one)
  %next74 = extractvalue {i64, i1} %next74.p.pair, 0
  %next74.p.bad = extractvalue {i64, i1} %next74.p.pair, 1
  br i1 %next74.p.bad, label %next74.p.trap, label %next74.p.ok
next74.p.trap:
  call void @llvm.trap()
  unreachable
next74.p.ok:
  br i1 %log10Neg, label %bb.check75, label %bb.fail74
bb.fail74:
  %code74 = bitcast i64 75 to i64
  ret i64 %code74
bb.check75:
  %count75 = phi i64 [ %next74, %next74.p.ok ]
  %sinZeroa = bitcast double 0.0 to double
  %sinZeror = call double @sin(double %sinZeroa)
  %sinZerowant = bitcast double 0.0 to double
  %sinZeroeq = fcmp oeq double %sinZeror, %sinZerowant
  %sinZeroaOrdered = fcmp oeq double %sinZeror, %sinZeror
  %sinZerobOrdered = fcmp oeq double %sinZerowant, %sinZerowant
  %sinZeroaIsNan = xor i1 %sinZeroaOrdered, true
  %sinZerobIsNan = xor i1 %sinZerobOrdered, true
  %sinZerobothNan = and i1 %sinZeroaIsNan, %sinZerobIsNan
  %sinZeroone = bitcast double 1.0 to double
  %sinZerora = fdiv double %sinZeroone, %sinZeror
  %sinZerorb = fdiv double %sinZeroone, %sinZerowant
  %sinZerosameSign = fcmp oeq double %sinZerora, %sinZerorb
  %sinZeroeqAndSign = and i1 %sinZeroeq, %sinZerosameSign
  %sinZero = or i1 %sinZerobothNan, %sinZeroeqAndSign
  %next75.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count75, i64 %one)
  %next75 = extractvalue {i64, i1} %next75.p.pair, 0
  %next75.p.bad = extractvalue {i64, i1} %next75.p.pair, 1
  br i1 %next75.p.bad, label %next75.p.trap, label %next75.p.ok
next75.p.trap:
  call void @llvm.trap()
  unreachable
next75.p.ok:
  br i1 %sinZero, label %bb.check76, label %bb.fail75
bb.fail75:
  %code75 = bitcast i64 76 to i64
  ret i64 %code75
bb.check76:
  %count76 = phi i64 [ %next75, %next75.p.ok ]
  %sinInfa = bitcast double 0x7FF0000000000000 to double
  %sinInfr = call double @sin(double %sinInfa)
  %sinInfwant = bitcast double 0x7FF8000000000000 to double
  %sinInfeq = fcmp oeq double %sinInfr, %sinInfwant
  %sinInfaOrdered = fcmp oeq double %sinInfr, %sinInfr
  %sinInfbOrdered = fcmp oeq double %sinInfwant, %sinInfwant
  %sinInfaIsNan = xor i1 %sinInfaOrdered, true
  %sinInfbIsNan = xor i1 %sinInfbOrdered, true
  %sinInfbothNan = and i1 %sinInfaIsNan, %sinInfbIsNan
  %sinInfone = bitcast double 1.0 to double
  %sinInfra = fdiv double %sinInfone, %sinInfr
  %sinInfrb = fdiv double %sinInfone, %sinInfwant
  %sinInfsameSign = fcmp oeq double %sinInfra, %sinInfrb
  %sinInfeqAndSign = and i1 %sinInfeq, %sinInfsameSign
  %sinInf = or i1 %sinInfbothNan, %sinInfeqAndSign
  %next76.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count76, i64 %one)
  %next76 = extractvalue {i64, i1} %next76.p.pair, 0
  %next76.p.bad = extractvalue {i64, i1} %next76.p.pair, 1
  br i1 %next76.p.bad, label %next76.p.trap, label %next76.p.ok
next76.p.trap:
  call void @llvm.trap()
  unreachable
next76.p.ok:
  br i1 %sinInf, label %bb.check77, label %bb.fail76
bb.fail76:
  %code76 = bitcast i64 77 to i64
  ret i64 %code76
bb.check77:
  %count77 = phi i64 [ %next76, %next76.p.ok ]
  %cosZeroa = bitcast double 0.0 to double
  %cosZeror = call double @cos(double %cosZeroa)
  %cosZerowant = bitcast double 1.0 to double
  %cosZeroeq = fcmp oeq double %cosZeror, %cosZerowant
  %cosZeroaOrdered = fcmp oeq double %cosZeror, %cosZeror
  %cosZerobOrdered = fcmp oeq double %cosZerowant, %cosZerowant
  %cosZeroaIsNan = xor i1 %cosZeroaOrdered, true
  %cosZerobIsNan = xor i1 %cosZerobOrdered, true
  %cosZerobothNan = and i1 %cosZeroaIsNan, %cosZerobIsNan
  %cosZeroone = bitcast double 1.0 to double
  %cosZerora = fdiv double %cosZeroone, %cosZeror
  %cosZerorb = fdiv double %cosZeroone, %cosZerowant
  %cosZerosameSign = fcmp oeq double %cosZerora, %cosZerorb
  %cosZeroeqAndSign = and i1 %cosZeroeq, %cosZerosameSign
  %cosZero = or i1 %cosZerobothNan, %cosZeroeqAndSign
  %next77.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count77, i64 %one)
  %next77 = extractvalue {i64, i1} %next77.p.pair, 0
  %next77.p.bad = extractvalue {i64, i1} %next77.p.pair, 1
  br i1 %next77.p.bad, label %next77.p.trap, label %next77.p.ok
next77.p.trap:
  call void @llvm.trap()
  unreachable
next77.p.ok:
  br i1 %cosZero, label %bb.check78, label %bb.fail77
bb.fail77:
  %code77 = bitcast i64 78 to i64
  ret i64 %code77
bb.check78:
  %count78 = phi i64 [ %next77, %next77.p.ok ]
  %cosLargea = bitcast double 123456.789 to double
  %cosLarger = call double @cos(double %cosLargea)
  %cosLargewant = bitcast double 0.05167253271870138 to double
  %cosLargeeq = fcmp oeq double %cosLarger, %cosLargewant
  %cosLargeaOrdered = fcmp oeq double %cosLarger, %cosLarger
  %cosLargebOrdered = fcmp oeq double %cosLargewant, %cosLargewant
  %cosLargeaIsNan = xor i1 %cosLargeaOrdered, true
  %cosLargebIsNan = xor i1 %cosLargebOrdered, true
  %cosLargebothNan = and i1 %cosLargeaIsNan, %cosLargebIsNan
  %cosLargeone = bitcast double 1.0 to double
  %cosLargera = fdiv double %cosLargeone, %cosLarger
  %cosLargerb = fdiv double %cosLargeone, %cosLargewant
  %cosLargesameSign = fcmp oeq double %cosLargera, %cosLargerb
  %cosLargeeqAndSign = and i1 %cosLargeeq, %cosLargesameSign
  %cosLarge = or i1 %cosLargebothNan, %cosLargeeqAndSign
  %next78.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count78, i64 %one)
  %next78 = extractvalue {i64, i1} %next78.p.pair, 0
  %next78.p.bad = extractvalue {i64, i1} %next78.p.pair, 1
  br i1 %next78.p.bad, label %next78.p.trap, label %next78.p.ok
next78.p.trap:
  call void @llvm.trap()
  unreachable
next78.p.ok:
  br i1 %cosLarge, label %bb.check79, label %bb.fail78
bb.fail78:
  %code78 = bitcast i64 79 to i64
  ret i64 %code78
bb.check79:
  %count79 = phi i64 [ %next78, %next78.p.ok ]
  %tanZeroa = bitcast double 0.0 to double
  %tanZeror = call double @tan(double %tanZeroa)
  %tanZerowant = bitcast double 0.0 to double
  %tanZeroeq = fcmp oeq double %tanZeror, %tanZerowant
  %tanZeroaOrdered = fcmp oeq double %tanZeror, %tanZeror
  %tanZerobOrdered = fcmp oeq double %tanZerowant, %tanZerowant
  %tanZeroaIsNan = xor i1 %tanZeroaOrdered, true
  %tanZerobIsNan = xor i1 %tanZerobOrdered, true
  %tanZerobothNan = and i1 %tanZeroaIsNan, %tanZerobIsNan
  %tanZeroone = bitcast double 1.0 to double
  %tanZerora = fdiv double %tanZeroone, %tanZeror
  %tanZerorb = fdiv double %tanZeroone, %tanZerowant
  %tanZerosameSign = fcmp oeq double %tanZerora, %tanZerorb
  %tanZeroeqAndSign = and i1 %tanZeroeq, %tanZerosameSign
  %tanZero = or i1 %tanZerobothNan, %tanZeroeqAndSign
  %next79.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count79, i64 %one)
  %next79 = extractvalue {i64, i1} %next79.p.pair, 0
  %next79.p.bad = extractvalue {i64, i1} %next79.p.pair, 1
  br i1 %next79.p.bad, label %next79.p.trap, label %next79.p.ok
next79.p.trap:
  call void @llvm.trap()
  unreachable
next79.p.ok:
  br i1 %tanZero, label %bb.check80, label %bb.fail79
bb.fail79:
  %code79 = bitcast i64 80 to i64
  ret i64 %code79
bb.check80:
  %count80 = phi i64 [ %next79, %next79.p.ok ]
  %tanLargea = bitcast double 1000000.0 to double
  %tanLarger = call double @tan(double %tanLargea)
  %tanLargewant = bitcast double -0.373624453987599 to double
  %tanLargeeq = fcmp oeq double %tanLarger, %tanLargewant
  %tanLargeaOrdered = fcmp oeq double %tanLarger, %tanLarger
  %tanLargebOrdered = fcmp oeq double %tanLargewant, %tanLargewant
  %tanLargeaIsNan = xor i1 %tanLargeaOrdered, true
  %tanLargebIsNan = xor i1 %tanLargebOrdered, true
  %tanLargebothNan = and i1 %tanLargeaIsNan, %tanLargebIsNan
  %tanLargeone = bitcast double 1.0 to double
  %tanLargera = fdiv double %tanLargeone, %tanLarger
  %tanLargerb = fdiv double %tanLargeone, %tanLargewant
  %tanLargesameSign = fcmp oeq double %tanLargera, %tanLargerb
  %tanLargeeqAndSign = and i1 %tanLargeeq, %tanLargesameSign
  %tanLarge = or i1 %tanLargebothNan, %tanLargeeqAndSign
  %next80.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count80, i64 %one)
  %next80 = extractvalue {i64, i1} %next80.p.pair, 0
  %next80.p.bad = extractvalue {i64, i1} %next80.p.pair, 1
  br i1 %next80.p.bad, label %next80.p.trap, label %next80.p.ok
next80.p.trap:
  call void @llvm.trap()
  unreachable
next80.p.ok:
  br i1 %tanLarge, label %bb.check81, label %bb.fail80
bb.fail80:
  %code80 = bitcast i64 81 to i64
  ret i64 %code80
bb.check81:
  %count81 = phi i64 [ %next80, %next80.p.ok ]
  %atan2Basica = bitcast double 1.0 to double
  %atan2Basicb = bitcast double 1.0 to double
  %atan2Basicr = call double @atan2(double %atan2Basica, double %atan2Basicb)
  %atan2Basicwant = bitcast double 0.7853981633974483 to double
  %atan2Basiceq = fcmp oeq double %atan2Basicr, %atan2Basicwant
  %atan2BasicaOrdered = fcmp oeq double %atan2Basicr, %atan2Basicr
  %atan2BasicbOrdered = fcmp oeq double %atan2Basicwant, %atan2Basicwant
  %atan2BasicaIsNan = xor i1 %atan2BasicaOrdered, true
  %atan2BasicbIsNan = xor i1 %atan2BasicbOrdered, true
  %atan2BasicbothNan = and i1 %atan2BasicaIsNan, %atan2BasicbIsNan
  %atan2Basicone = bitcast double 1.0 to double
  %atan2Basicra = fdiv double %atan2Basicone, %atan2Basicr
  %atan2Basicrb = fdiv double %atan2Basicone, %atan2Basicwant
  %atan2BasicsameSign = fcmp oeq double %atan2Basicra, %atan2Basicrb
  %atan2BasiceqAndSign = and i1 %atan2Basiceq, %atan2BasicsameSign
  %atan2Basic = or i1 %atan2BasicbothNan, %atan2BasiceqAndSign
  %next81.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count81, i64 %one)
  %next81 = extractvalue {i64, i1} %next81.p.pair, 0
  %next81.p.bad = extractvalue {i64, i1} %next81.p.pair, 1
  br i1 %next81.p.bad, label %next81.p.trap, label %next81.p.ok
next81.p.trap:
  call void @llvm.trap()
  unreachable
next81.p.ok:
  br i1 %atan2Basic, label %bb.check82, label %bb.fail81
bb.fail81:
  %code81 = bitcast i64 82 to i64
  ret i64 %code81
bb.check82:
  %count82 = phi i64 [ %next81, %next81.p.ok ]
  %atan2NegZeroa = bitcast double -0.0 to double
  %atan2NegZerob = bitcast double -1.0 to double
  %atan2NegZeror = call double @atan2(double %atan2NegZeroa, double %atan2NegZerob)
  %atan2NegZerowant = bitcast double -3.141592653589793 to double
  %atan2NegZeroeq = fcmp oeq double %atan2NegZeror, %atan2NegZerowant
  %atan2NegZeroaOrdered = fcmp oeq double %atan2NegZeror, %atan2NegZeror
  %atan2NegZerobOrdered = fcmp oeq double %atan2NegZerowant, %atan2NegZerowant
  %atan2NegZeroaIsNan = xor i1 %atan2NegZeroaOrdered, true
  %atan2NegZerobIsNan = xor i1 %atan2NegZerobOrdered, true
  %atan2NegZerobothNan = and i1 %atan2NegZeroaIsNan, %atan2NegZerobIsNan
  %atan2NegZeroone = bitcast double 1.0 to double
  %atan2NegZerora = fdiv double %atan2NegZeroone, %atan2NegZeror
  %atan2NegZerorb = fdiv double %atan2NegZeroone, %atan2NegZerowant
  %atan2NegZerosameSign = fcmp oeq double %atan2NegZerora, %atan2NegZerorb
  %atan2NegZeroeqAndSign = and i1 %atan2NegZeroeq, %atan2NegZerosameSign
  %atan2NegZero = or i1 %atan2NegZerobothNan, %atan2NegZeroeqAndSign
  %next82.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count82, i64 %one)
  %next82 = extractvalue {i64, i1} %next82.p.pair, 0
  %next82.p.bad = extractvalue {i64, i1} %next82.p.pair, 1
  br i1 %next82.p.bad, label %next82.p.trap, label %next82.p.ok
next82.p.trap:
  call void @llvm.trap()
  unreachable
next82.p.ok:
  br i1 %atan2NegZero, label %bb.check83, label %bb.fail82
bb.fail82:
  %code82 = bitcast i64 83 to i64
  ret i64 %code82
bb.check83:
  %count83 = phi i64 [ %next82, %next82.p.ok ]
  %atan2Nana = bitcast double 0x7FF8000000000000 to double
  %atan2Nanb = bitcast double 1.0 to double
  %atan2Nanr = call double @atan2(double %atan2Nana, double %atan2Nanb)
  %atan2Nanwant = bitcast double 0x7FF8000000000000 to double
  %atan2Naneq = fcmp oeq double %atan2Nanr, %atan2Nanwant
  %atan2NanaOrdered = fcmp oeq double %atan2Nanr, %atan2Nanr
  %atan2NanbOrdered = fcmp oeq double %atan2Nanwant, %atan2Nanwant
  %atan2NanaIsNan = xor i1 %atan2NanaOrdered, true
  %atan2NanbIsNan = xor i1 %atan2NanbOrdered, true
  %atan2NanbothNan = and i1 %atan2NanaIsNan, %atan2NanbIsNan
  %atan2Nanone = bitcast double 1.0 to double
  %atan2Nanra = fdiv double %atan2Nanone, %atan2Nanr
  %atan2Nanrb = fdiv double %atan2Nanone, %atan2Nanwant
  %atan2NansameSign = fcmp oeq double %atan2Nanra, %atan2Nanrb
  %atan2NaneqAndSign = and i1 %atan2Naneq, %atan2NansameSign
  %atan2Nan = or i1 %atan2NanbothNan, %atan2NaneqAndSign
  %next83.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count83, i64 %one)
  %next83 = extractvalue {i64, i1} %next83.p.pair, 0
  %next83.p.bad = extractvalue {i64, i1} %next83.p.pair, 1
  br i1 %next83.p.bad, label %next83.p.trap, label %next83.p.ok
next83.p.trap:
  call void @llvm.trap()
  unreachable
next83.p.ok:
  br i1 %atan2Nan, label %bb.check84, label %bb.fail83
bb.fail83:
  %code83 = bitcast i64 84 to i64
  ret i64 %code83
bb.check84:
  %count84 = phi i64 [ %next83, %next83.p.ok ]
  %atan2PosPosZeroa = bitcast double 0.0 to double
  %atan2PosPosZerob = bitcast double 0.0 to double
  %atan2PosPosZeror = call double @atan2(double %atan2PosPosZeroa, double %atan2PosPosZerob)
  %atan2PosPosZerowant = bitcast double 0.0 to double
  %atan2PosPosZeroeq = fcmp oeq double %atan2PosPosZeror, %atan2PosPosZerowant
  %atan2PosPosZeroaOrdered = fcmp oeq double %atan2PosPosZeror, %atan2PosPosZeror
  %atan2PosPosZerobOrdered = fcmp oeq double %atan2PosPosZerowant, %atan2PosPosZerowant
  %atan2PosPosZeroaIsNan = xor i1 %atan2PosPosZeroaOrdered, true
  %atan2PosPosZerobIsNan = xor i1 %atan2PosPosZerobOrdered, true
  %atan2PosPosZerobothNan = and i1 %atan2PosPosZeroaIsNan, %atan2PosPosZerobIsNan
  %atan2PosPosZeroone = bitcast double 1.0 to double
  %atan2PosPosZerora = fdiv double %atan2PosPosZeroone, %atan2PosPosZeror
  %atan2PosPosZerorb = fdiv double %atan2PosPosZeroone, %atan2PosPosZerowant
  %atan2PosPosZerosameSign = fcmp oeq double %atan2PosPosZerora, %atan2PosPosZerorb
  %atan2PosPosZeroeqAndSign = and i1 %atan2PosPosZeroeq, %atan2PosPosZerosameSign
  %atan2PosPosZero = or i1 %atan2PosPosZerobothNan, %atan2PosPosZeroeqAndSign
  %next84.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count84, i64 %one)
  %next84 = extractvalue {i64, i1} %next84.p.pair, 0
  %next84.p.bad = extractvalue {i64, i1} %next84.p.pair, 1
  br i1 %next84.p.bad, label %next84.p.trap, label %next84.p.ok
next84.p.trap:
  call void @llvm.trap()
  unreachable
next84.p.ok:
  br i1 %atan2PosPosZero, label %bb.check85, label %bb.fail84
bb.fail84:
  %code84 = bitcast i64 85 to i64
  ret i64 %code84
bb.check85:
  %count85 = phi i64 [ %next84, %next84.p.ok ]
  %atan2NegPosZeroa = bitcast double -0.0 to double
  %atan2NegPosZerob = bitcast double 0.0 to double
  %atan2NegPosZeror = call double @atan2(double %atan2NegPosZeroa, double %atan2NegPosZerob)
  %atan2NegPosZerowant = bitcast double -0.0 to double
  %atan2NegPosZeroeq = fcmp oeq double %atan2NegPosZeror, %atan2NegPosZerowant
  %atan2NegPosZeroaOrdered = fcmp oeq double %atan2NegPosZeror, %atan2NegPosZeror
  %atan2NegPosZerobOrdered = fcmp oeq double %atan2NegPosZerowant, %atan2NegPosZerowant
  %atan2NegPosZeroaIsNan = xor i1 %atan2NegPosZeroaOrdered, true
  %atan2NegPosZerobIsNan = xor i1 %atan2NegPosZerobOrdered, true
  %atan2NegPosZerobothNan = and i1 %atan2NegPosZeroaIsNan, %atan2NegPosZerobIsNan
  %atan2NegPosZeroone = bitcast double 1.0 to double
  %atan2NegPosZerora = fdiv double %atan2NegPosZeroone, %atan2NegPosZeror
  %atan2NegPosZerorb = fdiv double %atan2NegPosZeroone, %atan2NegPosZerowant
  %atan2NegPosZerosameSign = fcmp oeq double %atan2NegPosZerora, %atan2NegPosZerorb
  %atan2NegPosZeroeqAndSign = and i1 %atan2NegPosZeroeq, %atan2NegPosZerosameSign
  %atan2NegPosZero = or i1 %atan2NegPosZerobothNan, %atan2NegPosZeroeqAndSign
  %next85.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count85, i64 %one)
  %next85 = extractvalue {i64, i1} %next85.p.pair, 0
  %next85.p.bad = extractvalue {i64, i1} %next85.p.pair, 1
  br i1 %next85.p.bad, label %next85.p.trap, label %next85.p.ok
next85.p.trap:
  call void @llvm.trap()
  unreachable
next85.p.ok:
  br i1 %atan2NegPosZero, label %bb.check86, label %bb.fail85
bb.fail85:
  %code85 = bitcast i64 86 to i64
  ret i64 %code85
bb.check86:
  %count86 = phi i64 [ %next85, %next85.p.ok ]
  %atan2PosNegZeroa = bitcast double 0.0 to double
  %atan2PosNegZerob = bitcast double -0.0 to double
  %atan2PosNegZeror = call double @atan2(double %atan2PosNegZeroa, double %atan2PosNegZerob)
  %atan2PosNegZerowant = bitcast double 3.141592653589793 to double
  %atan2PosNegZeroeq = fcmp oeq double %atan2PosNegZeror, %atan2PosNegZerowant
  %atan2PosNegZeroaOrdered = fcmp oeq double %atan2PosNegZeror, %atan2PosNegZeror
  %atan2PosNegZerobOrdered = fcmp oeq double %atan2PosNegZerowant, %atan2PosNegZerowant
  %atan2PosNegZeroaIsNan = xor i1 %atan2PosNegZeroaOrdered, true
  %atan2PosNegZerobIsNan = xor i1 %atan2PosNegZerobOrdered, true
  %atan2PosNegZerobothNan = and i1 %atan2PosNegZeroaIsNan, %atan2PosNegZerobIsNan
  %atan2PosNegZeroone = bitcast double 1.0 to double
  %atan2PosNegZerora = fdiv double %atan2PosNegZeroone, %atan2PosNegZeror
  %atan2PosNegZerorb = fdiv double %atan2PosNegZeroone, %atan2PosNegZerowant
  %atan2PosNegZerosameSign = fcmp oeq double %atan2PosNegZerora, %atan2PosNegZerorb
  %atan2PosNegZeroeqAndSign = and i1 %atan2PosNegZeroeq, %atan2PosNegZerosameSign
  %atan2PosNegZero = or i1 %atan2PosNegZerobothNan, %atan2PosNegZeroeqAndSign
  %next86.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count86, i64 %one)
  %next86 = extractvalue {i64, i1} %next86.p.pair, 0
  %next86.p.bad = extractvalue {i64, i1} %next86.p.pair, 1
  br i1 %next86.p.bad, label %next86.p.trap, label %next86.p.ok
next86.p.trap:
  call void @llvm.trap()
  unreachable
next86.p.ok:
  br i1 %atan2PosNegZero, label %bb.check87, label %bb.fail86
bb.fail86:
  %code86 = bitcast i64 87 to i64
  ret i64 %code86
bb.check87:
  %count87 = phi i64 [ %next86, %next86.p.ok ]
  %atan2NegNegZeroa = bitcast double -0.0 to double
  %atan2NegNegZerob = bitcast double -0.0 to double
  %atan2NegNegZeror = call double @atan2(double %atan2NegNegZeroa, double %atan2NegNegZerob)
  %atan2NegNegZerowant = bitcast double -3.141592653589793 to double
  %atan2NegNegZeroeq = fcmp oeq double %atan2NegNegZeror, %atan2NegNegZerowant
  %atan2NegNegZeroaOrdered = fcmp oeq double %atan2NegNegZeror, %atan2NegNegZeror
  %atan2NegNegZerobOrdered = fcmp oeq double %atan2NegNegZerowant, %atan2NegNegZerowant
  %atan2NegNegZeroaIsNan = xor i1 %atan2NegNegZeroaOrdered, true
  %atan2NegNegZerobIsNan = xor i1 %atan2NegNegZerobOrdered, true
  %atan2NegNegZerobothNan = and i1 %atan2NegNegZeroaIsNan, %atan2NegNegZerobIsNan
  %atan2NegNegZeroone = bitcast double 1.0 to double
  %atan2NegNegZerora = fdiv double %atan2NegNegZeroone, %atan2NegNegZeror
  %atan2NegNegZerorb = fdiv double %atan2NegNegZeroone, %atan2NegNegZerowant
  %atan2NegNegZerosameSign = fcmp oeq double %atan2NegNegZerora, %atan2NegNegZerorb
  %atan2NegNegZeroeqAndSign = and i1 %atan2NegNegZeroeq, %atan2NegNegZerosameSign
  %atan2NegNegZero = or i1 %atan2NegNegZerobothNan, %atan2NegNegZeroeqAndSign
  %next87.p.pair = call {i64, i1} @llvm.sadd.with.overflow.i64(i64 %count87, i64 %one)
  %next87 = extractvalue {i64, i1} %next87.p.pair, 0
  %next87.p.bad = extractvalue {i64, i1} %next87.p.pair, 1
  br i1 %next87.p.bad, label %next87.p.trap, label %next87.p.ok
next87.p.trap:
  call void @llvm.trap()
  unreachable
next87.p.ok:
  br i1 %atan2NegNegZero, label %bb.done, label %bb.fail87
bb.fail87:
  %code87 = bitcast i64 88 to i64
  ret i64 %code87
bb.done:
  %total = phi i64 [ %next87, %next87.p.ok ]
  %expected = bitcast i64 88 to i64
  %allRan = icmp eq i64 %total, %expected
  br i1 %allRan, label %bb.passed, label %bb.miscounted
bb.passed:
  ret i64 %zero
bb.miscounted:
  %bad = bitcast i64 100 to i64
  ret i64 %bad
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
  %result = call tailcc i64 @primCheck()
  %code = trunc i64 %result to i32
  ret i32 %code
}

declare void @llvm.trap()
declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)
declare {i64, i1} @llvm.ssub.with.overflow.i64(i64, i64)
declare {i64, i1} @llvm.smul.with.overflow.i64(i64, i64)
declare double @llvm.sqrt.f64(double)
declare double @llvm.floor.f64(double)
declare double @llvm.ceil.f64(double)
declare double @llvm.round.f64(double)
declare double @pow(double, double)
declare double @exp(double)
declare double @log(double)
declare double @log2(double)
declare double @log10(double)
declare double @sin(double)
declare double @cos(double)
declare double @tan(double)
declare double @atan2(double, double)
declare i64 @strlen(ptr)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i64 @write(i32, ptr, i64)
declare void @exit(i32)
declare i32 @fflush(ptr)
declare ptr @getenv(ptr)
declare i32 @atexit(ptr)
declare i32 @unsetenv(ptr)
declare void @longjmp(ptr, i32) noreturn
