# Phase 3 baseline — 0add27a (2026-08-30)

## grammar/validate.py
fixture                        lark     tree-sitter  verdict
------------------------------------------------------------------
valid/01-basics.agents         parse    parse        ok
valid/02-match.agents          parse    parse        ok
valid/03-strings.agents        parse    parse        ok
valid/04-longest-run.agents    parse    parse        ok
valid/05-constructors.agents   parse    parse        ok
valid/06-module.agents         parse    parse        ok
valid/07-lambda-elision.agents parse    parse        ok
valid/08-io.agents             parse    parse        ok
valid/09-imported-types.agents parse    parse        ok
valid/10-imported-generic-types.agents parse    parse        ok
valid/11-name-coexistence.agents parse    parse        ok
valid/12-transitive-use.agents parse    parse        ok
valid/13-module-program.agents parse    parse        ok
valid/14-sequenced-bodies.agents parse    parse        ok
valid/15-shadowed-binders.agents parse    parse        ok
valid/16-recursive-schema.agents parse    parse        ok
valid/17-nested-cons.agents    parse    parse        ok
valid/18-pattern-binders.agents parse    parse        ok
valid/19-io-errors.agents      parse    parse        ok
valid/20-option-result-ctors.agents parse    parse        ok
valid/21-option-result-combinators.agents parse    parse        ok
valid/22-boolean-algebra.agents parse    parse        ok
valid/23-numeric.agents        parse    parse        ok
valid/24-list-reshaping.agents parse    parse        ok
valid/25-list-aggregation.agents parse    parse        ok
valid/26-map-lifecycle.agents  parse    parse        ok
valid/27-string-query.agents   parse    parse        ok
valid/28-string-transforms.agents parse    parse        ok
valid/29-literals.agents       parse    parse        ok
invalid/bare-decimal-point.agents reject   reject       ok
invalid/defun-list-params.agents reject   reject       ok
invalid/fn-typeparams.agents   reject   reject       ok
invalid/missing-arrow.agents   reject   reject       ok
invalid/pascal-function.agents reject   reject       ok
invalid/unbalanced.agents      reject   reject       ok
semantic/effect-in-pure-defun.agents parse    parse        ok
semantic/effect-in-pure-lambda.agents parse    parse        ok
semantic/exponent-is-not-a-literal.agents parse    parse        ok
semantic/export-bare-case.agents parse    parse        ok
semantic/export-undefined-type.agents parse    parse        ok
semantic/exported-without-doc.agents parse    parse        ok
semantic/import-cycle/a.agents parse    parse        ok
semantic/import-cycle/b.agents parse    parse        ok
semantic/import-unexported-case.agents parse    parse        ok
semantic/import-unexported-type.agents parse    parse        ok
semantic/imported-call-arity.agents parse    parse        ok
semantic/imported-ctor-missing-field.agents parse    parse        ok
semantic/imported-type-mismatch.agents parse    parse        ok
semantic/int32-literal-out-of-range.agents parse    parse        ok
semantic/int64-literal-out-of-range.agents parse    parse        ok
semantic/literal-in-call-head.agents parse    parse        ok
semantic/map-float-key.agents  parse    parse        ok
semantic/map-key-inferred.agents parse    parse        ok
semantic/map-key-io-error.agents parse    parse        ok
semantic/map-key-nested.agents parse    parse        ok
semantic/map-key-record.agents parse    parse        ok
semantic/map-key-through-typevar.agents parse    parse        ok
semantic/mixed-module-match.agents parse    parse        ok
semantic/non-exhaustive-imported-match.agents parse    parse        ok
semantic/non-exhaustive-match.agents parse    parse        ok
semantic/numeric-mix.agents    parse    parse        ok
semantic/parenthesised-case-is-not-a-binder.agents parse    parse        ok
semantic/private-type-in-exported-signature.agents parse    parse        ok
semantic/qualified-ctor-unexported.agents parse    parse        ok
semantic/reserved-prefix.agents parse    parse        ok
semantic/try-in-lambda.agents  parse    parse        ok
semantic/try-outside-result.agents parse    parse        ok
semantic/unapplied-pair-type.agents parse    parse        ok
semantic/unapplied-result-type.agents parse    parse        ok
semantic/unbound-in-cond.agents parse    parse        ok
semantic/unbound-name.agents   parse    parse        ok
semantic/unbound-typevar.agents parse    parse        ok
semantic/undetermined-lambda.agents parse    parse        ok
semantic/unexported-member.agents parse    parse        ok
semantic/unimported-alias-type.agents parse    parse        ok
semantic/wrong-alias-type.agents parse    parse        ok
semantic/wrong-argument-type.agents parse    parse        ok
semantic/wrong-arity.agents    parse    parse        ok
semantic/wrong-return-type.agents parse    parse        ok
modules/core/private.agents    parse    parse        ok
modules/core/shadow.agents     parse    parse        ok
modules/core/shapes.agents     parse    parse        ok
modules/core/strings.agents    parse    parse        ok
modules/core/trees.agents      parse    parse        ok
modules/text/report.agents     parse    parse        ok

