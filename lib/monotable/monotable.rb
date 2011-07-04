require File.join(File.dirname(__FILE__),"xbd")

%w{
  events/event
  events/event_queue
  constants
  tools
  file_handle
  journal
  journal_manager
  record
  chunk
  index_block
  index_block_encoder
  memory_chunk
  disk_chunk_base
  disk_chunk2
  path_store
  local_store
  }.each do |file|
    require File.join(File.dirname(__FILE__),"local_store",file)
end

%w{
  solo_daemon
  }.each do |file|
    require File.join(File.dirname(__FILE__),"solo_daemon",file)
end

module Monotable
  # Your code goes here...
end
