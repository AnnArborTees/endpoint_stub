require 'spec_helper'

class TestModel < ActiveResource::Base
  self.site = "http://www.not-a-site.com/api"
  alias_method :to_param, :id
end

module TestModule
  class InnerModel < ActiveResource::Base
    self.site = "http://www.inner-test.com/api"
  end
end

class TestModelWithPort < ActiveResource::Base
  self.site = "http://not-a-site.com:777/api"
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

    it 'should work with a port number other than 80' do
      Endpoint::Stub.create_for TestModelWithPort
      expect{TestModelWithPort.create(test_attr: '...')}.to_not raise_error
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

      it 'numbers should be converted to numbers' do
        subject = TestModel.new
        subject.test_attr = 'hello'
        subject.test_num = 2.2
        subject.save
        subject = TestModel.find(subject.id)
        expect(subject.test_num).to_not be_a String
        expect(subject.test_num).to eq 2.2
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
        expect(subject.id).to eq 0
        expect(subject.test_attr).to eq 'wow'
      end

      it 'ids should be properly converted to numbers' do
        TestModel.create(test_attr: 'nice')
        expect(TestModel.find(0).id).to_not be_a String
        expect(TestModel.find(0).id).to eq 0
      end

      it 'should allow the record to be saved afterwards' do
        subject = TestModel.create(test_attr: 'nice')
        expect(test_model_stub.records.count).to eq 1
        subject.test_attr = 'nice'
        subject.save
        subject.reload
        expect(subject.test_attr).to eq 'nice'
        expect(test_model_stub.records.count).to eq 1
      end

      it 'should allow comprehensive editing' do
        2.times { |n| TestModel.create(test_attr: "cool#{n}") }
        expect(test_model_stub.records.count).to eq 2

        first = TestModel.first
        expect(first.test_attr).to eq 'cool0'

        first.test_attr = 'now this'
        expect(first.save).to be_truthy
        expect{first.reload}.to_not raise_error
        expect(first.test_attr).to eq 'now this'

        expect(TestModel.all.count).to eq 2

        TestModel.all.map(&:test_attr).tap do |it|
          expect(it).to include 'now this'
          expect(it).to_not include 'cool0'
        end

        expect(TestModel.all.map(&:id).uniq).to eq TestModel.all.map(&:id)
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

    describe 'custom responses' do
      it 'should be addable to existing mocks' do
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

      it 'should be able to overwrite existing mocks with no path' do
        test_model_stub.records << { id: 0, test_attr: 'hey' }

        test_model_stub.mock_response :get, '.json' do |response, params, stub|
          { body: [{ id: 0, test_attr: 'overridden!' }] }
        end

        expect(TestModel.all.first.test_attr).to eq 'overridden!'
      end

      it 'should be able to override existing mocks and access the previous implementation' do
        test_model_stub.records << { id: 0, test_attr: 'hey' }

        test_model_stub.override_response :get, '.json' do |response, params, stub, &sup|
          body = sup.call[:body]
          body << { id: 1, test_attr: 'injected!' }
          { body: body }
        end

        expect(TestModel.all.first.test_attr).to eq 'hey'
        expect(TestModel.all.last.test_attr).to eq 'injected!'
      end

      it 'should be able to change the parameters for the previous implementation when overriding' do
        test_model_stub.records += [{ id: 0, test_attr: 'hey'}, {id: 1, test_attr: 'second' }]

        test_model_stub.override_response :get, '/:id.json' do |response, params, stub, &supre|
          params[:id] = params[:id].to_i + 1
          supre.call response, params
        end

        expect(TestModel.find(0).test_attr).to eq 'second'
      end

      it 'should be able to override all existing mocks' do
        test_model_stub.records << { id: 0, test_attr: 'hey' }
        dummy = Class.new do
          def test; 'here we go'; end
        end.new
        expect(dummy).to receive(:test).twice

        test_model_stub.override_all do |response, params, stub, &supre|
          { body: dummy.test }
        end

        TestModel.all
        TestModel.find(0) rescue ArgumentError
      end
    end
  end
end