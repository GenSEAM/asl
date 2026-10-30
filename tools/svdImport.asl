(module asl/tools/svdImport
  :x [parseSvd Peripheral Register Field findPeriph regKeys fieldKeysOf]
  :i [])

(schema Peripheral (:f name String) (:f baseAddress Int64) (:f derivedFrom (Option String)) (:f registers (List Register)))

(schema Register (:f name String) (:f addressOffset Int64) (:f size Int64) (:f resetValue Int64) (:f fields (List Field)))

(schema Field (:f name String) (:f bitOffset Int64) (:f bitWidth Int64))

(schema St
  (:f lines (List String)) (:f i Int64) (:f inComment Bool)
  (:f perOpen Bool) (:f perName String) (:f perBase Int64) (:f perDerived (Option String)) (:f perLine Int64)
  (:f regOpen Bool) (:f regName String) (:f regOff Int64) (:f regSize Int64) (:f regReset Int64) (:f regLine Int64)
  (:f fldOpen Bool) (:f fldName String) (:f fldOff Int64) (:f fldWidth Int64) (:f fldLine Int64)
  (:f regs (List Register)) (:f fields (List Field)) (:f periphs (List Peripheral)) (:f err (Option String)))

fn sliceFrom s: String i: Int64 -> String
  (optionOr (stringSlice s i (stringLength s)) "")

fn gtOf s: String -> Int64
  (optionOr (stringIndexOf s ">") (- 0 1))

fn tagOf s: String -> String
  (let [(gt (gtOf s))]
    (if (< gt 1) "" (optionOr (stringSlice s 1 gt) "")))

fn closeName s: String -> String
  (let [(gt (gtOf s))]
    (if (< gt 2) "" (optionOr (stringSlice s 2 gt) "")))

fn leafContent s: String -> (Option String)
  (let [(gt (gtOf s))]
    (if (< gt 0)
      (none)
      (match (stringIndexOf (sliceFrom s (+ gt 1)) "</")
        ((none) (none))
        ((some j) (some (optionOr (stringSlice s (+ gt 1) (+ gt 1 j)) ""))))))

fn hexDigit c: String -> Int64
  (match (stringIndexOf "0123456789ABCDEF" (stringUpper c))
    ((none) (- 0 1))
    ((some i) i))

fn hexVal s: String i: Int64 acc: Int64 -> (Option Int64)
  (if (>= i (stringLength s))
    (some acc)
    (let [(d (hexDigit (optionOr (stringSlice s i (+ i 1)) "")))]
      (if (< d 0) (none) (hexVal s (+ i 1) (+ (* acc 16) d)))))

fn parseNum s: String -> (Option Int64)
  (if (stringStartsWith? s "0x")
    (hexVal s 2 0)
    (stringToInt64 s))

fn errAt st: St ln: Int64 msg: String -> St
  (with st :err (some (str "line " (stringFromInt64 ln) ": " msg)))

fn closeTag st: St name: String ln: Int64 -> St
  (cond
    ((= name "field")
      (if (not st.fldOpen)
        (errAt st ln "</field> without <field>")
        (with st :fldOpen false
              :fields (cons (Field :name st.fldName :bitOffset st.fldOff :bitWidth st.fldWidth) st.fields))))
    ((= name "register")
      (cond
        ((not st.regOpen) (errAt st ln "</register> without <register>"))
        (st.fldOpen (errAt st ln "<field> not closed before </register>"))
        (else (with st :regOpen false :fields (list)
                    :regs (cons (Register :name st.regName :addressOffset st.regOff :size st.regSize :resetValue st.regReset :fields (listReverse st.fields)) st.regs)))))
    ((= name "peripheral")
      (cond
        ((not st.perOpen) (errAt st ln "</peripheral> without <peripheral>"))
        (st.regOpen (errAt st ln "<register> not closed before </peripheral>"))
        ((stringEmpty? st.perName) (errAt st st.perLine "<peripheral> has no name"))
        (else (with st :perOpen false :regs (list)
                    :periphs (cons (Peripheral :name st.perName :baseAddress st.perBase :derivedFrom st.perDerived :registers (listReverse st.regs)) st.periphs)))))
    (else st))

fn openStart st: St tag: String ln: Int64 -> St
  (cond
    ((= tag "peripheral")
      (if st.perOpen
        (errAt st ln "nested <peripheral>")
        (with st :perOpen true :perName "" :perBase 0 :perDerived (none) :perLine ln :regs (list))))
    ((= tag "register")
      (cond
        ((not st.perOpen) (errAt st ln "<register> outside <peripheral>"))
        (st.regOpen (errAt st ln "nested <register>"))
        (else (with st :regOpen true :regName "" :regOff 0 :regSize 0 :regReset 0 :regLine ln
                    :fields (list) :fldOpen false :fldName "" :fldOff 0 :fldWidth 0))))
    ((= tag "field")
      (cond
        ((not st.regOpen) (errAt st ln "<field> outside <register>"))
        (st.fldOpen (errAt st ln "nested <field>"))
        (else (with st :fldOpen true :fldName "" :fldOff 0 :fldWidth 0 :fldLine ln))))
    (else st))

