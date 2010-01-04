require 'vendor/gems/environment'
require 'rack2'
require 'sinatra/base'

class SyncApp < Sinatra::Base
  get '/' do
    "hello"
  end

  get '/:name' do |name|
    "hello #{name}"
  end
end

Rack2::Handlers::Thin.run(Rack2::Synchronize.new(SyncApp))
