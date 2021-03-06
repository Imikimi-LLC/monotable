require "rubygems"
require "inline"
require "benchmark"
require "../lib/monotable/monotable"
require "../spec/mono_table_helper_methods.rb"
Thread.abort_on_exception=true
$temp_dir=MonotableHelper.new.temp_dir
file=Monotable::FileHandle.new(File.join($temp_dir,"/test.tmp"))
puts "temp_dir=#{$temp_dir}"

def write_min_record_asi(key,record,file)
  command="set"
  str=[
    command.length.to_asi,
    command,
    key.length.to_asi,
    key,
    ]+record.keys.collect {|k| v=record[k];[k.length.to_asi,k,v.length.to_asi,v]}
  Monotable::Tools.write_asi_checksum_string file,str.join
  file.flush
end

def write_min_record_asi_noflush(key,record,file)
  command="set"
  str=[
    command.length.to_asi,
    command,
    key.length.to_asi,
    key,
    ]+record.keys.collect {|k| v=record[k];[k.length.to_asi,k,v.length.to_asi,v]}
  Monotable::Tools.write_asi_checksum_string file,str.join
end

# an alternative writing scheme that uses a slitghtly different checksum
# the main difference is we don't copy any strings in memory; we just write them out in the correct order
def write_min_record_asi2(key,record,file)
  command="set"
  strs=[
    command,
    key,
    ]+record.keys.collect {|k| v=record[k];[k,v]}
  strs=strs.flatten
  file.open_append(true) do |f|
    f.write strs.length.to_asi
    f.write Monotable::Tools.checksum_array(strs)
    strs.each do |str|
      f.write str.length.to_asi
      f.write str
    end
  end
  file.flush
end

# an alternative writing scheme that uses a slitghtly different checksum
# the main difference is we don't copy any strings in memory; we just write them out in the correct order
def exclusive_write_min_record_asi2(key,record,file)
  command="set"
  strs=[
    command,
    key,
    ]+record.keys.collect {|k| v=record[k];[k,v]}.flatten

  save_str=strs.collect {|str| [str.length.to_asi,str]}.flatten.join

  file.open_exclusive_append(true) do |f|
    Monotable::Tools.write_asi_checksum_string(f,save_str)
    f.fsync #file.flush
  end
end

def write_unchecked_record_asi(key,record,file)
  command="set"
  chunk="000000.mt_chunk"
  str=[
    command.length.to_asi,
    command,
    chunk.length.to_asi,
    chunk,
    key.length.to_asi,
    key,
#    record.length.to_asi
    ]+record.keys.collect {|k| v=record[k];[k.length.to_asi,k,v.length.to_asi,v]}
  file.write Monotable::Tools.to_asi_checksum_string(str.join) #.to_asi_string
  file.flush
end

def write_monotable_entry(k,r,file)
  entry=Monotable::Chunk.new
  entry.set(k,r)
  file.write entry.to_binary
  file.flush
end

def read_monotable_entry(file)
  Monotable::Chunk.new(file)
end

def read_asi(file)
  checksum_string=Monotable::Tools.read_asi_checksum_string_from_file(file)
  file = StringIO.new(checksum_string)
  command = file.read_asi_string
  key = file.read_asi_string
  fields={}
  while !file.eof?
    k=file.read_asi_string
    v=file.read_asi_string
    fields[k]=v
  end
  {:command=>command.intern,
  :key=>key,:fields=>fields}
end

def write_record_marshal(key,record,file)
  command="set"
  chunk="000000.mt_chunk"
  to_write={
    :cmd =>"set",
    :key => key,
    :rec => record,
    :chunk => chunk
    }
  str=Marshal.dump(to_write).to_asi_string
  file.write str
  fi5~le.flush
end

def read_marshal(file)
  m=file.read_asi_string
  Marshal.load(m)
end

def test(testname,benchmarker,file,records=500000)
  file.delete if file.exists?
  file.open_write(true)
  time=
  benchmarker.report("%-30s"%"#{records}x: #{testname}") {(1..records).each do |a|
    key=a.to_s
    val={"value"=>key}
    yield key,val,file
  end}.real
  file.close
  puts "\t\t\t\t\t\t\t\t\t\tsize=#{file.size} time=#{(time*1000).to_i}ms mB/sec=#{"%.1f"%(file.size/(time*1024*1024))} records/sec=#{(records/time).to_i}"
end

def threaded_test(testname,benchmarker,file,records=500000,threads=10)
  MonotableHelper.new.reset_temp_dir
  file.delete if file.exists?
  file.open_write(true)
  records/=threads
  time=
  benchmarker.report("%-30s"%"#{records}x#{threads}: #{testname}") do
    thread_array=[]
    threads.times do
      thread_array<<Thread.new(records,file) do |recs,file|
        records.times do |a|
          key=a.to_s
          val={"value"=>key}
          yield key,val,file
        end
      end
    end
    thread_array.each {|a| a.join}
  end.real
  file.close
  records*=threads
  puts "\t\t\t\t\t\t\t\t\t\tsize=#{file.size} time=#{(time*1000).to_i}ms mB/sec=#{"%.1f"%(file.size/(time*1024*1024))} records/sec=#{(records/time).to_i}"
  records_c2=0
  file.read(0,nil,true) do |io_stream|
    while !io_stream.eof?
      entry_string=Monotable::Tools.read_asi_checksum_string_from_file(io_stream)
      strings_stream = StringIO.new(entry_string)
      strings=[]
      strings<<strings_stream.read_asi_string while !strings_stream.eof?
