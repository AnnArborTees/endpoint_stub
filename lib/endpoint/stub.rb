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
        return if stubs.keys.include? model
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
    attr_accessor :records
    def initialize(model, options)
      @defaults = options[:defaults] || {}

      @model = model
      @site = URI "#{model.site}/#{model.name.underscore.pluralize}"

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
      attrs[:id] = current_id
      attrs.merge!(@defaults) { |k,a,b| a }

      new_attrs = {}

      attrs.each do |key, val|
        next unless /^(?<field>\w+)_attributes$/ =~ key.to_s

        attrs.delete(key)
        field_type = field.singularize.camelize

        begin
          stub = Endpoint::Stub.get_for(field_type)

          if val.is_a?(Array)
            new_attrs[field] = val.map do |field_attrs|
              stub.add_record(field_attrs)
            end
          else
            new_attrs[field] = stub.add_record(val)
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

      site = "#{@site.scheme}://#{@site.host}"
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

      @responses[type] ||= {}
      @responses[type][route] = Response.new(type, URI.parse(site+'/'+path.join('/')), self, &proc)
      @responses[type][route].activate!
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
    def clean_route(route)
      route = route[1..-1] if route[0] == '/'
      route = route[0...-1] if route[-1] == '/'
      route
    end

    class Response
      include WebMock::API

      # For remembering where a uri-based parameter is located.
      ParamIndices = Struct.new(:slash, :dot)
      # Allows more comfortable use of Symbol keys when accessing
      # params (which are string keys).
      class Params < Hash
        def [](key)
          super(key.to_s)
        end
        def []=(key, value)
          super(key.to_s, value)
        end
      end

      def initialize(type, url, stub, &proc)
        @param_indices = {}

        @url_regex = build_url_regex!(url)

        @type = type
        @proc = proc
        @stub = stub
      end

      # Should be called only once, internally to perform the actual WebMock stubbing.
      def activate!
        @stubbed_request = stub_request(@type, @url_regex).to_return do |request|
          params = extract_params(request)

          results = @proc.call(request, params, @stub)
          results[:body] = results[:body].to_json unless results[:body].is_a? String
          results
        end
      end

      # This should remove the request stubbed by #activate!
      def deactivate!
        remove_request_stub @stubbed_request
      end

      private
      # Bang is there because this method populates @param_indices.
      def build_url_regex!(url)
        regex = ""
        separate(url).each_with_index do |x, slash_index|
          regex += '/' unless slash_index == 0
          # If there is a colon, it's a parameter. i.e. /resource/:id.json
          if x.include? ':' and !(x[1..-1] =~ /^\d$/) # If it's just numbers, it's probably a port number
            # We split by dot at this point to separate the parameter from any
            # format/domain related suffix.
            dot_split = x.split('.')
            inner_regex = []

            dot_split.each_with_index do |name, dot_index|
              # A parameter can show up after a dot as well. i.e. /resource/:id.:format
              inner_regex << if name.include? ':'
                param_name = name[1..-1]
                @param_indices[param_name] = ParamIndices.new(slash_index, dot_index)
                # Add .+ regex to capture any data at this point in the url.
                ".+"
              else
                # If there's no colon, it's a static part of the target url.
                Regexp.escape(name)
              end
            end

            # "inner_regex" was built by splitting on dots, so we put the dots back.
            regex += inner_regex.join('\.')
          else
            # No colon, so this segment is static.
            regex += Regexp.escape(x)
          end
        end
        Regexp.new regex
      end

      def extract_params(request)
        url = separate request.uri
        params = Params.new
        @param_indices.each do |param_name, index|
          value = url[index.slash].split('.')[index.dot]

          params[param_name] = value
        end
        params
      end

      def separate(url)
        url.to_s[url.to_s.index('://')+3..-1].split '/'
      end
    end
  end
end