probe                terminal         lark     tree-sitter  verdict
------------------------------------------------------------------
param type           QUALIFIED_TYPE   1        1            ok
type application     QUALIFIED_TYPE   1        1            ok
return type          QUALIFIED_TYPE   1        1            ok
ctor head            QUALIFIED_TYPE   2        2            ok
export entry         TYPE_NAME        1        1            ok
enum pattern head    QUALIFIED        1        1            ok
division             OPERATOR         1        1            ok
negative int operand INT              1        1            ok
negative float operand FLOAT            1        1            ok
boundary int literal INT              1        1            ok
spaced subtraction   OPERATOR         1        1            ok
spaced subtraction operand INT              1        1            ok
negative literal pattern INT              3        3            ok

semantic-only fixtures (parse by design, rejected by checker/gate.py): effect-in-pure-defun.agents, effect-in-pure-lambda.agents, exponent-is-not-a-literal.agents, export-bare-case.agents, export-undefined-type.agents, exported-without-doc.agents, import-cycle/a.agents, import-cycle/b.agents, import-unexported-case.agents, import-unexported-type.agents, imported-call-arity.agents, imported-ctor-missing-field.agents, imported-type-mismatch.agents, int32-literal-out-of-range.agents, int64-literal-out-of-range.agents, literal-in-call-head.agents, map-float-key.agents, map-key-inferred.agents, map-key-io-error.agents, map-key-nested.agents, map-key-record.agents, map-key-through-typevar.agents, mixed-module-match.agents, non-exhaustive-imported-match.agents, non-exhaustive-match.agents, numeric-mix.agents, parenthesised-case-is-not-a-binder.agents, private-type-in-exported-signature.agents, qualified-ctor-unexported.agents, reserved-prefix.agents, try-in-lambda.agents, try-outside-result.agents, unapplied-pair-type.agents, unapplied-result-type.agents, unbound-in-cond.agents, unbound-name.agents, unbound-typevar.agents, undetermined-lambda.agents, unexported-member.agents, unimported-alias-type.agents, wrong-alias-type.agents, wrong-argument-type.agents, wrong-arity.agents, wrong-return-type.agents

0 failure(s)

## grammar/closure_audit.py
qualified heads (checker owns)  : 10
builtins defined in section 6 : 107
definitions found in sources  : 106
distinct call heads           : 135
executed builtins             : 107/107  (100%)

OK: spec and corpus are closed, and every builtin is executed

## prelude/generate.py --check

