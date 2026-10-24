(module asl-target-llvm/hashRt
  :x [hashSplice ownedFlags slotsNames hashKeyName nativeMarker]
  :i [])

; (:m :ref INTHASHMAP :do "native bodies for the HashMap primitives and the key hash: the reference bodies in asl/prelude/prelude.asl stay what every target runs, and this splice replaces them in the final LLVM text with the define line rebuilt from the compiled one (linkage, calling convention, Val or i64 parameters renamed %hashArgN). The map becomes one large ctor of (hash key value) triples; table bodies are spliced only under the untraced RC runtime, where every large ctor carries a count: a put on a map whose count is 0 writes in place, a shared or stuck one is copied first, so maps stay persistent. rc.asl calls hashSplice and starts the parameters ownedFlags names owned, so a count of 0 means the callee holds the only reference")

fn nativeMarker -> String
  "; hashRt native slots"

fn slotsNames -> (List String)
  (list "preludeHashNew" "preludeHashCapacity" "preludeHashCountOf" "preludeHashSetCount" "preludeHashState" "preludeHashKeyAt" "preludeHashValueAt" "preludeHashPutEntry" "preludeHashPutValue" "preludeHashClear" "preludeHashMoveSlot" "preludeHashFind" "preludeHashGrow" "hashMapSet" "hashMapGetOr")

fn hashKeyName -> String
  "preludeHashKey"

fn mangled name: String -> String
  (str "@prelude$2E" name "(")

fn lines xs: (List String) -> String
  (stringJoin xs "\n")

fn afterFirst s: String sep: String -> (Option String)
  (match (stringIndexOf s sep)
    ((none) (none))
    ((some at) (stringSlice s (+ at (stringLength sep)) (stringLength s))))

fn beforeFirst s: String sep: String -> String
  (match (stringIndexOf s sep)
    ((none) s)
    ((some at) (optionOr (stringSlice s 0 at) s)))

; (:m :ref INTHASHMAP :do "a define chunk is the text after one \"\\ndefine \": its header up to the first newline, its body up to the first line holding only }, then whatever follows before the next define")
schema Chunk
  (:f header String)
  (:f rest String)

fn chunkOf text: String -> (Option Chunk)
  (match (stringIndexOf text "\n}\n")
    ((none) (none))
    ((some at) (some (Chunk :header (beforeFirst text "\n") :rest (optionOr (stringSlice text (+ at 2) (stringLength text)) "")))))

schema Param
  (:f ty String)
  (:f name String)

fn paramsOf header: String name: String -> (List Param)
  (let [(inside (beforeFirst (optionOr (afterFirst header (mangled name)) "") ")"))]
    (if (stringEmpty? (stringTrim inside)) (list)
      (map (fn [(p String)] -> Param
             (let [(parts (stringSplit (stringTrim p) " "))]
               (Param :ty (optionOr (listHead parts) "") :name (optionOr (listLast parts) ""))))
           (stringSplit inside ","))))

fn retOf header: String name: String -> String
  (let [(head (beforeFirst header (str " " (mangled name))))]
    (optionOr (listLast (stringSplit head " ")) "%Val"))

; (:m :ref INTHASHMAP :do "an Int argument arrives as i64 or as a boxed Val; either way the native body reads the raw i64 named d")
fn intArg p: Param d: String -> String
  (if (= p.ty "i64") (str "  " d " = add i64 0, " p.name) (str "  " d " = extractvalue %Val " p.name ", 1"))

fn intRet ret: String v: String -> (List String)
  (if (= ret "i64") (list (str "  ret i64 " v))
    (list (str "  %ret.box = insertvalue %Val { i64 2, i64 0 }, i64 " v ", 1") "  ret %Val %ret.box"))

fn param ps: (List Param) i: Int64 -> Param
  (optionOr (listGet ps i) (Param :ty "%Val" :name "%missing"))

; (:m :ref INTHASHMAP :do "native layout: one ctor object (type 3, the preludeHashOf id when the module defines it) whose +12 holds nb, the count of boxed Val fields from +16, which is all RC scans or frees; field 0 the count, field 1 the info cap * 4 + mode; mode 0 pending (no slots yet, nb 2), mode 1 general (slot j: stored hash, key, value at fields 2 + 3j, 3 + 3j, 4 + 3j), mode 2 Int64 keys (slot j: the key at field 2 + 2j, an Int64 when occupied and Unit when vacant, its value at field 3 + 2j), 32 bytes per slot and no stored hash; every field is a Val, so RC sees only immediates or owned values")
fn nm p: String s: String -> String
  (str "%" p s)

fn at p: String base: String bytes: String -> String
  (str "  " p " = getelementptr inbounds i8, ptr " base ", i64 " bytes)

fn fieldAt p: String base: String idx: String -> (List String)
  (list (str "  " p ".f0 = mul i64 " idx ", 16") (str "  " p ".f1 = add i64 " p ".f0, 16") (at p base (str p ".f1")))

fn slotField p: String base: String j: String which: Int64 -> (List String)
  (listAppend (list (str "  " p ".s0 = mul i64 " j ", 3") (str "  " p ".s1 = add i64 " p ".s0, " (+ which 2))) (fieldAt p base (str p ".s1")))

fn valueField p: String base: String j: String -> (List String)
  (listAppend (list (str "  " p ".s0 = shl i64 " j ", 1") (str "  " p ".s1 = add i64 " p ".s0, 3")) (fieldAt p base (str p ".s1")))

; (:m :ref INTHASHMAP :do "the payload word of the key field of slot j in raw mode (field 2 + 2j at byte 48 + 32j, payload 8 further), read and written as a raw Int64")
fn keyWord p: String rb: String j: String -> (List String)
  (list (str "  " p ".o0 = shl i64 " j ", 5") (str "  " p ".o1 = add i64 " p ".o0, 56") (at p rb (str p ".o1")))

; (:m :ref INTHASHMAP :do "the tag word of the key field of slot j in raw mode: 2 (Int64) when occupied, 0 (Unit) when vacant; p.bit is the occupied tag, so or-ing it in marks the slot, and-ing its complement frees it")
fn bitWord p: String rb: String cap: String j: String -> (List String)
  (list (str "  " p ".o0 = shl i64 " j ", 5") (str "  " p ".o1 = add i64 " p ".o0, 48") (at p rb (str p ".o1"))
        (str "  " p ".bit = add i64 0, 2")
        (str "  " p ".word = load i64, ptr " p) (str "  " p ".and = and i64 " p ".word, " p ".bit")
        (str "  " p ".set = icmp ne i64 " p ".and, 0"))

; (:m :ref INTHASHMAP :do "the Int64 key hash, the same mix as the Int branch of hashBody, so a stored Int key recomputes the hash preludeHashKey gave it")
fn mix p: String x: String -> (List String)
  (list (str "  " p ".m1 = mul i64 " x ", -7046029254386353131") (str "  " p ".m2 = lshr i64 " p ".m1, 32") (str "  " p ".m3 = shl i64 " p ".m1, 32")
        (str "  " p ".m4 = or i64 " p ".m2, " p ".m3") (str "  " p ".m5 = and i64 " p ".m4, 4611686018427387903") (str "  " p " = or i64 " p ".m5, 1"))

; (:m :ref INTHASHMAP :do "pair mode (3, Int64 keys and Int64 values): no slot fields; from byte 48 the raw words, slot j a key word at 16j and its value word after it, then a bitmap of occupied slots at word 2 cap; RC sees two immediate fields")
fn pairWord p: String rb: String j: String -> (List String)
  (list (str "  " p ".o0 = shl i64 " j ", 4") (at p rb (str p ".o0")) (str "  " p ".v = getelementptr inbounds i8, ptr " p ", i64 8"))

fn pairBit p: String rb: String cap: String j: String -> (List String)
  (list (str "  " p ".w0 = lshr i64 " j ", 6") (str "  " p ".c2 = shl i64 " cap ", 1") (str "  " p ".w1 = add i64 " p ".c2, " p ".w0")
        (str "  " p " = getelementptr inbounds i64, ptr " rb ", i64 " p ".w1")
        (str "  " p ".b0 = and i64 " j ", 63") (str "  " p ".bit = shl i64 1, " p ".b0")
        (str "  " p ".word = load i64, ptr " p) (str "  " p ".and = and i64 " p ".word, " p ".bit")
        (str "  " p ".set = icmp ne i64 " p ".and, 0"))

