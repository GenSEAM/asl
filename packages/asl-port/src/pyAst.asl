(module asl-port/pyAst
  :x [parsePythonAst! parsePythonAstWithTool! whichTool!]
  :i [(asl-json/json :a json)])

fn ! executable? p: String -> Bool
  (mt (fileStat p)
    ((ok st) (and st.isFile (!= (& st.mode 73) 0)))
    ((err _) false))

fn findFirstExe! dirs: (List String) name: String -> String
  (mt (listHead dirs)
    ((some d)
      (let [(cand (str d "/" name))]
        (if (executable? cand)
          cand
          (findFirstExe! (optionOr (listTail dirs) (list)) name))))
    ((none) ""))

fn whichTool! name: String -> String
  (let [(pathEnv (optionOr (envGet "PATH") ""))
        (dirs (filter (fn [(d String)] -> Bool (not (stringEmpty? d))) (stringSplit pathEnv ":")))]
    (findFirstExe! dirs name))

fn readFdLoop! fd: Int64 acc: (List String) -> (Result String String)
  (mt (fdRead fd 65536)
    ((ok chunk)
      (if (stringEmpty? chunk)
        (let [(_ (fdClose fd))]
          (ok (stringJoin (listReverse acc) "")))
        (readFdLoop! fd (listAppend (list chunk) acc))))
    ((err e)
      (let [(_ (fdClose fd))]
        (err (str "ERR_FD_READ: " e)))))

fn readFdAll! fd: Int64 -> (Result String String)
  (readFdLoop! fd (list))

fn pyScript -> String
  (str "import ast,json,sys\n"
       "try:\n"
       "  with open(sys.argv[1],\"r\",encoding=\"utf-8\") as f: src=f.read()\n"
       "  tree=ast.parse(src,filename=sys.argv[1])\n"
       "  def n2d(n):\n"
       "    if isinstance(n,ast.AST):\n"
       "      d={\"_type\":n.__class__.__name__}\n"
       "      for a in (\"lineno\",\"col_offset\",\"end_lineno\",\"end_col_offset\"):\n"
       "        if hasattr(n,a): d[a]=getattr(n,a)\n"
       "      for f,v in ast.iter_fields(n): d[f]=n2d(v)\n"
       "      return d\n"
       "    elif isinstance(n,list): return [n2d(x) for x in n]\n"
       "    elif isinstance(n,(str,int,float,bool)) or n is None: return n\n"
       "    return str(n)\n"
       "  print(json.dumps(n2d(tree)))\n"
       "except Exception as e:\n"
       "  sys.stderr.write(str(e))\n"
       "  sys.exit(1)\n")

fn parsePythonAstWithTool! path: String tool: String -> (Result json/Json String)
  (let [(py (whichTool! tool))]
    (if (stringEmpty? py)
      (err "ERR_PYTHON3_MISSING: python3 not found")
      (mt (procSpawnv (list py "-c" (pyScript) path) (none) (none))
        ((err e)
          (if (= e "notFound")
            (err "ERR_PYTHON3_MISSING: python3 not found")
            (err (str "ERR_SPAWN: " e))))
        ((ok sp)
          (let [(_ (fdClose sp.stdin))
                (outRes (readFdAll! sp.stdout))
                (errRes (readFdAll! sp.stderr))
                (errText (mt errRes ((ok t) t) ((err e) e)))
                (waitRes (procWaitPid sp.pid false))
                (code (mt waitRes ((ok opt) (optionOr opt -1)) ((err _) -1)))]
            (if (!= code 0)
              (err (str "ERR_PYTHON_PARSE: " (stringTrim errText)))
              (mt outRes
                ((err e) (err e))
                ((ok outText)
                  (mt (json/jsonParse outText)
                    ((ok astVal) (ok astVal))
                    ((err je) (err (str "ERR_JSON_PARSE: " je))))))))))))

fn parsePythonAst! path: String -> (Result json/Json String)
  (parsePythonAstWithTool! path "python3")
