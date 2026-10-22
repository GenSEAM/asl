(module asl-tools/agentSurfaceAudit
  :x [Surface SurfaceCount AuditResult surfaces headerArmOn? parenArmOn?
      basenameOf skipName? matchesSurface? walkDir! walkEntries! walkEntry! filesUnder! joinRoot filesForSurface!
      fenceTag aslFenceTag? fencedBlocks unescapeLiteral quotedStringLiterals codeLike? quotedCodeLiterals
      parenGroupsLoop parenGroups
      snippetsOf snippetRetired readTextFile! scanFile! scanSurface! allCounts!
      itos q surfaceLine receiptOf ratchetPath ratchetCount! auditAll! main]
  :i [(asl-parser/ast :a a) (asl-parser/headerLines :a hl) (asl-parser/parenForms :a pfm)])

(schema Surface
  (:f id String)
  (:f kind String)
  (:f roots (List String))
  (:f exts (List String))
  (:f names (List String)))

(schema SurfaceCount
  (:f id String)
  (:f kind String)
  (:f files Int64)
  (:f snippets Int64)
  (:f retired Int64))

(schema AuditResult
  (:f counts (List SurfaceCount))
  (:f totalFiles Int64)
  (:f totalSnippets Int64)
  (:f totalRetired Int64)
  (:f ratchet Int64)
  (:f ok Bool)
  (:f receipt String))

; (:m :ref AGSURF :do "census, principal 2026-10-15: every agent-facing surface that can show ASL code to a model, so the strict readers only ever see the latest syntax quoted back to them")
fn surfaces -> (List Surface)
  (list
    (Surface :id "agentLoop" :kind "agentLoopPromptsAndSystemText"
      :roots (list "asl/agentLoop") :exts (list ".asl" ".asn") :names (list))
    (Surface :id "harnessPrompts" :kind "agentLoopPromptsAndSystemText"
      :roots (list "harness/prompts.asn" "harness/skills.asn" "harness/manifest.asn"
                   "harness/auditProtocols.asn" "harness/auditPlaybook.asn" "harness/paradigm.asn"
                   "harness/calibration")
      :exts (list ".asn") :names (list))
    (Surface :id "helpCatalogue" :kind "helpAndToolsCatalogue"
      :roots (list ".asl/mem/docs/tools.asn" "asl/packages/asl-help"
                   "asl/packages/asl-forms/tests/fixtures/recorded/know.asn")
      :exts (list ".asn" ".asl") :names (list))
    (Surface :id "grammarExamples" :kind "grammarExamplesAndCorpora"
      :roots (list "asl/grammar") :exts (list ".asn" ".asl" ".md") :names (list))
    (Surface :id "skills" :kind "skills"
      :roots (list "harness/skills" "asl/skills" "asl/packages/asl-agent-bus/skills"
                   "asl/packages/asl-contracts/skills" "editorial-matrix/skills")
      :exts (list ".md" ".asl" ".asn") :names (list))
    (Surface :id "renderedRules" :kind "renderedRuleAndClaudeMdSurfaces"
      :roots (list "CLAUDE.md" "AGENTS.md" "asl/grammar/rules.asn" ".asl/rules.asn")
      :exts (list ".md" ".asn") :names (list))
    (Surface :id "docRows" :kind "docAsnRowsWithCode"
      :roots (list "asl/packages") :exts (list) :names (list "doc.asn"))
    (Surface :id "modelFixtures" :kind "fixturesFedToModels"
      :roots (list "asl/agentLoop/tests" "harness/tests") :exts (list ".asn") :names (list)))


; (:m :ref AGSURF :do "CMSHAPE's header/paren strict readers are capability-complete but not yet wired into the live checker pipeline (ast/parse never calls hl/normalizeHeader; resolve.asl has no flat-header case), so turning these on here would flag syntax the real compiler cannot accept yet; they stay behind an arm until the SYN-PROBES verdict lands the wiring")
fn headerArmOn? -> Bool
  false

fn parenArmOn? -> Bool
  false

fn basenameOf path: String -> String
  (optionOr (listLast (stringSplit path "/")) path)

