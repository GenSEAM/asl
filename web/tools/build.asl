(module aslSite/tools/build
  :x [! main]
  :i [(asl-ir/types :a irTy)
      (asl-ir/link :a lk)
      (asl-target-llvm :a llvm)
      (asl-target-llvm/libc :a libc)
      (asl-target-llvm/target :a target)
      (asl-target-llvm/wasmLink :a wl)
      (asl-html/html :a h)
      (aslSite/app/theme :a theme)
      (aslSite/app/home :a home)
      (aslSite/app/mascot :a mascot)
      (aslSite/app/docs :a docs)
      (aslSite/app/blog :a blog)
      (aslSite/tools/posts :a posts)
      (aslSite/tools/feeds :a feeds)])

fn web -> String
  "asl/web"

fn dist -> String
  "asl/web/dist"

fn quoteSh s: String -> String
  (str "'" (stringReplace s "'" "'\\''") "'")

fn ! sh! cmd: String -> ProcessOutput
  (processRun cmd)

fn ! ok! what: String out: ProcessOutput -> Bool
  (if (= out.exitCode 0) true (do (eprintln (str "build: " what " failed\n" out.stdout out.stderr)) false))

fn ! firstTool! envName: String candidates: (List String) fallback: String -> String
  (let [(fromEnv (optionOr (envGet envName) ""))
        (found (filter (fn [(c String)] -> Bool (= (sh! (str "test -x " (quoteSh c))).exitCode 0)) candidates))]
    (cond
      ((not (stringEmpty? fromEnv)) fromEnv)
      ((not (listEmpty? found)) (optionOr (listHead found) fallback))
      (else (stringTrim (sh! (str "command -v " fallback " 2>/dev/null || echo " fallback)).stdout))))

fn llvmBins name: String -> (List String)
  (map (fn [(v String)] -> String (str "/usr/lib/llvm-" v "/bin/" name)) ["23" "22" "21" "20" "19" "18"])

fn ! llc! -> String
  (firstTool! "LLC" (listAppend ["/opt/homebrew/opt/llvm/bin/llc" "/usr/local/opt/llvm/bin/llc"] (llvmBins "llc")) "llc")

fn ! wasmLd! -> String
  (firstTool! "WASM_LD" (listAppend ["/opt/homebrew/bin/wasm-ld" "/opt/homebrew/opt/lld/bin/wasm-ld" "/usr/bin/wasm-ld"] (llvmBins "wasm-ld")) "wasm-ld")

fn diagText ds: (List irTy/IrDiag) -> String
  (stringJoin (map (fn [(d irTy/IrDiag)] -> String (str d.code ": " d.message)) ds) "\n")

fn wasmFacts -> libc/TripleFacts
  (optionOr (libc/libcFacts "wasm32-unknown-unknown") (libc/emptyTripleFacts))

fn portableIr text: String -> String
  (stringReplace (stringReplace (stringReplace text "llvm.va_start.p0" "llvm.va_start") "llvm.va_end.p0" "llvm.va_end") "llvm.va_copy.p0" "llvm.va_copy")

fn exports -> (List (Pair String String))
  [(pair "update" "i64 %a, i64 %b") (pair "render" "") (pair "measured" "i64 %a, i64 %b, i64 %c")]

fn exportDefine e: (Pair String String) -> String
  (str "define i64 @aslSite$2Fmain$2E" (pairFirst e) "(")

fn argList params: String -> String
  (stringJoin (map (fn [(p String)] -> String (stringTrim p)) (filter (fn [(p String)] -> Bool (not (stringEmpty? p))) (stringSplit params ","))) ", ")

fn exportShim e: (Pair String String) -> String
  (stringJoin ["" (str "define i64 @" (pairFirst e) "(" (pairSecond e) ") {") "entry:" (str "  %r = call i64 @aslSite$2Fmain$2E" (pairFirst e) "(" (argList (pairSecond e)) ")") "  ret i64 %r" "}"] "\n")

fn withExports part: String ir: (Result String (List irTy/IrDiag)) -> (Result String (List irTy/IrDiag))
  (mt ir
    ((err ds) (err ds))
    ((ok text)
      (let [(missing (filter (fn [(e (Pair String String))] -> Bool (not (stringContains? text (exportDefine e)))) (exports)))]
        (cond
          ((not (= part "main")) (ok text))
          ((listEmpty? missing) (ok (str text (stringJoin (map exportShim (exports)) "") "\n")))
          (else (err (map (fn [(e (Pair String String))] -> irTy/IrDiag (irTy/makeIrDiag "ERR_SITE_EXPORT" (str "aslSite/main no longer defines " (exportDefine e) "...), which boot.js calls") "asl/web/site/main.asl")) missing)))))))

