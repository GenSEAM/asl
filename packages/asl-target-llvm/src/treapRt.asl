(module asl-target-llvm/treapRt
  :x [treapSplice ownedFlags inPlaceMarker]
  :i [])

; (:m :ref MAPREUSE :do "in-place treap writes for the persistent Map under the untraced RC runtime: preludeTreeInsert, preludeTreeReplace, preludeTreeRemove and preludeTreeMerge get a native front whose compiled reference body stays under the name with $ref. A node whose count is 0 is held only by the caller, which owns it, so the front rewrites its child slot, value or rotation links in place with no reset, take or reuse; a shared or stuck node, or a leaf, goes to the reference, which copies, and duplicates the parts it keeps, so every node under a shared one is seen shared and copied too: a map with two live references keeps its old contents")

fn inPlaceMarker -> String
  "; treapRt in place"

fn lines xs: (List String) -> String
  (stringJoin xs "\n")

fn mangled name: String -> String
  (str "@prelude$2E" name "(")

fn refSym name: String -> String
  (str "@prelude$2E" name "$ref")

fn names -> (List String)
  (list "preludeTreeInsert" "preludeTreeReplace" "preludeTreeRemove" "preludeTreeMerge")

fn arityOf name: String -> Int64
  (if (or (= name "preludeTreeMerge") (= name "preludeTreeRemove")) 2 3)

; (:m :ref MAPREUSE :do "every parameter of a front is owned: a unique node is changed only when the callee holds the only reference, and a key or value it stores or passes on is consumed, as the reference bodies consume them")
fn ownedFlags name: String flags: (List Bool) -> (List Bool)
  (if (listContains? (map (fn [(n String)] -> String (str "prelude." n)) (names)) name)
    (map (fn [(f Bool)] -> Bool false) flags)
    flags)

fn beforeFirst s: String sep: String -> String
  (match (stringIndexOf s sep)
    ((none) s)
    ((some at) (optionOr (stringSlice s 0 at) s)))

fn afterFirst s: String sep: String -> String
  (match (stringIndexOf s sep)
    ((none) "")
    ((some at) (optionOr (stringSlice s (+ at (stringLength sep)) (stringLength s)) "")))

; (:m :ref MAPREUSE :do "a front replaces a define only when its header is the compiled tailcc %Val shape with every parameter a Val; any other shape keeps the reference alone")
fn shapeOk? header: String name: String -> Bool
  (let [(inside (beforeFirst (afterFirst header (mangled name)) ")"))
        (ps (stringSplit inside ","))]
    (and (stringContains? header (str "tailcc %Val " (mangled name)))
         (and (= (listLength ps) (arityOf name))
              (listAll? (fn [(p String)] -> Bool (stringStartsWith? (stringTrim p) "%Val ")) ps))))

fn argNames name: String -> (List String)
  (map (fn [(i Int64)] -> String (str "%treapArg" i)) (range 0 (arityOf name)))

fn headerOf header: String name: String -> String
  (str (beforeFirst header (mangled name)) (mangled name)
       (stringJoin (map (fn [(a String)] -> String (str "%Val " a)) (argNames name)) ", ") ") {")

fn argList as: (List String) -> String
  (stringJoin (map (fn [(a String)] -> String (str "%Val " a)) as) ", ")

fn self name: String as: (List String) -> String
  (str "call tailcc %Val " (mangled name) (argList as) ")")

fn slow name: String -> (List String)
  (list "slow:"
        (str "  %refR = tail call tailcc %Val " (refSym name) "(" (argList (argNames name)) ")")
        "  ret %Val %refR")

; (:m :ref MAPREUSE :do "p.o is the node of Val v (a ctor of five fields), branching to yes, else (a leaf or any other value) to no; p.u is set when its count is 0, so the caller holds the only reference; under ASan the header read is checked live")
fn nodeOf p: String v: String yes: String no: String -> (List String)
  (list (str "  " p ".t0 = extractvalue %Val " v ", 0")
        (str "  " p ".t = and i64 " p ".t0, 4294967295")
        (str "  " p ".isC = icmp eq i64 " p ".t, 8")
        (str "  br i1 " p ".isC, label %" (stringReplace p "%" "") ".obj, label %" no)
        (str (stringReplace p "%" "") ".obj:")
        (str "  " p ".w = extractvalue %Val " v ", 1")
        (str "  " p ".o = inttoptr i64 " p ".w to ptr")
        (str "  " p ".nz = icmp ne ptr " p ".o, null")
        (str "  br i1 " p ".nz, label %" (stringReplace p "%" "") ".head, label %" no)
        (str (stringReplace p "%" "") ".head:")
        (str "  " p ".h = load i64, ptr " p ".o")
        (str "  call void @aslRc.live(ptr " p ".o, i64 " p ".h)")
        (str "  " p ".c48 = lshr i64 " p ".h, 48")
        (str "  " p ".c8 = and i64 " p ".c48, 255")
        (str "  " p ".u = icmp eq i64 " p ".c8, 0")
        (str "  " p ".nbp = getelementptr inbounds i8, ptr " p ".o, i64 12")
        (str "  " p ".nb = load i32, ptr " p ".nbp")
        (str "  " p ".isN = icmp eq i32 " p ".nb, 5")
        (str "  br i1 " p ".isN, label %" yes ", label %" no))

