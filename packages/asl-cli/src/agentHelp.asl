(module asl-cli/agentHelp
  :x [agentBrief! coreOps]
  :i [(asl-forms/tools :a tools) (asl-forms/search :a s)])

; (:m :ref CLI-AGENT-HELP :do "the bare asl, -h, --help and help answer an agent: the calling convention in a few lines, then one example form per core op read from the (:tools) registry file, so the brief follows the catalogue; the human usage text lives under asl human help")
fn coreOps -> (List String)
  (list "read" "query" "observe" "intel" "check" "test")

fn writeOps -> (List String)
  (list "edit" "flush" "agent")

fn opExample op: tools/ToolOp -> String
  (match (listHead op.examples)
    ((some e) e)
    ((none) op.form))

fn ! rowsFor! reg: tools/Registry names: (List String) -> String
  (stringJoin (map (fn [(nm String)] -> String
                     (match (mapGet reg.ops nm)
                       ((none) "")
                       ((some o) (str "  " (opExample o) "\n"))))
                   names) "")

fn ! agentBrief! root: String -> String
  (let [(ctx (s/KnowCtx :ws root :toolRoot root :binDir "" :vfsDir "" :toolsFile "" :home ""))
        (head (str "(:asl :brief 1\n"
                   " :call \"asl '(:form ...) (:form ...)': forms in one call run as one batch, receipts in order\"\n"
                   " :stdin \"asl - <<'EOF' forms EOF: a quoted heredoc keeps single quotes; asl -f FILE\"\n"
                   " :any \"every capability is a form; call anything this way\"\n"
                   " :catalogue (\"(:tools)\" \"(:help :op NAME)\" \"(:help :builtin X)\")\n"))
        (tail " :human \"asl human help\")")]
    (match (tools/loadRegistry! ctx)
      ((none) (str head " :ops ()\n :err \"tools.asn missing\"\n" tail))
      ((some reg) (str head " :ops (\n" (rowsFor! reg (coreOps)) " )\n :writes (\n" (rowsFor! reg (writeOps)) " )\n :note \"edits stage in a buffer until (:flush); (:discard) drops them; :agent hands a task to Leon\"\n" tail))))
