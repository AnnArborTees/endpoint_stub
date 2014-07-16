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
      def create_for(model, options={})
        model = assure_model model
        return if stubs.keys.include? model
        new_stub = Stub.new(model, options)

        EndpointStub::Config.default_responses.each do |response|
          new_stub.mock_response(*response)
        end

        stubs[model] = new_stub
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
    attr_reader :model
    attr_accessor :records
    def initialize(model, options)
      @defaults = options[:defaults]

      @model = model
      @site = URI "#{model.site}/#{model.name.underscore.pluralize}"

      @responses = []

      @records = []
    end

    def last_id
      @records.count-1
    end

    def current_id
      @records.count
    end

    def model_name
      @model.name.underscore
    end

    def location(id)
      "#{@site}/#{id}"
    end

    def mock_response(type, route='', proc=nil, &block)
      proc = block if block_given?

      route = route[1..-1] if route[0] == '/'
      route = route[0...-1] if route[-1] == '/'

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

      @responses << Response.new(type, URI.parse(site+'/'+path.join('/')), self, &proc)
      @responses.last.activate!
    end

    class Response
      include WebMock::API

      ParamIndices = Struct.new(:slash, :dot)
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
        regex = ""
        separate(url).each_with_index do |x, slash_index|
          regex += '/' unless slash_index == 0
          if x.include? ':' and !(x[1..-1] =~ /^\d$/) # If it's just numbers, it's probably a port number
            dot_split = x.split('.')
            inner_regex = []

            dot_split.each_with_index do |name, dot_index|
              inner_regex << if name.include? ':'
                param_name = name[1..-1]
                @param_indices[param_name] = ParamIndices.new(slash_index, dot_index)
                ".+"
              else
                Regexp.escape(name)
              end
            end

            regex += inner_regex.join('\.')
          else
            regex += Regexp.escape(x)
          end
        end
        @url_regex = Regexp.new(regex)

        @type = type
        @proc = proc
        @stub = stub
      end

      def activate!
        stub_request(@type, @url_regex).to_return do |request|
          params = extract_params(request)

          results = @proc.call(request, params, @stub)
          results[:body] = results[:body].to_json unless results[:body].is_a? String
          results
        end
      end

      private
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