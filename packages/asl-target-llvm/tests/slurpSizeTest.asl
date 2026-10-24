(module asl-target-llvm/tests/slurpSizeTest
  :x [runTests]
  :i [(asl-ir/types :a ty)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/ssa :a ssa)
      (asl-tools/fleet/run :a run)])

; (:m :ref SLURPSIZE :do "SLURPSIZE: fileSlurp fstats the fd and allocates st_size+1 once; the IR assert pins the fstat before the loop, the pipe/shrink cases keep the doubling fallback honest, and the peak-RSS bound (Darwin time -l) is the allocation-size evidence")

fn clang -> String
  "/usr/bin/clang -Wno-override-module"

fn lib -> String
  "asl/host/out/libaslrt.a"

fn ! sh cmd: String -> run/Done
  (run/runShell! cmd "." (run/childEnv (list)) (run/limits 120 64))

fn ! shellText cmd: String -> String
  (stringReplace (resultOr (run/shellOut cmd 10000) "") "\n" "")

fn ! hostTriple -> String
  (let [(k (shellText "uname -s"))
        (m (shellText "uname -m"))]
    (cond
      ((and (= k "Darwin") (= m "arm64")) "darwin-arm64")
      ((and (= k "Darwin") (= m "x86_64")) "darwin-x86_64")
      ((and (= k "Linux") (= m "x86_64")) "linux-x86_64")
      ((and (= k "Linux") (or (= m "aarch64") (= m "arm64"))) "linux-aarch64")
      (else "")))

fn ! hostFacts -> libc/TripleFacts
  (match (libc/libcFacts (hostTriple))
    ((some f) f)
    ((none) (do (assert false (str "no libc.asl row for triple " (hostTriple))) (libc/emptyTripleFacts))))

fn diagText ds: (List ty/IrDiag) -> String
  (stringJoin (map (fn [(d ty/IrDiag)] -> String (str d.code " " d.message)) ds) "; ")

fn progSource -> String
  (stringJoin (list
    "(module slurpProg :x [main] :i [])"
    ""
    "fn ! main args: (List String) -> (Result Unit String)"
    "  (match (fileReadBytes (optionOr (listGet args 0) \"\"))"
    "    ((err e) (err (str \"read: \" e)))"
    "    ((ok b) (match (fileWrite (optionOr (listGet args 1) \"\") b)"
    "              ((err e) (err (str \"write: \" e)))"
    "              ((ok _) (do (println (bytesLength b)) (ok ()))))))"
    "") "\n")

fn ! build work: String -> String
  (let [(preludeText (resultOr (fileReadString (lk/preludePath)) ""))]
    (match (lk/lowerSourceWith (progSource) preludeText)
      ((err ds) (do (assert false (str "lowerSourceWith: " (diagText ds))) ""))
      ((ok m)
        (match (llvm/emitLlvmProgramFor (hostFacts) m "main")
          ((err ds) (do (assert false (str "emitLlvmProgramFor: " (diagText ds))) ""))
          ((ok text)
            (do (assert (ok? (fileWrite (str work "/slurpProg.ll") text)) "slurpProg.ll written")
                (let [(out (sh (str (clang) " -x ir " work "/slurpProg.ll -x none " (lib) " -lm -o " work "/slurpProg")))]
                  (do (assert (= out.exit 0) (str "slurpProg links; " out.out)) text))))))))

fn slurpDefinition ll: String name: String -> String
  (let [(parts (stringSplit ll (str "define internal tailcc %Val @" (ssa/llvmName (str "asl-target-llvm/sysRoute." name)) "(")))
        (rest (optionOr (listGet parts 1) ""))]
    (optionOr (listHead (stringSplit rest "\ndefine ")) ""))

fn ! checkSlurp ll: String name: String -> Bool
  (let [(body (slurpDefinition ll name))
        (fstatAt (optionOr (stringIndexOf body "@fstat") -1))
        (loopAt (optionOr (stringIndexOf body "@read") -1))
        (reallocAt (optionOr (stringIndexOf body "@realloc") -1))]
    (do (assert (not (stringEmpty? body)) (str "IR defines the " name " wrapper"))
        (assert (stringContains? body "@fstat") (str name " calls fstat"))
        (assert (and (>= fstatAt 0) (< fstatAt loopAt)) (str name " calls fstat before its read loop"))
        (assert (>= reallocAt 0) (str name " keeps the realloc fallback for pipes and growth"))
        true))

