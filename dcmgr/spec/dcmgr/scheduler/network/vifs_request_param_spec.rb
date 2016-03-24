# -*- coding: utf-8 -*-

require 'spec_helper'

Dir["#{File.dirname(__FILE__)}/vifs_request_param_examples/*.rb"].each {|f| require f }

describe Dcmgr::Scheduler::Network::VifsRequestParam do
  include NetworkHelper

  before(:all) do
    Dcmgr::Configurations.load Dcmgr::Configurations::Dcmgr,
    [DEFAULT_DCMGR_CONF]
  end

  describe "#schedule" do
    let(:inst) do
      i = Fabricate(:instance, request_params: {"vifs" => vifs_parameter})

      Dcmgr::Scheduler::Network::VifsRequestParam.new.schedule(i)

      i
    end

    before { Fabricate(:mac_range) }

    describe "sad paths" do
      # We need to place our subject in a function if we're checking for errors
      # Otherwise the error will happen before we 'expect' it
      # http://stackoverflow.com/questions/6837663/rspec-implicit-subject-and-exceptions
      subject { lambda { inst } }

      include_examples "malformed vifs"
      include_examples "dhcp range exhausted"
      include_examples "wrong network"
    end


    describe "happy paths" do
      subject { inst }

      include_examples "empty vifs"
      include_examples "single vif"
      include_examples "two vifs"
      include_examples "single vif no network"
    end
  end
end
