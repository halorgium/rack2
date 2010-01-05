require 'vendor/gems/environment'
require 'rack2'
require 'examples'

class NormalApp
  def start(request)
    sleep 1
    request.send_header(200, {"Content-Type" => "text/html"})
    sleep 1
    request.send_body("testing\n")
    sleep 1
    request.finish
  end
end

Rack2::Handler.run(:mongrel, Gzipper.new(Middleware2.new(Middleware.new(NormalApp.new))))
