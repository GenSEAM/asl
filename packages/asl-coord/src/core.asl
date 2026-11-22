(module asl-coord/core
  :x [Ctx Held receipt claimsOf claimLease releaseLease heartbeatLease pathAllowedIn importLegacy legacyDone? sweepHeld sweepAll retireStale staleAt? leaseKey epochIn]
  :i [(asl-store/types :a ty) (asl-coord/lease :a ls) (asl-coord/paths :a pa)])

; (:m :ref VS-COORD :do "everything the claim rules need from the world is a field: call is one adapter round trip, scope names the repository whose files are claimed, now is epoch ms, gone says the lease's worktree or branch no longer exists, alive says its declared holder process still runs, legacy lists every lease file of the per-repository claims directory, which old binaries still write, held read-only with the file mtime as heartbeat, and retireLegacy deletes the file of a unit the new rules claimed or released; the rules themselves touch no host")
(schema Ctx (:f call (fn [ty/Op] -> ty/Reply)) (:f scope String) (:f now Int64)
  (:f gone (fn [ls/Lease] -> Bool)) (:f alive (fn [ls/Lease] -> Bool)) (:f legacy (List ls/Lease)) (:f retireLegacy (fn [String] -> Unit)))

; (:m :ref VS-COORD :do "a grant has an epoch, taken from the revision of the scope's gate row that the claim bumped (a gate row is never deleted, so epochs never repeat) and stored in the lease text, and a row revision that every heartbeat advances; a heartbeat must name both")
(schema Held (:f lease ls/Lease) (:f epoch Int64) (:f rev Int64) (:f raw String))

fn receipt unit: String by: String path: String -> String
  (str "(:refused :unit " (ls/q unit) " :by " (ls/q by) " :path " (ls/q path) ")")

fn leaseKey ctx: Ctx unit: String -> ty/Key
  (ty/Key :collection "claims" :id (str ctx.scope "/" unit))

fn gateKey ctx: Ctx -> ty/Key
  (ty/Key :collection "claimGates" :id ctx.scope)

fn markerKey ctx: Ctx -> ty/Key
  (ty/Key :collection "meta" :id (str "legacyClaims-" ctx.scope))

fn errText r: ty/Reply -> String
  (match r
    ((ty/rErr code text) (str code ": " text))
    (_ "unexpected reply"))

fn epochIn raw: String -> Int64
  (optionOr (stringToInt64 (ls/atomField raw "epoch")) 0)

fn contentWith lease: ls/Lease epoch: Int64 -> String
  (let [(t (ls/leaseContent lease))
        (body (optionOr (stringSlice t 0 (- (stringLength t) 2)) t))]
    (str body " :epoch " (stringFromInt64 epoch) ")\n"))

; (:m :ref VS-COORD :do "a claims scan pages through every row of this scope; a row that does not parse into a lease with a unit and a branch is an error, never skipped")
fn scanFrom ctx: Ctx after: String acc: (List Held) guard: Int64 -> (Result (List Held) String)
  (if (> guard 1000)
    (err "claims scan did not end")
    (match (ctx.call (ty/opScan "claims" (str ctx.scope "/") after 1000 ctx.now))
      ((ty/rPage rows next)
        (let [(more (map (fn [(r ty/ScanRow)] -> Held (Held :lease (ls/parseLease r.value) :epoch (epochIn r.value) :rev r.rev :raw r.value)) rows))
              (bad (listFind (fn [(h Held)] -> Bool (or (stringEmpty? h.lease.unit) (stringEmpty? h.lease.branch))) more))]
          (match bad
            ((some _) (err "invalid lease row in the claims collection"))
            ((none)
              (if (stringEmpty? next)
                (ok (listAppend acc more))
                (scanFrom ctx next (listAppend acc more) (+ guard 1)))))))
      ((ty/rErr code text) (err (str code ": " text)))
      (_ (err "unexpected scan reply"))))

fn claimsOf ctx: Ctx -> (Result (List Held) String)
  (scanFrom ctx "" (list) 0)

