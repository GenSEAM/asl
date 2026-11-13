(module aslSite/app/msg
  :x [Msg msgCode msgOf onClick]
  :i [(asl-html/html :a h)])

(enum Msg (:c boot [] "the module started; arg carries the visitor's stored and system theme") (:c toggleTheme [] "flip between dark and light") (:c copyBatch [] "copy the toolbelt batch line") (:c resetCopy [] "restore the copy labels") (:c unknown [] "a code this build does not know"))

fn msgCode m: Msg -> Int64
  (match m ((boot) 1) ((toggleTheme) 2) ((copyBatch) 4) ((resetCopy) 5) ((unknown) 0))

fn msgOf code: Int64 -> Msg
  (cond ((= code 1) (boot)) ((= code 2) (toggleTheme)) ((= code 4) (copyBatch)) ((= code 5) (resetCopy)) (else (unknown)))

fn onClick m: Msg -> h/Attr
  (h/attr "data-msg" (stringFromInt64 (msgCode m)))