fn slotAt d: String o: String i: Int64 -> String
  (str "  " d " = getelementptr inbounds i8, ptr " o ", i64 " (+ 16 (* 16 i)))

fn field d: String o: String i: Int64 -> (List String)
  (list (slotAt (str d "p") o i) (str "  " d " = load %Val, ptr " d "p"))

fn rankOf d: String o: String -> (List String)
  (list (slotAt (str d "p") o 2) (str "  " d "v = load %Val, ptr " d "p") (str "  " d " = extractvalue %Val " d "v, 1"))

; (:m :ref MAPREUSE :do "preludeAbove on raw ranks: r1 above r2 when greater, or equal with key k1 before k2")
fn above d: String r1: String k1: String r2: String k2: String -> (List String)
  (list (str "  " d ".gt = icmp sgt i64 " r1 ", " r2)
        (str "  " d ".eq = icmp eq i64 " r1 ", " r2)
        (str "  " d ".c = call i64 @treapRt.cmp(%Val " k1 ", %Val " k2 ")")
        (str "  " d ".lt = icmp slt i64 " d ".c, 0")
        (str "  " d ".tie = and i1 " d ".eq, " d ".lt")
        (str "  " d " = or i1 " d ".gt, " d ".tie"))

; (:m :ref MAPREUSE :do "the front of a write on one tree: a unique node goes on at own with its key compared to the argument key, anything else to the reference")
fn header3 -> (List String)
  (listAppend (nodeOf "%t" "%treapArg0" "node" "slow")
    (listAppend (list "node:" "  br i1 %t.u, label %own, label %slow" "own:" (inPlaceMarker))
      (listAppend (field "%nk" "%t.o" 0)
        (list "  %cmp = call i64 @treapRt.cmp(%Val %treapArg1, %Val %nk)"
              (slotAt "%lp" "%t.o" 3)
              (slotAt "%gp" "%t.o" 4)))))

; (:m :ref MAPREUSE :do "insert into a unique node: the child on the key's side is inserted into (owned, so its slot is overwritten after), then stored back, or rotated above the node in place when its rank is above: for the left side the reference builds (preludeNode ck cv cr cl (preludeNode nk nv r cg g)), so the node takes the child's slot 4 and the child's slot 4 takes the node; the right side mirrors it through slot 3; the child is the result of an insert, a node the reference built fresh or a unique one this front changed, so its count is 0 and a shared child traps (no program reaches it)")
fn side s: String slot: String at: Int64 -> (List String)
  (let [(c (str "%" s "2"))]
    (listAppend
      (list (str s ":")
            (str "  %" s "v = load %Val, ptr " slot)
            (str "  " c " = " (self "preludeTreeInsert" (list (str "%" s "v") "%treapArg1" "%treapArg2")))
            (str "  %" s ".cw = extractvalue %Val " c ", 1")
            (str "  %" s ".o = inttoptr i64 %" s ".cw to ptr"))
      (listAppend (rankOf (str "%" s ".cr") (str "%" s ".o"))
        (listAppend (field (str "%" s ".ck") (str "%" s ".o") 0)
          (listAppend (above (str "%" s ".up") (str "%" s ".cr") (str "%" s ".ck") "%r" "%nk")
            (listAppend
              (list (str "  br i1 %" s ".up, label %" s "Rot, label %" s "Keep")
                    (str s "Keep:")
                    (str "  store %Val " c ", ptr " slot)
                    "  ret %Val %treapArg0"
                    (str s "Rot:")
                    (str "  %" s ".h2 = load i64, ptr %" s ".o")
                    (str "  %" s ".c2 = lshr i64 %" s ".h2, 48")
                    (str "  %" s ".k2 = and i64 %" s ".c2, 255")
                    (str "  %" s ".u2 = icmp eq i64 %" s ".k2, 0")
                    (str "  br i1 %" s ".u2, label %" s "In, label %" s "Shared")
                    (str s "In:"))
              (listAppend (field (str "%" s ".x") (str "%" s ".o") at)
                (listAppend
                  (list (str "  store %Val %" s ".x, ptr " slot)
                        (str "  store %Val %treapArg0, ptr %" s ".xp")
                        (str "  ret %Val " c))
                  (list (str s "Shared:") "  call void @llvm.trap()" "  unreachable")))))))))