; (:m :ref VS-COORD :do "a lease is stale when its worktree or branch is gone, or when now is past at + ttl and no live declared holder of this host stands behind it; the TTL compare is by the caller's now, never by a clock read here")
fn staleAt? ctx: Ctx lease: ls/Lease -> Bool
  (or (ctx.gone lease)
      (and (> ctx.now (+ lease.at (* lease.ttl 1000))) (not (ctx.alive lease))))

fn retireStale ctx: Ctx held: (List Held) -> (Result Unit String)
  (match (listHead held)
    ((none) (ok ()))
    ((some h)
      (let [(rest (optionOr (listTail held) (list)))]
        (if (staleAt? ctx h.lease)
          (match (ctx.call (ty/opDel (leaseKey ctx h.lease.unit) h.rev ctx.now))
            ((ty/rErr code text) (err (str code ": " text)))
            (_ (retireStale ctx rest)))
          (retireStale ctx rest)))))

; (:m :ref VS-COORD :do "a sweep retires stale rows by delete at the revision it read, so a heartbeat that landed in between wins and the row stays")
fn sweepHeld ctx: Ctx -> (Result (List Held) String)
  (match (claimsOf ctx)
    ((err e) (err e))
    ((ok held)
      (match (retireStale ctx held)
        ((err e) (err e))
        ((ok _) (match (claimsOf ctx) ((err e) (err e)) ((ok live) (ok (filter (fn [(h Held)] -> Bool (not (staleAt? ctx h.lease))) live))))))))

fn heldFor held: (List Held) unit: String -> (Option Held)
  (listFind (fn [(h Held)] -> Bool (= h.lease.unit unit)) held)

fn sameOwner? a: ls/Lease b: ls/Lease -> Bool
  (and (= a.host b.host) (and (= a.branch b.branch) (= a.agent b.agent)))

; (:m :ref VS-COORD :do "during the move from per-repository lease files to the vault both paths are live: every legacy file is held read-only, and when a unit has both a legacy lease and a vault row of the same owner the one with the later heartbeat wins (a tie goes to the vault row) while leases of different owners are both held; remove this dual path (CUTOVER-COORD-LEGACY) once every binary has been deployed")
fn supersededByLegacy h: Held legacy: (List ls/Lease) -> Bool
  (listAny? (fn [(l ls/Lease)] -> Bool (and (= l.unit h.lease.unit) (and (sameOwner? l h.lease) (> l.at h.lease.at)))) legacy)

fn supersededByVault g: Held vault: (List Held) -> Bool
  (listAny? (fn [(v Held)] -> Bool (and (= v.lease.unit g.lease.unit) (and (sameOwner? v.lease g.lease) (>= v.lease.at g.lease.at)))) vault)

fn liveAll ctx: Ctx vault: (List Held) -> (List Held)
  (let [(legacy (filter (fn [(l ls/Lease)] -> Bool (not (staleAt? ctx l))) ctx.legacy))
        (legacyHeld (map (fn [(l ls/Lease)] -> Held (Held :lease l :epoch 0 :rev 0 :raw "")) legacy))]
    (listAppend (filter (fn [(h Held)] -> Bool (not (supersededByLegacy h legacy))) vault)
                (filter (fn [(h Held)] -> Bool (not (supersededByVault h vault))) legacyHeld)))

fn sweepAll ctx: Ctx -> (Result (List Held) String)
  (match (sweepHeld ctx)
    ((err e) (err e))
    ((ok vault) (ok (liveAll ctx vault))))

fn conflictOf unit: String owns: (List String) held: (List Held) -> String
  (match (listHead held)
    ((none) "")
    ((some h)
      (let [(rest (optionOr (listTail held) (list)))
            (first (pa/overlapBetween owns h.lease.owns))]
        (if (or (= unit h.lease.unit) (stringEmpty? first))
          (conflictOf unit owns rest)
          (receipt unit h.lease.unit first)))))

fn gateRev ctx: Ctx -> Int64
  (match (ctx.call (ty/opGet (gateKey ctx) ctx.now))
    ((ty/rValue rev _ _) rev)
    (_ 0))

fn withAt lease: ls/Lease now: Int64 -> ls/Lease
  (with lease :at now)

