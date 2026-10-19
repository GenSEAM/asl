(module asl-know/examples/aslZip :x [gunzipText! selfTest] :i [(asl-zip/gzip :a z) (asl-syntax/core/bytesText :a bt)])

fn ! gunzipText! data: Bytes -> String
  (mt (z/gunzip! data)
    ((err e) (str "error: " e))
    ((ok out) (stringTrim (bt/bytesToString out))))

fn ! selfTest -> Bool
  (mt (bytesFromBase64 "H4sIAAAAAAAAA8tIzcnJV0ivyizgAgA5fGNWCwAAAA==")
    ((err _) false)
    ((ok gz) (= (gunzipText! gz) "hello gzip")))
