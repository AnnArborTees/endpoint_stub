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

  # Enable endpoint stubbing.
  # This will cause all HTTP requests to raise an error,
  # as per WebMock, unless relating to an ActiveResource 
  # model.
  def self.activate!
    WebMock.enable!
    Config.activated = true
  end
  # Disable endpoint stubbing.
  # This allows real HTTP requests again.
  def self.deactivate!
    WebMock.disable!
    Config.activated = false
  end

  # Calls deactivate, clears all stubs, then re-activates.
  def self.refresh!
    deactivate!
    Endpoint::Stub.clear!
    activate!
  end

  # Default to being deactivated.
  deactivate!

  # Feel free to add to these, and they will be applied to every 
  # stubbed endpoint thereafter.
  Config.default_responses = [
    ### Index ###
    [:get, '.json', ->(request, params, stub) {
      query = request.uri.query_values
      
      if !query || query.empty?
        { body: stub.records }
      else
        {
          body: stub.records.select do |record|
              query.all? { |field, value| record[field] == value }
            end
        }
      end
    }],

    ### Show ###
    [:get, '/:id.json', ->(request, params, stub) {
      { body: stub.records[params[:id].to_i] }
    }],

    ### Create ###
    [:post, '.json', ->(request, params, stub) {
      record = stub.add_record(JSON.parse(request.body))
      { body: record, 
        status: 201,
        headers: { 'Location' => stub.location(stub.last_id) }
      }
    }],

    ### Update ###
    [:put, '/:id.json', ->(request, params, stub) {
      if stub.update_record(params[:id], JSON.parse(request.body))
        { body: stub.records[params[:id].to_i], status: 204}
      else
        { body: "Failed to find #{stub.model_name} with id #{params[:id]}", 
          status: 404 }
      end
    }],

    ### Destroy ###
    [:delete, '/:id.json', ->(request, params, stub) {
      if stub.remove_record(params[:id])
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
