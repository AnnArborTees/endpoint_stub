# EndpointStub

I found that testing solutions for ActiveResource were either sub-optimal or
outdated, so I decided to make my own using WebMock.

EndpointStub is kind of like the built in ActiveResource HTTPMock, except
you can bind logic and dynamic routes to it, so it's like a mini controller
almost. EndpointStub comes with the default RESTful CRUD actions supported
by ActiveResource built in (currently JSON format only). It also comes with
an interface for defining your own routes and logic.

Nested resources are currently pending, but definitely implementable via custom
response mocking.

## Installation

Add this line to your application's Gemfile:

    gem 'webmock'
    gem 'endpoint_stub'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install endpoint_stub

## Usage

Add

    require 'endpoint_stub'

to your spec_helper / test_helper.
Then, in your tests, you can call

    Endpoint::Stub.create_for(MyActiveResourceModel)

which will bring MyActiveResourceModel to life!
Here is a more in-depth example.

    class Greeter < ActiveResource::Base
        def say_hi_to(someone)
            "#{self.greeting}, someone"
        end

        self.site = "http://example.com/api/greeter"
    end

    Endpoint::Stub.create_for(Greeter)
    record = Greeter.create(greeting: 'hello')
    record.say_hi_to('sir') # ===> "hello, sir"

    record.greeting = 'hey...'
    record.save     # ===> true
    record.greeting     # ===> 'hey...'

    record.destroy
    record.destroyed?   # ===> true

    Greeter.create(greeting: 'hi')
    Greeter.create(greeting: 'ahoy')

    Greeter.all # ===> [{id: 1, greeting: 'hi'}, {id: 2, greeting: 'ahoy'}]

Also, custom responses and default attributes:

    class Test < ActiveResource::Base
        self.site = "http://example.com/api/whatever"
    end

    Endpoint::Stub.create_for(Test) do
        add_default test_attr: 'nice'

        mock_response(:put, '/:id/change') do |response, params, stub|
          stub.update_record params[:id], test_attr: '*changed*'
          { body: "did it" }
        end
    end

    record = Test.create
    record.test_attr     # ===> 'nice'
    record.put(:change).body     # ===> 'did it'
    record.reload
    record.test_attr     # ===> '*changed*'

Afterwards, custom responses can be un-mocked:

    Endpoint::Stub[Test].unmock_response(:put, '/:id/change')    # ===> true

## Contributing

1. Fork it ( http://github.com/<my-github-username>/endpoint_stub/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
