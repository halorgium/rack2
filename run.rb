require 'vendor/gems/environment'
require 'rack2'
require 'examples'

Rack2::Handler.run(:thin, Gzipper.new(Middleware2.new(Middleware.new(App.new))))
