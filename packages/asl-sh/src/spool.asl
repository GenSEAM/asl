(module asl-sh/spool
  :d "APM Two-Tier Spooling: bounded 200-line RAM ring buffer and 10MB circular ephemeral disk spool with auto-unlink."
  :x [RingBuffer
      DiskSpool
      TwoTierSpool
      makeRingBuffer
      ringPush
      ringTail
      ringSize
      ringToString
      makeDiskSpool
      spoolWrite
      spoolSync!
      spoolWriteSync!
      spoolTruncate
      spoolUnlink
      spoolIsUnlinked?
      makeTwoTierSpool
      twoTierPush
      twoTierClose])

(dfs RingBuffer
  (:f capacity Int64 "Maximum number of lines retained in resident RAM (default 200)")
  (:f lines (List String) "Retained stream lines in FIFO order")
  (:f count Int64 "Total line count currently held in buffer"))

(df makeRingBuffer [(capacity Int64)] -> RingBuffer
  :d "Constructs an empty in-memory RingBuffer with specified capacity."
  (RingBuffer
    :capacity (if (<= capacity 0) 200 capacity)
    :lines (list)
    :count 0))

(df ringPush [(rb RingBuffer) (line String)] -> RingBuffer
  :d "Appends a line into the RingBuffer, evicting the oldest line if capacity is exceeded."
  (let [(cap (.-capacity rb))
        (cur (.-lines rb))
        (cnt (.-count rb))]
    (if (< cnt cap)
        (RingBuffer
          :capacity cap
          :lines (list-append cur (list line))
          :count (+ cnt 1))
        (let [(evictedTail (option-or (list-slice cur 1 cnt) (list)))]
          (RingBuffer
            :capacity cap
            :lines (list-append evictedTail (list line))
            :count cap)))))

(df ringTail [(rb RingBuffer) (n Int64)] -> (List String)
  :d "Returns the last n lines from the RingBuffer."
  (let [(cur (.-lines rb))
        (cnt (.-count rb))]
    (cond
      ((<= n 0) (list))
      ((>= n cnt) cur)
      (:else (option-or (list-slice cur (- cnt n) cnt) (list))))))

(df ringSize [(rb RingBuffer)] -> Int64
  :d "Returns the current number of lines held in the RingBuffer."
  (.-count rb))

(df ringToString [(rb RingBuffer)] -> String
  :d "Joins all lines in the RingBuffer into a single string separated by newlines."
  (string-join (.-lines rb) "\n"))

(dfs DiskSpool
  (:f path String "Filesystem path to ephemeral disk spool")
  (:f maxBytes Int64 "Hard storage cap in bytes (default 10MB: 10485760)")
  (:f currentBytes Int64 "Current byte size of spool data")
  (:f content String "Spool byte content")
  (:f isUnlinked Bool "State flag verifying file descriptor auto-unlink"))

(df makeDiskSpool [(path String) (maxBytes Int64)] -> DiskSpool
  :d "Constructs an ephemeral DiskSpool with specified maximum byte limit."
  (DiskSpool
    :path path
    :maxBytes (if (<= maxBytes 0) 10485760 maxBytes)
    :currentBytes 0
    :content ""
    :isUnlinked false))

(df spoolWrite [(spool DiskSpool) (chunk String)] -> DiskSpool
  :d "Writes data to disk spool, circularly truncating oldest bytes if max-bytes is exceeded."
  (let [(chunkLen (int32-to-int64 (string-length chunk)))]
    (if (<= chunkLen 0)
        spool
        (let [(cap (.-maxBytes spool))]
          (if (>= chunkLen cap)
              (let [(truncated (option-or (string-slice chunk (- chunkLen cap) chunkLen) ""))]
                (DiskSpool
                  :path (.-path spool)
                  :maxBytes cap
                  :currentBytes cap
                  :content truncated
                  :isUnlinked false))
              (let [(curLen (.-currentBytes spool))
                    (combLen (+ curLen chunkLen))]
                (if (<= combLen cap)
                    (DiskSpool
                      :path (.-path spool)
                      :maxBytes cap
                      :currentBytes combLen
                      :content (str (.-content spool) chunk)
                      :isUnlinked false)
                    (let [(keepLen (- cap chunkLen))
                          (headRetained (option-or (string-slice (.-content spool) (- curLen keepLen) curLen) ""))
                          (truncated (str headRetained chunk))]
                      (DiskSpool
                        :path (.-path spool)
                        :maxBytes cap
                        :currentBytes cap
                        :content truncated
                        :isUnlinked false)))))))))

(df ! spoolSync! [(spool DiskSpool)] -> (Result DiskSpool String)
  :d "Writes spool content to disk using builtin file-write, ensuring file on disk is strictly <= max-bytes."
  (mt (file-write (.-path spool) (.-content spool))
    ((ok _) (ok spool))
    ((err _) (err (str "Failed to sync disk spool to " (.-path spool))))))

(df ! spoolWriteSync! [(spool DiskSpool) (chunk String)] -> (Result DiskSpool String)
  :d "Pushes chunk circularly and flushes to disk."
  (let [(w (spoolWrite spool chunk))]
    (spoolSync! w)))

(df spoolTruncate [(spool DiskSpool)] -> DiskSpool
  :d "Enforces circular byte truncation to max-bytes."
  (let [(len (.-currentBytes spool))
        (cap (.-maxBytes spool))]
    (if (<= len cap)
        spool
        (let [(txt (.-content spool))
              (start (- len cap))
              (truncated (option-or (string-slice txt start len) ""))]
          (DiskSpool
            :path (.-path spool)
            :maxBytes cap
            :currentBytes cap
            :content truncated
            :isUnlinked (.-isUnlinked spool))))))

(df spoolUnlink [(spool DiskSpool)] -> DiskSpool
  :d "Reclaims disk spool storage and marks file descriptor as unlinked, truncating file on disk."
  (let [(_ (file-write (.-path spool) ""))]
    (DiskSpool
      :path (.-path spool)
      :maxBytes (.-maxBytes spool)
      :currentBytes 0
      :content ""
      :isUnlinked true)))

(df spoolIsUnlinked? [(spool DiskSpool)] -> Bool
  :d "Verifies whether the ephemeral disk spool has been unlinked."
  (.-isUnlinked spool))

(dfs TwoTierSpool
  (:f ring RingBuffer "Tier 1 RAM ring buffer")
  (:f disk DiskSpool "Tier 2 ephemeral circular disk spool"))

(df makeTwoTierSpool [(path String) (ringCap Int64) (diskCap Int64)] -> TwoTierSpool
  :d "Constructs coordinated two-tier spool with RAM ring buffer and circular disk spool."
  (TwoTierSpool
    :ring (makeRingBuffer ringCap)
    :disk (makeDiskSpool path diskCap)))

(df twoTierPush [(s TwoTierSpool) (line String)] -> TwoTierSpool
  :d "Simultaneously pushes line to RAM ring buffer and writes formatted line to disk spool."
  (let [(newRing (ringPush (.-ring s) line))
        (newDisk (spoolWrite (.-disk s) (str line "\n")))]
    (TwoTierSpool :ring newRing :disk newDisk)))

(df twoTierClose [(s TwoTierSpool)] -> TwoTierSpool
  :d "Closes two-tier spool, unlinking ephemeral disk storage while retaining ring buffer for tail inspection."
  (TwoTierSpool
    :ring (.-ring s)
    :disk (spoolUnlink (.-disk s))))