fn mapHead m: String -> (List String)
  (list (str "  %mw = extractvalue %Val " m ", 1") "  %mo = inttoptr i64 %mw to ptr"
        "  %mnp = getelementptr inbounds i8, ptr %mo, i64 12" "  %mn32 = load i32, ptr %mnp" "  %mn = sext i32 %mn32 to i64"
        "  %mip = getelementptr inbounds i8, ptr %mo, i64 40" "  %info = load i64, ptr %mip"
        "  %cap = lshr i64 %info, 2" "  %mode = and i64 %info, 3"
        "  %mrb.r1 = add i64 0, 0" (at "%mrb" "%mo" "%mrb.r1") "  %mrb3 = getelementptr inbounds i8, ptr %mo, i64 48")

fn inside j: String -> (List String)
  (list (str "  %inside = icmp ult i64 " j ", %cap") "  br i1 %inside, label %ok, label %outside" "outside:" "  call void @llvm.trap()" "  unreachable" "ok:")

fn ctorId id: Bool -> (List String)
  (if id
    (list "  %idReady = load i1, ptr @ctorIdReady.preludeHashOf" "  br i1 %idReady, label %idKnown, label %idInit" "idInit:" "  call void @ctorIdInit.preludeHashOf()" "  br label %idKnown" "idKnown:" "  %cid = load i32, ptr @ctorId.preludeHashOf")
    (list "  %cid = add i32 0, 0"))

; (:m :ref INTHASHMAP :do "the size of a table of this mode and capacity: p.nb boxed fields (2, or 2 + 3 cap general, 2 + 2 cap raw), p.by bytes; p.rw (raw words after the fields) is 0 in this layout and kept so a later unboxed column only changes it")
fn sizes p: String mode: String cap: String -> (List String)
  (list (str "  " (nm p ".gen") " = icmp eq i64 " mode ", 1")
        (str "  " (nm p ".isInt") " = icmp eq i64 " mode ", 2")
        (str "  " (nm p ".isPair") " = icmp eq i64 " mode ", 3")
        (str "  " (nm p ".k1") " = select i1 " (nm p ".isInt") ", i64 2, i64 0")
        (str "  " (nm p ".k") " = select i1 " (nm p ".gen") ", i64 3, i64 " (nm p ".k1"))
        (str "  " (nm p ".nb0") " = mul i64 " cap ", " (nm p ".k"))
        (str "  " (nm p ".pend") " = icmp eq i64 " mode ", 0")
        (str "  " (nm p ".nb1") " = add i64 " (nm p ".nb0") ", 2")
        (str "  " (nm p ".nb") " = select i1 " (nm p ".pend") ", i64 2, i64 " (nm p ".nb1"))
        (str "  " (nm p ".bw0") " = add i64 " cap ", 63")
        (str "  " (nm p ".bw") " = lshr i64 " (nm p ".bw0") ", 6")
        (str "  " (nm p ".rw2") " = shl i64 " cap ", 1")
        (str "  " (nm p ".rw0") " = add i64 " (nm p ".rw2") ", " (nm p ".bw"))
        (str "  " (nm p ".rw") " = select i1 " (nm p ".isPair") ", i64 " (nm p ".rw0") ", i64 0")
        (str "  " (nm p ".by0") " = mul i64 " (nm p ".nb") ", 16")
        (str "  " (nm p ".by1") " = add i64 " (nm p ".by0") ", 16")
        (str "  " (nm p ".rby") " = mul i64 " (nm p ".rw") ", 8")
        (str "  " (nm p ".by") " = add i64 " (nm p ".by1") ", " (nm p ".rby")))

; (:m :ref INTHASHMAP :do "a fresh table %p of mode 1 or 2: id, nb, count and info stored, every slot field Unit (a vacant key in either mode: hash payload 0, tag 0); %p.v is the map, %p.rb its base for the raw-mode key words")
fn fresh p: String mode: String cap: String count: String cid: String -> (List String)
  (listAppend (sizes p mode cap)
    (list (str "  " (nm p "") " = call ptr @asl_alloc(i32 3, i64 " (nm p ".by") ")")
          (at (nm p ".idp") (nm p "") "8") (str "  store i32 " cid ", ptr " (nm p ".idp"))
          (str "  " (nm p ".nb32") " = trunc i64 " (nm p ".nb") " to i32")
          (at (nm p ".nbp") (nm p "") "12") (str "  store i32 " (nm p ".nb32") ", ptr " (nm p ".nbp"))
          (str "  " (nm p ".cv") " = insertvalue %Val { i64 2, i64 0 }, i64 " count ", 1")
          (at (nm p ".cp") (nm p "") "16") (str "  store %Val " (nm p ".cv") ", ptr " (nm p ".cp"))
          (str "  " (nm p ".i0") " = shl i64 " cap ", 2")
          (str "  " (nm p ".i1") " = or i64 " (nm p ".i0") ", " mode)
          (str "  " (nm p ".iv") " = insertvalue %Val { i64 2, i64 0 }, i64 " (nm p ".i1") ", 1")
          (at (nm p ".ip") (nm p "") "32") (str "  store %Val " (nm p ".iv") ", ptr " (nm p ".ip"))
          (str "  br label " (nm p ".pre"))
          (str p ".pre:")
          (str "  br label " (nm p ".fill"))
          (str p ".fill:")
          (str "  " (nm p ".f") " = phi i64 [ 2, " (nm p ".pre") " ], [ " (nm p ".f1") ", " (nm p ".fillStep") " ]")
          (str "  " (nm p ".fmore") " = icmp slt i64 " (nm p ".f") ", " (nm p ".nb"))
          (str "  br i1 " (nm p ".fmore") ", label " (nm p ".fillStep") ", label " (nm p ".filled"))
          (str p ".fillStep:")
          (str "  " (nm p ".fo0") " = mul i64 " (nm p ".f") ", 16")
          (str "  " (nm p ".fo") " = add i64 " (nm p ".fo0") ", 16")
          (at (nm p ".fa") (nm p "") (nm p ".fo"))
          (str "  store %Val { i64 0, i64 0 }, ptr " (nm p ".fa"))
          (str "  " (nm p ".f1") " = add i64 " (nm p ".f") ", 1")
          (str "  br label " (nm p ".fill"))
          (str p ".filled:")
          (at (nm p ".rb") (nm p "") "0")
          (at (nm p ".rb3") (nm p "") (nm p ".by1"))
          (str "  " (nm p ".z0") " = select i1 " (nm p ".isPair") ", i64 " (nm p ".rw2") ", i64 0")
          (str "  br label " (nm p ".zero"))
          (str p ".zero:")
          (str "  " (nm p ".z") " = phi i64 [ " (nm p ".z0") ", " (nm p ".filled") " ], [ " (nm p ".z1") ", " (nm p ".zeroStep") " ]")
          (str "  " (nm p ".zmore") " = icmp slt i64 " (nm p ".z") ", " (nm p ".rw"))
          (str "  br i1 " (nm p ".zmore") ", label " (nm p ".zeroStep") ", label " (nm p ".zeroed"))
          (str p ".zeroStep:")
          (str "  " (nm p ".za") " = getelementptr inbounds i64, ptr " (nm p ".rb3") ", i64 " (nm p ".z"))
          (str "  store i64 0, ptr " (nm p ".za"))
          (str "  " (nm p ".z1") " = add i64 " (nm p ".z") ", 1")
          (str "  br label " (nm p ".zero"))
          (str p ".zeroed:")
          (str "  " (nm p ".w") " = ptrtoint ptr " (nm p "") " to i64")
          (str "  " (nm p ".v") " = insertvalue %Val { i64 8, i64 0 }, i64 " (nm p ".w") ", 1")))

; (:m :ref INTHASHMAP :do "a pending map: no slots, the capacity in its info word; the first PutEntry picks the mode from the key")
fn newBody ps: (List Param) id: Bool -> (List String)
  (listAppend (list (intArg (param ps 0) "%c0") "  %small = icmp slt i64 %c0, 1" "  %c = select i1 %small, i64 1, i64 %c0")
    (listAppend (ctorId id)
      (list "  %p = call ptr @asl_alloc(i32 3, i64 48)"
            "  %pidp = getelementptr inbounds i8, ptr %p, i64 8" "  store i32 %cid, ptr %pidp"
            "  %pnp = getelementptr inbounds i8, ptr %p, i64 12" "  store i32 2, ptr %pnp"
            "  %p0 = getelementptr inbounds i8, ptr %p, i64 16" "  store %Val { i64 2, i64 0 }, ptr %p0"
            "  %pi = shl i64 %c, 2" "  %piv = insertvalue %Val { i64 2, i64 0 }, i64 %pi, 1"
            "  %p1 = getelementptr inbounds i8, ptr %p, i64 32" "  store %Val %piv, ptr %p1"
            "  %pw = ptrtoint ptr %p to i64" "  %pv = insertvalue %Val { i64 8, i64 0 }, i64 %pw, 1" "  ret %Val %pv")))

fn capacityBody ps: (List Param) ret: String -> (List String)
  (listAppend (mapHead (param ps 0).name) (intRet ret "%cap"))

