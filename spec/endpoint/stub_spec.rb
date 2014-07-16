require 'spec_helper'

class TestModel < ActiveResource::Base
  self.site = "not-a-site.com/api"
end

describe Endpoint::Stub, stub_spec: true do
  describe '.stubs' do
    it 'should be a global hash of endpoint stubs, {model_name => endpoint_stub}' do
      expect(Endpoint::Stub.stubs).to be_a Hash
    end
  end

  context 'http requests' do
    it 'should fail when nothing is stubbed' do
      expect{Net::HTTP.get "whocares.com", '/'}.to raise_error WebMock::NetConnectNotAllowedError
    end
  end

  describe '.initialize_stub_for' do
    it 'should create a new Endpoint::Stub for the given ActiveResource model' do
      pending
      raise "unimplemented"
    end
  end
end