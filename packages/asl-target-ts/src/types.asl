(module asl-target-ts/types
  :x [emitTsType tsMangleIdent isTsKeyword? emitTsHeader emitTsRuntimeHelpers primitiveTsType isIntegerLiteral? tsNumberLiteral]
  :i [])

fn isTsKeyword? s: String -> Bool
  (listContains? (list "function" "class" "var" "let" "const" "import" "export" "default" "delete" "typeof" "instanceof" "void" "new" "in" "yield" "await" "return" "switch" "case" "break" "continue" "throw" "try" "catch" "finally" "debugger" "with" "enum") s)

fn kebabToCamel chars: (List String) toUpper: Bool acc: String -> String
  (mt (listHead chars)
    ((none) acc)
    ((some c)
      (let [(rest (optionOr (listTail chars) (list)))]
        (cond
          ((or (= c "-") (= c "_"))
            (kebabToCamel rest true acc))
          ((= c "?")
            (kebabToCamel rest false acc))
          ((= c "!")
            (kebabToCamel rest false (str acc "Mut")))
          (toUpper
            (kebabToCamel rest false (str acc (stringUpper c))))
          (else
            (kebabToCamel rest false (str acc c)))))))

fn tsMangleIdent s: String -> String
  (if (stringContains? s "/")
    (let [(parts (stringSplit s "/"))]
      (if (>= (listLength parts) 2)
        (let [(pfx (tsMangleIdent (optionOr (listHead parts) "")))
              (sfx (tsMangleIdent (optionOr (listGet parts 1) "")))]
          (str pfx "." sfx))
        s))
    (let [(base (if (and (stringEndsWith? s "?")
                         (not (stringStartsWith? s "is-"))
                         (not (stringStartsWith? s "is"))
                         (not (stringStartsWith? s "has-"))
                         (not (stringStartsWith? s "has")))
                  (str "is-" s)
                  s))
          (camel (kebabToCamel (stringChars base) false ""))]
      (if (or (isTsKeyword? camel) (or (= camel "true") (= camel "false")))
        (str camel "_")
        camel)))

fn isDigitChar? c: String -> Bool
  (and (>= c "0") (<= c "9"))

fn isAllDigits? chars: (List String) -> Bool
  (fold (fn [(acc Bool) (c String)] -> Bool (and acc (isDigitChar? c))) true chars)

fn isIntegerLiteral? s: String -> Bool
  (let [(body (if (stringStartsWith? s "-") (optionOr (stringSlice s 1 (stringLength s)) "") s))]
    (and (> (stringLength body) 0) (isAllDigits? (stringChars body))))

fn tsNumberLiteral s: String -> String
  (if (isIntegerLiteral? s) (str s "n") s)

fn primitiveTsType name: String -> (Option String)
  (cond
    ((or (= name "Int64") (or (= name "I64") (= name "Int"))) (some "bigint"))
    ((or (= name "Int32") (or (= name "I32") (= name "Int16"))) (some "number"))
    ((or (= name "Float") (or (= name "Float64") (or (= name "F64") (= name "Num")))) (some "number"))
    ((or (= name "String") (= name "Str")) (some "string"))
    ((or (= name "Bool") (= name "Boolean")) (some "boolean"))
    ((or (= name "Void") (or (= name "Unit") (= name "()"))) (some "void"))
    ((or (= name "Any") (= name "any")) (some "any"))
    (else (none)))

