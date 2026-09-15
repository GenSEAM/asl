(module asl-codegen/bootstrapCompileGate
  :d "North-star gate for self-hosting: bootstrap.c must compile under the flags the project's own C99 integration test uses. Red by design until the C99 core compiles itself; it reports the live distance rather than a label."
  :x [gateFlags countMatches compileBootstrapErrors testBootstrapCompilesClean testGateMeasuresHonestly runTests]
  :i [])

(df gateFlags [] -> Str
  :d "The exact strict flag set asl-codegen/c99IntegrationTest compiles emitted C99 under."
  "-std=c99 -Wall -Wextra -Werror -Wno-unused-function -pedantic -O2")

(df countMatches [(haystack Str) (needle Str)] -> Int64
  :d "Counts non-overlapping occurrences of needle in haystack."
  (if (string-empty? needle)
      0
      (fold (fn [(acc Int64) (line Str)] -> Int64
               (if (string-contains? line needle) (+ acc 1) acc))
            0
            (string-split haystack "\n"))))

(df ! compileBootstrapErrors [] -> Int64
  :d "Syntax-checks bootstrap.c with the strict flags and returns the diagnostic count."
  (let [(cmd (str "clang " (gateFlags) " -fsyntax-only -ferror-limit=0 -I engine bootstrap.c"))
        (res (sysExec cmd))]
    (countMatches (.-stderr res) "error:")))

(df ! testBootstrapCompilesClean [] -> Bool
  :d "The generated bootstrap.c must compile without a single diagnostic."
  (let [(errs (compileBootstrapErrors))]
    (print (str "(bootstrapCompile :errors " (string-from-int64 errs) ")"))
    (assert (= errs 0) (str "bootstrap.c must compile clean under the project flags; diagnostics remaining: " (string-from-int64 errs)))
    true))

(df ! testGateMeasuresHonestly [] -> Bool
  :d "Dual-polarity guard under D77: the counter must be able to report both zero and non-zero, so a green result cannot be vacuous."
  (let [(sample "a error: one\nb fine\nc error: two")]
    (assert (= (countMatches sample "error:") 2) "the counter finds the diagnostics that are present")
    (assert (= (countMatches sample "warning:") 0) "the counter reports zero for a pattern that is absent")
    (refute (= (countMatches sample "error:") 0) "a text carrying diagnostics must not count as clean")
    (refute (= (countMatches sample "error:") 3) "the counter must not overcount")
    true))

(df ! runTests [] -> Bool
  (do
    (assert (testGateMeasuresHonestly) "testGateMeasuresHonestly")
    (assert (testBootstrapCompilesClean) "testBootstrapCompilesClean")
    true))