fn leafValue st: St tag: String content: String ln: Int64 -> St
  (cond
    ((= tag "name")
      (cond
        (st.fldOpen (with st :fldName content))
        (st.regOpen (with st :regName content))
        (st.perOpen (with st :perName content))
        (else st)))
    ((= tag "baseAddress")
      (if (not st.perOpen) st
        (match (parseNum content)
          ((none) (errAt st ln (str "bad number in <baseAddress>: " content)))
          ((some n) (with st :perBase n)))))
    ((= tag "derivedFrom")
      (if st.perOpen (with st :perDerived (some content)) st))
    ((= tag "addressOffset")
      (if (not st.regOpen) st
        (match (parseNum content)
          ((none) (errAt st ln (str "bad number in <addressOffset>: " content)))
          ((some n) (with st :regOff n)))))
    ((= tag "size")
      (if (not st.regOpen) st
        (match (parseNum content)
          ((none) (errAt st ln (str "bad number in <size>: " content)))
          ((some n) (with st :regSize n)))))
    ((= tag "resetValue")
      (if (not st.regOpen) st
        (match (parseNum content)
          ((none) (errAt st ln (str "bad number in <resetValue>: " content)))
          ((some n) (with st :regReset n)))))
    ((= tag "bitOffset")
      (if (not st.fldOpen) st
        (match (parseNum content)
          ((none) (errAt st ln (str "bad number in <bitOffset>: " content)))
          ((some n) (with st :fldOff n)))))
    ((= tag "bitWidth")
      (if (not st.fldOpen) st
        (match (parseNum content)
          ((none) (errAt st ln (str "bad number in <bitWidth>: " content)))
          ((some n) (with st :fldWidth n)))))
    (else st))

fn openTag st: St line: String ln: Int64 -> St
  (let [(gt (gtOf line))]
    (if (< gt 1)
      st
      (if (= (stringTrim (sliceFrom line (+ gt 1))) "/")
        st
        (match (leafContent line)
          ((none) (openStart st (tagOf line) ln))
          ((some c) (leafValue st (tagOf line) (stringTrim c) ln))))))

fn stepLine st: St line: String ln: Int64 -> St
  (cond
    ((stringEmpty? line) st)
    (st.inComment (if (stringContains? line "-->") (with st :inComment false) st))
    ((stringStartsWith? line "<!--") (if (stringContains? line "-->") st (with st :inComment true)))
    ((stringStartsWith? line "<?") st)
    ((stringStartsWith? line "</") (closeTag st (closeName line) ln))
    ((stringStartsWith? line "<") (openTag st line ln))
    (else st))

fn finish st: St -> St
  (cond
    ((some? st.err) st)
    (st.fldOpen (errAt st st.fldLine "<field> not closed"))
    (st.regOpen (errAt st st.regLine "<register> not closed"))
    (st.perOpen (errAt st st.perLine "<peripheral> not closed"))
    (else st))

fn scanLines st: St -> St
  (if (or (some? st.err) (>= st.i (listLength st.lines)))
    (finish st)
    (let [(ln (+ st.i 1))
          (line (stringTrim (optionOr (listGet st.lines st.i) "")))]
      (scanLines (stepLine (with st :i ln) line ln))))

fn initial xml: String -> St
  (St :lines (stringSplit xml "\n") :i 0 :inComment false
      :perOpen false :perName "" :perBase 0 :perDerived (none) :perLine 0
      :regOpen false :regName "" :regOff 0 :regSize 0 :regReset 0 :regLine 0
      :fldOpen false :fldName "" :fldOff 0 :fldWidth 0 :fldLine 0
      :regs (list) :fields (list) :periphs (list) :err (none))

fn findPeriph ps: (List Peripheral) name: String -> (Option Peripheral)
  (listHead (filter (fn [(p Peripheral)] -> Bool (= p.name name)) ps))

fn findReg regs: (List Register) name: String -> (Option Register)
  (listHead (filter (fn [(r Register)] -> Bool (= r.name name)) regs))

fn resolveOne p: Peripheral ps: (List Peripheral) -> Peripheral
  (match p.derivedFrom
    ((none) p)
    ((some base)
      (match (findPeriph ps base)
        ((none) p)
        ((some b) (with p :registers b.registers)))))

fn resolveDerived ps: (List Peripheral) -> (List Peripheral)
  (map (fn [(p Peripheral)] -> Peripheral (resolveOne p ps)) ps)

fn parseSvd xml: String -> (Result (List Peripheral) String)
  (let [(st (scanLines (initial xml)))]
    (if (some? st.err)
      (err (optionOr st.err "parse error"))
      (ok (resolveDerived (listReverse st.periphs)))))

fn regKeys regs: (List Register) -> (List String)
  (map (fn [(r Register)] -> String (str r.name ":" (stringFromInt64 r.addressOffset) ":" (stringFromInt64 r.size))) regs)

fn fieldKeysOf regs: (List Register) regName: String -> (List String)
  (match (findReg regs regName)
    ((none) (list))
    ((some r) (map (fn [(f Field)] -> String (str f.name ":" (stringFromInt64 f.bitOffset) ":" (stringFromInt64 f.bitWidth))) r.fields)))
