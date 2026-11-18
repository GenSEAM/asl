(module aslAgent/tests/absorbRawLayoutTest
  :x [runTests]
  :i [(aslAgent/core :a c) (aslAgent/turn :a tr) (aslAgent/reply :a r)])

fn q -> String
  "```"

fn st k: String file: String -> String
  (str ":file \"" file "\" :" k " ")

fn bindIds -> (List String)
  (list "c01" "c04b" "c04f" "c04g" "c05d" "c06" "c06b" "c07" "c07b" "c07c" "c08" "c08b" "c08c" "c10" "c11" "c11b" "c11c" "c12" "c14" "c20" "c21" "c24" "c25" "h1")

fn refuseIds -> (List String)
  (list "c02" "c03" "c04" "c04c" "c04d" "c05b" "c05c" "c09" "c09b" "c09c" "c13" "c15" "c15b" "c16" "c19" "c26" "c27" "c28")

; (:m :ref ABSORB-AGENT-K1-K2-K4 :do "the grader's 50 layouts of 2026-11-18 (gK1bProbeTest) plus H1: a layout the rules read binds every field right, any other binds nothing in the whole reply; none is ever WRONG or PARTIAL")
fn want? name: String v: String -> Bool
  (let [id (optionOr (listHead (stringSplit name " ")) "")]
    (cond ((listContains? (bindIds) id) (= v "BIND"))
          ((listContains? (refuseIds) id) (= v "REFUSE"))
          (else (or (= v "BIND") (= v "REFUSE")))))

fn ! judge! name: String reply: String exp: (List (Pair String String)) -> Bool
  (let [b (r/bindRawBlocks reply)
        vs (map (fn [e] (let [key (pairFirst e) val (pairSecond e)]
                          (cond ((stringContains? b.text (str key "\"" (c/escapeAsn val) "\"")) "OK")
                                ((stringContains? b.text (str key "\"")) "BAD")
                                (else "REF")))) exp)
        v (cond ((listAny? (fn [x] (= x "BAD")) vs) "WRONG")
                ((listAll? (fn [x] (= x "OK")) vs) "BIND")
                ((listAll? (fn [x] (= x "REF")) vs) "REFUSE")
                (else "PARTIAL"))]
    (do (assert (want? name v) (str name ": each case binds right or the whole reply binds nothing, got " v " [" (stringJoin vs " ") "] missing " (stringJoin (map (fn [p] (pairSecond p)) b.missing) ",") " text " b.text)) true))