fn skipName? name: String -> Bool
  (or (stringStartsWith? name ".") (listContains? (list "node_modules" "out" "aslNativeBuild" "aslNativeBuild-fresh") name))

fn extOf path: String -> String
  (let [(parts (stringSplit path "."))]
    (if (<= (listLength parts) 1) "" (str "." (optionOr (listLast parts) ""))))

fn matchesSurface? surf: Surface path: String -> Bool
  (if (not (listEmpty? surf.names))
    (listContains? surf.names (basenameOf path))
    (listAny? (fn [(e String)] -> Bool (stringEndsWith? path e)) surf.exts))

fn ! walkEntry! path: String name: String depth: Int64 acc: (List String) -> (List String)
  (if (skipName? name)
    acc
    (match (fileStat path)
      ((err _) acc)
      ((ok st) (cond (st.isDir (walkDir! path (+ depth 1) acc)) (st.isFile (cons path acc)) (else acc)))))

fn ! walkEntries! dir: String names: (List String) depth: Int64 acc: (List String) -> (List String)
  (match (listHead names)
    ((none) acc)
    ((some n) (walkEntries! dir (optionOr (listTail names) (list)) depth (walkEntry! (str dir "/" n) n depth acc))))

fn ! walkDir! dir: String depth: Int64 acc: (List String) -> (List String)
  (if (>= depth 40)
    acc
    (match (dirList dir) ((err _) acc) ((ok names) (walkEntries! dir names depth acc))))

; (:m :ref AGSURF :do "a root that is itself a readable directory is walked; anything else, a plain file or a symlink to one which fileStat reports as a link rather than a file, is taken as a single file path and left to the real read in scanFile! to succeed or fail")
fn ! filesUnder! root: String -> (List String)
  (match (dirList root)
    ((ok names) (walkEntries! root names 0 (list)))
    ((err _) (list root)))

fn joinRoot root: String p: String -> String
  (if (= root ".") p (str root "/" p))

fn ! filesForSurface! root: String surf: Surface -> (List String)
  (filter (fn [(p String)] -> Bool (matchesSurface? surf p))
    (fold (fn [(acc (List String)) (r String)] -> (List String) (listAppend acc (filesUnder! (joinRoot root r)))) (list) surf.roots))

fn fenceTag line: String -> String
  (stringTrim (optionOr (stringSlice line 3 (stringLength line)) ""))

fn aslFenceTag? tag: String -> Bool
  (listContains? (list "" "asl" "asn" "lisp" "scheme" "clojure") (stringLower tag))

fn fencedBlocksLoop lines: (List String) inFence: Bool tag: String buf: (List String) acc: (List String) -> (List String)
  (match (listHead lines)
    ((none) acc)
    ((some l)
     (let [(rest (optionOr (listTail lines) (list)))]
       (if (stringStartsWith? (stringTrim l) "```")
         (if inFence
           (fencedBlocksLoop rest false "" (list) (if (aslFenceTag? tag) (listAppend acc (list (stringJoin (listReverse buf) "\n"))) acc))
           (fencedBlocksLoop rest true (fenceTag (stringTrim l)) (list) acc))
         (if inFence
           (fencedBlocksLoop rest inFence tag (cons l buf) acc)
           (fencedBlocksLoop rest inFence tag buf acc))))))

fn fencedBlocks text: String -> (List String)
  (fencedBlocksLoop (stringSplit text "\n") false "" (list) (list))

fn unescapeLiteral s: String -> String
  (stringReplace (stringReplace s "\\n" "\n") "\\\"" "\"")

fn quoteScanLoop bs: Bytes n: Int64 i: Int64 inStr: Bool start: Int64 text: String acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [(b (bytesGet bs i))]
      (cond
        ((and inStr (= b 92)) (quoteScanLoop bs n (+ i 2) inStr start text acc))
        ((and inStr (= b 34)) (quoteScanLoop bs n (+ i 1) false start text (cons (optionOr (stringSlice text start i) "") acc)))
        ((and (not inStr) (= b 34)) (quoteScanLoop bs n (+ i 1) true (+ i 1) text acc))
        (else (quoteScanLoop bs n (+ i 1) inStr start text acc)))))

