(module asl-coord/needs
  :x [needPost needList needTake needClose needText]
  :i [(asl-store/types :a ty) (asl-coord/lease :a ls) (asl-coord/core :a co)])

; (:m :ref VS-COORD :do "needs are not scoped to a repository: any agent of any project posts one and every project lists it; the id is the offset of the append to the needs stream, so two processes never get the same id, and the row is created once at expectRev 0")
fn needText id: String project: String agent: String pkg: String want: String repro: String prio: String state: String unit: String at: Int64 -> String
  (str "(:need :id " (ls/q id) " :project " (ls/q project) " :agent " (ls/q agent) " :pkg " (ls/q pkg)
       " :want " (ls/q want) " :repro " (ls/q repro) " :prio " (ls/q prio)
       " :state " (ls/q state) " :unit " (ls/q unit) " :at " (stringFromInt64 at) ")")

fn needKey id: String -> ty/Key
  (ty/Key :collection "needs" :id id)

fn errText r: ty/Reply -> String
  (match r
    ((ty/rErr code text) (str code ": " text))
    (_ "unexpected reply"))

fn needPost ctx: co/Ctx project: String agent: String pkg: String want: String repro: String prio: String -> (Result String String)
  (match (ctx.call (ty/opAppend "needs" want ctx.now))
    ((ty/rAppended off)
      (let [(id (str "n" (stringFromInt64 off)))]
        (match (ctx.call (ty/opCas (needKey id) 0 (needText id project agent pkg want repro prio "open" "" ctx.now) 0 ctx.now))
          ((ty/rWritten _) (ok id))
          (r (err (errText r))))))
    (r (err (errText r))))

fn pageRows ctx: co/Ctx after: String acc: (List String) guard: Int64 -> (Result (List String) String)
  (if (> guard 1000)
    (err "needs scan did not end")
    (match (ctx.call (ty/opScan "needs" "" after 1000 ctx.now))
      ((ty/rPage rows next)
        (let [(all (listAppend acc (map (fn [(r ty/ScanRow)] -> String r.value) rows)))]
          (if (stringEmpty? next) (ok all) (pageRows ctx next all (+ guard 1)))))
      (r (err (errText r)))))

fn needList ctx: co/Ctx state: String pkg: String -> (Result (List String) String)
  (match (pageRows ctx "" (list) 0)
    ((err e) (err e))
    ((ok rows)
      (ok (filter (fn [(t String)] -> Bool
                    (and (or (stringEmpty? state) (= (ls/quotedField t "state") state))
                         (or (stringEmpty? pkg) (= (ls/quotedField t "pkg") pkg))))
                  rows))))

fn rewrite t: String state: String unit: String at: Int64 -> String
  (needText (ls/quotedField t "id") (ls/quotedField t "project") (ls/quotedField t "agent") (ls/quotedField t "pkg")
            (ls/quotedField t "want") (ls/quotedField t "repro") (ls/quotedField t "prio") state unit at)

fn moveState ctx: co/Ctx id: String from: String unit: String state: String requireUnit: Bool -> (Result String String)
  (match (ctx.call (ty/opGet (needKey id) ctx.now))
    ((ty/rValue rev v _)
      (cond
        ((!= (ls/quotedField v "state") from) (err (str "(:refused :need " (ls/q id) " :state " (ls/q (ls/quotedField v "state")) ")")))
        ((and requireUnit (!= (ls/quotedField v "unit") unit)) (err (str "(:refused :need " (ls/q id) " :holder " (ls/q (ls/quotedField v "unit")) ")")))
        (else
          (match (ctx.call (ty/opCas (needKey id) rev (rewrite v state unit ctx.now) 0 ctx.now))
            ((ty/rWritten _) (ok (str "(:need :id " (ls/q id) " :state " (ls/q state) ")")))
            ((ty/rConflict _) (err (str "(:refused :need " (ls/q id) " :changed true)")))
            (r (err (errText r)))))))
    ((ty/rAbsent) (err (str "(:refused :need " (ls/q id) " :absent true)")))
    (r (err (errText r))))

; (:m :ref VS-COORD :do "take is a CAS from open to taken by one unit: of two units taking the same need exactly one gets it; close needs the taking unit and ends in done or the given state")
fn needTake ctx: co/Ctx id: String unit: String -> (Result String String)
  (moveState ctx id "open" unit "taken" false)

fn needClose ctx: co/Ctx id: String unit: String state: String -> (Result String String)
  (moveState ctx id "taken" unit state true)
