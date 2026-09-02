# Phase 5 — Derived oracle predictions (ORACLES.md)

Per-fixture expected stdout for the driver-wrapped programs, derived by
executing the Python lowering of the checked-in oracle (oracle.py). These are the
predictions the interpreter is compared against in I3/I4/I5/I6.

## 01-basics
```
9
a
3
```

## 03-strings
```
HI!
A.L
ok42
0,2,4
6
```

## 04-longest-run
```
b
3
none
```

## 05-constructors
```
2,3,5,7,11
negative
8
k1
```

## 07-lambda-elision
```
2,4
2,4
6
3
a,cc,bbb
```

## 02-match
```
10
9
ok:3
division by zero
negative
```

## 18-pattern-binders
```
hi
missing
other
```

## 16-recursive-schema
```
3
6
```

## 17-nested-cons
```
3,7,5
1
```

## 20-option-result-ctors
```
some/ok:3|TFTF
none/err:x|FTFT
```

## 21-option-result-combinators
```
ok:43|43|43
err:E<bad:x>|FB|0
```

## 22-boolean-algebra
```
TTFTFFTF
FTFTTTFT
```

## 23-numeric
```
9|3|1|14|5|7|-7|2|7|some 3|some 1
none|none
9.0|3.5|1.0|14.0|5.0|7.0|-7.0|2.0|7.0|some 3.5|some 1.0
none|none
some 2147483647|2147483647.0|some 2147483647
2.0|7.0|some 7
some -9223372036854775808|some 0
some 7|some 7
0
```

## 24-list-reshaping
```
[9,0,1,2,3]|[0,1,2,3,100,200,300]|[3,2,1,0]|some [1,2,3]|some 0|some 1
none
[1,2]
```

## 25-list-aggregation
```
F|4|9.0|1.0|3.0|[1.0,2.0,3.0,3.0]
T|0|0.0|none|none|[]
T|some 0|4|9|[3,3,2,1]
b|a
T|some 0|T|T
```

## 26-map-lifecycle
```
3|T|2|b,c
3|F|3|a,b,c
```

## 27-string-query
```
6|some 2|T|F|T|F|6
6|some 0|T|T|F|F|6
an
```

## 28-string-transforms
```
axbxc|AXBXC|cXbXa|a-b-c|aXbXc|n=5|none|0.0
123|123|321|123|123|n=3|some 123|123.0
```

## 29-literals
```
3|5|-8|5|-9223372036854775808|4|9223372036854775807|-9223372036854775808|2147483647|-2147483648
1.0|-0.0|-2.5|-1.5
minus-one|-1|-1,-2
other|-1|-1,-2
-1
```

## 06-module (--root grammar/corpus/modules)
```
HI!
12.56636
```

## 09-imported-types (--root grammar/corpus/modules)
```
circle
rectangle
```

## 10-imported-generic-types (--root grammar/corpus/modules)
```
1
1
```

## 11-name-coexistence (--root grammar/corpus/modules)
```
blob
circle
rectangle
```

## 12-transitive-use (--root grammar/corpus/modules)
```
rectangle 1.0
```

## 15-shadowed-binders (--root grammar/corpus/modules)
```
7 6 101 102
```

