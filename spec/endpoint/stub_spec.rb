require 'spec_helper'

class TestModel < ActiveResource::Base
  self.site = "http://www.not-a-site.com/api"
end

describe Endpoint::Stub, stub_spec: true do
  before(:each) { EndpointStub.activate! }
  after(:each) { EndpointStub.deactivate! }

  describe '.stubs' do
    it 'should be a global hash of endpoint stubs, {modle => endpoint_stub}' do
      expect(Endpoint::Stub.stubs).to be_a Hash
    end
  end

  context 'http requests' do
    it 'should fail when nothing is stubbed' do
      expect{Net::HTTP.get "whocares.com", '/'}.to raise_error WebMock::NetConnectNotAllowedError
    end
  end

  describe '.create_for' do
    it 'should create a new Endpoint::Stub for the given ActiveResource model' do
      Endpoint::Stub.create_for TestModel
      expect(Endpoint::Stub.stubs.keys).to include TestModel
    end

    it 'should be able to set default attributes', pending: 'literally what the hell' do
      Endpoint::Stub.create_for TestModel, defaults: { test_attr: 'hey' }
      expect(Endpoint::Stub.stubs[TestModel].defaults.keys).to include :test_attr
    end
  end

  describe '.clear_for' do
    it 'should remove the Endpoint::Stub entry for the given ActiveResource model' do
      Endpoint::Stub.create_for TestModel
      Endpoint::Stub.clear_for TestModel
      expect(Endpoint::Stub.stubs.keys).to_not include TestModel
    end
  end


  context 'With a stubbed model' do
    before(:each) do
      stub = Endpoint::Stub.create_for(TestModel)
      stub.mock_response(:get, '/:id.json') do |request, params|
        puts params
        { body: {id: 1, test_attr: 'whoaaaaaaa'}.to_json }
      end
      stub.mock_response(:get, '.json') do |request, params|
        puts params
        r = {
          body: 
          '['+[
            { id: 1, test_attr: 'first!' },
            { id: 2, test_attr: 'even better' }
          ].map(&:to_json).join(', ')+']'
        }
        puts r
        r
      end
    end
    after(:each) do
      Endpoint::Stub.clear_for TestModel
    end

    describe '.find', wip: true do
      it 'retrieves the model' do
        subject = TestModel.find 1
        expect(subject.test_attr).to eq 'whoaaaaaaa'
      end
    end

    describe '.all', wip: true do
      it 'retrieves all of the models' do
        subjects = TestModel.all
        expect(subjects.count).to eq 2
        expect(subjects.first.test_attr).to eq 'first!'
        expect(subjects.last.test_attr).to eq 'even better'
      end
    end

    describe 'setting record attributes' do
      it 'should work' do
        subject = TestModel.new
        subject.test_attr = "heyyyyyyy"
        subject.save
        expect(subject.test_attr).to eq "heyyyyyyy"
      end
    end

    describe 'creating a record' do
      it 'should work?' do
        subject = TestModel.create
        expect(subject.test_attr).to eq "cooool"
      end
    end

    describe '"new" record' do
      it 'should work?????' do
        subject = TestModel.new
        subject.test_attr = "alright...."
        subject.save
        expect(subject.test_attr).to eq 'alright....'
      end
    end
  end
end