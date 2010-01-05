require 'vendor/gems/environment'
require 'rack2'

class URLMap
  def initialize(mappings)
    @mappings = normalize(mappings)
  end

  def normalize(mappings)
    mappings.map { |location, app|
      if location =~ %r{\Ahttps?://(.*?)(/.*)}
        host, location = $1, $2
      else
        host = nil
      end

      unless location[0] == ?/
        raise ArgumentError, "paths need to start with /"
      end
      location = location.chomp('/')
      match = Regexp.new("^#{Regexp.quote(location).gsub('/', '/+')}(.*)", nil, 'n')

      [host, location, match, app]
    }.sort_by { |(h, l, m, a)| [h ? -h.size : (-1.0 / 0.0), -l.size] }  # Longest path first
  end

  def start(request)
    path = request.env["PATH_INFO"].to_s
    script_name = request.env['SCRIPT_NAME']
    hHost, sName, sPort = request.env.values_at('HTTP_HOST','SERVER_NAME','SERVER_PORT')
    @mappings.each do |host, location, match, app|
      next unless (hHost == host || sName == host \
        || (host.nil? && (hHost == sName || hHost == sName+':'+sPort)))
      next unless path =~ match && rest = $1
      next unless rest.empty? || rest[0] == ?/

      app.start(
        request.proxy(
          self,
          'SCRIPT_NAME' => (script_name + location),
          'PATH_INFO'   => rest
        )
      )
    end

    request.send_header(404, {"Content-Type" => "text/plain", "X-Cascade" => "pass"})
    request.send_body("Not Found: #{path}")
    request.finish
  end

  def send_header(request, *args)
    request.send_header(*args)
  end

  def send_body(request, chunk)
    request.send_body(chunk)
  end

  def finish(request)
    request.finish
  end
end

class SpecialApp
  def initialize(name)
    @name = name
  end

  def start(request)
    request.send_header(200, {"Content-Type" => "text/html"})
    request.send_body("hello from #{@name}\n")
    request.finish
  end
end

Rack2::Handler.run(:thin, URLMap.new("/foo/" => SpecialApp.new("foo"), "/bar/" => SpecialApp.new("bar")))