#      puts strings.inspect
      records_c2+=1
    end
  end
  puts "records=#{records} records_c2=#{records_c2}"
  exit 1
end

def test_journal(testname,benchmarker,file,records=500000,chunk_name="0000000.mt_chunk")
  file.delete if file.exists?
  file.close
  MonotableHelper.new.reset_temp_dir
  journal=Monotable::Journal.new(file.filename)
  journal.journal_file.open_append
  time=benchmarker.report("%-30s"%"#{records}x: #{testname}") {(1..records).each do |a|
    key=a.to_s
    val={"value"=>key}
    journal.set(chunk_name,key,val)
  end}.real
  file.close
  puts "\t\t\t\t\t\t\t\t\t\tsize=#{file.size} time=#{(time*1000).to_i}ms mB/sec=#{"%.1f"%(file.size/(time*1024*1024))} records/sec=#{(records/time).to_i}"
end

def test_mt(testname,benchmarker,records=500000,value="test")
  MonotableHelper.new.reset_temp_dir
  mt=yield # create the monotable object AFTER we empty the test dir
  #set max_journal_size >> total bytes we are going to write
  accounting_size_written=0
  val={"value"=>value}
  time=benchmarker.report("%-30s"%"#{records}x: #{testname}") {(1..records).each do |a|
    key=a.to_s
    record=mt.set(key,val)
    accounting_size_written+=record[:size]
  end}.real
  puts "\t\t\t\t\t\t\t\t\t\tsize=#{accounting_size_written} time=#{(time*1000).to_i}ms mB/sec=#{"%.1f"%(accounting_size_written/(time*1024*1024))} records/sec=#{(records/time).to_i}"
end

def read_test(testname,benchmarker,file)
  file.open_read
  records=0
  time=benchmarker.report("%-30s"%"#{records}x: #{testname}") do
    f=file.read_handle
    last_entry=nil
    while !f.eof
      last_entry=yield f
      records+=1
    end
    expected={:command=>:set, :key=>last_entry[:key], :fields=>{"value"=>last_entry[:key]}}
    raise "decode for first record failed. Decoded=#{last_entry.inspect} Expected=#{expected.inspect}" unless last_entry==expected
  end.real
  puts "\t\t\t\t\t\t\t\t\t\tsize=#{file.size} time=#{(time*1000).to_i}ms mB/sec=#{"%.1f"%(file.size/(time*1024*1024))} records/sec=#{(records/time).to_i}"
end

def journal_read_test(testname,benchmarker,file,expected_records)
  file.close
  records=0
#  journal=Monotable::Journal.new(file.filename)
  time=benchmarker.report("%-30s"%"#{expected_records}x: #{testname}") do
    last_entry=nil
    Monotable::Journal.each_entry(file) do |entry|
      last_entry=entry
      records+=1
    end

    expected={:command=>:set, :key=>last_entry[:key], :fields=>{"value"=>last_entry[:key]}, :chunk_file=>"0000000.mt_chunk"}
    raise "decode for first record failed. Decoded=#{last_entry.inspect} Expected=#{expected.inspect}" unless last_entry==expected
  end.real
  puts "\t\t\t\t\t\t\t\t\t\tsize=#{file.size} time=#{(time*1000).to_i}ms mB/sec=#{"%.1f"%(file.size/(time*1024*1024))} records/sec=#{(records/time).to_i}"
  raise "expected_records(#{expected_records}) != records(#{records})" unless expected_records==records
end


Benchmark.bm do |benchmarker|
  test(:min_possible2,benchmarker,file,10000) {|key,val,file| write_min_record_asi2(key,val,file);}
  threaded_test(:min_possible2_threaded,benchmarker,file,100000,10) do |key,val,file|
    exclusive_write_min_record_asi2(key,val,file)
  end

  test(:write_1_byte,benchmarker,file,10000) {|key,val,file| file.write("a");file.flush;}
  test(:write_1_byte_noflush,benchmarker,file,10000) {|key,val,file| file.write("a");}
  test(:min_possible,benchmarker,file,10000) {|key,val,file| write_min_record_asi(key,val,file);}
  test(:min_possible_noflush,benchmarker,file,10000) {|key,val,file| write_min_record_asi_noflush(key,val,file);}



  test(:unchecked,benchmarker,file,10000) {|key,val,file| write_unchecked_record_asi(key,val,file);}
  test_journal(:journal_min,benchmarker,file,10000)
  journal_read_test(:journal_read,benchmarker,file,10000)
  test_journal(:journal_real,benchmarker,file,10000,"/mnt/hgfs/shanebdavis/imikimi/opensource/monotable/test/tmp/test_chunk")


  test_mt(:disk_chunk,benchmarker,10000)                  {Monotable::DiskChunk.new(:filename=>File.join($temp_dir,"test_chunk"))}
                                                          ls_options={:store_paths=>[$temp_dir],:max_journal_size=>1024**4,:initialize_new_store=>true}
  test_mt(:local_store_small,benchmarker,10000)           {Monotable::LocalStore.new(ls_options)}
  test_mt(:local_store_1k,benchmarker,10000,"0"*1024)     {Monotable::LocalStore.new(ls_options)}
  test_mt(:local_store_10k,benchmarker,5000,"0"*10240)    {Monotable::LocalStore.new(ls_options)}
  test_mt(:local_store_100k,benchmarker,1000,"0"*102400)  {Monotable::LocalStore.new(ls_options)}
end

