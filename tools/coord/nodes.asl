(module asl-tools/coord/nodes
  :x [Node nodesPath roles roleOk? parseNode addRow readNodes! renderNode renderNodes writeNodes! upsertNode! parseCount coresCommand probeCores! probeOs! probeArch! probeRamGb! probeDiskFreeGb! probeClang! probe!]
  :i [(asl-tools/fleet/run :a fr) (tools/fleet/model :a fm) (asl-parser/reader :a rd)])

; (:m :ref FK-REGISTRY :do "one row per machine in ~/.asl/nodes.asn so a coordinator picks a node by role and capacity; probe! fills only the local row from the OS (sysctl/nproc, uname, df, clang) through fr/shellOut with a timeout; rows hold no tokens or keys, :channels names which worker lanes the node can run, :relay names how it is reached; every reader and writer takes an explicit path so tests never touch ~/.asl")

(schema Node
  (:f id String)
  (:f role String)
  (:f arch String)
  (:f os String)
  (:f cores Int64)
  (:f ramGb Int64)
  (:f diskFreeGb Int64)
  (:f clang String)
  (:f channels (List String))
  (:f relay String))

fn ! nodesPath -> String
  (str (resultOr (getHomeDir) ".") "/.asl/nodes.asn")

fn roles -> (List String)
  (list "primary" "worker" "macCheck")

fn roleOk? role: String -> Bool
  (listContains? (roles) role)

fn ! parseNode form: rd/SExpr -> (Result Node String)
  (let [(items (fm/itemsOf form))
        (text (fn [(key String)] -> String (fm/textOf (optionOr (fm/kvGet items key) (rd/makeAtom "")))))
        (num (fn [(key String)] -> Int64 (optionOr (fm/intOf (fm/kvGet items key)) 0)))
        (id (text ":id"))
        (role (text ":role"))
        (arch (text ":arch"))]
    (if (stringEmpty? id) (err "nodes: row without :id")
      (if (stringEmpty? role) (err (str "nodes: " id " has no :role"))
        (if (not (roleOk? role)) (err (str "nodes: " id " has unknown :role " role))
          (if (stringEmpty? arch) (err (str "nodes: " id " has no :arch"))
            (ok (Node :id id :role role :arch arch :os (text ":os")
                      :cores (num ":cores") :ramGb (num ":ramGb") :diskFreeGb (num ":diskFreeGb")
                      :clang (text ":clang")
                      :channels (fm/atomsOf (optionOr (fm/kvGet items ":channels") (fm/makeEmpty)))
                      :relay (let [(r (text ":relay"))] (if (stringEmpty? r) "none" r)))))))))

fn ! addRow acc: (Result (List Node) String) f: rd/SExpr -> (Result (List Node) String)
  (match acc
    ((err e) (err e))
    ((ok rows) (match (parseNode f)
      ((err e) (err e))
      ((ok n) (ok (listAppend rows (list n)))))))

fn ! readNodes! path: String -> (Result (List Node) String)
  (if (not (fileExists? path)) (ok (list))
    (match (fileReadString path)
      ((err e) (err (str "nodes: cannot read " path ": " e)))
      ((ok src) (match (fm/parseForms src)
        ((err e) (err (str "nodes: " path " does not read: " e)))
        ((ok forms) (fold addRow (ok (list)) forms))))))

fn renderNode n: Node -> String
  (str "(:node :id " n.id " :role " n.role " :arch " n.arch " :os " n.os
       " :cores " n.cores " :ramGb " n.ramGb " :diskFreeGb " n.diskFreeGb
       " :clang " (fm/asnQuote n.clang) " :channels " (fm/asnStrings n.channels) " :relay " n.relay ")")

fn renderNodes nodes: (List Node) -> String
  (str (stringJoin (map renderNode nodes) "\n") "\n")

fn ! writeNodes! path: String nodes: (List Node) -> (Result Unit String)
  (fileWrite path (renderNodes nodes))

fn ! upsertNode! path: String n: Node -> (Result Unit String)
  (match (readNodes! path)
    ((err e) (err e))
    ((ok rows) (writeNodes! path
      (if (listContains? (map (fn [(r Node)] -> String r.id) rows) n.id)
        (map (fn [(r Node)] -> Node (if (= r.id n.id) n r)) rows)
        (listAppend rows (list n))))))

fn parseCount text: String -> Int64
  (optionOr (stringToInt64 (stringTrim (optionOr (listHead (stringLines text)) ""))) 0)

fn ! out! cmd: String -> String
  (stringTrim (resultOr (fr/shellOut cmd 10000) ""))

fn ! probeOs! -> String
  (stringLower (out! "/usr/bin/uname -s"))

fn ! probeArch! -> String
  (out! "/usr/bin/uname -m")

fn coresCommand os: String -> String
  (if (= os "darwin") "/usr/sbin/sysctl -n hw.ncpu" "nproc")

fn ! probeCores! -> Int64
  (parseCount (out! (coresCommand (probeOs!))))

fn ! probeRamGb! -> Int64
  (if (= (probeOs!) "darwin")
    (/ (parseCount (out! "/usr/sbin/sysctl -n hw.memsize")) 1073741824)
    (/ (parseCount (out! "/usr/bin/awk '/MemTotal/ {print $2}' /proc/meminfo")) 1048576))

fn ! probeDiskFreeGb! -> Int64
  (/ (parseCount (out! "/bin/df -Pk / | /usr/bin/tail -1 | /usr/bin/awk '{print $4}'")) 1048576)

fn ! probeClang! -> String
  (out! "clang --version 2>/dev/null | head -1")

fn ! probe! id: String role: String channels: (List String) relay: String -> Node
  (Node :id id :role role :arch (probeArch!) :os (probeOs!)
        :cores (probeCores!) :ramGb (probeRamGb!) :diskFreeGb (probeDiskFreeGb!)
        :clang (probeClang!) :channels channels :relay relay)