; (:m :ref VS-COORD :do "a lost gate race puts the unit's row back exactly as it was read, by CAS at the revision this claim wrote, or deletes it at that revision when it was new, so a rolled-back claim leaves neither its owns nor a row behind and never touches a row another writer has since changed")
fn undoWrite ctx: Ctx unit: String previous: (Option Held) wrote: Int64 -> Unit
  (let [(_ (match previous
             ((some p) (ctx.call (ty/opCas (leaseKey ctx unit) wrote p.raw 0 ctx.now)))
             ((none) (ctx.call (ty/opDel (leaseKey ctx unit) wrote ctx.now)))))]
    ())

; (:m :ref VS-COORD :do "claims of different units cannot be made atomic by one row CAS, so each claim writes its lease row and then CASes the scope's gate row at the revision it read before scanning; a claim whose gate moved restores its row and rescans, so of two overlapping claims racing at most one survives and the loser sees the winner")
fn claimTry ctx: Ctx self: ls/Lease n: Int64 -> (Result String String)
  (if (> n 8)
    (err (receipt self.unit "" "claim gate busy"))
    (let [(gate (gateRev ctx))]
      (match (sweepHeld ctx)
        ((err e) (err e))
        ((ok vault)
          (let [(all (liveAll ctx vault))
                (others (filter (fn [(h Held)] -> Bool (!= h.lease.unit self.unit)) all))
                (refusal (conflictOf self.unit self.owns others))
                (foreign (listFind (fn [(h Held)] -> Bool (and (= h.lease.unit self.unit) (not (sameOwner? h.lease self)))) all))
                (previous (heldFor vault self.unit))
                (text (contentWith (withAt self ctx.now) (+ gate 1)))]
            (cond
              ((not (stringEmpty? refusal)) (err refusal))
              ((some? foreign)
                (err (receipt self.unit self.unit (optionOr (listHead self.owns) ""))))
              (else
                (let [(expect (match previous ((some p) p.rev) ((none) 0)))]
                  (match (ctx.call (ty/opCas (leaseKey ctx self.unit) expect text 0 ctx.now))
                    ((ty/rWritten wrote)
                      (match (ctx.call (ty/opCas (gateKey ctx) gate self.unit 0 ctx.now))
                        ((ty/rWritten _) (do (ctx.retireLegacy self.unit) (ok (str "(:claimed :unit " (ls/q self.unit) " :epoch " (stringFromInt64 (+ gate 1)) ")"))))
                        ((ty/rConflict _)
                          (do (undoWrite ctx self.unit previous wrote)
                              (claimTry ctx self (+ n 1))))
                        (r (do (undoWrite ctx self.unit previous wrote) (err (errText r))))))
                    ((ty/rConflict _) (claimTry ctx self (+ n 1)))
                    (r (err (errText r))))))))))))

fn claimLease ctx: Ctx self: ls/Lease -> (Result String String)
  (claimTry ctx self 0)

fn releaseLease ctx: Ctx unit: String caller: String self: ls/Lease -> (Result String String)
  (match (sweepHeld ctx)
    ((err e) (err e))
    ((ok vault)
      (let [(holders (filter (fn [(h Held)] -> Bool (= h.lease.unit unit)) (liveAll ctx vault)))]
        (match (listHead holders)
          ((none) (ok (str "(:released :unit " (ls/q unit) " :absent true)")))
          ((some h)
            (if (or (!= caller unit) (listAny? (fn [(x Held)] -> Bool (not (sameOwner? x.lease self))) holders))
              (err (receipt caller unit (optionOr (listHead h.lease.owns) "")))
              (match (heldFor vault unit)
                ((some v)
                  (match (ctx.call (ty/opDel (leaseKey ctx unit) v.rev ctx.now))
                    ((ty/rDeleted) (do (ctx.retireLegacy unit) (ok (str "(:released :unit " (ls/q unit) ")"))))
                    ((ty/rConflict _) (err (receipt caller unit "lease changed during release")))
                    (r (err (errText r)))))
                ((none) (do (ctx.retireLegacy unit) (ok (str "(:released :unit " (ls/q unit) ")")))))))))))

fn staleRefusal unit: String epoch: Int64 -> String
  (str "(:refused :unit " (ls/q unit) " :stale true :epoch " (stringFromInt64 epoch) ")")

