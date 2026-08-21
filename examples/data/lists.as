; The List section of the vocabulary, in use. A small scheduling helper: enough
; real work that every list operation appears where it belongs rather than in a
; roll-call.

(module data/lists
  :doc "Inspect and reorder a queue of task names."
  :export [empty-queue? size first-task rest-of-queue enqueue-front join-queues
           reversed page holds? position-of sorted sorted-by-length total-weight
           lightest heaviest nth-task])

(defun empty-queue? [(q (List String))] -> Bool
  :doc "True when the queue holds nothing."
  (list-empty? q))

(defun size [(q (List String))] -> Int64
  :doc "Number of queued tasks."
  (list-length q))

(defun first-task [(q (List String))] -> (Option String)
  :doc "The task at the head of the queue."
  (list-head q))

(defun rest-of-queue [(q (List String))] -> (List String)
  :doc "The queue without its head; an empty queue stays empty."
  (option-or (list-tail q) (list)))

(defun enqueue-front [(task String) (q (List String))] -> (List String)
  :doc "Put a task at the head of the queue."
  (list-cons task q))

(defun join-queues [(a (List String)) (b (List String))] -> (List String)
  :doc "One queue after another."
  (list-append a b))

(defun reversed [(q (List String))] -> (List String)
  :doc "The queue in reverse order."
  (list-reverse q))

(defun page [(q (List String)) (from Int64) (upto Int64)] -> (List String)
  :doc "A half-open window of the queue, empty when out of range."
  (option-or (list-slice q from upto) (list)))

(defun holds? [(q (List String)) (task String)] -> Bool
  :doc "True when the task is queued."
  (list-contains? q task))

(defun position-of [(q (List String)) (task String)] -> (Option Int64)
  :doc "Where a task sits in the queue."
  (list-index-of q task))

(defun sorted [(q (List String))] -> (List String)
  :doc "The queue in ascending order."
  (list-sort q))

(defun sorted-by-length [(q (List String))] -> (List String)
  :doc "The queue ordered by task-name length."
  (list-sort-by (fn [(t String)] -> Int64 (string-length t)) q))

(defun total-weight [(ws (List Int64))] -> Int64
  :doc "Sum of task weights."
  (list-sum ws))

(defun lightest [(ws (List Int64))] -> (Option Int64)
  :doc "Smallest task weight, when there is one."
  (list-min ws))

(defun heaviest [(ws (List Int64))] -> (Option Int64)
  :doc "Largest task weight, when there is one."
  (list-max ws))

(defun nth-task [(q (List String)) (i Int64)] -> (Option String)
  :doc "The task at an index."
  (list-get q i))
