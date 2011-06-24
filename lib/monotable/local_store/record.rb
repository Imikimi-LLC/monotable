module MonoTable

  class Record
    attr_accessor :accounting_size
    attr_accessor :key

    def accounting_size
      @accounting_size||=calculate_accounting_size
    end

    def [](key) fields[key] end

    def update(new_fields)
      fields.update(new_fields)
    end

    def length() fields.length end
    def keys() fields.keys end
    def ==(other) other && length==other.length && fields.each {|k,v| v==other[k]} end

    def Record.parse_record(data,column_dictionary,column_hash=nil)
      fields={}
      di=0
      data = StringIO.new(data) if data.kind_of?(String)
      until data.eof?
        col_id = data.read_asi
        col = column_dictionary[col_id]

        if column_hash && !column_hash[col]
          # we could be more efficient and skip over the col_data if the column isn't in the column_hash
          # currently: READ AND IGNORE
          col_data = data.read_asi_string
        else
          d=data.read_asi_string
          fields[col] = d
        end
      end
      fields
    end

    def calculate_accounting_size(fs=nil)
      sum=key.length #+ MINIMUM_CHUNK_RECORD_OVERHEAD_IN_BYTES
      (fs||fields).each do |k,v|
        sum+=k.length + v.length
      end
      sum
    end

    def encoded(columns)
      fields_local=fields
      keys.collect do |key|
        val=fields_local[key]
        columns[key].to_asi + val.to_asi_string if val  # nil field values are not stored
      end.compact.join
    end

    #api for derived classes to implement:
    #def fields(column_hash=nil) end
    #def update(column_hash) end
  end

  class MemoryRecord < Record
    attr_accessor :fields

    def fields(columns_hash=nil)
      if columns_hash
        Tools.select_columns(@fields,columns_hash)
      else
        @fields
      end
    end

    def initialize(key,fields=nil,column_dictionary=nil,columns_hash=nil)
      @key=key
      if fields
        if fields.respond_to?(:eof?) || fields.kind_of?(String)
          @fields=Record.parse_record(fields,column_dictionary,columns_hash)
        else
          fields=Tools.select_columns(fields,columns_hash) if columns_hash
          self.fields=fields
        end
      else
        @fields={}
      end
    end

    def validate_fields(fields)
      raise "fields must be a hash" unless fields.kind_of? Hash
      fields.each do |k,v|
        raise "keys must be strings (k.class == #{k.class})" unless k.kind_of? String
        raise "fields must be strings (v.class == #{v.class})" unless v.kind_of? String
      end
    end

    def fields=(fields)
      validate_fields(fields)
      @fields=fields
      @accounting_size=nil
      fields
    end

    def update(column_hash)
      validate_fields(column_hash)
      fields.merge! column_hash
      recalc_size
      fields
    end
  end

  class DiskRecord < Record
    attr_accessor :file_handle
    attr_accessor :offset
    attr_accessor :length
    attr_accessor :column_dictionary

    def initialize(key,offset,length,accounting_size,file_handle=nil,column_dictionary=nil)
      @key=key
      self.file_handle=file_handle
      self.offset=offset
      self.length=length
      self.accounting_size=accounting_size
      self.column_dictionary=column_dictionary
    end

    def [](key)
      fields({key=>true})
    end

    def fields(column_hash=nil)
      data=file_handle.read(offset,length)
      Record.parse_record(data,column_dictionary,column_hash)
    end

    def match_to_entry_on_disk(entry_offset_on_disk,entry_file_handle=nil,entry_columns_dictionary=nil)
      self.offset+=entry_offset_on_disk
      self.file_handle=entry_file_handle if entry_file_handle
      self.column_dictionary=entry_columns_dictionary if entry_columns_dictionary
    end
  end

  class JournalDiskRecord < Record
    attr_accessor :file_handle
    attr_accessor :offset
    attr_accessor :length

    def initialize(key,file_handle,offset,length,record)
      @key=key
      self.file_handle=file_handle
      self.offset=offset
      self.length=length
      self.accounting_size=case record
      when Record then record.accounting_size
      when Hash then calculate_accounting_size(record)
      else raise "invalid record class #{record.class}"
      end
    end

    def [](key)
      fields({key=>true})
    end

    def fields(columns_hash=nil)
      data=file_handle.read(offset,length)
      f=Journal.read_entry(StringIO.new(data))[:fields]
      f=Tools.select_columns(f,columns_hash) if columns_hash
      f
    end
  end
end