fn countBody ps: (List Param) ret: String -> (List String)
  (listAppend (list (str "  %mw = extractvalue %Val " (param ps 0).name ", 1") "  %mo = inttoptr i64 %mw to ptr"
                    "  %cp = getelementptr inbounds i8, ptr %mo, i64 24" "  %cn = load i64, ptr %cp")
    (intRet ret "%cn"))

fn stateBody ps: (List Param) ret: String -> (List String)
  (listAppend (mapHead (param ps 0).name)
    (listAppend (list (intArg (param ps 1) "%j")) (listAppend (inside "%j")
      (listAppend (list "  switch i64 %mode, label %pend [ i64 1, label %gen i64 2, label %int i64 3, label %pair ]" "pend:" "  br label %out" "gen:")
        (listAppend (slotField "%hp" "%mo" "%j" 0)
          (listAppend (list "  %hpp = getelementptr inbounds i8, ptr %hp, i64 8" "  %gh = load i64, ptr %hpp" "  br label %out" "int:")
            (listAppend (bitWord "%bw" "%mrb" "%cap" "%j")
              (listAppend (list "  br i1 %bw.set, label %intSet, label %out" "intSet:")
                (listAppend (keyWord "%kp" "%mrb" "%j")
                  (listAppend (list "  %kx = load i64, ptr %kp") (listAppend (mix "%ih" "%kx")
                    (listAppend (list "  br label %out" "pair:")
                      (listAppend (pairBit "%pb" "%mrb3" "%cap" "%j")
                        (listAppend (list "  br i1 %pb.set, label %pairSet, label %out" "pairSet:")
                          (listAppend (pairWord "%pk" "%mrb3" "%j")
                            (listAppend (list "  %px = load i64, ptr %pk") (listAppend (mix "%ph" "%px")
                              (listAppend (list "  br label %out" "out:" "  %st = phi i64 [ 0, %pend ], [ %gh, %gen ], [ 0, %int ], [ %ih, %intSet ], [ 0, %pair ], [ %ph, %pairSet ]")
                                (intRet ret "%st")))))))))))))))))))

fn keyBody ps: (List Param) -> (List String)
  (listAppend (mapHead (param ps 0).name)
    (listAppend (list (intArg (param ps 1) "%j")) (listAppend (inside "%j")
      (listAppend (list "  %isInt = icmp eq i64 %mode, 2" "  br i1 %isInt, label %intKey, label %genKey" "genKey:" "  %isGen = icmp eq i64 %mode, 1" "  br i1 %isGen, label %genOk, label %pairKey" "pairKey:" "  %isPair = icmp eq i64 %mode, 3" "  br i1 %isPair, label %pairBits, label %outside" "pairBits:")
        (listAppend (pairBit "%pb" "%mrb3" "%cap" "%j")
          (listAppend (list "  br i1 %pb.set, label %pairOk, label %outside" "pairOk:")
            (listAppend (pairWord "%pk" "%mrb3" "%j")
              (listAppend (list "  %px = load i64, ptr %pk" "  %pv = insertvalue %Val { i64 2, i64 0 }, i64 %px, 1" "  ret %Val %pv" "genOk:")
        (listAppend (slotField "%at" "%mo" "%j" 1)
          (listAppend (list "  %v = load %Val, ptr %at" "  %d = call tailcc i64 @aslRcDup(%Val %v)" "  ret %Val %v" "intKey:")
            (listAppend (bitWord "%bw" "%mrb" "%cap" "%j")
              (listAppend (list "  br i1 %bw.set, label %intOk, label %outside" "intOk:")
                (listAppend (keyWord "%kp" "%mrb" "%j")
                  (list "  %kx = load i64, ptr %kp" "  %kv = insertvalue %Val { i64 2, i64 0 }, i64 %kx, 1" "  ret %Val %kv"))))))))))))))

fn valueBody ps: (List Param) -> (List String)
  (listAppend (mapHead (param ps 0).name)
    (listAppend (list (intArg (param ps 1) "%j")) (listAppend (inside "%j")
      (listAppend (list "  switch i64 %mode, label %outside [ i64 1, label %gen i64 2, label %int i64 3, label %pair ]" "pair:")
        (listAppend (pairWord "%pk" "%mrb3" "%j")
          (listAppend (list "  %px = load i64, ptr %pk.v" "  %pv = insertvalue %Val { i64 2, i64 0 }, i64 %px, 1" "  ret %Val %pv" "gen:")
        (listAppend (slotField "%gp" "%mo" "%j" 2)
          (listAppend (list "  br label %read" "int:")
            (listAppend (valueField "%ip" "%mo" "%j")
              (list "  br label %read" "read:" "  %at = phi ptr [ %gp, %gen ], [ %ip, %int ]"
                    "  %v = load %Val, ptr %at" "  %d = call tailcc i64 @aslRcDup(%Val %v)" "  ret %Val %v"))))))))))

; (:m :ref INTHASHMAP :do "the uniqueness test every write runs on its owned map: count 0 -> %u is the map itself and the write goes in place; shared or stuck -> %u is a word-for-word copy (header excepted) whose boxed fields are duplicated, and the caller's reference to the original is dropped; %urb is the raw words of %u")
fn unique m: String -> (List String)
  (listAppend
    (list "  %h0 = load i64, ptr %mo" "  %c48 = lshr i64 %h0, 48" "  %c8 = and i64 %c48, 255" "  %isUnique = icmp eq i64 %c8, 0"
          "  br i1 %isUnique, label %own, label %copy"
          "own:"
          (nativeMarker)
          "  br label %write"
          "copy:")
    (listAppend (sizes "cz" "%mode" "%cap")
      (list "  %cp = call ptr @asl_alloc(i32 3, i64 %cz.by)"
            "  %cw = lshr i64 %cz.by, 3"
            "  br label %copyLoop"
            "copyLoop:"
            "  %ci = phi i64 [ 1, %copy ], [ %ci1, %copyStep ]"
            "  %cmore = icmp slt i64 %ci, %cw"
            "  br i1 %cmore, label %copyStep, label %dupLoop"
            "copyStep:"
            "  %csrc = getelementptr inbounds i64, ptr %mo, i64 %ci" "  %cdst = getelementptr inbounds i64, ptr %cp, i64 %ci"
            "  %cv = load i64, ptr %csrc" "  store i64 %cv, ptr %cdst"
            "  %ci1 = add i64 %ci, 1"
            "  br label %copyLoop"
            "dupLoop:"
            "  %di = phi i64 [ 0, %copyLoop ], [ %di1, %dupStep ]"
            "  %dmore = icmp slt i64 %di, %mn"
            "  br i1 %dmore, label %dupStep, label %duped"
            "dupStep:"
            "  %doff0 = mul i64 %di, 16" "  %doff = add i64 %doff0, 16"
            "  %dat = getelementptr inbounds i8, ptr %cp, i64 %doff"
            "  %dv = load %Val, ptr %dat"
            "  %dd = call tailcc i64 @aslRcDup(%Val %dv)"
            "  %di1 = add i64 %di, 1"
            "  br label %dupLoop"
            "duped:"
            (str "  %cdrop = call tailcc i64 @aslRcDrop(%Val " m ")")
            "  br label %write"
            "write:"
            "  %u = phi ptr [ %mo, %own ], [ %cp, %duped ]"
            "  %uw = ptrtoint ptr %u to i64" "  %uv = insertvalue %Val { i64 8, i64 0 }, i64 %uw, 1"
            "  %urb = getelementptr inbounds i8, ptr %u, i64 %mrb.r1" "  %urb3 = getelementptr inbounds i8, ptr %u, i64 48")))

fn store p: String v: String -> (List String)
  (list (str "  " p ".old = load %Val, ptr " p) (str "  store %Val " v ", ptr " p) (str "  " p ".drop = call tailcc i64 @aslRcDrop(%Val " p ".old)"))

; (:m :ref INTHASHMAP :do "a write: bounds, a table when the write needs slots (a pending map has none), uniqueness, the writes on %u, the map returned")
fn writeBody ps: (List Param) j: String table: Bool writes: (List String) -> (List String)
  (let [(m (param ps 0).name)]
    (listAppend (mapHead m)
      (listAppend (list j)
        (listAppend (inside "%j")
          (listAppend (if table (list "  %hasTable = icmp ne i64 %mode, 0" "  br i1 %hasTable, label %tableOk, label %outside" "tableOk:") (list))
            (listAppend (unique m) (listAppend writes (list "  ret %Val %uv"))))))))

