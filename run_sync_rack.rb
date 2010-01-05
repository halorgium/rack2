require 'vendor/gems/environment'
require 'sync_app'

Rack::Handler.get(:thin).run(SyncApp)
