(module asl-target-llvm/tests/wasmAllocTest
  :x [runTests]
  :i [(asl-target-llvm/wasmAlloc :a wa)])

fn ! sh cmd: String -> ProcessOutput
  (processRun cmd)

fn probeLl -> String
  (stringJoin
    (list
      "target triple = \"wasm32-unknown-unknown\""
      ""
      (stringJoin (wa/allocatorImports) "\n")
      (wa/wasmAllocatorText)
      ""
      "define i32 @probe() {"
      "entry:"
      "  %first = call ptr @malloc(i64 24)"
      "  %firstNull = icmp eq ptr %first, null"
      "  br i1 %firstNull, label %bad, label %reuseTry"
      "reuseTry:"
      "  call void @free(ptr %first)"
      "  %again = call ptr @malloc(i64 16)"
      "  %same = icmp eq ptr %first, %again"
      "  br i1 %same, label %copyTry, label %bad"
      "copyTry:"
      "  %bytep = getelementptr i8, ptr %again, i64 0"
      "  store i8 65, ptr %bytep, align 1"
      "  %moved = call ptr @realloc(ptr %again, i64 64)"
      "  %moveNull = icmp eq ptr %moved, null"
      "  br i1 %moveNull, label %bad, label %copied"
      "copied:"
      "  %movedBytep = getelementptr i8, ptr %moved, i64 0"
      "  %value = load i8, ptr %movedBytep, align 1"
      "  %byteOk = icmp eq i8 %value, 65"
      "  br i1 %byteOk, label %smallLoop, label %bad"
      "smallLoop:"
      "  br label %smallBody"
      "smallBody:"
      "  %index = phi i32 [ 0, %smallLoop ], [ %next, %advance ]"
      "  %done = icmp uge i32 %index, 512"
      "  br i1 %done, label %foreignTry, label %smallAlloc"
      "smallAlloc:"
      "  %item = call ptr @malloc(i64 16)"
      "  %itemNull = icmp eq ptr %item, null"
      "  br i1 %itemNull, label %bad, label %advance"
      "advance:"
      "  %next = add i32 %index, 1"
      "  br label %smallBody"
      "foreignTry:"
      "  %foreignPage = call i32 @llvm.wasm.memory.grow.i32(i32 0, i32 1)"
      "  %foreignFailed = icmp eq i32 %foreignPage, -1"
      "  br i1 %foreignFailed, label %bad, label %foreignGrown"
      "foreignGrown:"
      "  %foreignStart = shl i32 %foreignPage, 16"
      "  %foreignEnd = add i32 %foreignStart, 65536"
      "  %big = call ptr @malloc(i64 1100000)"
      "  %bigNull = icmp eq ptr %big, null"
      "  br i1 %bigNull, label %bad, label %bigPlaced"
      "bigPlaced:"
      "  %bigStart = ptrtoint ptr %big to i32"
      "  %bigLast = add i32 %bigStart, 1099999"
      "  %endsBefore = icmp ult i32 %bigLast, %foreignStart"
      "  %startsAfter = icmp uge i32 %bigStart, %foreignEnd"
      "  %disjoint = or i1 %endsBefore, %startsAfter"
      "  br i1 %disjoint, label %oomTry, label %bad"
      "oomTry:"
      "  %tooBig = call ptr @malloc(i64 4000000)"
      "  %oom = icmp eq ptr %tooBig, null"
      "  br i1 %oom, label %success, label %bad"
      "success:"
      "  ret i32 0"
      "bad:"
      "  ret i32 1"
      "}"
      "")
    "\n")

fn nodeDriver -> String
  (stringJoin
    (list
      "const fs = require('fs');"
      "const bytes = fs.readFileSync(process.argv[2]);"
      "WebAssembly.instantiate(bytes, {}).then(({instance}) => {"
      "  const result = instance.exports.probe();"
      "  console.log(result);"
      "  if (result !== 0) process.exitCode = 1;"
      "}).catch(error => { console.error(error); process.exitCode = 1; });")
    "\n")

fn ! testAllocator -> Bool
  (let [(dirOut (sh "mktemp -d /tmp/wasm-alloc-test.XXXXXX"))
        (work (stringReplace dirOut.stdout "\n" ""))
        (ll (str work "/probe.ll"))
        (obj (str work "/probe.o"))
        (wasm (str work "/probe.wasm"))
        (js (str work "/probe.js"))]
    (do
      (assert (= dirOut.exitCode 0) "create isolated wasm allocator test directory")
      (assert (ok? (fileWrite ll (probeLl))) "write executable allocator LLVM module")
      (assert (ok? (fileWrite js (nodeDriver))) "write WebAssembly execution driver")
      (let [(compiled (sh (str "/opt/homebrew/opt/llvm/bin/llc -mtriple=wasm32-unknown-unknown -mattr=+bulk-memory -filetype=obj " ll " -o " obj)))
            (linked (sh (str "/opt/homebrew/opt/lld/bin/wasm-ld --fatal-warnings --no-entry --export=probe --initial-memory=131072 --max-memory=2359296 " obj " -o " wasm)))
            (ran (sh (str (optionOr (envGet "HOME") "") "/.local/bin/node " js " " wasm)))
            (cleaned (sh (str "rm -rf " work)))]
        (do
          (assert (= compiled.exitCode 0) (str "compile allocator wasm: " compiled.stderr))
          (assert (= linked.exitCode 0) (str "link allocator wasm: " linked.stderr))
          (assert (= ran.exitCode 0) (str "M1 free-list reuse, M2 failed growth, M3 realloc copy, M4 a run never overlaps a page grown by someone else, and bump allocation execute: " ran.stdout " " ran.stderr))
          (assert (= (stringReplace ran.stdout "\n" "") "0") "wasm allocator behavior checks all pass")
          (assert (= cleaned.exitCode 0) "remove only the test-owned temporary directory")
          true))))

fn ! runTests -> Bool
  (do (assert (testAllocator) "execute wasm allocator behavior") true)
