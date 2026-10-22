(module asl-cli/irSplitTest :x [runTests] :i [(asl-tools/fleet/run :a run) (asl/packages/asl-cli/src/irSplit :a ir) (asl/packages/asl-cli/src/nativeBuild :a nb)])

fn program -> String
  (stringJoin (list
    "source_filename = \"irSplitFixture\""
    ""
    "%Val = type { i64, i64 }"
    ""
    "@str.0 = private unnamed_addr constant [6 x i8] c\"hello\\00\""
    "@str.1 = private unnamed_addr constant [4 x i8] c\"%s \\00\""
    "@str.2 = private unnamed_addr constant [4 x i8] c\"%d\\0A\\00\""
    "@str.3 = private unnamed_addr constant [25 x i8] c\"@g = internal global i64\\00\""
    "@counter = internal global i64 0"
    "@ready = internal global i1 false"
    "@cells = internal global [4 x i64] zeroinitializer"
    "@base = weak global i64 5, align 8"
    ""
    "declare i32 @printf(ptr, ...)"
    ""
    "define linkonce_odr hidden i64 @twice(i64 %x) alwaysinline {"
    "bb.entry:"
    "  %r = mul i64 %x, 2"
    "  ret i64 %r"
    "}"
    ""
    "define internal i64 @bump(i64 %by) alwaysinline {"
    "bb.entry:"
    "  %c = load i64, ptr @counter"
    "  %n = add i64 %c, %by"
    "  store i64 %n, ptr @counter"
    "  store i1 true, ptr @ready"
    "  ret i64 %n"
    "}"
    ""
    "define internal void @say(ptr %s) {"
    "bb.entry:"
    "  %r = call i32 (ptr, ...) @printf(ptr @str.1, ptr %s)"
    "  ret void"
    "}"
    ""
    "define tailcc i64 @step(i64 %a, %Val %v) {"
    "bb.entry:"
    "  %t = call i64 @twice(i64 %a)"
    "  %slot = getelementptr [4 x i64], ptr @cells, i64 0, i64 1"
    "  store i64 %t, ptr %slot"
    "  %w = extractvalue %Val %v, 1"
    "  %b = load i64, ptr @base"
    "  %c = load i64, ptr @counter"
    "  %s1 = add i64 %t, %b"
    "  %s2 = add i64 %s1, %c"
    "  %s3 = add i64 %s2, %w"
    "  ret i64 %s3"
    "}"
    ""
    "define i32 @main(i32 %argc, ptr %argv) {"
    "bb.entry:"
    "  call void @say(ptr @str.0)"
    "  %a = call i64 @bump(i64 3)"
    "  %v = insertvalue %Val { i64 0, i64 0 }, i64 100, 1"
    "  %s = call tailcc i64 @step(i64 %a, %Val %v)"
    "  %k = load i1, ptr @ready"
    "  %bonus = select i1 %k, i64 1000, i64 0"
    "  %out = add i64 %s, %bonus"
    "  %slot = getelementptr [4 x i64], ptr @cells, i64 0, i64 1"
    "  %cell = load i64, ptr %slot"
    "  %p = call i32 (ptr, ...) @printf(ptr @str.2, i64 %out)"
    "  %code = trunc i64 %cell to i32"
    "  ret i32 %code"
    "}"
    "") "\n")

fn having parts: (List String) text: String -> Int64
  (listLength (filter (fn [(p String)] -> Bool (stringContains? p text)) parts))