fn quotedStringLiterals text: String -> (List String)
  (let [(bs (stringToBytes text))] (quoteScanLoop bs (bytesLength bs) 0 false 0 text (list)))

fn codeLike? s: String -> Bool
  (let [(t (stringTrim s))] (and (> (stringLength t) 3) (stringStartsWith? t "(")))

fn quotedCodeLiterals text: String -> (List String)
  (filter codeLike? (map unescapeLiteral (quotedStringLiterals text)))

; (:m :ref AGSURF :do "a markdown example such as the asl-toolbelt SKILL.md is often inline prose, (mt s ((circle r) ...) ...), not a fenced block; parenGroupsLoop collects every top-level balanced (...) span outside a quoted string so an inline example is checked the same as a fenced one; the exact-head-token match in a/spellingErrors keeps ordinary prose parentheticals from ever matching")
fn parenGroupsLoop bs: Bytes n: Int64 i: Int64 depth: Int64 inStr: Bool start: Int64 text: String acc: (List String) -> (List String)
  (if (>= i n)
    (listReverse acc)
    (let [(b (bytesGet bs i))]
      (cond
        (inStr (cond
                 ((= b 92) (parenGroupsLoop bs n (+ i 2) depth inStr start text acc))
                 ((= b 34) (parenGroupsLoop bs n (+ i 1) depth false start text acc))
                 (else (parenGroupsLoop bs n (+ i 1) depth inStr start text acc))))
        ((= b 34) (parenGroupsLoop bs n (+ i 1) depth true start text acc))
        ((= b 40) (parenGroupsLoop bs n (+ i 1) (+ depth 1) inStr (if (= depth 0) i start) text acc))
        ((and (= b 41) (> depth 0))
         (let [(newDepth (- depth 1))]
           (if (= newDepth 0)
             (parenGroupsLoop bs n (+ i 1) newDepth inStr start text (cons (optionOr (stringSlice text start (+ i 1)) "") acc))
             (parenGroupsLoop bs n (+ i 1) newDepth inStr start text acc))))
        (else (parenGroupsLoop bs n (+ i 1) depth inStr start text acc)))))

fn parenGroups text: String -> (List String)
  (let [(bs (stringToBytes text))] (filter codeLike? (parenGroupsLoop bs (bytesLength bs) 0 0 false 0 text (list))))

fn snippetsOf path: String text: String -> (List String)
  (cond
    ((stringEndsWith? path ".asl") (list text))
    ((stringEndsWith? path ".md") (listAppend (fencedBlocks text) (parenGroups text)))
    (else (quotedCodeLiterals text)))

; (:m :ref AGSURF :do "the retired forms named by the gate, (mt ...)/(== ...)/(not= ...), are exactly what a/retiredFormErrors flags via retiredHeadMessage; it runs unconditionally, not gated by strictSpellingDefault, so a surface is checked whether or not the global strict arm is on. fn ! f and a bare effectful builtin call are deliberately not counted here any more: SYN-ARMS-DECISION-20261016 keeps fn ! name (E9) and bare builtins (E10), reversing the earlier builtinBang/fn-header-mark decisions that AGENTSURFACE-BANG-STALE had already started walking back; see LANG-LANDING")
fn snippetRetired path: String src: String -> Int64
  (+ (listLength (a/retiredFormErrors src))
     (+ (if (and (headerArmOn?) (stringEndsWith? path ".asl")) (match (hl/headerError src true) ((some _) 1) ((none) 0)) 0)
        (if (and (parenArmOn?) (stringEndsWith? path ".asl")) (match (pfm/bracketError src true) ((some _) 1) ((none) 0)) 0)))

fn ! readTextFile! path: String -> (Option String)
  (match (fileReadString path) ((ok s) (some s)) ((err _) (none)))

fn ! scanFile! path: String -> (Pair Int64 Int64)
  (match (readTextFile! path)
    ((none) (pair 0 0))
    ((some text)
     (let [(snips (snippetsOf path text))]
       (pair (listLength snips) (fold (fn [(acc Int64) (s String)] -> Int64 (+ acc (snippetRetired path s))) 0 snips)))))

