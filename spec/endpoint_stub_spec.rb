require 'spec_helper'

describe EndpointStub, endpoint_stub_spec: true do
  describe '.activate!' do
    it 'should make http requests raise WebMock::NetConnectNotAllowedError' do
      EndpointStub.activate!
      expect{Net::HTTP.get "test.com", "/nothing"}.to raise_error WebMock::NetConnectNotAllowedError
    end
  end

  describe '.deactivate!' do
    it 'should allow http requests once again' do
      # TODO make this account for not being connected to the internet.
      EndpointStub.activate!
      EndpointStub.deactivate!
      expect{Net::HTTP.get "example.com", "/foo"}.to_not raise_error
    end
  end
end