require 'spec_helper'

class TestModel < ActiveResource::Base
  self.site = "http://www.not-a-site.com/api"
end

module TestModule
  class InnerModel < ActiveResource::Base
    self.site = "http://www.inner-test.com/api"
  end
end

describe Endpoint::Stub, stub_spec: true do
  before(:each) { EndpointStub.refresh! }

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

    it 'should be able to set default attributes' do
      Endpoint::Stub.create_for(TestModel, {defaults: { test_attr: 'hey' }})
      expect(Endpoint::Stub[TestModel].defaults.keys).to include :test_attr
    end

    it 'assigns the url properly for namespaced models' do
      subject = Endpoint::Stub.create_for TestModule::InnerModel
      expect(subject.site.to_s).to_not include "test_module"
      expect(subject.site.to_s).to include "inner_models"
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
    let!(:test_model_stub) { Endpoint::Stub.create_for(TestModel) }
    after(:each) do
      Endpoint::Stub.clear_for TestModel
    end

    describe '.find' do
      it 'retrieves the model' do
        test_model_stub.records << { id: 0, test_attr: 'hey' }
        test_model_stub.records << { id: 1, test_attr: 'nice!' }

        subject = TestModel.find 1
        expect(subject.test_attr).to eq 'nice!'
      end
    end

    describe '.all' do
      it 'retrieves all of the models' do
        test_model_stub.records << { id: 0, test_attr: 'first!' }
        test_model_stub.records << { id: 1, test_attr: 'even better' }

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

    describe 'creating a new record' do
      it 'should work' do
        subject = TestModel.new
        subject.test_attr = "alright...."
        subject.save
        expect(subject.test_attr).to eq 'alright....'
      end

      it 'should work with .create method' do
        subject = TestModel.create(test_attr: 'wow')
        expect(subject.id).to eq '0'
        expect(subject.test_attr).to eq 'wow'
      end
    end

    describe 'destroying a record' do
      it 'should work' do
        test_model_stub.records << { id: 0, test_attr: 'first!' }
        test_model_stub.records << { id: 1, test_attr: 'even better' }

        TestModel.find(0).destroy

        expect{TestModel.find(0)}.to raise_error
      end
    end

    describe 'the mocked responses' do
      it 'should be removable' do
        test_model_stub.records << { id: 0, test_attr: 'hey' }

        expect{TestModel.find(0).test_attr}.to_not raise_error

        expect(
          test_model_stub.unmock_response(:get, '/:id.json')
        ).to be_truthy

        expect{TestModel.find(0).test_attr}.to raise_error
      end
    end

    describe 'custom response' do
      it 'should be addable to existing stubs' do
        test_model_stub.records << { id: 0, test_attr: 'hey' }

        test_model_stub.mock_response(:put, '/:id/change') do |response, params, stub|
          stub.update_record params[:id], test_attr: '*changed*'
          { body: "did it" }
        end
        
        subject = TestModel.find(0)
        expect(subject.test_attr).to_not eq '*changed*'
        expect(subject.put(:change).body).to eq 'did it'
        subject.reload
        expect(subject.test_attr).to eq '*changed*'
      end

      it 'should be removable' do
        test_model_stub.mock_response(:put, '/test') do |r,p,s|
          { body: 'test' }
        end
        expect{TestModel.put(:test)}.to_not raise_error
        test_model_stub.unmock_response(:put, '/test')
        expect{TestModel.put(:test)}.to raise_error
      end
    end
  end
end