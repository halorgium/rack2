Thin::Connection.new(:foo)
Thin.send(:remove_const, :Connection)

require 'socket'

module Thin
  # Connection between the server and client.
  # This class is instanciated by EventMachine on each new connection
  # that is opened.
  class Connection < EventMachine::Connection
    CONTENT_LENGTH    = 'Content-Length'.freeze
    TRANSFER_ENCODING = 'Transfer-Encoding'.freeze
    CHUNKED_REGEXP    = /\bchunked\b/i.freeze

    include Logging
    
    # This is a template async response. N.B. Can't use string for body on 1.9
    AsyncResponse = [-1, {}, []].freeze
    
    # Rack application (adapter) served by this connection.
    attr_accessor :app

    # Backend to the server
    attr_accessor :backend

    # Current request served by the connection
    attr_accessor :request

    # Next response sent through the connection
    attr_accessor :response

    # Calling the application in a threaded allowing
    # concurrent processing of requests.
    attr_writer :threaded

    # Get the connection ready to process a request.
    def post_init
      @request  = Request.new
      @response = Response.new
    end

    # Called when data is received from the client.
    def receive_data(data)
      trace { data }
      process if @request.parse(data)
    rescue InvalidRequest => e
      log "!! Invalid request"
      log_error e
      close_connection
    end

    # Called when all data was received and the request
    # is ready to be processed.
    def process
      # Add client info to the request env
      @request.remote_address = remote_address
      @rack2_request = Rack2::Request.new(self, @request.env)
      @app.start(@rack2_request)
    rescue Exception
      handle_error
      terminate_request
      nil
    end

    def send_header(status, headers)
      @header_sent = true
      @response.status = status
      @response.headers = headers
      send_data @response.head
    end

    def send_body(chunk)
      raise "Header not sent" unless @header_sent
      trace { chunk }
      send_data chunk
    end

    def finish
      terminate_request
    end

    # Logs catched exception and closes the connection.
    def handle_error
      log "!! Unexpected error while processing request: #{$!.message}"
      log "!! #{$!.backtrace.join("\n")}"
      log_error
      close_connection rescue nil
    end

    def close_request_response
      @request.async_close.succeed if @request.async_close
      @request.close  rescue nil
      @response.close rescue nil
    end

    # Does request and response cleanup (closes open IO streams and
    # deletes created temporary files).
    # Re-initializes response and request if client supports persistent
    # connection.
    def terminate_request
      unless persistent?
        close_connection_after_writing rescue nil
        close_request_response
      else
        close_request_response
        # Prepare the connection for another request if the client
        # supports HTTP pipelining (persistent connection).
        post_init
      end
    end

    # Called when the connection is unbinded from the socket
    # and can no longer be used to process requests.
    def unbind
      @request.async_close.succeed if @request.async_close
      @response.body.fail if @response.body.respond_to?(:fail)
      @backend.connection_finished(self)
    end

    # Allows this connection to be persistent.
    def can_persist!
      @can_persist = true
    end

    # Return +true+ if this connection is allowed to stay open and be persistent.
    def can_persist?
      @can_persist
    end

    # Return +true+ if the connection must be left open
    # and ready to be reused for another request.
    def persistent?
      @can_persist && @response.persistent?
    end

    # +true+ if <tt>app.call</tt> will be called inside a thread.
    # You can set all requests as threaded setting <tt>Connection#threaded=true</tt>
    # or on a per-request case returning +true+ in <tt>app.deferred?</tt>.
    def threaded?
      @threaded || (@app.respond_to?(:deferred?) && @app.deferred?(@request.env))
    end

    # IP Address of the remote client.
    def remote_address
      socket_address
    rescue Exception
      log_error
      nil
    end

    protected

      # Returns IP address of peer as a string.
      def socket_address
        Socket.unpack_sockaddr_in(get_peername)[1]
      end

    private
      def need_content_length?(result)
        status, headers, body = result
        return false if status == -1
        return false if headers.has_key?(CONTENT_LENGTH)
        return false if (100..199).include?(status) || status == 204 || status == 304
        return false if headers.has_key?(TRANSFER_ENCODING) && headers[TRANSFER_ENCODING] =~ CHUNKED_REGEXP
        return false unless body.kind_of?(String) || body.kind_of?(Array)
        true
      end

      def set_content_length(result)
        headers, body = result[1..2]
        case body
        when String
          # See http://redmine.ruby-lang.org/issues/show/203
          headers[CONTENT_LENGTH] = (body.respond_to?(:bytesize) ? body.bytesize : body.size).to_s
        when Array
           bytes = 0
           body.each do |p|
             bytes += p.respond_to?(:bytesize) ? p.bytesize : p.size
           end
           headers[CONTENT_LENGTH] = bytes.to_s
        end
      end
  end
end