fn setCountBody ps: (List Param) -> (List String)
  (writeBody ps "  %j = add i64 0, 0" false
    (listAppend (list (intArg (param ps 1) "%count") "  %cnt = insertvalue %Val { i64 2, i64 0 }, i64 %count, 1" "  %c0p = getelementptr inbounds i8, ptr %u, i64 16")
      (store "%c0p" "%cnt")))

; (:m :ref INTHASHMAP :do "hash and key into slot j; on a pending map this first builds the table, Int64 keys (tag 2) taking the raw mode; a key of another tag in a raw-mode map traps (typing gives one key type per map)")
fn putEntryBody ps: (List Param) -> (List String)
  (let [(m (param ps 0).name) (k (param ps 3).name)]
    (listAppend (mapHead m)
      (listAppend (list (intArg (param ps 1) "%j") (intArg (param ps 2) "%hv")
                        (str "  %kt0 = extractvalue %Val " k ", 0") "  %kt = and i64 %kt0, 4294967295" (str "  %kb = extractvalue %Val " k ", 1") "  %kInt = icmp eq i64 %kt, 2")
        (listAppend (inside "%j")
          (listAppend (list "  %pending = icmp eq i64 %mode, 0" "  br i1 %pending, label %make, label %have" "make:"
                            "  %nmode = select i1 %kInt, i64 2, i64 1"
                            "  %oidp = getelementptr inbounds i8, ptr %mo, i64 8" "  %oid = load i32, ptr %oidp"
                            "  %ocp = getelementptr inbounds i8, ptr %mo, i64 24" "  %oc = load i64, ptr %ocp")
            (listAppend (fresh "t" "%nmode" "%cap" "%oc" "%oid")
              (listAppend (list (str "  %pdrop = call tailcc i64 @aslRcDrop(%Val " m ")") "  br label %put" "have:")
                (listAppend (unique m)
                  (listAppend (list "  br label %put" "put:"
                                    "  %w = phi ptr [ %t, %t.zeroed ], [ %u, %write ]"
                                    "  %wv = phi %Val [ %t.v, %t.zeroed ], [ %uv, %write ]"
                                    "  %wmode = phi i64 [ %nmode, %t.zeroed ], [ %mode, %write ]"
                                    "  %wrb = phi ptr [ %t.rb, %t.zeroed ], [ %urb, %write ]"
                                    "  %wrb3 = getelementptr inbounds i8, ptr %w, i64 48"
                                    "  %wPair = icmp eq i64 %wmode, 3" "  br i1 %wPair, label %putP, label %putN" "putP:" "  br i1 %kInt, label %putPok, label %outside" "putPok:")
                    (listAppend (pairWord "%pe" "%wrb3" "%j")
                    (listAppend (list "  store i64 %kb, ptr %pe")
                    (listAppend (pairBit "%pq" "%wrb3" "%cap" "%j")
                    (listAppend (list "  %pqn = or i64 %pq.word, %pq.bit" "  store i64 %pqn, ptr %pq" "  ret %Val %wv" "putN:"
                                    "  %wInt = icmp eq i64 %wmode, 2"
                                    "  br i1 %wInt, label %putI, label %putG"
                                    "putG:"
                                    "  %hval = insertvalue %Val { i64 2, i64 0 }, i64 %hv, 1")
                    (listAppend (slotField "%hp" "%w" "%j" 0)
                      (listAppend (store "%hp" "%hval")
                        (listAppend (slotField "%kp" "%w" "%j" 1)
                          (listAppend (store "%kp" k)
                            (listAppend (list "  ret %Val %wv" "putI:" "  br i1 %kInt, label %putIok, label %outside" "putIok:")
                              (listAppend (keyWord "%rk" "%wrb" "%j")
                                (listAppend (list "  store i64 %kb, ptr %rk")
                                  (listAppend (bitWord "%bw" "%wrb" "%cap" "%j")
                                    (list "  %bwn = or i64 %bw.word, %bw.bit" "  store i64 %bwn, ptr %bw" "  ret %Val %wv"))))))))))))))))))))))

fn putValueBody ps: (List Param) -> (List String)
  (writeBody ps (intArg (param ps 1) "%j") true
    (listAppend (list "  %pvPair = icmp eq i64 %mode, 3" "  br i1 %pvPair, label %pvP, label %pvN" "pvP:"
                      (str "  %pvt0 = extractvalue %Val " (param ps 2).name ", 0") "  %pvt = and i64 %pvt0, 4294967295" (str "  %pvb = extractvalue %Val " (param ps 2).name ", 1")
                      "  %pvIsInt = icmp eq i64 %pvt, 2" "  br i1 %pvIsInt, label %pvPok, label %outside" "pvPok:")
    (listAppend (pairWord "%pw" "%urb3" "%j")
    (listAppend (list "  store i64 %pvb, ptr %pw.v" "  ret %Val %uv" "pvN:")
    (listAppend (list "  %pvInt = icmp eq i64 %mode, 2" "  br i1 %pvInt, label %pvI, label %pvG" "pvG:")
      (listAppend (slotField "%gp" "%u" "%j" 2)
        (listAppend (list "  br label %pvDo" "pvI:")
          (listAppend (valueField "%ip" "%u" "%j")
            (listAppend (list "  br label %pvDo" "pvDo:" "  %vp = phi ptr [ %gp, %pvG ], [ %ip, %pvI ]")
              (store "%vp" (param ps 2).name))))))))))

fn clearBody ps: (List Param) -> (List String)
  (writeBody ps (intArg (param ps 1) "%j") true
    (listAppend (list "  %clPair = icmp eq i64 %mode, 3" "  br i1 %clPair, label %clP, label %clN" "clP:")
    (listAppend (pairBit "%cb" "%urb3" "%cap" "%j")
    (listAppend (list "  %cbm = xor i64 %cb.bit, -1" "  %cbn = and i64 %cb.word, %cbm" "  store i64 %cbn, ptr %cb" "  ret %Val %uv" "clN:")
    (listAppend (list "  %clInt = icmp eq i64 %mode, 2" "  br i1 %clInt, label %clI, label %clG" "clG:")
      (listAppend (slotField "%hp" "%u" "%j" 0) (listAppend (store "%hp" "{ i64 2, i64 0 }")
        (listAppend (slotField "%kp" "%u" "%j" 1) (listAppend (store "%kp" "{ i64 2, i64 0 }")
          (listAppend (slotField "%vp" "%u" "%j" 2) (listAppend (store "%vp" "{ i64 2, i64 0 }")
            (listAppend (list "  br label %clDone" "clI:")
              (listAppend (bitWord "%bw" "%urb" "%cap" "%j")
                (listAppend (list "  %bwm = xor i64 %bw.bit, -1" "  %bwn = and i64 %bw.word, %bwm" "  store i64 %bwn, ptr %bw")
                  (listAppend (valueField "%iv" "%u" "%j")
                    (listAppend (store "%iv" "{ i64 2, i64 0 }") (list "  br label %clDone" "clDone:")))))))))))))))))

