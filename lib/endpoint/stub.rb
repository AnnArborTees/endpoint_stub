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
      @defaults = options[:defaults]

      @model = model
      @site = URI "#{model.site}/#{model.name.underscore.pluralize}"

      @current_id = 0
      @responses = []
    end

    def next_id
      id = @current_id
      @current_id += 1
      id
    end

    def mock_response(type, route='', &block)
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

      @responses << Response.new(type, URI.parse(site+'/'+path.join('/')), &block)
      @responses.last.activate!
    end

    class Response
      include WebMock::API

      ParamIndices = Struct.new(:slash, :dot)

      def initialize(type, url, &proc)
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
      end

      def activate!
        stub_request(@type, @url_regex).to_return do |request|
          params = extract_params(request)
          @proc.call(request, params)
        end
      end

      private
      def extract_params(request)
        url = separate request.uri
        params = {}
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