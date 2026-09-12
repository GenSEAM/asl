(module asl-sh/spool
  :d "APM Two-Tier Spooling: bounded 200-line RAM ring buffer and 10MB circular ephemeral disk spool with auto-unlink."
  :x [RingBuffer
      DiskSpool
      TwoTierSpool
      make-ring-buffer
      ring-push
      ring-tail
      ring-size
      ring-to-string
      make-disk-spool
      spool-write
      spool-sync!
      spool-write-sync!
      spool-truncate
      spool-unlink
      spool-is-unlinked?
      make-two-tier-spool
      two-tier-push
      two-tier-close])

(dfs RingBuffer
  (:f capacity Int64 "Maximum number of lines retained in resident RAM (default 200)")
  (:f lines (List String) "Retained stream lines in FIFO order")
  (:f count Int64 "Total line count currently held in buffer"))

(df make-ring-buffer [(capacity Int64)] -> RingBuffer
  :d "Constructs an empty in-memory RingBuffer with specified capacity."
  (RingBuffer
    :capacity (if (<= capacity 0) 200 capacity)
    :lines (list)
    :count 0))

(df ring-push [(rb RingBuffer) (line String)] -> RingBuffer
  :d "Appends a line into the RingBuffer, evicting the oldest line if capacity is exceeded."
  (let [(cap (.-capacity rb))
        (cur (.-lines rb))
        (cnt (.-count rb))]
    (if (< cnt cap)
        (RingBuffer
          :capacity cap
          :lines (list-append cur (list line))
          :count (+ cnt 1))
        (let [(evicted-tail (option-or (list-slice cur 1 cnt) (list)))]
          (RingBuffer
            :capacity cap
            :lines (list-append evicted-tail (list line))
            :count cap)))))

(df ring-tail [(rb RingBuffer) (n Int64)] -> (List String)
  :d "Returns the last n lines from the RingBuffer."
  (let [(cur (.-lines rb))
        (cnt (.-count rb))]
    (cond
      ((<= n 0) (list))
      ((>= n cnt) cur)
      (:else (option-or (list-slice cur (- cnt n) cnt) (list))))))

(df ring-size [(rb RingBuffer)] -> Int64
  :d "Returns the current number of lines held in the RingBuffer."
  (.-count rb))

(df ring-to-string [(rb RingBuffer)] -> String
  :d "Joins all lines in the RingBuffer into a single string separated by newlines."
  (string-join (.-lines rb) "\n"))

(dfs DiskSpool
  (:f path String "Filesystem path to ephemeral disk spool")
  (:f max-bytes Int64 "Hard storage cap in bytes (default 10MB: 10485760)")
  (:f current-bytes Int64 "Current byte size of spool data")
  (:f content String "Spool byte content")
  (:f is-unlinked Bool "State flag verifying file descriptor auto-unlink"))

(df make-disk-spool [(path String) (max-bytes Int64)] -> DiskSpool
  :d "Constructs an ephemeral DiskSpool with specified maximum byte limit."
  (DiskSpool
    :path path
    :max-bytes (if (<= max-bytes 0) 10485760 max-bytes)
    :current-bytes 0
    :content ""
    :is-unlinked false))

(df spool-write [(spool DiskSpool) (chunk String)] -> DiskSpool
  :d "Writes data to disk spool, circularly truncating oldest bytes if max-bytes is exceeded."
  (let [(chunk-len (int32-to-int64 (string-length chunk)))]
    (if (<= chunk-len 0)
        spool
        (let [(cap (.-max-bytes spool))]
          (if (>= chunk-len cap)
              (let [(truncated (option-or (string-slice chunk (- chunk-len cap) chunk-len) ""))]
                (DiskSpool
                  :path (.-path spool)
                  :max-bytes cap
                  :current-bytes cap
                  :content truncated
                  :is-unlinked false))
              (let [(cur-len (.-current-bytes spool))
                    (comb-len (+ cur-len chunk-len))]
                (if (<= comb-len cap)
                    (DiskSpool
                      :path (.-path spool)
                      :max-bytes cap
                      :current-bytes comb-len
                      :content (str (.-content spool) chunk)
                      :is-unlinked false)
                    (let [(keep-len (- cap chunk-len))
                          (head-retained (option-or (string-slice (.-content spool) (- cur-len keep-len) cur-len) ""))
                          (truncated (str head-retained chunk))]
                      (DiskSpool
                        :path (.-path spool)
                        :max-bytes cap
                        :current-bytes cap
                        :content truncated
                        :is-unlinked false)))))))))

(df ! spool-sync! [(spool DiskSpool)] -> (Result DiskSpool String)
  :d "Writes spool content to disk using builtin file-write, ensuring file on disk is strictly <= max-bytes."
  (mt (file-write (.-path spool) (.-content spool))
    ((ok _) (ok spool))
    ((err _) (err (str "Failed to sync disk spool to " (.-path spool))))))

(df ! spool-write-sync! [(spool DiskSpool) (chunk String)] -> (Result DiskSpool String)
  :d "Pushes chunk circularly and flushes to disk."
  (let [(w (spool-write spool chunk))]
    (spool-sync! w)))

(df spool-truncate [(spool DiskSpool)] -> DiskSpool
  :d "Enforces circular byte truncation to max-bytes."
  (let [(len (.-current-bytes spool))
        (cap (.-max-bytes spool))]
    (if (<= len cap)
        spool
        (let [(txt (.-content spool))
              (start (- len cap))
              (truncated (option-or (string-slice txt start len) ""))]
          (DiskSpool
            :path (.-path spool)
            :max-bytes cap
            :current-bytes cap
            :content truncated
            :is-unlinked (.-is-unlinked spool))))))

(df spool-unlink [(spool DiskSpool)] -> DiskSpool
  :d "Reclaims disk spool storage and marks file descriptor as unlinked, truncating file on disk."
  (let [(_ (file-write (.-path spool) ""))]
    (DiskSpool
      :path (.-path spool)
      :max-bytes (.-max-bytes spool)
      :current-bytes 0
      :content ""
      :is-unlinked true)))

(df spool-is-unlinked? [(spool DiskSpool)] -> Bool
  :d "Verifies whether the ephemeral disk spool has been unlinked."
  (.-is-unlinked spool))

(dfs TwoTierSpool
  (:f ring RingBuffer "Tier 1 RAM ring buffer")
  (:f disk DiskSpool "Tier 2 ephemeral circular disk spool"))

(df make-two-tier-spool [(path String) (ring-cap Int64) (disk-cap Int64)] -> TwoTierSpool
  :d "Constructs coordinated two-tier spool with RAM ring buffer and circular disk spool."
  (TwoTierSpool
    :ring (make-ring-buffer ring-cap)
    :disk (make-disk-spool path disk-cap)))

(df two-tier-push [(s TwoTierSpool) (line String)] -> TwoTierSpool
  :d "Simultaneously pushes line to RAM ring buffer and writes formatted line to disk spool."
  (let [(new-ring (ring-push (.-ring s) line))
        (new-disk (spool-write (.-disk s) (str line "\n")))]
    (TwoTierSpool :ring new-ring :disk new-disk)))

(df two-tier-close [(s TwoTierSpool)] -> TwoTierSpool
  :d "Closes two-tier spool, unlinking ephemeral disk storage while retaining ring buffer for tail inspection."
  (TwoTierSpool
    :ring (.-ring s)
    :disk (spool-unlink (.-disk s))))
