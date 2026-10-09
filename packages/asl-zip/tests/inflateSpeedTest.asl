(module asl-zip/tests/inflateSpeedTest
  :x [runTests main]
  :i [(asl-zip/gzip :a gz)])

fn ! readAll path: String -> (Result Bytes String)
  (mt (fileSize path)
    ((err e) (err (str path ": " e)))
    ((ok n)
     (mt (fileReadRange path 0 n)
       ((ok b) (ok b))
       ((err e) (err (str path ": " e))))))

fn firstMismatch a: Bytes b: Bytes i: Int64 n: Int64 -> Int64
  (cond
    ((>= i n) (if (= (bytesLength a) (bytesLength b)) -1 n))
    ((!= (bytesGet a i) (bytesGet b i)) i)
    (else (firstMismatch a b (+ i 1) n)))

fn fixture name: String -> String
  (str "asl/packages/asl-zip/tests/fixtures/" name)

fn ! edgeOk! name: String plain: String -> String
  (mt (readAll (fixture name))
    ((err e) (str "unreadable " e))
    ((ok packed)
     (mt (readAll (fixture plain))
       ((err e) (str "unreadable " e))
       ((ok want)
        (mt (gz/gunzip! packed)
          ((err e) (str "err " e))
          ((ok got)
           (if (= (firstMismatch got want 0 (min (bytesLength got) (bytesLength want))) -1)
             (str "ok" (bytesLength got))
             "differs")))))))

fn ! edgeErr! name: String -> String
  (mt (readAll (fixture name))
    ((err e) (str "unreadable " e))
    ((ok packed)
     (mt (gz/gunzip! packed)
       ((err e) e)
       ((ok _) "ok"))))

fn ! main args: (List String) -> (Result Int64 String)
  (mt (envGet "INFLATE_SPEED_DIR")
    ((none) (err "INFLATE_SPEED_DIR is unset"))
    ((some dir)
     (mt (readAll (str dir "/input.txt.gz"))
       ((err e) (err e))
       ((ok packed)
        (mt (readAll (str dir "/reference.txt"))
          ((err e) (err e))
          ((ok want)
           (let [(t0 (monotonicNs))
                 (decoded (gz/gunzip! packed))
                 (t1 (monotonicNs))]
             (mt decoded
               ((err e) (err e))
               ((ok got)
                (do
                  (println (str "decoded=" (bytesLength got) " reference=" (bytesLength want)
                                " firstMismatch=" (firstMismatch got want 0 (min (bytesLength got) (bytesLength want)))
                                " decodeWallNs=" (- t1 t0)))
                  (println (str "edgeEmpty=" (edgeOk! "empty.txt.gz" "empty.txt")))
                  (println (str "edgeStored=" (edgeOk! "random_stored.bin.gz" "random_stored.bin")))
                  (println (str "edgeTruncated=" (edgeErr! "corrupt_truncated.gz")))
                  (println (str "edgeBadCrc=" (edgeErr! "corrupt_crc.gz")))
                  (ok 0)))))))))))

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn generator -> String
  "perl -e 'my $x=12345; sub r { $x=($x*1103515245+12345)%2147483648; return $x>>8 } my @s=qw(BTCUSDT ETHUSDT SOLUSDT BNBUSDT XRPUSDT ADAUSDT DOGEUSDT AVAXUSDT); open my $f, q{>:raw}, $ARGV[0] or die; my $n=0; my $t=1759700000000; while ($n<64000000) { $t+=r()%997; my $l=sprintf(q{%d,%s,%d.%04d,%d.%06d,%s,%d}.chr(10),$t,$s[r()%8],20000+r()%50000,r()%10000,r()%100,r()%1000000,(r()%2?q{buy}:q{sell}),r()%100000); print $f $l or die; $n+=length $l } close $f or die'"

fn cpuRunner -> String
  "perl -e 'my $p=fork; die unless defined $p; if (!$p) { exec @ARGV or exit 127 } waitpid($p,0); my @t=times; printf STDERR q{cpuSeconds=%.3f exit=%d}.chr(10), $t[2]+$t[3], $?>>8; exit($?>>8)'"