## checker/gate.py
fixture                                expected    reported                     verdict
----------------------------------------------------------------------------------------
valid/01-basics.agents                 clean      -                            ok
valid/02-match.agents                  clean      -                            ok
valid/03-strings.agents                clean      -                            ok
valid/04-longest-run.agents            clean      -                            ok
valid/05-constructors.agents           clean      -                            ok
valid/06-module.agents                 clean      -                            ok
valid/07-lambda-elision.agents         clean      -                            ok
valid/08-io.agents                     clean      -                            ok
valid/09-imported-types.agents         clean      -                            ok
valid/10-imported-generic-types.agents clean      -                            ok
valid/11-name-coexistence.agents       clean      -                            ok
valid/12-transitive-use.agents         clean      -                            ok
valid/13-module-program.agents         clean      -                            ok
valid/14-sequenced-bodies.agents       clean      -                            ok
valid/15-shadowed-binders.agents       clean      -                            ok
valid/16-recursive-schema.agents       clean      -                            ok
valid/17-nested-cons.agents            clean      -                            ok
valid/18-pattern-binders.agents        clean      -                            ok
valid/19-io-errors.agents              clean      -                            ok
valid/20-option-result-ctors.agents    clean      -                            ok
valid/21-option-result-combinators.agents clean      -                            ok
valid/22-boolean-algebra.agents        clean      -                            ok
valid/23-numeric.agents                clean      -                            ok
valid/24-list-reshaping.agents         clean      -                            ok
valid/25-list-aggregation.agents       clean      -                            ok
valid/26-map-lifecycle.agents          clean      -                            ok
valid/27-string-query.agents           clean      -                            ok
valid/28-string-transforms.agents      clean      -                            ok
valid/29-literals.agents               clean      -                            ok
modules/core/private.agents            clean      -                            ok
modules/core/shadow.agents             clean      -                            ok
modules/core/shapes.agents             clean      -                            ok
modules/core/strings.agents            clean      -                            ok
modules/core/trees.agents              clean      -                            ok
modules/text/report.agents             clean      -                            ok
semantic/effect-in-pure-defun.agents   rule-12     rule-12                      ok
semantic/effect-in-pure-lambda.agents  rule-12     rule-12                      ok
semantic/exponent-is-not-a-literal.agents rule-2      rule-2                       ok
semantic/export-bare-case.agents       rule-2!     rule-2                       ok
semantic/export-undefined-type.agents  rule-2!     rule-2                       ok
semantic/exported-without-doc.agents   rule-8      rule-8                       ok
semantic/import-cycle/a.agents         rule-11     rule-11                      ok
semantic/import-cycle/b.agents         rule-11     rule-11                      ok
semantic/import-unexported-case.agents rule-9!     rule-9                       ok
semantic/import-unexported-type.agents rule-9!     rule-9                       ok
semantic/imported-call-arity.agents    arity!      arity                        ok
semantic/imported-ctor-missing-field.agents ctor!       ctor                         ok
semantic/imported-type-mismatch.agents type!       type                         ok
semantic/int32-literal-out-of-range.agents literal-range! literal-range                ok
semantic/int64-literal-out-of-range.agents literal-range! literal-range                ok
semantic/literal-in-call-head.agents   not-callable! not-callable                 ok
semantic/map-float-key.agents          map-key-order! map-key-order                ok
semantic/map-key-inferred.agents       map-key-order! map-key-order                ok
semantic/map-key-io-error.agents       map-key-order! map-key-order                ok
semantic/map-key-nested.agents         map-key-order! map-key-order                ok
semantic/map-key-record.agents         map-key-order! map-key-order                ok
semantic/map-key-through-typevar.agents map-key-order! map-key-order                ok
semantic/mixed-module-match.agents     rule-4!     rule-4                       ok
semantic/non-exhaustive-imported-match.agents rule-4!     rule-4                       ok
semantic/non-exhaustive-match.agents   rule-4      rule-4                       ok
semantic/numeric-mix.agents            rule-6      rule-6,rule-6                ok
semantic/parenthesised-case-is-not-a-binder.agents rule-4!     rule-4                       ok
semantic/private-type-in-exported-signature.agents rule-13!    rule-13                      ok
semantic/qualified-ctor-unexported.agents rule-9!     rule-9,rule-9,rule-9         ok
semantic/reserved-prefix.agents        rule-7      rule-7                       ok
semantic/try-in-lambda.agents          rule-5      rule-5,type                  ok
semantic/try-outside-result.agents     rule-5      rule-5,type                  ok
semantic/unapplied-pair-type.agents    type-arity! type-arity                   ok
semantic/unapplied-result-type.agents  type-arity! type-arity                   ok
semantic/unbound-in-cond.agents        rule-2!     rule-2                       ok
semantic/unbound-name.agents           rule-2      rule-2                       ok
semantic/unbound-typevar.agents        rule-10     rule-10,rule-10              ok
semantic/undetermined-lambda.agents    annotation  annotation                   ok
semantic/unexported-member.agents      rule-9      rule-9                       ok
semantic/unimported-alias-type.agents  rule-9!     rule-9                       ok
semantic/wrong-alias-type.agents       rule-9!     rule-9                       ok
semantic/wrong-argument-type.agents    type        type                         ok
semantic/wrong-arity.agents            arity       arity                        ok
semantic/wrong-return-type.agents      type        type                         ok


0 failure(s)

## backend/check_corpus.py
fixture                    python       compile    run        rust         rustc     
------------------------------------------------------------------------------------
01-basics.agents           ok           ok         ok         ok           ok        
02-match.agents            ok           ok         ok         ok           ok        
03-strings.agents          ok           ok         ok         ok           ok        
04-longest-run.agents      ok           ok         ok         ok           ok        
05-constructors.agents     ok           ok         ok         ok           ok        
06-module.agents           ok           ok         ok         ok           ok        
07-lambda-elision.agents   ok           ok         ok         ok           ok        
08-io.agents               ok           ok         -          ok           ok        
09-imported-types.agents   ok           ok         ok         ok           ok        
10-imported-generic-types.agents ok           ok         ok         ok           ok        
11-name-coexistence.agents ok           ok         ok         ok           ok        
12-transitive-use.agents   ok           ok         ok         ok           ok        
13-module-program.agents   ok           ok         -          ok           ok        
14-sequenced-bodies.agents ok           ok         ok         ok           ok        
15-shadowed-binders.agents ok           ok         ok         ok           ok        
16-recursive-schema.agents ok           ok         ok         ok           ok        
17-nested-cons.agents      ok           ok         ok         ok           ok        
18-pattern-binders.agents  ok           ok         ok         ok           ok        
19-io-errors.agents        ok           ok         -          ok           ok        
20-option-result-ctors.agents ok           ok         ok         ok           ok        
21-option-result-combinators.agents ok           ok         ok         ok           ok        
22-boolean-algebra.agents  ok           ok         ok         ok           ok        
23-numeric.agents          ok           ok         ok         ok           ok        
24-list-reshaping.agents   ok           ok         ok         ok           ok        
25-list-aggregation.agents ok           ok         ok         ok           ok        
26-map-lifecycle.agents    ok           ok         ok         ok           ok        
27-string-query.agents     ok           ok         ok         ok           ok        
28-string-transforms.agents ok           ok         ok         ok           ok        
29-literals.agents         ok           ok         ok         ok           ok        
histogram.agents           ok           ok         -          ok           ok        
tight.agents               ok           ok         -          ok           ok        


0 failure(s)

