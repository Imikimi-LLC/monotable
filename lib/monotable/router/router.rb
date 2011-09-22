# encoding: BINARY
module Monotable
  class Router
    attr_accessor :local_store
    attr_accessor :clients

    #options[:local_store] => LocalStore
    def initialize(options={})
      @local_store=options[:local_store]
      @clients=[]
      raise ArgumentError,"options[:local_store].kind_of?(LocalStore) required" unless @local_store.kind_of?(LocalStore)
    end

    def paxos_record
    end

    # find the servers containing the chunk that covers key
    def servers(internal_key)
      if internal_key[0..paxos_record.key.length-1]==paxos_record.key
        paxos_record[:servers]
      else
        get("+"+internal_key)[:record]["servers"].split(",")
      end
    end

    def server_client(ikey)
      ss=servers(ikey)
      server=ss[rand(ss.length)]
      clients[server]
    end

    def Router.internalize_key(external_key)
      "u/"+external_key
    end

    def Router.externalize_key(internal_key)
      internal_key[2..-1]
    end

    def Router.internalize_range_options(range_options)
      [:gte,:gt,:lte,:lt,:with_prefix].each do |key|
        range_options[key]=Router.internalize_key(range_options[key]) if range_options[key]
      end
      range_options
    end
  end

  # see ReadAPI
  module RoutedReadAPI
    include ReadAPI

    # see ReadAPI
    def get(key,field_names=nil)
      route(key) {|store,key| store.get(key,field_names)}
    end

    # see ReadAPI
    def get_first(options={})
      route_get_range(options,:gte) {|store,options| process_get_range_result store.get_first(options)}
    end

    # see ReadAPI
    def get_last(options={})
      route_get_range(options,:lte) {|store,options| process_get_range_result store.get_last(options)}
    end
  end

  # see WriteAPI
  module RoutedWriteAPI
    include WriteAPI

    # see WriteAPI
    def set(key,fields)
      route(key) {|store,key| store.set(key,fields)}
    end

    # see WriteAPI
    def update(key,fields)
      route(key) {|store,key| store.update(key,fields)}
    end

    # see WriteAPI
    def delete(key)
      route(key) {|store,key| store.delete(key)}
    end
  end

  class ExternalRequestRouter
    include RoutedReadAPI
    include RoutedWriteAPI

    attr_accessor :router

    def initialize(router)
      @router=router
      raise ArgumentError,"router.kind_of?(Router) required" unless router.kind_of?(Router)
      raise InternalError,"router.local_store not set" unless router.local_store
    end

    def process_get_range_result(result)
      result[:records]=result[:records].collect do |k,v|
        [Router.externalize_key(k),v]
      end
      result
    end

    #routing_option should be :gte or :lte
    # yields the store to route to and the options, internalized
    def route_get_range(options,routing_option)
      Tools.normalize_range_options(options)
      route(options[routing_option]) do |store,key|
        yield store,Router.internalize_range_options(options)
      end
    end

    # yields store, key
    #   store => store to route to
    #   key => use this key instead of the key passed to route
    def route(key)
      ikey=Router.internalize_key(key)
      work_log=[]
      ret=if router.local_store.local?(ikey)
        work_log<<"processed locally"
        yield router.local_store,ikey
      else
        sc=router.server_client(ikey)
        work_log<<"forwarding request to: #{sc}"
        yield sc,ikey
      end
      ret[:work_log]=(ret[:work_log]||[])+work_log
      ret
    end
  end

  class InternalRequestRouter
    include RoutedReadAPI
    include RoutedWriteAPI

    attr_accessor :router

    def initialize(router)
      @router=router
    end

    def process_get_range_result(result)
      result
    end

    #routing_option should be :gte or :lte
    # yields the store to route to and the options, internalized
    def route_get_range(options,routing_option)
      Tools.normalize_range_options(options)
      route(options[routing_option]) do |store,key|
        yield store,options
      end
    end

    # yields store, key
    #   store => store to route to
    #   key => use this key instead of the key passed to route
    def route(key)
      work_log=[]
      ret=if router.local_store.local?(key)
        work_log<<"processed locally"
        yield router.local_store,key
      else
        {:error=>"key not covered by local chunks"}
      end
      ret[:work_log]=(ret[:work_log]||[])+work_log
      ret
    end
  end
end