fn field text: String key: String -> String
  (mt (stringIndexOf text (str key "="))
    ((none) "")
    ((some at)
     (let [(from (+ at (+ (stringLength key) 1)))
           (rest (optionOr (stringSlice text from (stringLength text)) ""))
           (line (optionOr (listHead (stringSplit rest "\n")) ""))]
       (optionOr (listHead (stringSplit line " ")) ""))))

fn ! runTests -> Bool
  (let [(made (sh "mktemp -d /tmp/inflateSpeed.XXXXXX"))
        (dir (stringReplace made.stdout "\n" ""))
        (gen (sh (str (generator) " " dir "/plain.txt && /usr/bin/gzip -6 -c " dir "/plain.txt > " dir "/input.txt.gz && /usr/bin/gzip -dc " dir "/input.txt.gz > " dir "/reference.txt && rm " dir "/plain.txt && wc -c < " dir "/reference.txt")))
        (refBytes (optionOr (stringToInt64 (stringTrim gen.stdout)) 0))
        (built (sh (str "asl/host/out/asl-host run asl/packages/asl-compiler/src/asl1.asl build asl/packages/asl-zip/tests/inflateSpeedTest.asl -o " dir "/speed.ll")))
        (linked (sh (str "/usr/bin/clang -O2 -Wno-override-module -x ir " dir "/speed.ll -x none asl/host/out/libaslrt.a -lm -o " dir "/speed")))
        (run (sh (str "INFLATE_SPEED_DIR=" dir " " (cpuRunner) " " dir "/speed")))
        (load (sh "uptime"))
        (cleanup (sh (str "rm -rf " dir)))
        (cpu (optionOr (stringToFloat64 (field run.stderr "cpuSeconds")) 0.0))
        (mbps (if (> cpu 0.0) (/ (/ (int64ToFloat64 refBytes) 1000000.0) cpu) 0.0))]
    (do
      (assert (= made.exitCode 0) (str "mktemp makes the work directory: " made.stderr))
      (assert (= gen.exitCode 0) (str "fixture written, gzip -6 and gzip -dc ran: " gen.stderr))
      (assert (>= refBytes 10000000) (str "reference is at least 10 MB: " refBytes))
      (assert (= built.exitCode 0) (str "asl1 builds the native gate: " built.stdout built.stderr))
      (assert (= linked.exitCode 0) (str "clang -O2 links it against libaslrt.a: " linked.stderr))
      (assert (= run.exitCode 0) (str "native artifact exits 0: " run.stdout run.stderr))
      (assert (= (field run.stdout "decoded") (stringFromInt64 refBytes)) (str "decoded length is the gzip -dc length " refBytes ": " run.stdout))
      (assert (= (field run.stdout "firstMismatch") "-1") (str "decoded output equals gzip -dc output byte for byte: " run.stdout))
      (assert (= (field run.stdout "edgeEmpty") "ok0") (str "empty member decodes to 0 bytes natively: " run.stdout))
      (assert (= (field run.stdout "edgeStored") "ok2500") (str "stored-block member decodes to its 2500 bytes natively: " run.stdout))
      (assert (stringContains? run.stdout "edgeTruncated=error at offset") (str "truncated member is an Err with its offset natively: " run.stdout))
      (assert (stringContains? run.stdout ": truncated input") (str "truncated member reports truncated input: " run.stdout))
      (assert (stringContains? run.stdout "CRC mismatch") (str "bad CRC is an Err natively: " run.stdout))
      (assert (= cleanup.exitCode 0) (str "work directory removed: " cleanup.stderr))
      (assert (> cpu 0.0) (str "child CPU seconds parsed: " run.stderr))
      (println (str "inflateSpeed: " refBytes " bytes, cpuSeconds=" (stringFromFloat64 cpu) " mbps=" (stringFromFloat64 mbps) " " run.stdout " load: " load.stdout))
      (assert (>= mbps 50.0) (str "native gunzip at least 50 MB/s per CPU second, got " (stringFromFloat64 mbps)))
      true))
