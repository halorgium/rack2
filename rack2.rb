require 'eventmachine'
require 'thin'

Thin::Connection.new(:foo)
Thin.send(:remove_const, :Connection)

require 'thin_connection'

module Rack2
  class Proxy
    def initialize(request, middleware)
      @request    = request
      @middleware = middleware
    end

    def proxy(middleware)
      Proxy.new(self, middleware)
    end

    def env
      @request.env
    end

    def send_header(status, headers)
      @middleware.send_header(@request, status, headers)
    end

    def send_body(chunk)
      @middleware.send_body(@request, chunk)
    end

    def finish
      @middleware.finish(@request)
    end
  end

  class Request
    def initialize(connection, env)
      @connection = connection
      @env        = env
    end
    attr_reader :env

    def proxy(middleware)
      Proxy.new(self, middleware)
    end

    def send_header(status, headers)
      @connection.send_header(status, headers)
    end

    def send_body(chunk)
      @connection.send_body(chunk)
    end

    def finish
      @connection.finish
    end
  end

  class Synchronize
    def initialize(app)
      @app = app
    end

    def start(request)
      status, headers, body = @app.call(request.env)
      request.send_header(status, headers)
      body.each do |chunk|
        request.send_body(chunk)
      end
      request.finish
    end
  end

  class Handler
    def self.run(app)
      new(app).run
    end

    def initialize(app)
      @app = app
    end
    attr_reader :app
  end

  module Handlers
    class Thin < Handler
      def run
        EM.run do
          backend = ::Thin::Backends::TcpServer.new("127.0.0.1", 3000)
          backend.server = self
          backend.start
        end
      end
    end
  end
end
