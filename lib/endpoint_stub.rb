require "endpoint_stub/version"
require 'endpoint/stub'
require 'webmock'

module EndpointStub
  class Config
    class << self
      attr_accessor :activated
    end
  end

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
end

class Array
  def to_json
    '['+map do |e| 
      e.respond_to?(:to_json) ? e.to_json : e.to_s 
    end.join(', ')+']'
  end
end
