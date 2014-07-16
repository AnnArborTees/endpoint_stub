module Endpoint
  ##
  # Represents a stubbed endpoint that creates, updates, 
  # destroys, and stores data based on http requests.
  class Stub
    @stubs = {}
    class << self
      attr_reader :stubs
      def create_for(model, options={})
        model = assure_model model
        return if stubs.keys.include? model
        stubs[model] = Stub.new(model, options)
      end

      def clear_for(model)
        model = assure_model model
        stubs.delete model
      end

      private
      def assure_model(model)
        if model.ancestors.include? ActiveResource::Base
          model
        else
          Kernel.const_get model
        end
      end
    end

    attr_reader :defaults
    def initialize(model, options)
      puts options[:defaults]
      @defaults = options[:defaults]
    end
  end
end