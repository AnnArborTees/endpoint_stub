require 'webmock'

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
    @stub = stub

    @response_stack = [proc]
  end

  def activated?
    !@stubbed_request.nil?
  end

  # This should add the stubbed request to WebMock.
  def activate!
    @stubbed_request = stub_request(@type, @url_regex).
      to_return(&create_response_proc(@response_stack))
  end

  # This should remove the request stubbed by #activate!
  # Passing a block will reactivate when done with block logic
  # if previously activated.
  def deactivate!
    remove_request_stub @stubbed_request
    if block_given?
      yield
      activate! if @stubbed_request
    else
      @stubbed_request = nil
    end
  end

  def reset!
    deactivate!
    activate!
  end

  def add_to_stack(&proc)
    deactivate! do
      @response_stack << proc
    end
  end

  # Return to the first stubbed response.
  def drop_overrides!
    deactivate! do
      remove_request_stub @stubbed_request
      @response_stack = @response_stack[0..1]
    end
  end

  private

  # Creates a proc that can be passed as a block to WebMock's stub_request method.
  def create_response_proc(callback_stack)
    execute_callback_with_super = ->(stack, request, params, stub) {
      stack.last.call(request, params, stub) do
        if stack.count == 1
          {}
        else
          execute_callback_with_super.call(stack[0...-1], request, params, stub)
        end
      end
    }

    Proc.new do |request|
      params = extract_params(request)

      results = execute_callback_with_super.call(
        callback_stack, request, params, @stub)

      results[:body] = results[:body].to_json unless results[:body].is_a? String
      results
    end
  end

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
        # However, we occasionally get uris like "http://site.com/api/.json",
        # so we account for that with an optional slash.
        if x.include? '.'
          dot_split = x.split('.')
          dot_split.each_with_index do |part, i|
            regex += '\/?\.' unless i == 0
            regex += Regexp.escape(part)
          end
        else
          regex += Regexp.escape(x)
        end
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