(module aslMem/vfsFork :x [CompensatingAction VFSBranch forkVfsBranch forkVfsBranchWithCausal writeBranchBuffer registerCompensation commitBranch! abortBranch branchDiff] :i [(vfs :a v)])

(schema CompensatingAction (:f actionId Str) (:f kind Str) (:f target Str) (:f handler Str) (:f registeredAtMs I64))

(schema VFSBranch (:f branchId Str) (:f parentId Str) (:f createdAtMs I64) (:f buffers (List v/VFSBuffer)) (:f compensations (List CompensatingAction)) (:f status Str) (:f causalId Str))

fn findBranchBuffer buffers: (List v/VFSBuffer) targetPath: Str -> (Option v/VFSBuffer)
  (fold (fn [(acc (Option v/VFSBuffer)) (buf v/VFSBuffer)] -> (Option v/VFSBuffer) (mt acc ((some b) (some b)) ((none) (if (= buf.path targetPath) (some buf) (none))))) (none) buffers)

fn updateOrAppendBuffer buffers: (List v/VFSBuffer) targetPath: Str newBuf: v/VFSBuffer -> (List v/VFSBuffer)
  (let [(found (fold (fn [(acc Bool) (b v/VFSBuffer)] -> Bool (if acc true (= b.path targetPath))) false buffers))] (if found (fold (fn [(acc (List v/VFSBuffer)) (b v/VFSBuffer)] -> (List v/VFSBuffer) (if (= b.path targetPath) (listAppend acc (list newBuf)) (listAppend acc (list b)))) (list) buffers) (listAppend buffers (list newBuf))))

fn forkVfsBranch registry: v/VFSRegistry branchId: Str -> VFSBranch
  (let [(paths registry.activePaths) (bufsMap registry.buffers) (branchBuffers (fold (fn [(acc (List v/VFSBuffer)) (p Str)] -> (List v/VFSBuffer) (mt (mapGet bufsMap p) ((none) acc) ((some b) (listAppend acc (list b))))) (list) paths))] (VFSBranch :branchId branchId :parentId "root" :createdAtMs 1725793200000 :buffers branchBuffers :compensations (list) :status "active" :causalId ""))

fn forkVfsBranchWithCausal registry: v/VFSRegistry branchId: Str causalId: Str -> VFSBranch
  (let [(paths registry.activePaths) (bufsMap registry.buffers) (branchBuffers (fold (fn [(acc (List v/VFSBuffer)) (p Str)] -> (List v/VFSBuffer) (mt (mapGet bufsMap p) ((none) acc) ((some b) (listAppend acc (list b))))) (list) paths))] (VFSBranch :branchId branchId :parentId "root" :createdAtMs 1725793200000 :buffers branchBuffers :compensations (list) :status "active" :causalId causalId))

fn registerCompensation branch: VFSBranch action: CompensatingAction -> VFSBranch
  (if (!= branch.status "active") branch (with branch :compensations (listAppend branch.compensations (list action))))

fn writeBranchBuffer branch: VFSBranch path: Str content: Str -> VFSBranch
  (if (!= branch.status "active") branch (let [(norm (v/normalizePath path)) (newHash (v/vfsCasHash content)) (existingOpt (findBranchBuffer branch.buffers norm)) (newBuf (mt existingOpt ((none) (v/VFSBuffer :path norm :content content :baseContent "" :casHash newHash :baseHash "" :revision 1 :dirty true :loadedAt 0 :leaseHolder "" :leaseExpiresAt 0 :leaseToken 0)) ((some prev) (let [(baseH prev.baseHash) (baseC prev.baseContent) (isDirty (!= newHash baseH))] (v/VFSBuffer :path norm :content content :baseContent baseC :casHash newHash :baseHash baseH :revision (+ prev.revision 1) :dirty isDirty :loadedAt prev.loadedAt :leaseHolder prev.leaseHolder :leaseExpiresAt prev.leaseExpiresAt :leaseToken prev.leaseToken))))) (updatedBuffers (updateOrAppendBuffer branch.buffers norm newBuf))] (with branch :buffers updatedBuffers)))

fn commitBranch! branch: VFSBranch registry: v/VFSRegistry -> v/VFSRegistry
  (if (!= branch.status "active") registry (let [(collision (fold (fn [(acc Bool) (b v/VFSBuffer)] -> Bool (if acc true (let [(trunkOpt (v/vfsRead registry b.path))] (mt trunkOpt ((none) false) ((some tb) (if (= b.baseHash "") false (!= b.baseHash tb.casHash))))))) false branch.buffers))] (if collision registry (fold (fn [(accReg v/VFSRegistry) (b v/VFSBuffer)] -> v/VFSRegistry (if (or b.dirty (none? (v/vfsRead accReg b.path))) (v/vfsWrite accReg b.path b.content) accReg)) registry branch.buffers))))

fn abortBranch branch: VFSBranch -> VFSBranch
  (let [(executed (fold (fn [(acc I64) (action CompensatingAction)] -> I64 (+ acc 1)) 0 branch.compensations))] (with branch :buffers (list) :compensations (list) :status "aborted"))

fn branchDiff branch: VFSBranch path: Str -> (Option Str)
  (let [(norm (v/normalizePath path)) (bufOpt (findBranchBuffer branch.buffers norm))] (mt bufOpt ((none) (none)) ((some b) (if (not b.dirty) (some "") (let [(diffLines (v/vfsDiff b))] (some (stringJoin diffLines "\n")))))))