## backend/monomorphism.py
probed builtins : 56
  excluded [effect       ]   9: read-line read-all print println eprintln file-read file-write file-append file-exists?
  excluded [variadic     ]   2: str list
  excluded [higher-order ]   7: list-sort-by map filter fold option-map result-map result-map-err
  excluded [monomorphic  ]  33: and or not string-length string-empty? string-slice string-index-of string-contains? string-starts-with? string-ends-with? string-split string-join string-upper string-lower string-trim string-reverse string-replace string-chars string-from-int64 string-from-float64 string-to-int64 string-to-float64 int32-to-int64 int64-to-int32 int64-to-float64 float64-to-int64 range not-found permission-denied already-exists invalid-path interrupted other
candidates      : 440
narrowed        : 40 (map-key-order)
probes          : 400
checker diags   : 0
rustc           : ok
py_compile      : ok

0 failure(s)

## backend/differential.py

option-result-ctors — classify
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'3', 'x'     ["pair", "some/ok:3|TFTF", "none/err:x|FTFT"] ["pair", "some/ok:3|TFTF", "none/err:x|FTFT"] ["pair", "some/ok:3|TFTF", "none/err:x|FTFT"]
'x', '3'     ["pair", "none/err:x|FTFT", "some/ok:3|TFTF"] ["pair", "none/err:x|FTFT", "some/ok:3|TFTF"] ["pair", "none/err:x|FTFT", "some/ok:3|TFTF"]
'', '0'      ["pair", "none/err:|FTFT", "some/ok:0|TFTF"] ["pair", "none/err:|FTFT", "some/ok:0|TFTF"] ["pair", "none/err:|FTFT", "some/ok:0|TFTF"]

option-result-combinators — resolve
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'21', 0      "ok:43|43|43"          "ok:43|43|43"          "ok:43|43|43"         
'x', 5       "err:E<bad:x>|FB|5"    "err:E<bad:x>|FB|5"    "err:E<bad:x>|FB|5"   
'', 9        "err:E<bad:>|FB|9"     "err:E<bad:>|FB|9"     "err:E<bad:>|FB|9"    

boolean-algebra — band
input        expected               python                 rust                  
----------------------------------------------------------------------------------
3, 3, 7      "TTFTFFTF"             "TTFTFFTF"             "TTFTFFTF"            
3, 7, 7      "TTTFTTFF"             "TTTFTTFF"             "TTTFTTFF"            
3, 2, 7      "FTFTTTFT"             "FTFTTTFT"             "FTFTTTFT"            
3, 8, 7      "TFTFTFTT"             "TFTFTFTT"             "TFTFTFTT"            
3, 5, 7      "TTTTTTFF"             "TTTTTTFF"             "TTTTTTFF"            

numeric-int64-edge — edge
input        expected               python                 rust                  
----------------------------------------------------------------------------------
-1           "none|some 0"          "none|some 0"          "none|some 0"         
1            "some -9223372036854775808|some 0" "some -9223372036854775808|some 0" "some -9223372036854775808|some 0"
0            "none|none"            "none|none"            "none|none"           
2            "some -4611686018427387904|some 0" "some -4611686018427387904|some 0" "some -4611686018427387904|some 0"
3            "some -3074457345618258602|some -2" "some -3074457345618258602|some -2" "some -3074457345618258602|some -2"

numeric-float64 — fnum
input        expected               python                 rust                  
----------------------------------------------------------------------------------
7, 2         "9.0|3.5|1.0|14.0|5.0|7.0|-7.0|2.0|7.0|some 3.5|some 1.0" "9.0|3.5|1.0|14.0|5.0|7.0|-7.0|2.0|7.0|some 3.5|some 1.0" "9.0|3.5|1.0|14.0|5.0|7.0|-7.0|2.0|7.0|some 3.5|some 1.0"
-7, 2        "-5.0|-3.5|-1.0|-14.0|-9.0|7.0|7.0|-7.0|2.0|some -3.5|some -1.0" "-5.0|-3.5|-1.0|-14.0|-9.0|7.0|7.0|-7.0|2.0|some -3.5|some -1.0" "-5.0|-3.5|-1.0|-14.0|-9.0|7.0|7.0|-7.0|2.0|some -3.5|some -1.0"
5, 0         "none|none"            "none|none"            "none|none"           
7, 3         "10.0|2.3333333333333335|1.0|21.0|4.0|7.0|-7.0|3.0|7.0|some 2.3333333333333335|some 1.0" "10.0|2.3333333333333335|1.0|21.0|4.0|7.0|-7.0|3.0|7.0|some 2.3333333333333335|some 1.0" "10.0|2.3333333333333335|1.0|21.0|4.0|7.0|-7.0|3.0|7.0|some 2.3333333333333335|some 1.0"
9007199254740993, 2 "9007199254740994.0|4503599627370496.0|0.0|1.8014398509481984e+16|9007199254740990.0|9007199254740992.0|-9007199254740992.0|2.0|9007199254740992.0|some 4503599627370496.0|some 0.0" "9007199254740994.0|4503599627370496.0|0.0|1.8014398509481984e+16|9007199254740990.0|9007199254740992.0|-9007199254740992.0|2.0|9007199254740992.0|some 4503599627370496.0|some 0.0" "9007199254740994.0|4503599627370496.0|0.0|1.8014398509481984e+16|9007199254740990.0|9007199254740992.0|-9007199254740992.0|2.0|9007199254740992.0|some 4503599627370496.0|some 0.0"