; (:m :ref INTHASHMAP :do "move slot from over slot to (whose key and value are dropped) and leave from vacant without dropping what moved")
fn moveBody ps: (List Param) -> (List String)
  (writeBody ps (intArg (param ps 1) "%j") true
    (listAppend (list (intArg (param ps 2) "%to") "  %toIn = icmp ult i64 %to, %cap" "  br i1 %toIn, label %moveOk, label %outside" "moveOk:"
                      "  %mvPair = icmp eq i64 %mode, 3" "  br i1 %mvPair, label %mvP, label %mvN" "mvP:")
    (listAppend (pairWord "%pf" "%urb3" "%j") (listAppend (pairWord "%pt" "%urb3" "%to")
    (listAppend (list "  %pfk = load i64, ptr %pf" "  %pfv = load i64, ptr %pf.v" "  store i64 %pfk, ptr %pt" "  store i64 %pfv, ptr %pt.v")
    (listAppend (pairBit "%qt" "%urb3" "%cap" "%to")
    (listAppend (list "  %qtn = or i64 %qt.word, %qt.bit" "  store i64 %qtn, ptr %qt")
    (listAppend (pairBit "%qf" "%urb3" "%cap" "%j")
    (listAppend (list "  %qfm = xor i64 %qf.bit, -1" "  %qfn = and i64 %qf.word, %qfm" "  store i64 %qfn, ptr %qf" "  ret %Val %uv" "mvN:"
                      "  %mvInt = icmp eq i64 %mode, 2" "  br i1 %mvInt, label %mvI, label %mvG" "mvG:")
      (listAppend (slotField "%fh" "%u" "%j" 0) (listAppend (slotField "%fk" "%u" "%j" 1) (listAppend (slotField "%fv" "%u" "%j" 2)
        (listAppend (slotField "%th" "%u" "%to" 0) (listAppend (slotField "%tk" "%u" "%to" 1) (listAppend (slotField "%tv" "%u" "%to" 2)
          (listAppend
            (list "  %mh = load %Val, ptr %fh" "  %mk = load %Val, ptr %fk" "  %mv = load %Val, ptr %fv"
                  "  %ok0 = load %Val, ptr %tk" "  %ov0 = load %Val, ptr %tv"
                  "  store %Val %mh, ptr %th" "  store %Val %mk, ptr %tk" "  store %Val %mv, ptr %tv"
                  "  store %Val { i64 2, i64 0 }, ptr %fh" "  store %Val { i64 2, i64 0 }, ptr %fk" "  store %Val { i64 2, i64 0 }, ptr %fv"
                  "  %okd = call tailcc i64 @aslRcDrop(%Val %ok0)" "  %ovd = call tailcc i64 @aslRcDrop(%Val %ov0)"
                  "  br label %mvDone" "mvI:")
            (listAppend (keyWord "%rkf" "%urb" "%j") (listAppend (keyWord "%rkt" "%urb" "%to")
              (listAppend (list "  %rkv = load i64, ptr %rkf" "  store i64 %rkv, ptr %rkt")
                (listAppend (bitWord "%bt" "%urb" "%cap" "%to")
                  (listAppend (list "  %btn = or i64 %bt.word, %bt.bit" "  store i64 %btn, ptr %bt")
                    (listAppend (bitWord "%bf" "%urb" "%cap" "%j")
                      (listAppend (list "  %bfm = xor i64 %bf.bit, -1" "  %bfn = and i64 %bf.word, %bfm" "  store i64 %bfn, ptr %bf")
                        (listAppend (valueField "%ivf" "%u" "%j") (listAppend (valueField "%ivt" "%u" "%to")
                          (list "  %imv = load %Val, ptr %ivf" "  %iov = load %Val, ptr %ivt"
                                "  store %Val %imv, ptr %ivt" "  store %Val { i64 2, i64 0 }, ptr %ivf"
                                "  %iovd = call tailcc i64 @aslRcDrop(%Val %iov)"
                                "  br label %mvDone" "mvDone:"))))))))))))))))))))))))))

; (:m :ref INTHASHMAP :do "the probe: general mode compares the stored hashes (0 = vacant ends the probe) and then the key, two Int64 by icmp, else opsrt.eq; raw mode tests the key tag and compares the key payloads; a pending map answers the home slot; map and key are only read")
fn findBody ps: (List Param) ret: String -> (List String)
  (let [(k (param ps 2).name)]
    (listAppend (mapHead (param ps 0).name)
      (listAppend
        (list (intArg (param ps 1) "%h") (intArg (param ps 3) "%j0") "  %mask = sub i64 %cap, 1"
              (str "  %kt0 = extractvalue %Val " k ", 0") "  %kt = and i64 %kt0, 4294967295" (str "  %kb = extractvalue %Val " k ", 1")
              "  %kint = icmp eq i64 %kt, 2"
              "  switch i64 %mode, label %fpend [ i64 1, label %gen i64 2, label %int i64 3, label %pair ]"
              "fpend:"
              "  br label %out"
              "gen:"
              "  br label %probe"
              "probe:"
              "  %j = phi i64 [ %j0, %gen ], [ %jn, %next ]")
        (listAppend (slotField "%hp" "%mo" "%j" 0)
          (listAppend
            (list "  %hpp = getelementptr inbounds i8, ptr %hp, i64 8" "  %sh = load i64, ptr %hpp"
                  "  %vacant = icmp eq i64 %sh, 0"
                  "  br i1 %vacant, label %found, label %hash"
                  "hash:"
                  "  %sameHash = icmp eq i64 %sh, %h"
                  "  br i1 %sameHash, label %key, label %next"
                  "key:"
                  "  %ekp = getelementptr inbounds i8, ptr %hp, i64 16" "  %ek = load %Val, ptr %ekp"
                  "  %ekt0 = extractvalue %Val %ek, 0" "  %ekt = and i64 %ekt0, 4294967295" "  %ekb = extractvalue %Val %ek, 1"
                  "  %ekInt = icmp eq i64 %ekt, 2" "  %ints = and i1 %kint, %ekInt"
                  "  br i1 %ints, label %intKey, label %anyKey"
                  "intKey:"
                  "  %sameInt = icmp eq i64 %ekb, %kb"
                  "  br i1 %sameInt, label %found, label %next"
                  "anyKey:"
                  (str "  %same = call i1 @opsrt.eq(%Val %ek, %Val " k ")")
                  "  br i1 %same, label %found, label %next"
                  "next:"
                  "  %jp = add i64 %j, 1" "  %jn = and i64 %jp, %mask"
                  "  br label %probe"
                  "found:"
                  "  br label %out"
                  "int:"
                  "  br i1 %kint, label %iprobe, label %vprobe"
                  "iprobe:"
                  "  %ij = phi i64 [ %j0, %int ], [ %ijn, %inext ]")
            (listAppend (bitWord "%ib" "%mrb" "%cap" "%ij")
              (listAppend (list "  br i1 %ib.set, label %ikey, label %ifound" "ikey:")
                (listAppend (keyWord "%ikp" "%mrb" "%ij")
                  (listAppend (list "  %ik = load i64, ptr %ikp" "  %isame = icmp eq i64 %ik, %kb"
                                    "  br i1 %isame, label %ifound, label %inext"
                                    "inext:" "  %ijp = add i64 %ij, 1" "  %ijn = and i64 %ijp, %mask" "  br label %iprobe"
                                    "ifound:" "  br label %out"
                                    "vprobe:" "  %vj = phi i64 [ %j0, %int ], [ %vjn, %vnext ]")
                    (listAppend (bitWord "%vb" "%mrb" "%cap" "%vj")
                      (listAppend (list "  br i1 %vb.set, label %vnext, label %vfound"
                                        "vnext:" "  %vjp = add i64 %vj, 1" "  %vjn = and i64 %vjp, %mask" "  br label %vprobe"
                                        "vfound:" "  br label %out"
                                        "pair:" "  br i1 %kint, label %pprobe, label %qprobe"
                                        "pprobe:" "  %pj = phi i64 [ %j0, %pair ], [ %pjn, %pnext ]")
                        (listAppend (pairBit "%pb" "%mrb3" "%cap" "%pj")
                        (listAppend (list "  br i1 %pb.set, label %pkey, label %pfound" "pkey:")
                        (listAppend (pairWord "%pk" "%mrb3" "%pj")
                        (listAppend (list "  %pkx = load i64, ptr %pk" "  %psame = icmp eq i64 %pkx, %kb" "  br i1 %psame, label %pfound, label %pnext"
                                          "pnext:" "  %pjp = add i64 %pj, 1" "  %pjn = and i64 %pjp, %mask" "  br label %pprobe"
                                          "pfound:" "  br label %out"
                                          "qprobe:" "  %qj = phi i64 [ %j0, %pair ], [ %qjn, %qnext ]")
                        (listAppend (pairBit "%qb" "%mrb3" "%cap" "%qj")
                        (listAppend (list "  br i1 %qb.set, label %qnext, label %qfound"
                                          "qnext:" "  %qjp = add i64 %qj, 1" "  %qjn = and i64 %qjp, %mask" "  br label %qprobe"
                                          "qfound:" "  br label %out"
                                          "out:" "  %res = phi i64 [ %j0, %fpend ], [ %j, %found ], [ %ij, %ifound ], [ %vj, %vfound ], [ %pj, %pfound ], [ %qj, %qfound ]")
                        (intRet ret "%res"))))))))))))))))))

