require File.join(File.dirname(__FILE__),"mono_table_helper_methods")
require File.join(File.dirname(__FILE__),"common_api_tests")

describe Monotable::DiskChunkBase do
  include MonotableHelperMethods

  def blank_store
    reset_temp_dir
    filename=File.join(temp_dir,"test#{Monotable::CHUNK_EXT}")
    Monotable::MemoryChunk.new().save(filename)
    Monotable::DiskChunkBase.new(:filename=>filename)
  end

  api_tests
end