numeric-from-float — from-float
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'9223372036854775808' "none|none"            "none|none"            "none|none"           
'-9223372036854775808' "some -9223372036854775808|some -9223372036854775808" "some -9223372036854775808|some -9223372036854775808" "some -9223372036854775808|some -9223372036854775808"
'1e30'       "none|none"            "none|none"            "none|none"           
'nan'        "none|none"            "none|none"            "none|none"           
'1_0'        "some 0|none"          "some 0|none"          "some 0|none"         
'-3.9'       "some -3|none"         "some -3|none"         "some -3|none"        
'12'         "some 12|some 12"      "some 12|some 12"      "some 12|some 12"     

numeric-int64 — num
input        expected               python                 rust                  
----------------------------------------------------------------------------------
7, 2         "9|3|1|14|5|7|-7|2|7|some 3|some 1" "9|3|1|14|5|7|-7|2|7|some 3|some 1" "9|3|1|14|5|7|-7|2|7|some 3|some 1"
-7, 2        "-5|-3|-1|-14|-9|7|7|-7|2|some -3|some -1" "-5|-3|-1|-14|-9|7|7|-7|2|some -3|some -1" "-5|-3|-1|-14|-9|7|7|-7|2|some -3|some -1"
5, 0         "none|none"            "none|none"            "none|none"           
7, 3         "10|2|1|21|4|7|-7|3|7|some 2|some 1" "10|2|1|21|4|7|-7|3|7|some 2|some 1" "10|2|1|21|4|7|-7|3|7|some 2|some 1"
9007199254740993, 2 "9007199254740995|4503599627370496|1|18014398509481986|9007199254740991|9007199254740993|-9007199254740993|2|9007199254740993|some 4503599627370496|some 1" "9007199254740995|4503599627370496|1|18014398509481986|9007199254740991|9007199254740993|-9007199254740993|2|9007199254740993|some 4503599627370496|some 1" "9007199254740995|4503599627370496|1|18014398509481986|9007199254740991|9007199254740993|-9007199254740993|2|9007199254740993|some 4503599627370496|some 1"

numeric-minmax — minmax
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'nan', '1.0' "1.0|nan|none"         "1.0|nan|none"         "1.0|nan|none"        
'1.0', 'nan' "1.0|nan|some 1"       "1.0|nan|some 1"       "1.0|nan|some 1"      
'nan', 'nan' "nan|nan|none"         "nan|nan|none"         "nan|nan|none"        
'3.9', '1.5' "1.5|3.9|some 3"       "1.5|3.9|some 3"       "1.5|3.9|some 3"      
'-3.9', '1.5' "-3.9|1.5|some -3"     "-3.9|1.5|some -3"     "-3.9|1.5|some -3"    
'2.0', '2.0' "2.0|2.0|some 2"       "2.0|2.0|some 2"       "2.0|2.0|some 2"      
'x', '1.0'   "0.0|1.0|some 0"       "0.0|1.0|some 0"       "0.0|1.0|some 0"      

numeric-conversions — narrow
input        expected               python                 rust                  
----------------------------------------------------------------------------------
2147483647   "some 2147483647|2147483647.0|some 2147483647" "some 2147483647|2147483647.0|some 2147483647" "some 2147483647|2147483647.0|some 2147483647"
2147483648   "none|2147483648.0|some 2147483648" "none|2147483648.0|some 2147483648" "none|2147483648.0|some 2147483648"
-2147483648  "some -2147483648|-2147483648.0|some -2147483648" "some -2147483648|-2147483648.0|some -2147483648" "some -2147483648|-2147483648.0|some -2147483648"
-2147483649  "none|-2147483649.0|some -2147483649" "none|-2147483649.0|some -2147483649" "none|-2147483649.0|some -2147483649"
9007199254740993 "none|9007199254740992.0|some 9007199254740992" "none|9007199254740992.0|some 9007199254740992" "none|9007199254740992.0|some 9007199254740992"

list-pairs — pairs
input        expected               python                 rust                  
----------------------------------------------------------------------------------
2            [["pair", 0, "a"], ["pair", 1, "b"]] [["pair", 0, "a"], ["pair", 1, "b"]] [["pair", 0, "a"], ["pair", 1, "b"]]
5            [["pair", 0, "a"], ["pair", 1, "b"], ["pair", 2, "c"]] [["pair", 0, "a"], ["pair", 1, "b"], ["pair", 2, "c"]] [["pair", 0, "a"], ["pair", 1, "b"], ["pair", 2, "c"]]