; (:m :ref INTHASHMAP :do "growth in one native pass: at load above 3/4 a fresh table of the same mode and twice the capacity gets the count and every slot at its probe slot by its stored (general) or recomputed (raw) hash; a unique old map gives its keys and values up (fields cleared before its drop), a shared one keeps them and each moved boxed key and value is duplicated")
fn growBody ps: (List Param) id: Bool -> (List String)
  (let [(m (param ps 0).name)]
    (listAppend (mapHead m)
      (listAppend
        (list (intArg (param ps 1) "%n")
              "  %n4 = mul i64 %n, 4" "  %cap3 = mul i64 %cap, 3"
              "  %over = icmp sgt i64 %n4, %cap3" "  %hasTable = icmp ne i64 %mode, 0" "  %must = and i1 %over, %hasTable"
              "  br i1 %must, label %grow, label %keep"
              "keep:"
              (str "  ret %Val " m)
              "grow:"
              "  %oh = load i64, ptr %mo" "  %oc = lshr i64 %oh, 48" "  %oc8 = and i64 %oc, 255" "  %ounique = icmp eq i64 %oc8, 0"
              "  %oidp = getelementptr inbounds i8, ptr %mo, i64 8" "  %oid = load i32, ptr %oidp"
              "  %ncap = mul i64 %cap, 2" "  %nmask = sub i64 %ncap, 1")
        (listAppend (fresh "t" "%mode" "%ncap" "%n" "%oid")
          (listAppend
            (list "  %gPair = icmp eq i64 %mode, 3" "  br i1 %gPair, label %pmove, label %gsel" "gsel:"
                  "  %gInt = icmp eq i64 %mode, 2" "  br i1 %gInt, label %imove, label %gmove"
                  "gmove:" "  br label %gloop"
                  "gloop:" "  %gi = phi i64 [ 0, %gmove ], [ %gi1, %gnext ]" "  %gmore = icmp slt i64 %gi, %cap"
                  "  br i1 %gmore, label %gone, label %done"
                  "gone:")
            (listAppend (slotField "%gh" "%mo" "%gi" 0)
              (listAppend (list "  %ghp = getelementptr inbounds i8, ptr %gh, i64 8" "  %ghv = load i64, ptr %ghp" "  %gvac = icmp eq i64 %ghv, 0"
                                "  br i1 %gvac, label %gnext, label %gplace" "gplace:")
                (listAppend (slotField "%gk" "%mo" "%gi" 1) (listAppend (slotField "%gv" "%mo" "%gi" 2)
                  (listAppend (list "  %gkv = load %Val, ptr %gk" "  %gvv = load %Val, ptr %gv"
                                    "  %gh1 = lshr i64 %ghv, 1" "  %ghome = and i64 %gh1, %nmask" "  br label %gprobe"
                                    "gprobe:" "  %gj = phi i64 [ %ghome, %gplace ], [ %gjn, %gprobeNext ]")
                    (listAppend (slotField "%gth" "%t" "%gj" 0)
                      (listAppend (list "  %gthp = getelementptr inbounds i8, ptr %gth, i64 8" "  %gtv = load i64, ptr %gthp" "  %gfree = icmp eq i64 %gtv, 0"
                                        "  br i1 %gfree, label %gput, label %gprobeNext"
                                        "gprobeNext:" "  %gjp = add i64 %gj, 1" "  %gjn = and i64 %gjp, %nmask" "  br label %gprobe"
                                        "gput:" "  %ghval = insertvalue %Val { i64 2, i64 0 }, i64 %ghv, 1" "  store %Val %ghval, ptr %gth")
                        (listAppend (slotField "%gtk" "%t" "%gj" 1) (listAppend (slotField "%gtw" "%t" "%gj" 2)
                          (listAppend (list "  store %Val %gkv, ptr %gtk" "  store %Val %gvv, ptr %gtw"
                                            "  br i1 %ounique, label %ggive, label %gshare"
                                            "ggive:" "  store %Val { i64 2, i64 0 }, ptr %gk" "  store %Val { i64 2, i64 0 }, ptr %gv" "  br label %gnext"
                                            "gshare:" "  %gkd = call tailcc i64 @aslRcDup(%Val %gkv)" "  %gvd = call tailcc i64 @aslRcDup(%Val %gvv)" "  br label %gnext"
                                            "gnext:" "  %gi1 = add i64 %gi, 1" "  br label %gloop"
                                            "imove:" "  br label %iloop"
                                            "iloop:" "  %ii = phi i64 [ 0, %imove ], [ %ii1, %inext ]" "  %imore = icmp slt i64 %ii, %cap"
                                            "  br i1 %imore, label %ione, label %done"
                                            "ione:")
                            (listAppend (bitWord "%ib" "%mrb" "%cap" "%ii")
                              (listAppend (list "  br i1 %ib.set, label %iplace, label %inext" "iplace:")
                                (listAppend (keyWord "%ikp" "%mrb" "%ii")
                                  (listAppend (list "  %ikx = load i64, ptr %ikp")
                                    (listAppend (valueField "%iv" "%mo" "%ii")
                                      (listAppend (list "  %ivv = load %Val, ptr %iv")
                                        (listAppend (mix "%ih" "%ikx")
                                          (listAppend (list "  %ih1 = lshr i64 %ih, 1" "  %ihome = and i64 %ih1, %nmask" "  br label %iprobe"
                                                            "iprobe:" "  %ij = phi i64 [ %ihome, %iplace ], [ %ijn, %iprobeNext ]")
                                            (listAppend (bitWord "%tb" "%t.rb" "%ncap" "%ij")
                                              (listAppend (list "  br i1 %tb.set, label %iprobeNext, label %iput"
                                                                "iprobeNext:" "  %ijp = add i64 %ij, 1" "  %ijn = and i64 %ijp, %nmask" "  br label %iprobe"
                                                                "iput:" "  %tbn = or i64 %tb.word, %tb.bit" "  store i64 %tbn, ptr %tb")
                                                (listAppend (keyWord "%tkp" "%t.rb" "%ij")
                                                  (listAppend (list "  store i64 %ikx, ptr %tkp")
                                                    (listAppend (valueField "%tv" "%t" "%ij")
                                                      (listAppend (list "  store %Val %ivv, ptr %tv"
                                                            "  br i1 %ounique, label %igive, label %ishare"
                                                            "igive:" "  store %Val { i64 2, i64 0 }, ptr %iv" "  br label %inext"
                                                            "ishare:" "  %ivd = call tailcc i64 @aslRcDup(%Val %ivv)" "  br label %inext"
                                                            "inext:" "  %ii1 = add i64 %ii, 1" "  br label %iloop"
                                                            "pmove:" "  br label %ploop"
                                                            "ploop:" "  %pi = phi i64 [ 0, %pmove ], [ %pi1, %pnext ]" "  %pmore = icmp slt i64 %pi, %cap" "  br i1 %pmore, label %pone, label %done"
                                                            "pone:")
    (listAppend (pairBit "%pb" "%mrb3" "%cap" "%pi")
    (listAppend (list "  br i1 %pb.set, label %pplace, label %pnext" "pplace:")
    (listAppend (pairWord "%pw" "%mrb3" "%pi")
    (listAppend (list "  %pk = load i64, ptr %pw" "  %pv = load i64, ptr %pw.v")
    (listAppend (mix "%ph" "%pk")
    (listAppend (list "  %ph1 = lshr i64 %ph, 1" "  %phome = and i64 %ph1, %nmask" "  br label %pprobe"
                      "pprobe:" "  %pj = phi i64 [ %phome, %pplace ], [ %pjn, %pprobeNext ]")
    (listAppend (pairBit "%tq" "%t.rb3" "%ncap" "%pj")
    (listAppend (list "  br i1 %tq.set, label %pprobeNext, label %pput"
                      "pprobeNext:" "  %pjp = add i64 %pj, 1" "  %pjn = and i64 %pjp, %nmask" "  br label %pprobe"
                      "pput:" "  %tqn = or i64 %tq.word, %tq.bit" "  store i64 %tqn, ptr %tq")
    (listAppend (pairWord "%tw" "%t.rb3" "%pj")
    (list "  store i64 %pk, ptr %tw" "  store i64 %pv, ptr %tw.v" "  br label %pnext"
          "pnext:" "  %pi1 = add i64 %pi, 1" "  br label %ploop"
          "done:"
                                                            (str "  %od = call tailcc i64 @aslRcDrop(%Val " m ")")
                                                            "  ret %Val %t.v")))))))))))))))))))))))))))))))))))))))

fn bodyFor name: String ps: (List Param) ret: String id: Bool -> (List String)
  (cond
    ((= name "preludeHashNew") (newBody ps id))
    ((= name "preludeHashCapacity") (capacityBody ps ret))
    ((= name "preludeHashCountOf") (countBody ps ret))
    ((= name "preludeHashSetCount") (setCountBody ps))
    ((= name "preludeHashState") (stateBody ps ret))
    ((= name "preludeHashKeyAt") (keyBody ps))
    ((= name "preludeHashValueAt") (valueBody ps))
    ((= name "preludeHashPutEntry") (putEntryBody ps))
    ((= name "preludeHashPutValue") (putValueBody ps))
    ((= name "preludeHashClear") (clearBody ps))
    ((= name "preludeHashMoveSlot") (moveBody ps))
    ((= name "preludeHashFind") (findBody ps ret))
    (else (growBody ps id)))

; (:m :ref INTHASHMAP :do "the arity each native body expects; a compiled define with another count (a parameter past the fourth goes through the spill area) keeps its reference body")
fn arityOf name: String -> Int64
  (cond
    ((listContains? (list "preludeHashNew" "preludeHashCapacity" "preludeHashCountOf" "preludeHashKey") name) 1)
    ((listContains? (list "preludeHashSetCount" "preludeHashState" "preludeHashKeyAt" "preludeHashValueAt" "preludeHashClear" "preludeHashGrow") name) 2)
    ((listContains? (list "preludeHashPutValue" "preludeHashMoveSlot" "hashMapSet" "hashMapGetOr") name) 3)
    (else 4))