fn insertBody -> (List String)
  (listAppend (header3)
    (listAppend (rankOf "%r" "%t.o")
      (listAppend (list "  %goLeft = icmp slt i64 %cmp, 0" "  br i1 %goLeft, label %left, label %right")
        (listAppend (side "left" "%lp" 4)
          (listAppend (side "right" "%gp" 3) (slow "preludeTreeInsert"))))))

; (:m :ref MAPREUSE :do "replace in a unique node: the node holding the key takes the new key and value and drops the old ones, as the reference's (preludeNode k v r l g) does; above it the child slot takes the result in place")
fn replaceBody -> (List String)
  (listAppend (header3)
    (listAppend
      (list "  switch i64 %cmp, label %right [ i64 0, label %here i64 -1, label %left ]"
            "here:"
            "  store %Val %treapArg1, ptr %nkp")
      (listAppend (field "%nv" "%t.o" 1)
        (listAppend
          (list "  store %Val %treapArg2, ptr %nvp"
                "  %dk = call tailcc i64 @aslRcDrop(%Val %nk)"
                "  %dv = call tailcc i64 @aslRcDrop(%Val %nv)"
                "  ret %Val %treapArg0"
                "left:"
                "  %lv = load %Val, ptr %lp"
                (str "  %l2 = " (self "preludeTreeReplace" (list "%lv" "%treapArg1" "%treapArg2")))
                "  store %Val %l2, ptr %lp"
                "  ret %Val %treapArg0"
                "right:"
                "  %gv = load %Val, ptr %gp"
                (str "  %g2 = " (self "preludeTreeReplace" (list "%gv" "%treapArg1" "%treapArg2")))
                "  store %Val %g2, ptr %gp"
                "  ret %Val %treapArg0")
          (slow "preludeTreeReplace")))))

; (:m :ref MAPREUSE :do "remove from a unique node: the key's node gives its two kids to the merge, its kid slots are cleared to Unit and it is dropped, which frees it with its key and value, and the argument key is dropped as the reference drops it; above it the child slot takes the result in place")
fn removeBody -> (List String)
  (listAppend (header3)
    (listAppend
    (list "  switch i64 %cmp, label %right [ i64 0, label %here i64 -1, label %left ]"
          "here:"
          "  %lv0 = load %Val, ptr %lp"
          "  %gv0 = load %Val, ptr %gp"
          "  store %Val { i64 0, i64 0 }, ptr %lp"
          "  store %Val { i64 0, i64 0 }, ptr %gp"
          "  %dt = call tailcc i64 @aslRcDrop(%Val %treapArg0)"
          "  %dk = call tailcc i64 @aslRcDrop(%Val %treapArg1)"
          (str "  %m = " (self "preludeTreeMerge" (list "%lv0" "%gv0")))
          "  ret %Val %m"
          "left:"
          "  %lv = load %Val, ptr %lp"
          (str "  %l2 = " (self "preludeTreeRemove" (list "%lv" "%treapArg1")))
          "  store %Val %l2, ptr %lp"
          "  ret %Val %treapArg0"
          "right:"
          "  %gv = load %Val, ptr %gp"
          (str "  %g2 = " (self "preludeTreeRemove" (list "%gv" "%treapArg1")))
          "  store %Val %g2, ptr %gp"
          "  ret %Val %treapArg0")
      (slow "preludeTreeRemove")))

