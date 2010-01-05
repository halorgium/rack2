require 'vendor/gems/environment'
require 'rack2'
require 'sync_app'

Rack2::Handler.run(:thin, Rack2::Synchronize.new(SyncApp))
