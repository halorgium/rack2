require 'vendor/gems/environment'
require 'rack2'

class Middleware
  def initialize(app)
    @app = app
  end

  def call(env)
    rack_header = env["rack.header"]
    env["rack.header"] = lambda {|status, headers|
      rack_header.call(status, headers.merge("X-Hax" => "awesome"))
    }
    @app.call(env)
  end
end

class App
  def call(env)
    env["rack.header"].call(200, "Content-Type" => "text/html")
    env["rack.body"].call("hax\n")
    env["rack.finish"].call
  end
end

require 'thin_connection2'
Rack2::Handler.run(:thin, Middleware.new(App.new))
