require "endpoint_stub/version"
require 'endpoint/stub'
require 'webmock'

module EndpointStub
  class Config
    class << self
      attr_accessor :activated
      attr_accessor :default_responses
    end
  end

  # TODO make clearing stubs possible

  # Enable endpoint stubbing.
  # This will cause all HTTP requests to raise an error,
  # unless relating to an ActiveResource model.
  def self.activate!
    return if Config.activated
    WebMock.enable!
    Config.activated = true
  end
  # Disable endpoint stubbing.
  # This allows HTTP requests again.
  def self.deactivate!
    return unless Config.activated
    WebMock.disable!
    Config.activated = false
  end

  def self.refresh!
    deactivate!
    activate!
  end

  Config.default_responses = [
    ### Index ###
    [:get, '.json', ->(request, params, stub) {
      { body: stub.records }
    }],

    ### Show ###
    [:get, '/:id.json', ->(request, params, stub) {
      { body: stub.records[params[:id].to_i] }
    }],

    ### Create ###
    [:post, '.json', ->(request, params, stub) {
      stub.records << JSON.parse(request.body).merge(id: stub.current_id)
      { body: '', 
        status: 201,
        headers: { 'Location' => stub.location(stub.last_id) }
      }
    }],

    ### Update ###
    [:put, '/:id.json', ->(request, params, stub) {
      record = stub.records[params[:id].to_i]
      if record
        record.merge! JSON.parse(request.body)
        { body: '', status: 204}
      else
        { body: "Failed to find #{stub.model_name} with id #{params[:id]}", 
          status: 404 }
      end
    }],

    ### Destroy ###
    [:delete, '/:id.json', ->(request, params, stub) {
      record = stub.records[params[:id].to_i]
      if record
        record.merge! JSON.parse(request.body)
        { body: '', status: 200}
      else
        { body: "Failed to find #{stub.model_name} with id #{params[:id]}", 
          status: 404 }
      end
    }]
  ]
end

class Array
  def to_json
    '['+map do |e| 
      e.respond_to?(:to_json) ? e.to_json : e.to_s 
    end.join(', ')+']'
  end
end