fn ! scanSurface! root: String surf: Surface -> SurfaceCount
  (let [(files (filesForSurface! root surf))
        (results (map scanFile! files))
        (snippets (fold (fn [(acc Int64) (r (Pair Int64 Int64))] -> Int64 (+ acc (pairFirst r))) 0 results))
        (retired (fold (fn [(acc Int64) (r (Pair Int64 Int64))] -> Int64 (+ acc (pairSecond r))) 0 results))]
    (SurfaceCount :id surf.id :kind surf.kind :files (listLength files) :snippets snippets :retired retired))

fn ! allCounts! root: String -> (List SurfaceCount)
  (map (fn [(s Surface)] -> SurfaceCount (scanSurface! root s)) (surfaces))

fn itos k: Int64 -> String
  (stringFromInt64 k)

fn q s: String -> String
  (str "\"" (stringReplace (stringReplace s "\\" "\\\\") "\"" "\\\"") "\"")

fn surfaceLine c: SurfaceCount -> String
  (str "(:surface :id " (q c.id) " :kind " (q c.kind) " :files " (itos c.files) " :snippets " (itos c.snippets) " :retired " (itos c.retired) ")")

fn receiptOf counts: (List SurfaceCount) totalFiles: Int64 totalSnippets: Int64 totalRetired: Int64 ratchet: Int64 ok: Bool -> String
  (str "(:agentSurfaceAudit"
       "\n  :surfaces (" (stringJoin (map surfaceLine counts) "\n             ") ")"
       "\n  :totalFiles " (itos totalFiles)
       "\n  :totalSnippets " (itos totalSnippets)
       "\n  :totalRetired " (itos totalRetired)
       "\n  :ratchet " (itos ratchet)
       "\n  :ok " (if ok "true" "false")
       ")")

fn ratchetPath root: String -> String
  (str root "/tools/agentSurfaceAuditRatchet.asn")

fn digitPrefix s: String -> String
  (if (<= (stringLength s) 1)
    (if (some? (stringToInt64 s)) s "")
    (if (some? (stringToInt64 s)) s (digitPrefix (optionOr (stringSlice s 0 (- (stringLength s) 1)) ""))))

fn intAfter text: String marker: String -> (Option Int64)
  (match (stringIndexOf text marker)
    ((none) (none))
    ((some i)
     (let [(start (+ i (stringLength marker)))
           (rest (optionOr (stringSlice text start (stringLength text)) ""))
           (tok (optionOr (listHead (filter (fn [(w String)] -> Bool (not (stringEmpty? w))) (stringSplit rest " "))) ""))]
       (stringToInt64 (digitPrefix (stringTrim tok))))))

fn ! ratchetCount! root: String -> Int64
  (match (fileReadString (ratchetPath root))
    ((err _) 0)
    ((ok text) (optionOr (intAfter text ":total ") 0)))

fn ! auditAll! root: String -> AuditResult
  (let [(counts (allCounts! root))
        (totalFiles (fold (fn [(acc Int64) (c SurfaceCount)] -> Int64 (+ acc c.files)) 0 counts))
        (totalSnippets (fold (fn [(acc Int64) (c SurfaceCount)] -> Int64 (+ acc c.snippets)) 0 counts))
        (totalRetired (fold (fn [(acc Int64) (c SurfaceCount)] -> Int64 (+ acc c.retired)) 0 counts))
        (ratchet (ratchetCount! root))
        (ok (<= totalRetired ratchet))]
    (AuditResult :counts counts :totalFiles totalFiles :totalSnippets totalSnippets :totalRetired totalRetired
      :ratchet ratchet :ok ok :receipt (receiptOf counts totalFiles totalSnippets totalRetired ratchet ok)))

fn ! main args: (List String) -> (Result Int64 String)
  (let [(root (optionOr (listHead args) "."))
        (r (auditAll! root))]
    (do
      (println r.receipt)
      (ok (if r.ok 0 1))))