list-reshaping — reshape
input        expected               python                 rust                  
----------------------------------------------------------------------------------
4            "[9,0,1,2,3]|[0,1,2,3,100,200,300]|[3,2,1,0]|some [1,2,3]|some 0|some 1" "[9,0,1,2,3]|[0,1,2,3,100,200,300]|[3,2,1,0]|some [1,2,3]|some 0|some 1" "[9,0,1,2,3]|[0,1,2,3,100,200,300]|[3,2,1,0]|some [1,2,3]|some 0|some 1"
1            "[9,0]|[0,100,200,300]|[0]|some []|some 0|none" "[9,0]|[0,100,200,300]|[0]|some []|some 0|none" "[9,0]|[0,100,200,300]|[0]|some []|some 0|none"
0            "[9]|[100,200,300]|[]|none|none|none" "[9]|[100,200,300]|[]|none|none|none" "[9]|[100,200,300]|[]|none|none|none"

list-window — window
input        expected               python                 rust                  
----------------------------------------------------------------------------------
4, 1, 3      ["some", [1, 2]]       ["some", [1, 2]]       ["some", [1, 2]]      
4, 0, 4      ["some", [0, 1, 2, 3]] ["some", [0, 1, 2, 3]] ["some", [0, 1, 2, 3]]
4, 0, 5      ["none"]               ["none"]               ["none"]              
4, 3, 1      ["none"]               ["none"]               ["none"]              
4, 2, 2      ["some", []]           ["some", []]           ["some", []]          

list-aggregation — agg
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'3,1,3,2'    "F|4|9.0|1.0|3.0|[1.0,2.0,3.0,3.0]" "F|4|9.0|1.0|3.0|[1.0,2.0,3.0,3.0]" "F|4|9.0|1.0|3.0|[1.0,2.0,3.0,3.0]"
'0.1,0.2'    "F|2|0.30000000000000004|0.1|0.2|[0.1,0.2]" "F|2|0.30000000000000004|0.1|0.2|[0.1,0.2]" "F|2|0.30000000000000004|0.1|0.2|[0.1,0.2]"
''           "F|1|0.0|0.0|0.0|[0.0]" "F|1|0.0|0.0|0.0|[0.0]" "F|1|0.0|0.0|0.0|[0.0]"
'-2,-9,4'    "F|3|-7.0|-9.0|4.0|[-9.0,-2.0,4.0]" "F|3|-7.0|-9.0|4.0|[-9.0,-2.0,4.0]" "F|3|-7.0|-9.0|4.0|[-9.0,-2.0,4.0]"
'5'          "F|1|5.0|5.0|5.0|[5.0]" "F|1|5.0|5.0|5.0|[5.0]" "F|1|5.0|5.0|5.0|[5.0]"

list-aggregation-empty — agg-empty
input        expected               python                 rust                  
----------------------------------------------------------------------------------
             "T|0|0.0|none|none|[]" "T|0|0.0|none|none|[]" "T|0|0.0|none|none|[]"

list-lookup — lookup
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'3,1,3,2', 2 "T|some 3|4|9|[3,3,2,1]" "T|some 3|4|9|[3,3,2,1]" "T|some 3|4|9|[3,3,2,1]"
'3,1,3,2', 3 "T|some 0|4|9|[3,3,2,1]" "T|some 0|4|9|[3,3,2,1]" "T|some 0|4|9|[3,3,2,1]"
'3,1,3,2', 9 "F|none|4|9|[3,3,2,1]" "F|none|4|9|[3,3,2,1]" "F|none|4|9|[3,3,2,1]"

list-nan-identity — nan-identity
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'nan,1'      "F|none|F|F"           "F|none|F|F"           "F|none|F|F"          
'1,2'        "T|some 0|T|T"         "T|some 0|T|T"         "T|some 0|T|T"        
'1,nan'      "T|some 0|F|T"         "T|some 0|F|T"         "T|some 0|F|T"        

list-sort-by-nan-keys — rank
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'3,-nan,1,nan,2' "1|2|3|-nan|nan"       "1|2|3|-nan|nan"       "1|2|3|-nan|nan"      
'nan,3,1'    "1|3|nan"              "1|3|nan"              "1|3|nan"             
'2,1'        "1|2"                  "1|2"                  "1|2"                 

list-aggregation-nan — agg
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'3,nan,0.5,1,2' "F|5|nan|0.5|nan|[0.5,1.0,2.0,3.0,nan]" "F|5|nan|0.5|nan|[0.5,1.0,2.0,3.0,nan]" "F|5|nan|0.5|nan|[0.5,1.0,2.0,3.0,nan]"
'3,1,nan,2'  "F|4|nan|1.0|nan|[1.0,2.0,3.0,nan]" "F|4|nan|1.0|nan|[1.0,2.0,3.0,nan]" "F|4|nan|1.0|nan|[1.0,2.0,3.0,nan]"
'nan'        "F|1|nan|nan|nan|[nan]" "F|1|nan|nan|nan|[nan]" "F|1|nan|nan|nan|[nan]"
'nan,nan,1'  "F|3|nan|1.0|nan|[1.0,nan,nan]" "F|3|nan|1.0|nan|[1.0,nan,nan]" "F|3|nan|1.0|nan|[1.0,nan,nan]"