fn ! runTests -> Bool
  (let [(root (resultOr (realPath ".") "."))
        (work (str root "/.asl/cache/irSplitTest." (stringFromInt64 (procSelf))))
        (made (dirCreate work))
        (ll (str work "/program.ll"))
        (wrote (fileWrite ll (program)))
        (split (ir/split (program) 4))
        (parts (resultOr split (list)))
        (b (nb/Build :root root :cache work :tmp work :lib (str root "/asl/host/out/libaslrt.a") :base "" :clangVersion "" :owner ""
                     :deadlineNs (+ (monotonicNs) 300000000000) :maxDesc 16))
        (linked (nb/link! b ll (str work "/program.bin")))
        (ran (run/runOneLimited (run/job (list (str work "/program.bin")) work (list)) (run/limits 30 4)))
        (objects (filter (fn [(k Int64)] -> Bool (fileExists? (str ll ".part" (stringFromInt64 k) ".ll.o"))) (range 0 4)))
        (cleaned (pathRemove work))]
    (do (assert (ok? made) (str "the work directory " work " was created"))
        (assert (ok? wrote) "the fixture IR was written")
        (assert (= (listLength parts) 4) (str "five bodies split into four parts: " (stringFromInt64 (listLength parts))))
        (assert (>= (having parts "define hidden ") 1) "an internal body is defined hidden in its own part")
        (assert (>= (listLength (filter (fn [(p String)] -> Bool (or (stringContains? p "define hidden ") (or (stringContains? p "define tailcc ") (stringContains? p "define i32 @main(")))) parts)) 3) "the bodies spread over at least three parts")
        (assert (= (having parts "@counter = hidden global i64 0") 1) "one part defines the internal global as hidden")
        (assert (= (having parts "@counter = external hidden global i64\n") 3) "the other parts declare the internal global")
        (assert (= (having parts "@cells = external hidden global [4 x i64]\n") 3) "an array global keeps its whole type in a declaration")
        (assert (= (having parts "@base = external global i64\n") 3) "a weak global is declared without hidden and without its align")
        (assert (= (having parts "define linkonce_odr hidden i64 @twice(i64 %x) alwaysinline {") 4) "every part carries the linkonce_odr body")
        (assert (= (having parts "define hidden i64 @bump(i64 %by) alwaysinline {") 1) "the owner of an internal alwaysinline body defines it hidden")
        (assert (= (having parts "define available_externally i64 @bump(i64 %by) alwaysinline {") 3) "the other parts get an available_externally copy to inline")
        (assert (= (having parts "define hidden void @say(ptr %s) {") 1) "an internal function is defined hidden once")
        (assert (= (having parts "declare hidden void @say(ptr)\n") 3) "an internal function is declared hidden where it is not defined")
        (assert (= (having parts "declare tailcc i64 @step(i64, %Val)\n") 3) "an external function is declared with its calling convention and parameter types")
        (assert (= (having parts "@str.2 = private unnamed_addr constant") 4) "every part repeats the private constants")
        (assert (= (having parts "@str.3 = private unnamed_addr constant [25 x i8] c\"@g = internal global i64\\00\"") 4) "a constant whose text names an internal global stays a repeated constant")
        (assert (= (having parts "define i32 @main(") 1) "exactly one part defines main")
        (assert (= (ir/declOf "define internal i64 @f(i64 %a, ...) noinline cold {") (some "declare i64 @f(i64, ...)")) "a declaration keeps varargs and drops attributes")
        (assert (= (ir/declOf "define weak ptr @g() {") (some "declare ptr @g()")) "a declaration of a weak function with no parameters")
        (assert (= (ir/externOf "@x = internal global %Val zeroinitializer") (some "@x = external hidden global %Val")) "an internal %Val global becomes an external hidden declaration")
        (assert (match linked ((ok _) true) ((err e) (do (eprintln e) false))) "nb/link! builds the fixture through its parts")
        (assert (= (listLength objects) 4) (str "nb/link! compiled each of the four parts to an object: " (stringFromInt64 (listLength objects))))
        (assert (= ran.exit 6) (str "the linked program returns the cell its tailcc step stored (6): " (stringFromInt64 ran.exit) " " ran.out))
        (assert (= (stringTrim ran.out) "hello 1114") (str "the linked program sees one counter, one ready flag and one weak base across the parts: " ran.out))
        (assert (ok? cleaned) "the work directory was removed")
        true))
