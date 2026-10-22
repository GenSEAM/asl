(module asl-zip/tests/zipWriterTest
  :x [runTests]
  :i [(asl-zip/zipWriter :a zw) (asl-zip/gzipWriter :a gw) (asl-zip/gzip :a gz) (asl-tools/fleet/run :a run)])

fn ! sh! root: String argv: (List String) timeoutS: Int64 maxDesc: Int64 -> run/Done
  (run/runOneLimited (run/job argv root (run/childEnv (list))) (run/limits timeoutS maxDesc))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (made (sh! root (list "mktemp" "-d" "/tmp/asl_zip_writer_XXXXXX") 10 4))
        (tmp (stringTrim made.out))
        (unzip (sh! root (list "/bin/sh" "-c" "command -v unzip") 10 4))
        (repeat (stringToBytes "writer data writer data writer data writer data"))
        (archive (zw/zipArchive!
                   (list
                     (zw/ZipEntry :name "stored.txt" :data (stringToBytes "stored bytes") :method 0)
                     (zw/ZipEntry :name "compressed.txt" :data repeat :method 8)
                     (zw/ZipEntry :name "empty.txt" :data (bytesAlloc 0) :method 8)) 6))
        (gzip (gw/gzip! repeat 6))]
    (do
      (assert (and (= made.exit 0) (!= tmp "")) "temporary directory is created")
      (if (!= unzip.exit 0) (do (sh! root (list "rm" "-rf" tmp) 30 8) ()) ())
      (assert (= unzip.exit 0) "unzip must be installed; install unzip to run ZIP writer tests")
      (match archive
        ((err e) (do (assert false (str "ZIP writer returned error: " e)) false))
        ((ok bytes)
          (let [(writeResult (fileWrite (str tmp "/sample.zip") bytes))
                (testResult (sh! root (list "unzip" "-t" (str tmp "/sample.zip")) 60 8))
                (stdout testResult.out)]
            (do
              (assert (ok? writeResult) "archive bytes are written to the temporary file")
              (assert (= testResult.exit 0) (str "unzip -t accepts the generated archive: " stdout))
              (assert (stringContains? stdout "stored.txt") "unzip lists stored entry")
              (assert (stringContains? stdout "compressed.txt") "unzip lists deflated entry")
              (assert (stringContains? stdout "empty.txt") "unzip lists empty entry")
              true))))
      (match gzip
        ((err e) (do (assert false (str "gzip writer returned error: " e)) false))
        ((ok bytes)
          (let [(writeResult (fileWrite (str tmp "/sample.gz") bytes))
                (testResult (sh! root (list "gzip" "-t" (str tmp "/sample.gz")) 60 8))
                (decoded (gz/gunzip! bytes))]
            (do
              (assert (ok? writeResult) "gzip bytes are written to the temporary file")
              (assert (= testResult.exit 0) "gzip -t accepts the generated member")
              (match decoded
                ((err _) (assert false "gzip member is readable by the existing gzip reader"))
                ((ok plain) (assert (= (bytesSha256 plain) (bytesSha256 repeat)) "gzip writer output round-trips through existing reader")))
              true))))
      (sh! root (list "rm" "-rf" tmp) 30 8)
      true))