; (:m :ref INTHASHMAP :do "parameters started owned: the map of every write and of every prelude function that ends in one, the key and value of a pair write, so a unique caller hands its only reference down to the write")
fn ownedIndices name: String -> (List Int64)
  (cond
    ((= name "prelude.preludeHashPutEntry") (list 0 3))
    ((= name "prelude.preludeHashPutValue") (list 0 2))
    ((listContains? (list "prelude.hashMapSet" "prelude.hashMapGetOr") name) (list 0 1 2))
    ((listContains? (list "prelude.preludeHashSetCount" "prelude.preludeHashClear" "prelude.preludeHashMoveSlot" "prelude.preludeHashGrow" "prelude.hashMapRemove" "prelude.preludeHashShift") name) (list 0))
    (else (list)))

; (:m :ref INTHASHMAP :do "hash of a key consistent with =: an Int64 by a Fibonacci multiply (the product rotated by 32, so the slot bits are its high half), a String by FNV-1a 64 over its bytes then the same multiply, a Keyword by its interned name id (the high half of its tag word, which is what = compares) then the same multiply, any other value by the reference body kept under the name preludeHashKey$ref; the result is odd and non-negative, as the reference's is")
fn hashBody ps: (List Param) ret: String refSym: String -> (List String)
  (let [(k (param ps 0).name)]
    (listAppend
      (list (str "  %kt = extractvalue %Val " k ", 0") "  %tag = and i64 %kt, 4294967295" (str "  %kb = extractvalue %Val " k ", 1")
            "  switch i64 %tag, label %other [ i64 2, label %mix i64 4, label %keyword i64 5, label %string ]"
            "keyword:"
            "  %kaux = lshr i64 %kt, 32"
            "  br label %mixed"
            "string:"
            "  %ko = inttoptr i64 %kb to ptr"
            "  %klp = getelementptr inbounds i8, ptr %ko, i64 8" "  %kl = load i64, ptr %klp"
            "  %kx = getelementptr inbounds i8, ptr %ko, i64 16"
            "  br label %fnv"
            "fnv:"
            "  %fi = phi i64 [ 0, %string ], [ %fi1, %fnvStep ]"
            "  %fh = phi i64 [ -3750763034362895579, %string ], [ %fh2, %fnvStep ]"
            "  %fmore = icmp ult i64 %fi, %kl"
            "  br i1 %fmore, label %fnvStep, label %mixed"
            "fnvStep:"
            "  %fbp = getelementptr inbounds i8, ptr %kx, i64 %fi" "  %fb8 = load i8, ptr %fbp" "  %fb = zext i8 %fb8 to i64"
            "  %fh1 = xor i64 %fh, %fb" "  %fh2 = mul i64 %fh1, 1099511628211"
            "  %fi1 = add i64 %fi, 1"
            "  br label %fnv"
            "mix:"
            "  br label %mixed"
            "mixed:"
            "  %x = phi i64 [ %kb, %mix ], [ %fh, %fnv ], [ %kaux, %keyword ]"
            "  %m1 = mul i64 %x, -7046029254386353131"
            "  %m2 = lshr i64 %m1, 32" "  %m2b = shl i64 %m1, 32" "  %m3 = or i64 %m2, %m2b"
            "  %m4 = and i64 %m3, 4611686018427387903" "  %h = or i64 %m4, 1")
      (listAppend (intRet ret "%h")
        (list "other:"
              (str "  %r = call " (if (= ret "i64") "i64" "%Val") " " refSym "(%Val " k ")")
              (str "  ret " (if (= ret "i64") "i64" "%Val") " %r")))))

; (:m :ref INTHASHMAP :do "the header keeps its attributes but loses a personality or prefix data it may carry; the body opens with entry: since the fill loop phis name it")
fn defineText header: String body: (List String) -> String
  (str (beforeFirst header "{") "{\nentry:\n" (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) body)) "\n}\n")

fn replaceChunk chunk: String name: String id: Bool -> String
  (match (chunkOf chunk)
    ((none) chunk)
    ((some c)
      (let [(given (paramsOf c.header name)) (ret (retOf c.header name)) (ps (renamed given)) (header (headerWith c.header name ps))]
        (cond
          ((!= (listLength given) (arityOf name)) chunk)
          ((and (listContains? (list "hashMapSet" "hashMapGetOr") name) (or (!= ret "%Val") (listAny? (fn [(p Param)] -> Bool (!= p.ty "%Val")) given))) chunk)
          ((listContains? (refNames) name)
          (let [(refName (str "@prelude$2E" name "$ref("))
                (refHeader (stringReplace c.header (mangled name) refName))
                (refSym (beforeFirst refName "("))]
            (str (defineText header (refBody name ps ret refSym)) "\ndefine " (stringReplace chunk c.header refHeader))))
          (else (str (defineText header (bodyFor name ps ret id)) c.rest))))))

fn targetOf chunk: String names: (List String) -> (Option String)
  (let [(header (beforeFirst chunk "\n"))]
    (listFind (fn [(n String)] -> Bool (stringContains? header (mangled n))) names))

; (:m :ref INTHASHMAP :do "one split on define boundaries only when a target body is present, so a program without HashMap pays one substring scan per name and keeps its text byte for byte")
fn hashSplice text: String notrace: Bool -> String
  (let [(id (stringContains? text "@ctorId.preludeHashOf = "))
        (names (if notrace (cons (hashKeyName) (slotsNames)) (list (hashKeyName))))
        (present (filter (fn [(n String)] -> Bool (stringContains? text (mangled n))) names))]
    (if (listEmpty? present) text
      (let [(chunks (stringSplit text "\ndefine "))]
        (stringJoin (cons (optionOr (listHead chunks) "")
                          (map (fn [(c String)] -> String
                                 (match (targetOf c present)
                                   ((some n) (replaceChunk c n id))
                                   ((none) c)))
                               (optionOr (listTail chunks) (list))))
                    "\ndefine "))))

fn ownedFlags name: String flags: (List Bool) -> (List Bool)
  (let [(owned (ownedIndices name))]
    (if (listEmpty? owned) flags
      (map (fn [(p (Pair Int64 Bool))] -> Bool (and (pairSecond p) (not (listContains? owned (pairFirst p))))) (enumerate flags))))

; (:m :ref INTHASHMAP :do "the parameters are renamed %hashArg0.. in the rebuilt define line, so no native local can collide with a compiled parameter name such as %n")
fn renamed ps: (List Param) -> (List Param)
  (map (fn [(p (Pair Int64 Param))] -> Param (Param :ty (pairSecond p).ty :name (str "%hashArg" (pairFirst p)))) (enumerate ps))

fn headerWith header: String name: String ps: (List Param) -> String
  (let [(head (beforeFirst header (mangled name)))
        (tail (optionOr (afterFirst (optionOr (afterFirst header (mangled name)) "") ")") ""))]
    (str head (mangled name) (stringJoin (map (fn [(p Param)] -> String (str p.ty " " p.name)) ps) ", ") ")" tail))


; (:m :ref INTHASHMAP :do "the functions spliced with a native fast path in front of their compiled reference body, which stays under the name with $ref and takes every case the fast path does not")
fn refNames -> (List String)
  (list (hashKeyName) "hashMapSet" "hashMapGetOr")

fn argList ps: (List Param) -> String
  (stringJoin (map (fn [(p Param)] -> String (str p.ty " " p.name)) ps) ", ")

; (:m :ref INTHASHMAP :do "the key test and map head shared by the fused set and get")
fn fusedHead ps: (List Param) -> (List String)
  (let [(m (param ps 0).name) (k (param ps 1).name)]
    (list (str "  %kt0 = extractvalue %Val " k ", 0") "  %kt = and i64 %kt0, 4294967295" (str "  %kb = extractvalue %Val " k ", 1") "  %kInt = icmp eq i64 %kt, 2"
          (str "  %mw = extractvalue %Val " m ", 1") "  %mo = inttoptr i64 %mw to ptr"
          "  %mip = getelementptr inbounds i8, ptr %mo, i64 40" "  %info = load i64, ptr %mip"
          "  %cap = lshr i64 %info, 2" "  %mode = and i64 %info, 3" "  %mask = sub i64 %cap, 1"
          "  %isRaw = icmp eq i64 %mode, 2" "  %isPair = icmp eq i64 %mode, 3" "  %isPend = icmp eq i64 %mode, 0"))

fn slowCall ps: (List Param) ret: String refSym: String -> (List String)
  (list "slow:" (str "  %r = tail call tailcc " ret " " refSym "(" (argList ps) ")") (str "  ret " ret " %r"))

