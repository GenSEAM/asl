(module aslAgentCore/fastKnowledgeCache
  :x [AstSymbolEntry KnowledgeSnapshot knowledgeCacheCreate knowledgeIndexSymbol knowledgeLookupSymbol
      knowledgeUpdateTask knowledgeGetTaskStatus knowledgeRecordDefect knowledgeAddNote formatKnowledgeSnapshot]
  :i [])

(schema AstSymbolEntry
  (:f symbol Str)
  (:f module Str)
  (:f file Str)
  (:f anchor Str)
  (:f kind Str))

(schema KnowledgeSnapshot
  (:f epoch I64)
  (:f symbols (Map Str AstSymbolEntry))
  (:f taskStatuses (Map Str Str))
  (:f defectLedger (List Str))
  (:f notesSnapshot (List Str)))

fn knowledgeCacheCreate -> KnowledgeSnapshot
  (KnowledgeSnapshot
    :epoch 1
    :symbols (mapEmpty)
    :taskStatuses (mapEmpty)
    :defectLedger (list)
    :notesSnapshot (list))

fn knowledgeIndexSymbol snap: KnowledgeSnapshot sym: Str mod: Str file: Str anchor: Str kind: Str -> KnowledgeSnapshot
  (let [(entry (AstSymbolEntry :symbol sym :module mod :file file :anchor anchor :kind kind))
        (updated (mapSet snap.symbols sym entry))]
    (with snap :epoch (+ snap.epoch 1) :symbols updated))

fn knowledgeLookupSymbol snap: KnowledgeSnapshot sym: Str -> (Option AstSymbolEntry)
  (mapGet snap.symbols sym)

fn knowledgeUpdateTask snap: KnowledgeSnapshot taskId: Str status: Str -> KnowledgeSnapshot
  (let [(updated (mapSet snap.taskStatuses taskId status))]
    (with snap :epoch (+ snap.epoch 1) :taskStatuses updated))

fn knowledgeGetTaskStatus snap: KnowledgeSnapshot taskId: Str -> (Option Str)
  (mapGet snap.taskStatuses taskId)

fn knowledgeRecordDefect snap: KnowledgeSnapshot defectId: Str -> KnowledgeSnapshot
  (let [(updated (cons defectId snap.defectLedger))]
    (with snap :epoch (+ snap.epoch 1) :defectLedger updated))

fn knowledgeAddNote snap: KnowledgeSnapshot note: Str -> KnowledgeSnapshot
  (let [(updated (cons note snap.notesSnapshot))]
    (with snap :epoch (+ snap.epoch 1) :notesSnapshot updated))

fn formatKnowledgeSnapshot snap: KnowledgeSnapshot -> Str
  (str "(:knowledge-snapshot :epoch " (stringFromInt64 snap.epoch)
       " :symbols-count " (stringFromInt64 (mapSize snap.symbols))
       " :tasks-count " (stringFromInt64 (mapSize snap.taskStatuses))
       " :defects-count " (stringFromInt64 (listLength snap.defectLedger))
       " :notes-count " (stringFromInt64 (listLength snap.notesSnapshot)) ")")
