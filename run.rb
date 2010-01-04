require 'vendor/gems/environment'
require 'rack2'
require 'pp'
require 'zlib'

class App
  def start(request)
    request.send_header(200, {"Content-Type" => "text/html"})

    request.send_body("fail\n")
    request.send_body("hello\n")
    EM.add_timer(1) do
      request.send_body("there\n")
      EM.add_timer(1) do
        request.finish
      end
    end
  end
end

class Middleware
  def initialize(app)
    @app = app
  end

  def start(request)
    @app.start(request.proxy(self))
  end

  def send_header(request, status, headers)
    request.send_header(status, headers)
  end

  def send_body(request, chunk)
    return if chunk =~ /fail/
    request.send_body(chunk + "foo\n")
  end

  def finish(request)
    request.finish
  end
end

class Middleware2
  def initialize(app)
    @app = app
  end

  def start(request)
    @app.start(request.proxy(self))
  end

  def send_header(request, status, headers)
    request.send_header(301, headers)
  end

  def send_body(request, chunk)
    request.send_body(chunk)
  end

  def finish(request)
    request.finish
  end
end

class Gzipper
  def initialize(app)
    @app = app
  end

  def start(request)
    request.env["gzip.stream"] = ::Zlib::GzipWriter.new(GzipStream.new(request))
    @app.start(request.proxy(self))
  end

  def send_header(request, status, headers)
    request.send_header(status, headers)
  end

  def send_body(request, chunk)
    request.env["gzip.stream"].write(chunk)
  end

  def finish(request)
    request.env["gzip.stream"].close
    request.finish
  end

  class GzipStream
    def initialize(request)
      @request = request
    end

    def write(data)
      @request.send_body(data)
    end
  end
end

Rack2::Handlers::Thin.run(Gzipper.new(Middleware2.new(Middleware.new(App.new))))