; (:m :ref VS-COORD :do "a heartbeat names the epoch of its grant and the row revision it last saw; a different epoch (the unit was released and claimed again, even at the same row revision) or a different revision (another heartbeat or a takeover) makes it stale and it is refused with the current epoch")
fn heartbeatLease ctx: Ctx unit: String epoch: Int64 rev: Int64 -> (Result Int64 String)
  (match (ctx.call (ty/opGet (leaseKey ctx unit) ctx.now))
    ((ty/rValue r v _)
      (if (or (!= r rev) (!= (epochIn v) epoch))
        (err (staleRefusal unit (epochIn v)))
        (match (ctx.call (ty/opCas (leaseKey ctx unit) r (contentWith (withAt (ls/parseLease v) ctx.now) epoch) 0 ctx.now))
          ((ty/rWritten n) (ok n))
          ((ty/rConflict _) (err (staleRefusal unit (epochIn v))))
          (x (err (errText x))))))
    ((ty/rAbsent) (err (str "(:refused :unit " (ls/q unit) " :absent true)")))
    (x (err (errText x))))

fn heartbeatQuiet ctx: Ctx h: Held -> Unit
  (if (> h.rev 0)
    (let [(_ (heartbeatLease ctx h.lease.unit h.epoch h.rev))] ())
    ())

fn allowedIn ctx: Ctx caller: String path: String live: (List Held) all: (List Held) -> (Result String String)
  (match (listHead live)
    ((none)
      (do (match (heldFor all caller) ((some h) (heartbeatQuiet ctx h)) ((none) ()))
          (ok "")))
    ((some h)
      (let [(rest (optionOr (listTail live) (list)))
            (found (pa/listOverlapPath h.lease.owns path))]
        (cond
          ((= caller h.lease.unit)
            (if (and (not (listEmpty? h.lease.owns)) (not (pa/pathUnderOwns? path h.lease.owns)))
              (err (receipt caller caller path))
              (allowedIn ctx caller path rest all)))
          ((not (stringEmpty? found)) (err (receipt caller h.lease.unit path)))
          (else (allowedIn ctx caller path rest all))))))

fn pathAllowedIn ctx: Ctx caller: String rel: String -> (Result String String)
  (match (sweepAll ctx)
    ((err e) (err e))
    ((ok live) (allowedIn ctx caller (pa/trimPath rel) live live)))

fn legacyDone? ctx: Ctx -> Bool
  (match (ctx.call (ty/opGet (markerKey ctx) ctx.now))
    ((ty/rValue _ _ _) true)
    (_ false))

fn legacyAt raw: ls/Lease mtimeMs: Int64 -> ls/Lease
  (with raw :at mtimeMs)

fn importRows ctx: Ctx rows: (List (Pair String Int64)) n: Int64 -> (Result Int64 String)
  (match (listHead rows)
    ((none) (ok n))
    ((some row)
      (let [(rest (optionOr (listTail rows) (list)))
            (lease (legacyAt (ls/parseLease (pairFirst row)) (pairSecond row)))]
        (if (or (stringEmpty? lease.unit) (stringEmpty? lease.branch))
          (importRows ctx rest n)
          (match (ctx.call (ty/opCas (leaseKey ctx lease.unit) 0 (ls/leaseContent lease) 0 ctx.now))
            ((ty/rWritten _) (importRows ctx rest (+ n 1)))
            ((ty/rConflict _) (importRows ctx rest n))
            (r (err (errText r))))))))

; (:m :ref VS-COORD :do "the old per-repository lease files are imported once: each (text, mtime ms) becomes a claims row unless a row for its unit exists, then a marker row for the scope is created and later calls skip the import")
fn importLegacy ctx: Ctx rows: (List (Pair String Int64)) -> (Result Int64 String)
  (if (legacyDone? ctx)
    (ok 0)
    (match (importRows ctx rows 0)
      ((err e) (err e))
      ((ok n)
        (match (ctx.call (ty/opCas (markerKey ctx) 0 (str "(:imported :count " (stringFromInt64 n) " :at " (stringFromInt64 ctx.now) ")") 0 ctx.now))
          ((ty/rErr code text) (err (str code ": " text)))
          (_ (ok n))))))
