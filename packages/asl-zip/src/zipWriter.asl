(module asl-zip/zipWriter
  :x [ZipEntry zipArchive!]
  :i [(asl-zip/deflate :a df) (asl-zip/gzipWriter :a gw)])

(schema ZipEntry
  (:f name String)
  (:f data Bytes)
  (:f method Int64))

(schema EncodedEntry
  (:f name Bytes)
  (:f body Bytes)
  (:f plain Bytes)
  (:f method Int64)
  (:f crc Int64)
  (:f offset Int64))

fn set16! b: Bytes p: Int64 x: Int64 -> Unit
  (do
    (bytesSet b p (lowBits x 8))
    (bytesSet b (+ p 1) (lowBits (>> x 8) 8)))

fn set32! b: Bytes p: Int64 x: Int64 -> Unit
  (do
    (set16! b p x)
    (set16! b (+ p 2) (>> x 16)))

fn lowBits x: Int64 k: Int64 -> Int64
  (- x (<< (>> x k) k))

fn copy! dst: Bytes dp: Int64 src: Bytes sp: Int64 n: Int64 i: Int64 -> Unit
  (if (>= i n) ()
    (do
      (bytesSet dst (+ dp i) (bytesGet src (+ sp i)))
      (copy! dst dp src sp n (+ i 1))))

fn encodeEntries! entries: (List ZipEntry) level: Int64 pos: Int64 acc: (List EncodedEntry) -> (Result (List EncodedEntry) String)
  (if (listEmpty? entries)
    (ok (listReverse acc))
    (let [(entry (optionOr (listHead entries) (ZipEntry :name "" :data (bytesAlloc 0) :method 0)))
          (tail (optionOr (listTail entries) (list)))
          (name (stringToBytes entry.name))
          (plain entry.data)
          (method entry.method)
          (size (bytesLength plain))
          (nameSize (bytesLength name))]
      (cond
        ((or (< method 0) (> method 8) (and (!= method 0) (!= method 8))) (err "invalid zip method"))
        ((or (> nameSize 65535) (> size 4294967295) (> pos 4294967295)) (err "zip64Required"))
        ((= method 0)
          (encodeEntries! tail level (+ pos (+ 30 (+ nameSize size)))
            (cons (EncodedEntry :name name :body plain :plain plain :method 0 :crc (gw/crc32! plain) :offset pos) acc)))
        (else
          (match (df/deflateWithLevel! plain level)
            ((err e) (err e))
            ((ok body)
              (if (> (bytesLength body) 4294967295)
                (err "zip64Required")
                (encodeEntries! tail level (+ pos (+ 30 (+ nameSize (bytesLength body))))
                  (cons (EncodedEntry :name name :body body :plain plain :method 8 :crc (gw/crc32! plain) :offset pos) acc)))))))))

fn locals! out: Bytes entries: (List EncodedEntry) p: Int64 -> Int64
  (if (listEmpty? entries) p
    (let [(e (optionOr (listHead entries) (EncodedEntry :name (bytesAlloc 0) :body (bytesAlloc 0) :plain (bytesAlloc 0) :method 0 :crc 0 :offset 0)))
          (tail (optionOr (listTail entries) (list)))
          (name e.name)
          (body e.body)
          (plain e.plain)
          (nn (bytesLength name))
          (bn (bytesLength body))]
      (do
        (set32! out p 67324752)
        (set16! out (+ p 4) 20)
        (set16! out (+ p 6) 2048)
        (set16! out (+ p 8) e.method)
        (set16! out (+ p 10) 0)
        (set16! out (+ p 12) 33)
        (set32! out (+ p 14) e.crc)
        (set32! out (+ p 18) bn)
        (set32! out (+ p 22) (bytesLength plain))
        (set16! out (+ p 26) nn)
        (set16! out (+ p 28) 0)
        (copy! out (+ p 30) name 0 nn 0)
        (copy! out (+ p (+ 30 nn)) body 0 bn 0)
        (locals! out tail (+ p (+ 30 (+ nn bn)))))))

fn centrals! out: Bytes entries: (List EncodedEntry) p: Int64 -> Int64
  (if (listEmpty? entries) p
    (let [(e (optionOr (listHead entries) (EncodedEntry :name (bytesAlloc 0) :body (bytesAlloc 0) :plain (bytesAlloc 0) :method 0 :crc 0 :offset 0)))
          (tail (optionOr (listTail entries) (list)))
          (name e.name)
          (body e.body)
          (plain e.plain)
          (nn (bytesLength name))
          (bn (bytesLength body))]
      (do
        (set32! out p 33639248)
        (set16! out (+ p 4) 20)
        (set16! out (+ p 6) 20)
        (set16! out (+ p 8) 2048)
        (set16! out (+ p 10) e.method)
        (set16! out (+ p 12) 0)
        (set16! out (+ p 14) 33)
        (set32! out (+ p 16) e.crc)
        (set32! out (+ p 20) bn)
        (set32! out (+ p 24) (bytesLength plain))
        (set16! out (+ p 28) nn)
        (set16! out (+ p 30) 0)
        (set16! out (+ p 32) 0)
        (set16! out (+ p 34) 0)
        (set16! out (+ p 36) 0)
        (set32! out (+ p 38) 0)
        (set32! out (+ p 42) e.offset)
        (copy! out (+ p 46) name 0 nn 0)
        (centrals! out tail (+ p (+ 46 nn))))))

fn zipArchive! entries: (List ZipEntry) level: Int64 -> (Result Bytes String)
  (cond
    ((or (< level 0) (> level 9)) (err "invalid deflate level"))
    ((> (listLength entries) 65535) (err "zip64Required"))
    (else
      (match (encodeEntries! entries level 0 (list))
        ((err e) (err e))
        ((ok encoded)
          (let [(localsSize (fold (fn [(sum Int64) (e EncodedEntry)] -> Int64
                                    (+ sum (+ 30 (+ (bytesLength e.name) (bytesLength e.body))))) 0 encoded))
                (centralSize (fold (fn [(sum Int64) (e EncodedEntry)] -> Int64
                                      (+ sum (+ 46 (bytesLength e.name)))) 0 encoded))
                (total (+ (+ localsSize centralSize) 22))]
            (if (or (> localsSize 4294967295) (> centralSize 4294967295))
              (err "zip64Required")
              (let [(out (bytesAlloc total))
                    (cd (locals! out encoded 0))
                    (ce (centrals! out encoded cd))]
                (do
                  (set32! out ce 101010256)
                  (set16! out (+ ce 4) 0)
                  (set16! out (+ ce 6) 0)
                  (set16! out (+ ce 8) (listLength encoded))
                  (set16! out (+ ce 10) (listLength encoded))
                  (set32! out (+ ce 12) centralSize)
                  (set32! out (+ ce 16) cd)
                  (set16! out (+ ce 20) 0)
                  (ok out)))))))))