map-counts — counts
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'a b a c'    {"a": 2, "b": 1, "c": 1} {"a": 2, "b": 1, "c": 1} {"a": 2, "b": 1, "c": 1}
''           {}                     {}                     {}                    
'b a'        {"a": 1, "b": 1}       {"a": 1, "b": 1}       {"a": 1, "b": 1}      

map-lifecycle — lifecycle
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'a b a c', 'a' "3|T|2|b,c"            "3|T|2|b,c"            "3|T|2|b,c"           
'a b a c', 'z' "3|F|3|a,b,c"          "3|F|3|a,b,c"          "3|F|3|a,b,c"         
'', 'a'      "0|F|0|"               "0|F|0|"               "0|F|0|"              
'c b a', 'b' "3|T|2|a,c"            "3|T|2|a,c"            "3|T|2|a,c"           

string-cut — cut
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'banana', 1, 3 ["some", "an"]         ["some", "an"]         ["some", "an"]        
'banana', 0, 6 ["some", "banana"]     ["some", "banana"]     ["some", "banana"]    
'banana', 0, 7 ["none"]               ["none"]               ["none"]              
'banana', 3, 1 ["none"]               ["none"]               ["none"]              
'héllo', 1, 3 ["some", "\u00e9l"]    ["some", "\u00e9l"]    ["some", "\u00e9l"]   

string-query — query
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'banana', 'na' "6|some 2|T|F|T|F|6"   "6|some 2|T|F|T|F|6"   "6|some 2|T|F|T|F|6"  
'log:hello', 'log:' "9|some 0|T|T|F|F|9"   "9|some 0|T|T|F|F|9"   "9|some 0|T|T|F|F|9"  
'hello.log', '.log' "9|some 5|T|F|T|F|9"   "9|some 5|T|F|T|F|9"   "9|some 5|T|F|T|F|9"  
'abc', 'abc' "3|some 0|T|T|T|F|3"   "3|some 0|T|T|T|F|3"   "3|some 0|T|T|T|F|3"  
'abc', 'z'   "3|none|F|F|F|F|3"     "3|none|F|F|F|F|3"     "3|none|F|F|F|F|3"    
'', 'a'      "0|none|F|F|F|T|0"     "0|none|F|F|F|T|0"     "0|none|F|F|F|T|0"    
'héllo', 'l' "5|some 2|T|F|F|F|5"   "5|some 2|T|F|F|F|5"   "5|some 2|T|F|F|F|5"  

string-transforms — transform
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'aXbXc'      "axbxc|AXBXC|cXbXa|a-b-c|aXbXc|n=5|none|0.0" "axbxc|AXBXC|cXbXa|a-b-c|aXbXc|n=5|none|0.0" "axbxc|AXBXC|cXbXa|a-b-c|aXbXc|n=5|none|0.0"
'Hello World' "hello world|HELLO WORLD|dlroW olleH|Hello World|Hello+World|n=11|none|0.0" "hello world|HELLO WORLD|dlroW olleH|Hello World|Hello+World|n=11|none|0.0" "hello world|HELLO WORLD|dlroW olleH|Hello World|Hello+World|n=11|none|0.0"
'abc'        "abc|ABC|cba|abc|abc|n=3|none|0.0" "abc|ABC|cba|abc|abc|n=3|none|0.0" "abc|ABC|cba|abc|abc|n=3|none|0.0"
'42'         "42|42|24|42|42|n=2|some 42|42.0" "42|42|24|42|42|n=2|some 42|42.0" "42|42|24|42|42|n=2|some 42|42.0"
'2.5'        "2.5|2.5|5.2|2.5|2.5|n=3|none|2.5" "2.5|2.5|5.2|2.5|2.5|n=3|none|2.5" "2.5|2.5|5.2|2.5|2.5|n=3|none|2.5"
'0.1'        "0.1|0.1|1.0|0.1|0.1|n=3|none|0.1" "0.1|0.1|1.0|0.1|0.1|n=3|none|0.1" "0.1|0.1|1.0|0.1|0.1|n=3|none|0.1"
'x'          "x|X|x|x|x|n=1|none|0.0" "x|X|x|x|x|n=1|none|0.0" "x|X|x|x|x|n=1|none|0.0"
''           "|||||n=0|none|0.0"    "|||||n=0|none|0.0"    "|||||n=0|none|0.0"   

literal-floats — floats
input        expected               python                 rust                  
----------------------------------------------------------------------------------
2.5          "1.0|-0.0|-2.5|-1.5"   "1.0|-0.0|-2.5|-1.5"   "1.0|-0.0|-2.5|-1.5"  
0.0          "-1.5|-0.0|-0.0|-1.5"  "-1.5|-0.0|-0.0|-1.5"  "-1.5|-0.0|-0.0|-1.5" 
-1.5         "-3.0|-0.0|1.5|-1.5"   "-3.0|-0.0|1.5|-1.5"   "-3.0|-0.0|1.5|-1.5"  

