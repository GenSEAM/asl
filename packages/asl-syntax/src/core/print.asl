(module asl-syntax/core/print
  :x [printTreeString
      printTreeBytes!
      printTree!
      print
      printBytes!
      printNode]
  :i [(asl-syntax/core/source :a src)
      (asl-syntax/core/tree :a tr)])

fn collectLeafStringSlices text: String leaves: (List tr/Token) acc: (List String) -> (List String)
  (if (listEmpty? leaves)
    acc
    (let [(tok (optionOr (listHead leaves) (tr/Token :kind "" :start 0 :end 0)))
          (rest (optionOr (listTail leaves) (list)))
          (slice (optionOr (stringSlice text tok.start tok.end) ""))]
      (collectLeafStringSlices text rest (cons slice acc))))

fn printTreeString text: String root: tr/Node -> String
  (let [(leaves (tr/nodeLeaves root))
        (slicesRev (collectLeafStringSlices text leaves (list)))
        (slices (listReverse slicesRev))]
    (stringJoin slices ""))

fn copyLeafBytes! src: Bytes srcIdx: Int64 dst: Bytes dstIdx: Int64 count: Int64 -> Unit
  (if (<= count 0)
    ()
    (do
      (bytesSet dst dstIdx (bytesGet src srcIdx))
      (copyLeafBytes! src (+ srcIdx 1) dst (+ dstIdx 1) (- count 1))))

fn copyLeavesBytes! src: Bytes leaves: (List tr/Token) dst: Bytes dstOffset: Int64 -> Unit
  (if (listEmpty? leaves)
    ()
    (let [(tok (optionOr (listHead leaves) (tr/Token :kind "" :start 0 :end 0)))
          (rest (optionOr (listTail leaves) (list)))
          (s tok.start)
          (e tok.end)
          (len (- e s))]
      (do
        (copyLeafBytes! src s dst dstOffset len)
        (copyLeavesBytes! src rest dst (+ dstOffset len)))))

fn printTreeBytes! bs: Bytes root: tr/Node -> Bytes
  (let [(leaves (tr/nodeLeaves root))
        (totalLen (- root.end root.start))
        (out (bytesAlloc totalLen))]
    (copyLeavesBytes! bs leaves out 0)
    out)

fn printTree! s: src/Source root: tr/Node -> Bytes
  (printTreeBytes! (src/sourceBytes s) root)

fn print text: String root: tr/Node -> String
  (printTreeString text root)

fn printBytes! bs: Bytes root: tr/Node -> Bytes
  (printTreeBytes! bs root)

fn printNode root: tr/Node text: String -> String
  (printTreeString text root)
