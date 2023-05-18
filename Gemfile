# -*- ruby -*-

source "https://rubygems.org/"

gem "berkshelf"
gem "bundler"
gem "chef"
gem "cool.io"
gem "grn2drn"
gem "rake"
gem "red-datasets"
gem "test-unit", :require => false

base_dir = File.dirname(__FILE__)
local_droonga_engine = File.join(base_dir, "..", "droonga-engine")
if File.exist?(local_droonga_engine)
  gem "droonga-engine", :path => local_droonga_engine
else
  gem "droonga-engine", :github => "droonga/droonga-engine"
end

local_droonga_client_ruby = File.join(base_dir, "..", "droonga-client-ruby")
if File.exist?(local_droonga_client_ruby)
  gem "droonga-client", :path => local_droonga_client_ruby
else
  gem "droonga-client", :github => "droonga/droonga-client-ruby"
end