; (:m :ref MAPREUSE :do "merge of two owned trees: the one whose root is above keeps its root and takes the merge of the rest into its inner slot (a's slot 4, b's slot 3), in place when that root is unique; a leaf on either side, or a shared root that would change, goes to the reference")
fn mergeBody -> (List String)
  (listAppend (nodeOf "%a" "%treapArg0" "aNode" "slow")
    (listAppend (list "aNode:")
      (listAppend (nodeOf "%b" "%treapArg1" "bNode" "slow")
        (listAppend (list "bNode:")
          (listAppend (rankOf "%ar" "%a.o")
            (listAppend (field "%ak" "%a.o" 0)
              (listAppend (rankOf "%br" "%b.o")
                (listAppend (field "%bk" "%b.o" 0)
                  (listAppend (above "%aUp" "%ar" "%ak" "%br" "%bk")
                    (listAppend
                      (list "  br i1 %aUp, label %keepA, label %keepB"
                            "keepA:"
                            "  br i1 %a.u, label %inA, label %slow"
                            "inA:"
                            (inPlaceMarker)
                            (slotAt "%agp" "%a.o" 4)
                            "  %ag = load %Val, ptr %agp"
                            (str "  %am = " (self "preludeTreeMerge" (list "%ag" "%treapArg1")))
                            "  store %Val %am, ptr %agp"
                            "  ret %Val %treapArg0"
                            "keepB:"
                            "  br i1 %b.u, label %inB, label %slow"
                            "inB:"
                            (slotAt "%blp" "%b.o" 3)
                            "  %bl = load %Val, ptr %blp"
                            (str "  %bm = " (self "preludeTreeMerge" (list "%treapArg0" "%bl")))
                            "  store %Val %bm, ptr %blp"
                            "  ret %Val %treapArg1")
                      (slow "preludeTreeMerge")))))))))))

fn bodyFor name: String -> (List String)
  (cond
    ((= name "preludeTreeInsert") (insertBody))
    ((= name "preludeTreeReplace") (replaceBody))
    ((= name "preludeTreeRemove") (removeBody))
    (else (mergeBody)))

; (:m :ref MAPREUSE :do "the three-way key order of opsrt.keyCmp with the two-Int case inline")
fn cmpText -> String
  (lines (list "define internal i64 @treapRt.cmp(%Val %a, %Val %b) alwaysinline {"
               "entry:"
               "  %at0 = extractvalue %Val %a, 0"
               "  %at = trunc i64 %at0 to i32"
               "  %bt0 = extractvalue %Val %b, 0"
               "  %bt = trunc i64 %bt0 to i32"
               "  %ai = icmp eq i32 %at, 2"
               "  %bi = icmp eq i32 %bt, 2"
               "  %ints = and i1 %ai, %bi"
               "  br i1 %ints, label %int, label %other"
               "int:"
               "  %x = extractvalue %Val %a, 1"
               "  %y = extractvalue %Val %b, 1"
               "  %lt = icmp slt i64 %x, %y"
               "  %gt = icmp sgt i64 %x, %y"
               "  %up = zext i1 %gt to i64"
               "  %r = select i1 %lt, i64 -1, i64 %up"
               "  ret i64 %r"
               "other:"
               "  %c = call %Val @opsrt.keyCmp(%Val %a, %Val %b)"
               "  %cr = extractvalue %Val %c, 1"
               "  ret i64 %cr"
               "}"))

fn targetOf header: String -> (Option String)
  (listFind (fn [(n String)] -> Bool (stringContains? header (mangled n))) (names))

fn defineText header: String body: (List String) -> String
  (str header "\nentry:\n" (lines (filter (fn [(l String)] -> Bool (not (stringEmpty? l))) body)) "\n}\n")

fn spliceChunk chunk: String -> String
  (let [(header (beforeFirst chunk "\n"))]
    (match (targetOf header)
      ((none) chunk)
      ((some n)
        (if (not (shapeOk? header n)) chunk
          (str (defineText (headerOf header n) (bodyFor n))
               "\ndefine " (stringReplace chunk header (stringReplace header (mangled n) (str (refSym n) "("))))))))

; (:m :ref MAPREUSE :do "a front needs its compiled reference body, the RC runtime (aslRcDup, aslRcDrop, aslRc.live, present in every RC text) and opsrt.keyCmp in the same text; every present write gets its front, since the remove front calls the merge, which the reference remove calls too; a text without opsrt.keyCmp or with none of the names is returned unchanged, as is every text when the runtime is not the untraced one")
fn treapSplice text: String notrace: Bool -> String
  (let [(chunks (stringSplit text "\ndefine "))
        (headers (map (fn [(c String)] -> String (beforeFirst c "\n")) (optionOr (listTail chunks) (list))))
        (present (filter (fn [(n String)] -> Bool (listAny? (fn [(h String)] -> Bool (and (stringContains? h (mangled n)) (shapeOk? h n))) headers)) (names)))]
    (if (or (not notrace) (or (listEmpty? present) (not (stringContains? text "@opsrt.keyCmp(%Val %a, %Val %b) {"))))
      text
      (str (stringJoin (cons (optionOr (listHead chunks) "") (map spliceChunk (optionOr (listTail chunks) (list)))) "\ndefine ")
           "\n" (cmpText) "\n")))