fn emitTsType t: String -> String
  (let [(clean (stringTrim t))]
    (let [(prim (primitiveTsType clean))]
      (mt prim
        ((some p) p)
        ((none)
          (cond
            ((and (stringStartsWith? clean "(List ") (stringEndsWith? clean ")"))
              (let [(inner (optionOr (stringSlice clean 6 (- (stringLength clean) 1)) ""))]
                (str "Array<" (emitTsType inner) ">")))
            ((stringStartsWith? clean "List ")
              (let [(inner (optionOr (stringSlice clean 5 (stringLength clean)) ""))]
                (str "Array<" (emitTsType inner) ">")))
            ((and (stringStartsWith? clean "(Option ") (stringEndsWith? clean ")"))
              (let [(inner (optionOr (stringSlice clean 8 (- (stringLength clean) 1)) ""))]
                (str (emitTsType inner) " | null")))
            ((stringStartsWith? clean "Option ")
              (let [(inner (optionOr (stringSlice clean 7 (stringLength clean)) ""))]
                (str (emitTsType inner) " | null")))
            ((and (stringStartsWith? clean "(Result ") (stringEndsWith? clean ")"))
              (let [(sub (optionOr (stringSlice clean 8 (- (stringLength clean) 1)) ""))
                    (parts (stringSplit (stringTrim sub) " "))
                    (okTy (if (> (listLength parts) 0) (emitTsType (optionOr (listGet parts 0) "void")) "void"))
                    (errTy (if (> (listLength parts) 1) (emitTsType (optionOr (listGet parts 1) "string")) "string"))]
                (str "{ ok: true; value: " okTy " } | { ok: false; error: " errTy " }")))
            ((stringStartsWith? clean "Result ")
              (let [(sub (optionOr (stringSlice clean 7 (stringLength clean)) ""))
                    (parts (stringSplit (stringTrim sub) " "))
                    (okTy (if (> (listLength parts) 0) (emitTsType (optionOr (listGet parts 0) "void")) "void"))
                    (errTy (if (> (listLength parts) 1) (emitTsType (optionOr (listGet parts 1) "string")) "string"))]
                (str "{ ok: true; value: " okTy " } | { ok: false; error: " errTy " }")))
            ((and (stringStartsWith? clean "(Pair ") (stringEndsWith? clean ")"))
              (let [(sub (optionOr (stringSlice clean 6 (- (stringLength clean) 1)) ""))
                    (parts (stringSplit (stringTrim sub) " "))
                    (aTy (if (> (listLength parts) 0) (emitTsType (optionOr (listGet parts 0) "any")) "any"))
                    (bTy (if (> (listLength parts) 1) (emitTsType (optionOr (listGet parts 1) "any")) "any"))]
                (str "[" aTy ", " bTy "]")))
            (else (tsMangleIdent clean)))))))

fn emitTsRuntimeHelpers -> String
  (str "export function stringFromInt64(n: bigint | number): string {\n"
       "  return String(n);\n"
       "}\n\n"
       "export function aslFold<T, R>(fn: (acc: R, item: T) => R, init: R, list: Array<T>): R {\n"
       "  return list.reduce(fn, init);\n"
       "}\n\n"
       "export function aslMap<T, R>(fn: (item: T) => R, list: Array<T>): Array<R> {\n"
       "  return list.map(fn);\n"
       "}\n\n"
       "export function aslFilter<T>(fn: (item: T) => boolean, list: Array<T>): Array<T> {\n"
       "  return list.filter(fn);\n"
       "}\n\n"
       "export function aslFloorDiv(a: bigint, b: bigint): bigint {\n"
       "  if (b === 0n) throw new RangeError('division by zero');\n"
       "  const q = a / b;\n"
       "  const r = a % b;\n"
       "  return (r !== 0n && ((r < 0n) !== (b < 0n))) ? q - 1n : q;\n"
       "}\n\n"
       "export function aslFloorMod(a: bigint, b: bigint): bigint {\n"
       "  if (b === 0n) throw new RangeError('modulo by zero');\n"
       "  const r = a % b;\n"
       "  return (r !== 0n && ((r < 0n) !== (b < 0n))) ? r + b : r;\n"
       "}\n\n"
       "export function aslStringSlice(s: string, start: number | bigint, end: number | bigint): string {\n"
       "  const st = typeof start === 'bigint' ? Number(start) : start;\n"
       "  const en = typeof end === 'bigint' ? Number(end) : end;\n"
       "  return s.slice(Math.max(0, st), Math.max(0, en));\n"
       "}\n\n"
       "export function aslStringIndexOf(s: string, sub: string): bigint | null {\n"
       "  const idx = s.indexOf(sub);\n"
       "  return idx >= 0 ? BigInt(idx) : null;\n"
       "}\n\n"
       "export function aslOptionOr<T>(opt: T | null | undefined, fallback: T): T {\n"
       "  return (opt !== null && opt !== undefined) ? opt : fallback;\n"
       "}\n\n")

fn emitTsHeader -> String
  (str "/**\n"
       " * Generated by AgentSlang (ASL) TypeScript Target (asl-target-ts).\n"
       " * Single Source of Truth: pure typed ASL AST.\n"
       " */\n\n"
       "declare const process: { exitCode: number; stdout: { write(s: string): void } };\n\n"
       (emitTsRuntimeHelpers))
