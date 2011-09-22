module Monotable
  COMPACT_DIR_EXT=".compact"
  CHUNK_EXT=".mt_chunk"
  JOURNAL_EXT=".mt_journal"
  DEFAULT_MAX_KEY_LENGTH = 1024
  DEFAULT_MAX_CHUNK_SIZE = 64 * 1024 * 1024
  DEFAULT_MAX_JOURNAL_SIZE = 128 * 1024 * 1024
  MINIMUM_CHUNK_RECORD_OVERHEAD_IN_BYTES=5
  DEFAULT_MAX_INDEX_BLOCK_SIZE = 64 * 1024
  JOURNAL_COMPACTION_SUCCESS_FILENAME = "journal_compaction_was_successful"

  FIRST_DATA_KEY="0"
  INDEX_KEY_PREFIX="+"
end