fn ! checkIr ll: String -> Bool
  (do (checkSlurp ll "fileSlurpBytes")
      (assert (not (stringContains? ll "@stringToBytes")) "fileReadBytes builds Bytes in the slurp, no stringToBytes copy")
      true)

fn ! check label: String good: Bool -> Bool
  (do (assert good label) good)

; (:m :ref SLURPSIZE :do "each case: write the input with head -c from a seeded byte stream, run the built program under the fleet runner's timeout, byte-compare output with cmp")
fn ! fileCase work: String size: Int64 -> Bool
  (let [(inp (str work "/in" size))
        (outp (str work "/out" size))
        (gen (sh (str "perl -e 'srand(7); print join(\"\", map { chr(int(rand(256))) } 1.." size ")' > " inp)))
        (run1 (sh (str work "/slurpProg " inp " " outp " && cmp " inp " " outp)))]
    (do (assert (= gen.exit 0) (str "fixture " size " written"))
        (check (str "regular file " size " bytes read byte-identical, exit " run1.exit " " run1.out) (and (= run1.exit 0) (stringContains? run1.out (str size))))))

fn ! pipeCase work: String size: Int64 -> Bool
  (let [(inp (str work "/in" size))
        (outp (str work "/pipe" size))
        (r (sh (str "cat " inp " | " work "/slurpProg /dev/stdin " outp " && cmp " inp " " outp)))]
    (check (str "pipe " size " bytes read byte-identical, exit " r.exit " " r.out) (= r.exit 0)))

; (:m :ref SLURPSIZE :do "shrink between fstat and read: fd 0 is a regular file whose offset dd moved to byte 100, so fstat reports the full size and read returns size-100 bytes; macOS /dev/stdin shares the fd offset, Linux reopens it so the case is skipped there")
fn ! shrinkCase work: String -> Bool
  (if (= (shellText "uname -s") "Darwin")
    (let [(inp (str work "/in5000000"))
          (outp (str work "/shrunk"))
          (r (sh (str "( dd bs=100 count=1 of=/dev/null 2>/dev/null; " work "/slurpProg /dev/stdin " outp " ) < " inp " && tail -c +101 " inp " | cmp - " outp)))]
      (check (str "short read after fstat (shrink) is byte-identical, exit " r.exit " " r.out) (= r.exit 0)))
    true)

; (:m :ref SLURPSIZE :do "allocation-size evidence: peak RSS reading a 64 MiB file; base doubling realloc ends a 128 MiB buffer plus the text and Bytes copies, the sized read stays under the bound")
fn ! rssCase work: String -> Bool
  (if (= (shellText "uname -s") "Darwin")
    (let [(inp (str work "/inbig"))
          (g (sh (str "head -c 67108864 /dev/zero > " inp)))
          (r (sh (str "/usr/bin/time -l " work "/slurpProg " inp " " work "/outbig 2>&1 | awk '/maximum resident/ {print $1}'")))
          (rss (optionOr (stringToInt64 (stringTrim r.out)) 0))]
      (do (assert (= g.exit 0) "64 MiB fixture written")
          (check (str "peak RSS " rss " bytes under 2.4x of 64 MiB (sized single read)") (and (> rss 0) (< rss 160000000)))))
    true)

fn ! runTests -> Bool
  (let [(work (shellText "mktemp -d"))]
    (do (assert (not (stringEmpty? work)) "mktemp -d makes a work directory")
        (let [(ll (build work))]
          (do (map (fn [(n Int64)] -> Bool (fileCase work n)) (list 0 1 4095 4096 4097 5000000))
              (rssCase work)
              (checkIr ll)))
        (map (fn [(n Int64)] -> Bool (pipeCase work n)) (list 0 1 4097 5000000))
        (shrinkCase work)
        (sh (str "chmod -R u+rwx " work " 2>/dev/null; rm -rf " work))
        true))