; (:m :ref INTHASHMAP :do "the raw-mode (2) probe from the home slot of %kb in %mo: %vp is the value field of the slot, branching to rawHit on the key and rawVacant on the first vacant slot")
fn rawProbe -> (List String)
  (listAppend (mix "%h" "%kb")
    (list "  %h1 = lshr i64 %h, 1" "  %j0 = and i64 %h1, %mask" "  br label %probe"
          "probe:" "  %j = phi i64 [ %j0, %raw ], [ %jn, %next ]"
          "  %ko0 = shl i64 %j, 5" "  %ko = add i64 %ko0, 48" "  %kp = getelementptr inbounds i8, ptr %mo, i64 %ko"
          "  %kw = load i64, ptr %kp" "  %kwt = and i64 %kw, 2" "  %occ = icmp ne i64 %kwt, 0"
          "  %kpp = getelementptr inbounds i8, ptr %kp, i64 8" "  %vp = getelementptr inbounds i8, ptr %kp, i64 16"
          "  br i1 %occ, label %cmp, label %rawVacant"
          "cmp:" "  %ek = load i64, ptr %kpp" "  %same = icmp eq i64 %ek, %kb" "  br i1 %same, label %rawHit, label %next"
          "next:" "  %jp = add i64 %j, 1" "  %jn = and i64 %jp, %mask" "  br label %probe"))

; (:m :ref INTHASHMAP :do "the pair-mode (3) probe from the home slot of %kb in the table at %po: %pv points at the value word, branching to pairHit on the key and pairVacant on the first vacant slot, whose bitmap word is %pb")
fn pairProbe from: String -> (List String)
  (listAppend (mix "%ph" "%kb")
    (listAppend (list "  %prb = getelementptr inbounds i8, ptr %po, i64 48" "  %ph1 = lshr i64 %ph, 1" "  %pj0 = and i64 %ph1, %mask" "  br label %pprobe"
                      "pprobe:" (str "  %pj = phi i64 [ %pj0, " from " ], [ %pjn, %pnext ]"))
      (listAppend (pairBit "%pb" "%prb" "%cap" "%pj")
        (listAppend (pairWord "%pk" "%prb" "%pj")
          (list "  br i1 %pb.set, label %pcmp, label %pairVacant"
                "pcmp:" "  %pkx = load i64, ptr %pk" "  %psame = icmp eq i64 %pkx, %kb" "  br i1 %psame, label %pairHit, label %pnext"
                "pnext:" "  %pjp = add i64 %pj, 1" "  %pjn = and i64 %pjp, %mask" "  br label %pprobe")))))

; (:m :ref INTHASHMAP :do "hashMapSet fused for a unique map with room for one more key: raw mode (Int64 keys) and pair mode (Int64 keys and values) probe and write in place, a pending map with an Int64 key and value becomes a pair-mode table; a shared map, a full one or any other case goes to the reference, which copies and grows")
fn setFastBody ps: (List Param) ret: String refSym: String -> (List String)
  (let [(m (param ps 0).name) (v (param ps 2).name)]
    (listAppend (fusedHead ps)
      (listAppend
        (list (str "  %vt0 = extractvalue %Val " v ", 0") "  %vt = and i64 %vt0, 4294967295" (str "  %vb = extractvalue %Val " v ", 1") "  %vInt = icmp eq i64 %vt, 2"
              "  %h0 = load i64, ptr %mo" "  %c48 = lshr i64 %h0, 48" "  %c8 = and i64 %c48, 255" "  %uniq = icmp eq i64 %c8, 0"
              "  %cnp = getelementptr inbounds i8, ptr %mo, i64 24" "  %cnt = load i64, ptr %cnp"
              "  %n1 = add i64 %cnt, 1" "  %n4 = shl i64 %n1, 2" "  %c3 = mul i64 %cap, 3" "  %room = icmp sle i64 %n4, %c3"
              "  %ok0 = and i1 %uniq, %room" "  %ok1 = and i1 %ok0, %kInt" "  %kv = and i1 %kInt, %vInt" "  %ok3 = and i1 %ok0, %kv"
              "  %f2 = and i1 %ok1, %isRaw" "  %f3 = and i1 %ok3, %isPair" "  %pr = and i1 %kv, %room" "  %mk = and i1 %pr, %isPend"
              "  br i1 %f2, label %raw, label %chk3"
              "chk3:" "  br i1 %f3, label %pairGo, label %chkMk"
              "chkMk:" "  br i1 %mk, label %make, label %slow")
        (listAppend (slowCall ps ret refSym)
          (listAppend (list "raw:" (nativeMarker))
            (listAppend (rawProbe)
              (listAppend
                (list "rawHit:"
                      "  %old = load %Val, ptr %vp" (str "  store %Val " v ", ptr %vp") "  %oldDrop = call tailcc i64 @aslRcDrop(%Val %old)"
                      (str "  ret %Val " m)
                      "rawVacant:"
                      "  store i64 2, ptr %kp" "  store i64 %kb, ptr %kpp"
                      (str "  store %Val " v ", ptr %vp")
                      "  store i64 %n1, ptr %cnp"
                      (str "  ret %Val " m)
                      "make:"
                      "  %oidp = getelementptr inbounds i8, ptr %mo, i64 8" "  %oid = load i32, ptr %oidp")
                (listAppend (fresh "t" "3" "%cap" "0" "%oid")
                  (listAppend
                    (list (str "  %pdrop = call tailcc i64 @aslRcDrop(%Val " m ")") "  br label %pairGo"
                          "pairGo:"
                          "  %po = phi ptr [ %mo, %chk3 ], [ %t, %t.zeroed ]"
                          (str "  %pval = phi %Val [ " m ", %chk3 ], [ %t.v, %t.zeroed ]")
                          "  %pc = phi i64 [ %n1, %chk3 ], [ 1, %t.zeroed ]")
                    (listAppend (pairProbe "%pairGo")
                      (list "pairHit:"
                            "  store i64 %vb, ptr %pk.v" "  ret %Val %pval"
                            "pairVacant:"
                            "  store i64 %kb, ptr %pk" "  store i64 %vb, ptr %pk.v"
                            "  %pbn = or i64 %pb.word, %pb.bit" "  store i64 %pbn, ptr %pb"
                            "  %pcp = getelementptr inbounds i8, ptr %po, i64 24" "  store i64 %pc, ptr %pcp"
                            "  ret %Val %pval")))))))))))

; (:m :ref INTHASHMAP :do "hashMapGetOr fused for an Int64 key on a raw-mode or pair-mode map: a hit returns the value (duplicated, or boxed from its word) and drops the default, a miss returns the default; the map is dropped either way (it is owned)")
fn getOrFastBody ps: (List Param) ret: String refSym: String -> (List String)
  (let [(m (param ps 0).name) (d (param ps 2).name)]
    (listAppend (fusedHead ps)
      (listAppend
        (list "  %g2 = and i1 %kInt, %isRaw" "  %g3 = and i1 %kInt, %isPair"
              "  br i1 %g2, label %raw, label %chk3"
              "chk3:" "  br i1 %g3, label %pair, label %slow")
        (listAppend (slowCall ps ret refSym)
          (listAppend (list "raw:")
            (listAppend (rawProbe)
              (listAppend
                (list "rawHit:"
                      "  %v = load %Val, ptr %vp" "  %vd = call tailcc i64 @aslRcDup(%Val %v)"
                      (str "  %dd = call tailcc i64 @aslRcDrop(%Val " d ")")
                      (str "  %md = call tailcc i64 @aslRcDrop(%Val " m ")")
                      "  ret %Val %v"
                      "rawVacant:"
                      (str "  %mv = call tailcc i64 @aslRcDrop(%Val " m ")")
                      (str "  ret %Val " d)
                      "pair:"
                      "  %po = getelementptr inbounds i8, ptr %mo, i64 0")
                (listAppend (pairProbe "%pair")
                  (list "pairHit:"
                        "  %pvx = load i64, ptr %pk.v" "  %pvv = insertvalue %Val { i64 2, i64 0 }, i64 %pvx, 1"
                        (str "  %pdd = call tailcc i64 @aslRcDrop(%Val " d ")")
                        (str "  %pmd = call tailcc i64 @aslRcDrop(%Val " m ")")
                        "  ret %Val %pvv"
                        "pairVacant:"
                        (str "  %pmv = call tailcc i64 @aslRcDrop(%Val " m ")")
                        (str "  ret %Val " d))))))))))

fn refBody name: String ps: (List Param) ret: String refSym: String -> (List String)
  (cond
    ((= name "hashMapSet") (setFastBody ps ret refSym))
    ((= name "hashMapGetOr") (getOrFastBody ps ret refSym))
    (else (hashBody ps ret refSym)))