fn ! runTests -> Bool
  (let [f (q)
        F (str f "`")
        A (str f "\nAAA\n" f "\n") B (str f "\nBBB\n" f "\n") C (str f "\nCCC\n" f "\n") X (str f "\nXXX\n" f "\n")
        sa "(:step :op \"write\" :file \"a\" :content :raw)" sb "(:step :op \"write\" :file \"b\" :content :raw)" sc "(:step :op \"write\" :file \"c\" :content :raw)"
        ea (st "content" "a") eb (st "content" "b") ec (st "content" "c")
        AA "AAA\n" BB "BBB\n" CC "CCC\n"
        md (str "# Title\n\n" f "\ncode ( \"\n" f "\n\n" f "asl\n(fn x)\n" f "\ntext\n")
        code (str "(:txn (:step :op \"write\" :file \"evil\" :content :raw)) \"q\\\" ( (:step :op \"run\" :cmd \"x\")\n:content :raw ) ) )\n")
        r (list
          (judge! "h1 inline block in second step, tail for first" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  (:step :op \"write\" :file \"b\" :content :raw\n" B "))\n" A) (list (pair ea AA) (pair eb BB)))
          (judge! "c01 three mixed in/after/in" (str "(:txn :owns (\"a\" \"b\" \"c\")\n  " sa "\n" A "  " sb "\n  " sc "\n" C ")\n" B) (list (pair ea AA) (pair eb BB) (pair ec CC)))
          (judge! "c02 tail more than steps" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" A B X) (list (pair ea AA) (pair eb BB)))
          (judge! "c03 tail fewer than steps" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" A) (list (pair ea AA) (pair eb BB)))
          (judge! "c04 txn then step with own block" (str "(:txn :owns (\"a\")\n  " sa ")\n" sb "\n" B) (list (pair ea AA) (pair eb BB)))
          (judge! "c04b txn block, step block" (str "(:txn :owns (\"a\")\n  " sa ")\n" A sb "\n" B) (list (pair ea AA) (pair eb BB)))
          (judge! "c04c txn two steps one tail, then step with block" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" A sc "\n" C) (list (pair ea AA) (pair eb BB) (pair ec CC)))
          (judge! "c04d step then txn, block after txn" (str sa "\n(:txn :owns (\"b\")\n  " sb ")\n" B) (list (pair ea AA) (pair eb BB)))
          (judge! "c04e two txns, block inside second" (str "(:txn :owns (\"a\")\n  " sa ")\n(:txn :owns (\"b\")\n  " sb "\n" B ")") (list (pair ea AA) (pair eb BB)))
          (judge! "c04f two txns each with tail" (str "(:txn :owns (\"a\")\n  " sa ")\n" A "(:txn :owns (\"b\")\n  " sb ")\n" B) (list (pair ea AA) (pair eb BB)))
          (judge! "c04g step block before txn with inner" (str sa "\n" A "(:txn :owns (\"b\")\n  " sb "\n" B ")") (list (pair ea AA) (pair eb BB)))
          (judge! "c05 edit old inside, new after txn" (str "(:txn :owns (\"a\")\n  (:step :op \"edit\" :file \"a\" :old :raw\n" f "\nOLD\n" f "\n :new :raw))\n" f "\nNEW\n" f "\n") (list (pair ":old " "OLD\n") (pair ":new " "NEW\n")))
          (judge! "c05b edit new inline after :new, old after txn" (str "(:txn :owns (\"a\")\n  (:step :op \"edit\" :file \"a\" :old :raw :new :raw\n" f "\nNEW\n" f "\n))\n" f "\nOLD\n" f "\n") (list (pair ":old " "OLD\n") (pair ":new " "NEW\n")))
          (judge! "c05c edit old in region after close, new after txn" (str "(:txn :owns (\"a\")\n  (:step :op \"edit\" :file \"a\" :old :raw :new :raw)\n" f "\nOLD\n" f "\n)\n" f "\nNEW\n" f "\n") (list (pair ":old " "OLD\n") (pair ":new " "NEW\n")))
          (judge! "c05d edit plain two after" (str "(:step :op \"edit\" :file \"a\" :old :raw :new :raw)\n" f "\nOLD\n" f "\n" f "\nNEW\n" f "\n") (list (pair ":old " "OLD\n") (pair ":new " "NEW\n")))
          (judge! "c06 inline between raw steps inner" (str "(:txn :owns (\"a\" \"b\" \"c\")\n  " sa "\n" A "  (:step :op \"write\" :file \"b\" :content \"inl\")\n  " sc "\n" C ")") (list (pair ea AA) (pair eb "inl") (pair ec CC)))
          (judge! "c06b inline between raw steps tail" (str "(:txn :owns (\"a\" \"b\" \"c\")\n  " sa "\n  (:step :op \"write\" :file \"b\" :content \"inl\")\n  " sc ")\n" A C) (list (pair ea AA) (pair eb "inl") (pair ec CC)))
          (judge! "c06c block in inline step region" (str "(:txn :owns (\"a\" \"b\" \"c\")\n  " sa "\n  (:step :op \"write\" :file \"b\" :content \"inl\")\n" A "  " sc ")\n" C) (list (pair ea AA) (pair ec CC)))
          (judge! "c06d inline then raw step after b inner, a tail" (str "(:txn :owns (\"a\" \"b\" \"c\")\n  " sa "\n  " sc "\n  (:step :op \"write\" :file \"b\" :content \"inl\")\n" C ")\n" A) (list (pair ea AA) (pair ec CC)))
          (judge! "c07 code with step txn raw parens quotes inner" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n" f "\n" code f "\n  " sb "\n" B ")") (list (pair ea code) (pair eb BB)))
          (judge! "c07b code tail" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" f "\n" code f "\n" B) (list (pair ea code) (pair eb BB)))
          (judge! "c07c code single step" (str sa "\n" f "\n" code f "\n") (list (pair ea code)))
          (judge! "c08 four-tick md inner" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n" F "\n" md F "\n  " sb "\n" B ")") (list (pair ea md) (pair eb BB)))
          (judge! "c08b four-tick md tail" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" F "md\n" md F "\n" B) (list (pair ea md) (pair eb BB)))
          (judge! "c08c four-tick md single" (str sa "\n" F "\n" md F "\n") (list (pair ea md)))
          (judge! "c09 three-tick md with lang inner single" (str sa "\n" f "\n" md f "\n") (list (pair ea md)))
          (judge! "c09b three-tick md bare inner fence single" (str sa "\n" f "\n# T\n" f "\ncode\n" f "\nend\n" f "\n") (list (pair ea "# T\n```\ncode\n```\nend\n")))
          (judge! "c09c three-tick md bare inner fence in txn tail" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" f "\n# T\n" f "\ncode\n" f "\nend\n" f "\n" B) (list (pair ea "# T\n```\ncode\n```\nend\n") (pair eb BB)))
          (judge! "c10 lang opener" (str sa "\n" f "asl\nAAA\n" f "\n") (list (pair ea AA)))
          (judge! "c11 prose between step and block" (str sa "\nHere is the file:\n\n" A) (list (pair ea AA)))
          (judge! "c11b prose inside txn" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\nHere is a:\n" A "  " sb "\nand b:\n" B ")") (list (pair ea AA) (pair eb BB)))
          (judge! "c11c prose after txn" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\nFile a:\n" A "File b:\n" B) (list (pair ea AA) (pair eb BB)))
          (judge! "c12 CRLF" (str "(:txn :owns (\"a\" \"b\")\r\n  " sa "\r\n" f "\r\nAAA\r\n" f "\r\n  " sb ")\r\n" f "\r\nBBB\r\n" f "\r\n") (list (pair ea "AAA\r\n") (pair eb "BBB\r\n")))
          (judge! "c13 unclosed single" (str "(:step :op \"write\" :file \"a.asl\" :content :raw)\n" f "\nfn a -> Int64\n  (+ 1") (list (pair (st "content" "a.asl") "x")))
          (judge! "c13b unclosed second in tail" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" A f "\nBB partial") (list (pair ea AA) (pair eb BB)))
          (judge! "c13c unclosed tail eats next" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  " sb ")\n" f "\nAAA partial\n" B) (list (pair ea AA) (pair eb BB)))
          (judge! "c14 empty block" (str sa "\n" f "\n" f "\n") (list (pair ea "")))
          (judge! "c15 two blocks one field single" (str sa "\n" A X) (list (pair ea AA)))
          (judge! "c15b two blocks one field in txn" (str "(:txn :owns (\"a\")\n  " sa "\n" A X ")") (list (pair ea AA)))
          (judge! "c16 raw in why field" (str "(:step :op \"write\" :file \"a\" :why :raw :content :raw)\n" X A) (list (pair ea AA)))
          (judge! "c17 nested txn" (str "(:txn :owns (\"a\" \"b\")\n  (:txn :owns (\"a\")\n    " sa "\n" A ")\n  " sb "\n" B ")") (list (pair ea AA) (pair eb BB)))
          (judge! "c18 same file twice" (str "(:txn :owns (\"a\")\n  " sa "\n" A "  " sa "\n" B ")") (list (pair ea AA) (pair ea BB)))
          (judge! "c19 two single steps one block" (str sa "\n" sb "\n" B) (list (pair ea AA) (pair eb BB)))
          (judge! "c20 inline-after-raw b, a tail" (str "(:txn :owns (\"a\" \"b\")\n  " sa "\n  (:step :op \"write\" :file \"b\" :content :raw\n" B "))\n" A) (list (pair ea AA) (pair eb BB)))
          (judge! "c21 hoisted a then b inner" (str "(:txn :owns (\"a\" \"b\")\n  (:step :op \"write\" :file \"a\" :content :raw\n" A ")\n  " sb "\n" B ")") (list (pair ea AA) (pair eb BB)))
          (judge! "c22 step then non-raw step then block" (str sa "\n(:step :op \"gate\")\n" A) (list (pair ea AA)))
          (judge! "c23 block before txn" (str A "(:txn :owns (\"a\")\n  " sa ")") (list (pair ea AA)))
          (judge! "c24 tail blocks then second txn inner" (str "(:txn :owns (\"a\")\n  " sa ")\n" A "(:txn :owns (\"b\")\n  " sb "\n" B ")") (list (pair ea AA) (pair eb BB)))
          (judge! "c25 three in a row inner" (str "(:txn :owns (\"a\" \"b\" \"c\")\n  " sa "\n" A "  " sb "\n" B "  " sc "\n" C ")") (list (pair ea AA) (pair eb BB) (pair ec CC)))
          (judge! "c26 txn missing block for middle inner" (str "(:txn :owns (\"a\" \"b\" \"c\")\n  " sa "\n" A "  " sb "\n  " sc "\n" C ")") (list (pair ea AA) (pair eb BB) (pair ec CC)))
          (judge! "c27 stray block after a form whose block sits inside it" (str "(:step :op \"write\" :file \"a\" :content :raw\n" A ")\n" B) (list (pair ea AA)))
          (judge! "c28 raw marker on a key other than content, old or new" (str "(:step :op \"write\" :file \"a\" :content :raw :why :raw)\n" A) (list (pair ea AA))))]
    (listAll? (fn [x] x) r))
