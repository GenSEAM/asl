(module ws/asl/tools/obs/archive
  :x [octalText Member archiveDir indexPath readIndex! parseMember renderMember memberBytes! verify! extractText! tarHeader gzipLevel monthOf]
  :i [(ws/asl/tools/obs/sx :a sx)
      (asl-zip/gzip :a gz)])

; (:m :ref OBSCORPUS :do "archive layout: <home>/.asl/run/archive/YYYY-MM.tar.gz holds ustar members, each header, data and zero padding as its own gzip member (concatenated gzip is one valid gzip stream, so tar xzf reads it); index.asn has one row per member with the byte offset and length of its data member, so one member is read back with a ranged read and one gunzip, never the whole month")
(schema Member
  (:f archive String)
  (:f source String)
  (:f path String)
  (:f kind String)
  (:f month String)
  (:f bytes Int64)
  (:f sha String)
  (:f from String)
  (:f to String)
  (:f off Int64)
  (:f len Int64)
  (:f mt Int64))

fn gzipLevel -> Int64
  6

fn archiveDir home: String -> String
  (str home "/.asl/run/archive")

fn indexPath home: String -> String
  (str (archiveDir home) "/index.asn")

fn monthOf day: String -> String
  (optionOr (stringSlice day 0 7) day)

fn q t: String -> String
  (sx/quoteText t)

fn n v: Int64 -> String
  (stringFromInt64 v)

fn renderMember m: Member -> String
  (str "(:member :archive " (q m.archive) " :source " (q m.source) " :path " (q m.path) " :kind " (q m.kind) " :month " (q m.month)
       " :bytes " (n m.bytes) " :sha " (q m.sha) " :from " (q m.from) " :to " (q m.to) " :off " (n m.off) " :len " (n m.len) " :mt " (n m.mt) ")")

fn parseMember line: String -> Member
  (let [(f (sx/topFields line))
        (s (fn [(k String)] -> String (optionOr (sx/field f k) "")))]
    (Member :archive (s ":archive") :source (s ":source") :path (s ":path") :kind (s ":kind") :month (s ":month")
            :bytes (sx/intField f ":bytes") :sha (s ":sha") :from (s ":from") :to (s ":to")
            :off (sx/intField f ":off") :len (sx/intField f ":len") :mt (sx/intField f ":mt")))

fn readIndex! home: String -> (List Member)
  (map parseMember (filter (fn [(l String)] -> Bool (stringStartsWith? l "(:member ")) (stringLines (resultOr (fileReadString (indexPath home)) ""))))

fn octal v: Int64 width: Int64 -> String
  (let [(digits (octalDigits v (list)))
        (s (stringJoin digits ""))]
    (str (stringRepeat "0" (max 0 (- width (stringLength s)))) s))

fn octalText v: Int64 -> String
  (stringJoin (octalDigits v (list)) "")

fn octalDigits v: Int64 acc: (List String) -> (List String)
  (if (< v 8)
    (cons (stringFromInt64 v) acc)
    (octalDigits (/ v 8) (cons (stringFromInt64 (- v (* 8 (/ v 8)))) acc)))

fn putText! b: Bytes at: Int64 t: String -> Unit
  (let [(src (stringToBytes t))
        (_ (fold (fn [(u Unit) (i Int64)] -> Unit (bytesSet b (+ at i) (bytesGet src i))) () (range 0 (bytesLength src))))]
    ())

; (:m :ref OBSCORPUS :do "ustar header: name, mode 0644, size, mtime in seconds, regular file, checksum over the block with the checksum field as spaces")
fn tarHeader name: String size: Int64 mtimeSec: Int64 -> Bytes
  (let [(b (bytesAlloc 512))
        (_0 (fold (fn [(u Unit) (i Int64)] -> Unit (bytesSet b i 0)) () (range 0 512)))
        (_1 (putText! b 0 (clipName name)))
        (_2 (putText! b 100 "0000644"))
        (_3 (putText! b 108 "0000000"))
        (_4 (putText! b 116 "0000000"))
        (_5 (putText! b 124 (octal size 11)))
        (_6 (putText! b 136 (octal mtimeSec 11)))
        (_7 (fold (fn [(u Unit) (i Int64)] -> Unit (bytesSet b i 32)) () (range 148 156)))
        (_8 (bytesSet b 156 48))
        (_9 (putText! b 257 "ustar"))
        (_a (putText! b 263 "00"))
        (sum (fold (fn [(acc Int64) (i Int64)] -> Int64 (+ acc (bytesGet b i))) 0 (range 0 512)))
        (_b (putText! b 148 (octal sum 6)))
        (_c (bytesSet b 154 0))
        (_d (bytesSet b 155 32))]
    b)

fn clipName name: String -> String
  (if (> (stringLength name) 100) (optionOr (stringSlice name 0 100) name) name)

fn memberBytes! home: String m: Member -> (Result Bytes String)
  (match (fileReadRange (str (archiveDir home) "/" m.archive) m.off m.len)
    ((err e) (err e))
    ((ok z) (gz/gunzip! z)))

; (:m :do "a member verifies when its data member inflates to the recorded length and sha")
fn verify! home: String m: Member -> Bool
  (match (memberBytes! home m)
    ((err _) false)
    ((ok b) (and (= (bytesLength b) m.bytes) (= (bytesSha256 b) m.sha))))

; (:m :ref OBSCORPUS :do "no bytes-to-string builtin exists, so a member is written to a scratch file and read back as text, then the scratch file is removed")
fn extractText! home: String m: Member -> (Result String String)
  (match (memberBytes! home m)
    ((err e) (err e))
    ((ok b)
      (let [(tmp (str (archiveDir home) "/.extract-" (n (procSelf)) "-" (n (nowNs))))
            (w (fileWrite tmp b))
            (t (fileReadString tmp))
            (_ (pathRemove tmp))]
        t)))
