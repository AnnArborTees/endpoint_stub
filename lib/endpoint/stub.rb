module Endpoint
  ##
  # Represents a stubbed endpoint that creates, updates, 
  # destroys, and stores data based on http requests.
  class Stub
    @stubs = {}
    
    class << self
      attr_accessor :stubs
    end
  end
end