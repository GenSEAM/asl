(module aslPack/pkgCli
  :x [main mainIn! configIndex usageText]
  :i [(pkgStore :a st) (pkgIndex :a ix) (asl-parser/reader :a rd) (asl-tools/fleet/run :a fr)])

fn usageText -> String
  "usage: asl pkg list [--available] | info NAME | install NAME[@VER]... | remove NAME | update [NAME]... | verify"

; (:m :ref PKG-CLIENT :do "the index URL lives in ~/.asl/pkg.asn as (:pkgConfig :index \"URL\"); there is no environment setting")
fn ! configIndex home: String -> String
  (let [(path (str home "/.asl/pkg.asn"))]
    (if (not (fileExists? path)) ""
      (match (fileReadString path)
        ((err _) "")
        ((ok text) (ix/strField (rd/sexprToList (rd/parseSexpr text)) ":index")))))

fn ! show! r: (Result String String) -> Int64
  (match r
    ((ok text) (do (println text) 0))
    ((err e) (do (eprintln e) 1)))

fn ! requests! args: (List String) -> (Result (List (Pair String String)) String)
  (ix/mapResult ix/parseRequest args)

fn ! installAll! ctx: st/Ctx args: (List String) -> Int64
  (match (requests! args)
    ((err e) (do (eprintln e) 2))
    ((ok reqs) (if (listEmpty? reqs) (do (eprintln (usageText)) 2) (show! (st/install! ctx reqs)))))

fn ! mainIn! ctx: st/Ctx args: (List String) -> Int64
  (match (listHead args)
    ((none) (do (eprintln (usageText)) 2))
    ((some verb)
     (let [(rest (optionOr (listTail args) (list)))]
       (cond
         ((= verb "list") (show! (if (listContains? rest "--available") (st/available! ctx) (st/installed! ctx))))
         ((and (= verb "info") (= (listLength rest) 1)) (show! (st/info! ctx (optionOr (listHead rest) ""))))
         ((= verb "install") (installAll! ctx rest))
         ((and (= verb "remove") (= (listLength rest) 1)) (show! (st/remove! ctx (optionOr (listHead rest) ""))))
         ((= verb "update") (show! (st/update! ctx rest)))
         ((and (= verb "verify") (listEmpty? rest)) (show! (st/verify! ctx)))
         (else (do (eprintln (usageText)) 2))))))

fn ! main args: (List String) -> (Result Int64 String)
  (match (getHomeDir)
    ((err e) (err (str "ERR_PKG_HOME: " e)))
    ((ok home)
     (let [(aslBin (match (fr/nativeCliPath!) ((ok p) p) ((err _) "")))]
       (ok (mainIn! (st/makeCtx home (configIndex home) (st/hostTriple) aslBin) args)))))
