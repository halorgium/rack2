require 'sinatra/base'

class SyncApp < Sinatra::Base
  get '/' do
    "hello"
  end

  get '/:name' do |name|
    "hello #{name}"
  end
end
