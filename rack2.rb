require 'eventmachine'
require 'thin'
require 'mongrel'
require 'stringio'

require 'thin_connection'

module Rack2
  class Proxy
    def initialize(request, middleware, env)
      @request    = request
      @request.env.merge(env)
      @middleware = middleware
    end

    def proxy(middleware, env = {})
      Proxy.new(self, middleware, env)
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

    def proxy(middleware, env = {})
      Proxy.new(self, middleware, env)
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
    def self.run(name, app)
      get(name).new(app).run
    end

    def self.get(name)
      all[name.to_s] || raise("Handler for #{name.to_s.inspect} not found")
    end

    def self.register(name)
      Handler.all[name.to_s] = self
    end

    def self.all
      @all ||= {}
    end

    def initialize(app)
      @app = app
    end
    attr_reader :app
  end

  module Handlers
    class Thin < Handler
      register :thin

      def run
        EM.run do
          backend = ::Thin::Backends::TcpServer.new("127.0.0.1", 3000)
          backend.server = self
          backend.start
        end
      end
    end

    class Mongrel < Handler
      register :mongrel

      def run
        options = {}
        server = ::Mongrel::HttpServer.new(
          options[:Host]           || '0.0.0.0',
          options[:Port]           || 8080,
          options[:num_processors] || 950,
          options[:throttle]       || 0,
          options[:timeout]        || 60)
        server.register('/', Endpoint.new(app))
        server.run.join
      end

      class Endpoint < ::Mongrel::HttpHandler
        def initialize(app)
          @app = app
        end

        def process(request, response)
          Connection.new(@app, request, response).process
        end

        class Connection
          def initialize(app, request, response)
            @app      = app
            @request  = request
            @response = response
          end

          def process
            env = {}.replace(@request.params)
            env.delete "HTTP_CONTENT_TYPE"
            env.delete "HTTP_CONTENT_LENGTH"

            env["SCRIPT_NAME"] = ""  if env["SCRIPT_NAME"] == "/"

            rack_input = @request.body || StringIO.new('')
            rack_input.set_encoding(Encoding::BINARY) if rack_input.respond_to?(:set_encoding)

            env.update({"rack.version" => [1,1],
                         "rack.input" => rack_input,
                         "rack.errors" => $stderr,

                         "rack.multithread" => true,
                         "rack.multiprocess" => false, # ???
                         "rack.run_once" => false,

                         "rack.url_scheme" => "http",
                       })
            env["QUERY_STRING"] ||= ""

            rack2_request = Rack2::Request.new(self, env)
            @app.start(rack2_request)
          end

          def send_header(status, headers)
            @response.status = status.to_i
            @response.send_status(nil)

            headers.each { |k, vs|
              vs.split("\n").each { |v|
                @response.header[k] = v
              }
            }
            @response.send_header
          end

          def send_body(part)
            @response.write part
            @response.socket.flush
          end

          def finish
            # NO-OP
          end
        end
      end
    end
  end
end
