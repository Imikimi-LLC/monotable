require File.join(File.dirname(__FILE__),"..","mono_table_helper_methods")

describe Monotable::EventMachineServer do
  include DaemonTestHelper

  before(:each) do
    start_daemon(:initialize_new_store=>true,:num_index_levels => 2)
    start_daemon(:join=>daemon_address(0))
  end

  after(:each) do
    shutdown_daemon
  end

  it "should be possible to start up 2 daemons" do
    server_pids.length.should == 2
    server_client(0).up?.should==true
    server_client(1).up?.should==true
  end

  it "should be possible replicate" do
    chunk_name = server_client.chunks[-1]
    server_client(0).set_chunk_replication(chunk_name,nil,daemon_address(1))
    server_client(0).chunk_status(chunk_name)["replication_client"].should == daemon_address(1)

    server_client(1).chunks.should==[]
    server_client(1).clone_chunk(chunk_name,daemon_address(0))
    server_client(1).chunks.should==[chunk_name]

    server_client(0).chunk_keys(chunk_name).should==[]
    server_client(1).chunk_keys(chunk_name).should==[]

    # set
    server_client.set("frank","foo" => "bar", "peggy" => "sue")
    server_client(0).internal["u/frank"].should == {"foo" => "bar", "peggy" => "sue"}
    server_client(1).internal["u/frank"].should == {"foo" => "bar", "peggy" => "sue"}

    # overwrite
    server_client.set("frank","foo" => "bar", "peggy" => "food")
    server_client(0).internal["u/frank"].should == {"foo" => "bar", "peggy" => "food"}
    server_client(1).internal["u/frank"].should == {"foo" => "bar", "peggy" => "food"}

    # update
    server_client.update("frank","foo" => "star")
    server_client(0).internal["u/frank"].should == {"foo" => "star", "peggy" => "food"}
    server_client(1).internal["u/frank"].should == {"foo" => "star", "peggy" => "food"}

    server_client.delete("frank")
    server_client(0).internal["u/frank"].should == nil
    server_client(1).internal["u/frank"].should == nil
  end
end
