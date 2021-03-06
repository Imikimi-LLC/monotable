require File.join(File.dirname(__FILE__),"..","mono_table_helper_methods")

describe Monotable::LocalStore do
  include MonotableHelperMethods

  def blank_store
    reset_temp_dir
    Monotable::LocalStore.new(:store_paths=>[temp_dir],:initialize_new_test_store=>true)
  end

  it "should be possible to initialize a new LocalStore" do
    local_store=blank_store
    local_store.chunks.length.should == 1
  end

  it "should be OK to init a localstore with no path-stores" do
    local_store = Monotable::LocalStore.new

    local_store.chunks.length.should == 0
  end

  it "should be possible to init from an existing LocalStore" do
    local_store=blank_store

    # open existing localstore
    local_store=Monotable::LocalStore.new(:store_paths=>[temp_dir])
    local_store.chunks.length.should == 1

    local_store.chunks.each do |k,v|
      v.kind_of?(Monotable::DiskChunk).should == true
    end
  end

  it "should be possible to add entries to the localstore" do
    local_store=blank_store

    #load-it-up
    local_store.chunks.length.should == 1
    local_store.get_chunk("").accounting_size.should == 0
    load_test_data_directory(local_store)
    local_store.chunks.length.should == 1
    local_store.get_chunk("").records.length.should == 5
    local_store.get_chunk("").verify_accounting_size
    local_store.get_chunk("").accounting_size.should == 147095
  end

  it "should be possible to attach a localstore to a path with existing data" do
    local_store=blank_store
    load_test_data_directory(local_store)
    local_store.compact #get_chunk("").journal.compact

    #load LocalStore anew
    local_store2=Monotable::LocalStore.new(:store_paths=>[temp_dir])
    local_store2.chunks.length.should == 1
    local_store2.get_chunk("").length.should == 5
    Monotable::MemoryChunk.load(local_store2.get_chunk("").filename).accounting_size.should == 147095
  end

  it "should be possible to attach a localstore to a path with a non-compacted journal" do
    local_store=blank_store
    load_test_data_directory(local_store)

    #load LocalStore anew
    local_store2 = Monotable::LocalStore.new(:store_paths=>[temp_dir])
    local_store2.chunks.length.should == 1
    local_store2.get_chunk("").length.should == 5
    Monotable::MemoryChunk.load(local_store2.get_chunk("").filename).accounting_size.should == 147095

    #test write
    local_store2.set("testkey",{"field"=>"value"})
  end

  it "should be possible to compact a journal" do
    local_store=blank_store

    #load-it-up
    load_test_data_directory(local_store)

    # compact it
    local_store.path_stores[0].journal_manager.current_journal.compact

    # load the chunk
    chunk=Monotable::MemoryChunk.load(local_store.get_chunk("").filename)
    chunk.keys.sort.should == ["0-255.binary", "0-65535.words.binary", "declaration_of_independence.txt", "plato.jpeg", "simple.png"].sort
  end

  it "should be possible to split a chunk" do
    local_store=blank_store

    #load-it-up
    load_test_data_directory(local_store)

    # split the chunk
    chunk1=local_store.get_chunk("")
    chunk1.length.should==5
    chunk2=chunk1.split("declaration_of_independence.txt")
    chunk1.length.should==2
    chunk2.length.should==3
  end

  it "should be possible to split a chunk on a specific key" do
    local_store=blank_store

    #load-it-up
    load_test_data_directory(local_store)

    # split the chunk
    chunk1=local_store.get_chunk("")
    chunk1.length.should==5
    chunk2=chunk1.split
    chunk1.length.should==2
    chunk2.length.should==3
  end

  it "max_chunk_size and max_index_block_size should propagate" do
    reset_temp_dir
    test_max_chunk_size = 16 * 1024
    test_max_index_block_size = 256
    local_store=Monotable::LocalStore.new(
      :store_paths => [temp_dir],
      :max_chunk_size => test_max_chunk_size,
      :max_index_block_size => test_max_index_block_size,
      :initialize_new_test_store => true
    )

    # split the chunk
    path_store1 = local_store.path_stores[0]
    path_store1.max_chunk_size.should == test_max_chunk_size
    path_store1.max_index_block_size.should == test_max_index_block_size

    # split the chunk
    chunk1 = local_store.get_chunk("")
    chunk1.max_chunk_size.should == test_max_chunk_size
    chunk1.max_index_block_size.should == test_max_index_block_size
  end

  it "should not return the record after we've deleted it" do
    local_store=blank_store

    record_key = 'apple'
    record_value = { 'x' => '1' }
    local_store.set(record_key,record_value)

    local_store.get(record_key)[:record].should_not==nil

    local_store.delete(record_key)
    local_store.get(record_key)[:record].should==nil
  end

  it "should be possible to read a record back after compaction" do
    local_store=blank_store
    record_key = 'apple'
    record_value = { 'x' => '1' }
    local_store.set(record_key,record_value)

    current_async_compaction = Monotable::Journal.async_compaction
    local_store.compact
    Monotable::Journal.async_compaction = current_async_compaction

    local_store.get(record_key).should >= {:record=>{"x"=>"1"}, :size=>7, :num_fields=>1}
  end

  it "should be possible to write 2 records and read the second back from the journal" do
    local_store=blank_store
    record_key = 'apple'
    record_value = { 'x' => '1' }
    local_store.set(record_key,record_value)
    local_store.set(record_key+"2",{ 'x' => '2'})
    local_store.set(record_key+"3",{ 'x' => '3'})

    Monotable::Cache.global_cache.reset

    local_store.get(record_key+"3").should >= {:record=>{"x"=>"3"}, :size=>8, :num_fields=>1}
    local_store.get(record_key+"2").should >= {:record=>{"x"=>"2"}, :size=>8, :num_fields=>1}
    local_store.get(record_key).should >= {:record=>{"x"=>"1"}, :size=>7, :num_fields=>1}
  end

end