literal-near — near
input        expected               python                 rust                  
----------------------------------------------------------------------------------
-1           "minus-one|-1|-1,-2"   "minus-one|-1|-1,-2"   "minus-one|-1|-1,-2"  
0            "other|-1|-1,-2"       "other|-1|-1,-2"       "other|-1|-1,-2"      
-9223372036854775808 "other|-1|-1,-2"       "other|-1|-1,-2"       "other|-1|-1,-2"      

literal-signs — signs
input        expected               python                 rust                  
----------------------------------------------------------------------------------
4            "3|5|-8|5|-9223372036854775808|4|9223372036854775807|-9223372036854775808|2147483647|-2147483648" "3|5|-8|5|-9223372036854775808|4|9223372036854775807|-9223372036854775808|2147483647|-2147483648" "3|5|-8|5|-9223372036854775808|4|9223372036854775807|-9223372036854775808|2147483647|-2147483648"
0            "-1|1|0|5|-9223372036854775808|0|9223372036854775807|-9223372036854775808|2147483647|-2147483648" "-1|1|0|5|-9223372036854775808|0|9223372036854775807|-9223372036854775808|2147483647|-2147483648" "-1|1|0|5|-9223372036854775808|0|9223372036854775807|-9223372036854775808|2147483647|-2147483648"
-3           "-4|-2|6|5|-9223372036854775808|-3|9223372036854775807|-9223372036854775808|2147483647|-2147483648" "-4|-2|6|5|-9223372036854775808|-3|9223372036854775807|-9223372036854775808|2147483647|-2147483648" "-4|-2|6|5|-9223372036854775808|-3|9223372036854775807|-9223372036854775808|2147483647|-2147483648"

literal-step — step
input        expected               python                 rust                  
----------------------------------------------------------------------------------
0            -1                     -1                     -1                    
-2147483647  -2147483648            -2147483648            -2147483648           
2147483647   2147483646             2147483646             2147483646            

histogram — histogram
input        expected               python                 rust                  
----------------------------------------------------------------------------------
'a b c'      {"a": 1, "b": 1, "c": 1} {"a": 1, "b": 1, "c": 1} {"a": 1, "b": 1, "c": 1}
'a b b a'    {"a": 2, "b": 2}       {"a": 2, "b": 2}       {"a": 2, "b": 2}      
'a b c a b'  {"a": 2, "b": 2}       {"a": 2, "b": 2}       {"a": 2, "b": 2}      
'b b b b a'  {"b": 4}               {"b": 4}               {"b": 4}              
''           {}                     {}                     {}                    
'   '        {}                     {}                     {}                    
'a'          {"a": 1}               {"a": 1}               {"a": 1}              

argv                   python                   stderr               rust                     exit
--------------------------------------------------------------------------------------------------------
sample.txt             'hello from a file\n\n'  ''                   'hello from a file\n\n'  0/0
missing.txt            'missing\n'              ''                   'missing\n'              0/0
sample.txt out.txt     'hello from a file\n\n'  ''                   'hello from a file\n\n'  0/0
sample.txt nodir/out.txt ''                       'not-found\n'        ''                       1/1
                       ''                       'usage: io-demo SRC [DST]\n' ''                       0/0

argv                   python                   stderr               rust                     exit
--------------------------------------------------------------------------------------------------------
                       'rectangle\n6.0\n'       ''                   'rectangle\n6.0\n'       0/0

argv                   python                   stderr               rust                     exit
--------------------------------------------------------------------------------------------------------
                       'function-1\nlet-1\ncond-1\nelse-1\nmatch-ok-1\nmatch-err-1\nlambda-1\nlambda-1\ncond-bare\nelse-bare\n15\n13\n30\n' ''                   'function-1\nlet-1\ncond-1\nelse-1\nmatch-ok-1\nmatch-err-1\nlambda-1\nlambda-1\ncond-bare\nelse-bare\n15\n13\n30\n' 0/0

argv                   python                   stderr               rust                     exit
--------------------------------------------------------------------------------------------------------
                       '7 6 101 102\n'          ''                   '7 6 101 102\n'          0/0

argv                   python                   stderr               rust                     exit
--------------------------------------------------------------------------------------------------------
log.txt                'A\nB\n'                 ''                   'A\nB\n'                 0/0
absent.txt             'absent\n'               ''                   'absent\n'               0/0
nodir/out.txt          'not-found\n'            'not-found\n'        'not-found\n'            1/1
noperm.txt             'permission-denied\n'    'permission-denied\n' 'permission-denied\n'    1/1
log.txt                'A\n'                    ''                   'A\n'                    0/0
--labels               'not-found,permission-denied,already-exists,invalid-path,interrupted,other\n' ''                   'not-found,permission-denied,already-exists,invalid-path,interrupted,other\n' 0/0
--slurp                'x\ny\n'                 ''                   'x\ny\n'                 0/0

0 disagreement(s) across 120 function cases + 15 program cases x 2 backends

## backend/exec_coverage.py
programs executed : 69
executed builtins : 107/107  (100%)

0 coverage failure(s)

## pytest
[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m [ 44%]
[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m [ 89%]
[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m.[0m[32m                                                        [100%][0m
[32m[32m[1m161 passed[0m[32m in 48.76s[0m[0m
