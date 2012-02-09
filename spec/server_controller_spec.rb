require File.expand_path(File.join(File.dirname(__FILE__),'..','lib','monotable','monotable'))
require 'rubygems'
require 'rest_client'
require 'tmpdir'
require 'fileutils'
require 'net/http'
require 'json'
require 'uri'
require File.expand_path(File.join(File.dirname(__FILE__),'daemon_test_helper'))

describe Monotable::HttpServer::ServerController do
  include DaemonTestHelper

  before(:all) do
    start_daemon
  end

  after(:all) do
    shutdown_daemon
  end

  it "server/servers should return valid known-servers list" do
    server_client.servers.keys.should == ["127.0.0.1:32100"]
  end

  it "server/join joining the cluster should add the joining server-name to the known servers list" do
    server_client.join("frank")
    server_client.servers.keys.should == ["127.0.0.1:32100","frank"]
  end

  it "server/heartbeat should work" do
    server_client.up?.should == true
  end

  it "server/chunks should work" do
    server_client.chunks.should == [""] # a new, one-chunk test-store
  end

  it "server/chunk should work" do
    server_client.chunk("").should == {:records=>[]} # an empty chunk
  end

  it "server/local_store_status should work" do
    status = server_client.local_store_status
    status[:chunk_count].should==1
    status[:record_count].should==0
  end

  it "server/up_replicate_chunk should work" do
    # add something to the chunk we are going to up-replicate so we can verify it gets passed through
    test_record = {"field1"=>"value1"}
    server_client.set("foo",test_record)
    server_client["foo"].should==test_record

    # up_replicate
    chunk_data = server_client.up_replicate_chunk("")

    # parse and verify returned data
    chunk = Monotable::MemoryChunk.new(:data => chunk_data)
    chunk.range_start.should == ""
    chunk.keys.should == ["u/foo"]
    chunk["u/foo"].should == test_record
  end

  it "server/down_replicate_chunk should work" do
    server_client.chunks.should == [""]
    server_client.down_replicate_chunk("")
    server_client.chunks.should == []
  end

end
