require "fileutils"
=begin
NOT THREADSAFE
  Journals will not be threadsafe. Instead, JournalManagers will guarantee serial access to Journals
=end

module Monotable
  class Journal
    class << self
      # set Journal.async_compaction=true to enable asynchronous compaction
      attr_accessor :async_compaction

      def parse_entry_without_checksum(io_stream)
        strings = []
        strings << io_stream.read_asi_string while !io_stream.eof?
        command = strings[1]
        chunk_basename = strings[0]
        {:command => command.to_sym, :chunk_basename => chunk_basename}.merge(case command
          when "delete"       then {:key=>strings[2]}
          when "delete_chunk" then {}
          when "split"        then {:on_key => strings[2], :to_basename => strings[3]}
          when "move_chunk"   then {:to_store_path => strings[2]}
          when "set"          then {:key => strings[2], :fields => Hash[*strings[3..-1]]}
          else raise InternalError.new "parse_entry: invalid journal entry command: #{command.inspect}"
        end)
      end

      def parse_entry(io_stream)
        entry_string=Monotable::Tools.read_asi_checksum_string_from_file(io_stream)
        parse_entry_without_checksum StringIO.new(entry_string)
      end
    end

    # all possible mutations to a chunk go through this API
    module WriteAPI
      def set(chunk,key,record)
        offset=@size
        save_str=save_entry("set", chunk, key, record.collect {|k,v| [k,v]})
        length=save_str.length
        JournalDiskRecord.new(chunk,key,self,offset,length,record)
      end

      def delete(chunk,key)
        save_entry "delete", chunk, key
      end

      def delete_chunk(chunk)
        save_entry "delete_chunk", chunk
      end

      def move_chunk(chunk,path_store)
        save_entry "move_chunk", chunk, path_store.path
      end

      def split(chunk,key,to_basename)
        save_entry "split", chunk, key, to_basename
      end
    end

    attr_accessor :journal_file
    attr_accessor :read_only
    attr_accessor :size
    attr_accessor :journal_manager
    attr_accessor :max_journal_size
    include WriteAPI

    def initialize(file_name,options={})
      @journal_manager=options[:journal_manager]
      @journal_file=FileHandle.new(file_name.chomp(COMPACT_DIR_EXT))
      @read_only=@journal_file.exists?
      @size=@journal_file.length
      @max_journal_size = options[:max_journal_size] || DEFAULT_MAX_JOURNAL_SIZE
    end

    def full?
      @size > @max_journal_size
    end

    def read_entry(disk_offset,disk_length)
      journal_file.open_read(true)
      journal_file.read_handle.seek(disk_offset)
      Journal.parse_entry(journal_file.read_handle)
    end

    def journal
      self
    end

    def local_store
      @local_store ||= journal_manager && journal_manager.local_store
    end

    def journal_write(save_str)
      journal_file.open_append(true)
      @size+=Monotable::Tools.write_asi_checksum_string(journal_file,save_str)
      journal_file.flush
      EM::next_tick {self.compact} if full?
      save_str
    end

    def save_entry(command,chunk,*args)
      partial_save_string = [command,args].flatten.collect {|str| [str.length.to_asi,str]}.flatten.join

      chunk.journal_write(partial_save_string)

#      journal_write(save_str)
    end

    # compact this journal and all the chunks it is tied to
    # the end result is the journal is deleted and all the chunk files have been updated
    # Contains auto-recovery code. If it crashes at any point, just run it again and it will recover assuming the failure was temporary (like a machine crash).
    # TODO: This assumes the journal and chunk files are not corrupt, if they
    #   are corrupt, we do not currently handle that. Corruption is currently being detected
    #   via checksums resulting, currently, in exceptions being thrown out of this
    #   method. We should trap these exceptions, and re-replicate from other servers where necessary.
    # TODO: This does not currently handle multitasking where the current in-memory copies of the chunks need to be updated safely
    # option:
    #   :async => true
    #     if async is true, then the phase_1 compaction is run externally and control is returned immediately.
    #     Be sure to run CompactionManager.singleton.process_queue at some later point to finalize journal processing.
    def compact(options={},&block)
      journal_manager && journal_manager.freeze_journal(self)
      @read_only=true

      if Journal.async_compaction #options[:async]
        CompactionManager.compact(journal_file, :local_store => local_store, &block)
      else
        compactor = Compactor.new(journal_file, :local_store => local_store)
        compactor.compact_phase_1
        compactor.compact_phase_2
        yield if block
      end
    end
  end
end

