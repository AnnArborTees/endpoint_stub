require 'endpoint/response'
require 'endpoint_stub'
require 'webmock'

module Endpoint
  ##
  # Represents a stubbed endpoint that creates, updates,
  # destroys, and stores data based on http requests.
  class Stub
    @stubs = {}
    class << self
      attr_reader :stubs
      ##
      # Creates a fake endpoint for the given ActiveResource model.
      #
      # The options hash currently only accepts :defaults, which allows
      # you to define default attribute values for the endpoint to
      # consider on record creation.
      #
      # If a block is supplied, it will be executed in the context
      # of the new Endpoint::Stub, allowing you to elegantly mock
      # custom responses if needed.
      def create_for(model, options={}, &block)
        model = assure_model model
        return if stubs.keys.map(&:name).include? model.name
        new_stub = Stub.new(model, options)

        EndpointStub::Config.default_responses.each do |response|
          new_stub.mock_response(*response)
        end

        @stubs[model] = new_stub

        new_stub.instance_eval(&block) if block_given?
        new_stub
      end

      ##
      # Removes fake endpoint for the given model, meaning any
      # ActiveResource activity on the model will raise errors
      # once again.
      def clear_for(model)
        stubs.delete assure_model model
      end

      def get_for(model)
        @stubs[assure_model(model)]
      end

      def fuzzy_get_for(model_name)
        @stubs.each do |type, stub|
          if type.name.include?(model_name)
            return stub
          end
        end
        nil
      end

      def clear_all_records!
        @stubs.values.each(&:clear_records!)
      end

      ##
      # Clears all endpoint stubs.
      def clear!
        @stubs = {}
      end

      ##
      # Gets or creates a stub for the given model.
      # i.e. Endpoint::Stub[Post]
      def [](model)
        create_for model or get_for model
      end

      def each(&block)
        @stubs.each(&block)
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
    attr_reader :model
    attr_reader :site
    attr_accessor :records
    def initialize(model, options)
      @defaults = options[:defaults] || {}

      @model = model
      @site = URI "#{model.site}/#{model.name.split('::').last.underscore.pluralize}"

      @responses = {}

      @records = []
    end

    ##
    # Adds a record to the stub, automatically assigning an id as though
    # it were in a database.
    def add_record(attrs)
      unless attrs.is_a? Hash
        raise "Endpoint::Stub#add_record expects a Hash. Got #{attrs.class.name}."
      end
      attrs.merge!(@defaults) { |k,a,b| a }
      attrs['id'] = current_id

      new_attrs = {}

      attrs.each do |key, val|
        next unless /^(?<field>\w+)_attributes$/ =~ key.to_s

        attrs.delete(key)
        field_type = field.singularize.camelize

        begin
          stub = Endpoint::Stub.fuzzy_get_for(field_type)

          if val.is_a?(Array)
            new_attrs[field] = val.map do |field_attrs|
              stub.add_record(field_attrs)
            end
          else
            multiple = true

            val.each do |index, child_attrs|
              break (multiple = false) unless child_attrs.is_a?(Hash)

              new_attrs[field] ||= []
              new_attrs[field] << child_attrs

              # TODO use index to update existing records... if you need to test that.
            end

            new_attrs[field] = stub.add_record(val) unless multiple
          end
        rescue NameError
          new_attrs[field] = val
        end
      end

      attrs.merge!(new_attrs)
      @records << attrs
      attrs
    end

    ##
    # Updates the record with the given id with the given attributes.
    def update_record(id, attrs)
      unless attrs.is_a? Hash
        raise "Endpoint::Stub#update_record expects a Hash. Got #{attrs.class.name}."
      end
      id = id.to_i
      if @records[id]
        @records[id].merge! attrs
      end
    end

    ##
    # Removes the record with the given id from the fake database.
    def remove_record(id)
      id = id.to_i
      if @records[id]
        @records[id] = nil
        true
      end
    end

    ##
    # Clear all records in this stub.
    def clear_records!
      @records = []
    end

    ##
    # Get the record at the given id. Accepts strings as well as ints.
    def record(id)
      @records[id.to_i]
    end

    ##
    # The last assigned id.
    def last_id
      @records.count-1
    end

    ##
    # The next id for a record to be assigned to.
    def current_id
      @records.count
    end

    ##
    # The name of the represented model in underscore notation.
    def model_name
      @model.name.underscore
    end

    ##
    # Gets the url location for the given id, as used by RESTful
    # record creation.
    def location(id)
      site = @site.to_s[-1] == '/' ? @site.to_s[0...-1] : @site
      "#{site}/#{id}"
    end

    ##
    # Adds default attributes for record creation.
    def add_default(attrs)
      @defaults.merge!(attrs)
    end
    alias_method :add_defaults, :add_default

    ##
    # Mock a custom response. Requires a type (http mthod), and route.
    # This method will override any previous responses assigned to the
    # given type and route.
    #
    # The route is the uri relative to the record's assigned site and
    # can be formatted similarly to rails routes. Such as:
    # '/test/:some_param.json'
    # or
    # '.xml' to simply imply the model's site with '.xml' appended.
    #
    # Lastly, a proc or block is needed to actually handle requests.
    # The proc will be called with the request object, the extracted
    # parameters from the uri, and the stub object so that you can
    # interact with the stubbed records.
    def mock_response(type, route='', proc=nil, &block)
      proc = block if block_given?
      route = clean_route route

      @responses[type] ||= {}
      @responses[type][route].deactivate! if @responses[type][route]
      @responses[type][route] = Response.new(type, prepare_uri(type, route), self, &proc)
      @responses[type][route].activate!
    end

    ##
    # Same thing as mock_response, except it will not overWRITE existing
    # mocks. Instead, it allows you to call a block inside of your response
    # which will act as a 'super' call, invoking previously defined
    # responses. Yielding inside a top-level response will give you
    # an empty hash, so no nil related issues should arrise (unless of
    # course the super-response returns nil, which it shouldn't).
    #
    # Also note that this does not re-activate a deactivated response.
    def override_response(type, route, proc=nil, &block)
      proc = block if block_given?
      route = clean_route route

      if @responses[type] and @responses[type][route]
        @responses[type][route].add_to_stack(&proc)
      else
        mock_response(type, route, proc)
      end
    end

    ##
    # Overrides all currently assigned responses. Will not have any effect
    # on responses mocked after this method is called.
    def override_all(&block)
      @responses.each do |type, responses|
        responses.each do |route, response|
          response.add_to_stack(&block)
        end
      end
    end

    ##
    # Removes all overrides, reducing each response to their originals.
    def drop_overrides!
      @responses.each do |type, responses|
        responses.each do |route, response|
          response.drop_overrides!
        end
      end
    end

    ##
    # Remove a mocked response with the given type and route.
    def unmock_response(type, route)
      route = clean_route route
      if @responses[type] && @responses[type][route]
        @responses[type][route].deactivate!
        @responses[type][route] = nil
        true
      end
    end

    private
    def prepare_uri(type, route)
      site = "#{@site.scheme}://#{@site.host}:#{@site.port}"
      path = @site.path.split(/\/+/).reject(&:empty?)

      if route[0] == '.' && !route.include?('/')
        # This allows passing '.json', etc as the route
        if path.last
          path = path[0...-1] + [path.last+route]
        else
          site += route
        end
      else
        path += route.split('/')
      end

      URI.parse site+'/'+path.join('/')
    end

    def clean_route(route)
      route = route[1..-1] if route[0] == '/'
      route = route[0...-1] if route[-1] == '/'
      route
    end
  end
end