fn ! object! llc: String work: String part: String lowered: (Result String (List irTy/IrDiag)) -> Bool
  (mt (withExports part lowered)
    ((err ds) (do (eprintln (str "build: lowering " part " failed\n" (diagText ds))) false))
    ((ok text)
      (let [(ll (str work "/" part ".ll"))]
        (do
          (fileWrite ll (portableIr text))
          (ok! (str "llc " part) (sh! (str (quoteSh llc) " -O2 -mtriple=wasm32-unknown-unknown -mattr=+bulk-memory,+tail-call -filetype=obj " (quoteSh ll) " -o " (quoteSh (str ll ".o")))))))))

fn ! compileWasm! work: String out: String -> Bool
  (let [(llc (llc!))
        (program (mt (lk/linkEntry! (str (web) "/site/main.asl"))
                   ((err ds) (err ds))
                   ((ok m) (llvm/emitLlvmProgramForTarget (wasmFacts) (target/wasm32TargetFacts) m (str m.name ".main")))))]
    (and (object! llc work "main" program)
      (and (object! llc work "runtime" (llvm/emitLlvmRuntimeForTarget (wasmFacts) (target/wasm32TargetFacts)))
        (and (object! llc work "support" (llvm/emitLlvmSupportForTarget (wasmFacts) (target/wasm32TargetFacts)))
          (ok! "wasm-ld" (wl/linkWasm32 (wasmLd!) [(str work "/main.ll.o") (str work "/runtime.ll.o") (str work "/support.ll.o")] (map pairFirst (exports)) out))))))

fn ! lineCount! path: String -> Int64
  (mt (fileRead path) ((ok s) (stringCountChar s "\n")) ((err e) 0))

fn ! aslLines! -> Int64
  (let [(files (filter (fn [(f String)] -> Bool (not (stringEmpty? f))) (stringSplit (sh! (str "find " (web) "/site asl/packages/asl-html/src -name '*.asl'")).stdout "\n")))]
    (listSum (map lineCount! files)))

fn ! writePage! route: String node: h/Node -> Bool
  (let [(dir (if (= route "/") (dist) (str (dist) route)))]
    (and (ok! (str "mkdir " dir) (sh! (str "mkdir -p " (quoteSh dir))))
      (ok? (fileWrite (str dir "/index.html") (h/renderDocument node)))))

fn ! main -> Int64
  (let [(work (str (dist) "/.work"))
        (wasm (str (dist) "/site.wasm"))]
    (if (not (and (ok! "clean" (sh! (str "rm -rf " (quoteSh (dist)) " && mkdir -p " (quoteSh work) " && cp -R " (quoteSh (str (web) "/public/.")) " " (quoteSh (dist)) " && cp " (quoteSh (str (web) "/bridge/boot.js")) " asl/llms.txt " (quoteSh (dist)))))
                  (compileWasm! work wasm)))
      1
      (let [(stats (home/Stats :wasmBytes (resultOr (fileSize wasm) 0) :aslLines (aslLines!) :bridgeLines (lineCount! (str (web) "/bridge/boot.js"))))
            (all (posts/loadPosts! (str (web) "/content/blog")))
            (pages (listAppend [(pair "/" (home/homePage stats)) (pair "/docs" (docs/docsPage)) (pair "/blog" (blog/blogIndexPage all))]
                               (map (fn [(p blog/Post)] -> (Pair String h/Node) (pair (str "/blog/" p.slug) (blog/postPage p))) all)))
            (wrote (and (ok? (fileWrite (str (dist) "/site.css") (theme/stylesheet)))
                     (and (ok? (fileWrite (str (dist) "/favicon.svg") (h/render (mascot/iconSvg))))
                     (and (ok? (fileWrite (str (dist) "/404.html") (h/renderDocument (blog/notFoundPage))))
                       (and (ok? (fileWrite (str (dist) "/sitemap.xml") (feeds/sitemapXml all)))
                         (and (ok? (fileWrite (str (dist) "/rss.xml") (feeds/rssXml all)))
                           (listAll? (fn [(page (Pair String h/Node))] -> Bool (writePage! (pairFirst page) (pairSecond page))) pages)))))))]
        (do
          (sh! (str "rm -rf " (quoteSh work)))
          (println (str "built " (dist) ": " (stringFromInt64 (listLength pages)) " pages, site.wasm " (stringFromInt64 stats.wasmBytes) " bytes, " (stringFromInt64 stats.aslLines) " lines of ASL"))
          (if (and wrote (> (listLength all) 0)) 0 1)))))
