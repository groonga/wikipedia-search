# -*- ruby -*-

source "https://rubygems.org/"

gem "rake"
gem "bundler"
gem "grn2drn"
gem "cool.io"
gem "test-unit", :require => false

base_dir = File.dirname(__FILE__)
local_fluent_plugin_droonga = File.join(base_dir, "..", "fluent-plugin-droonga")
if File.exist?(local_fluent_plugin_droonga)
  gem "fluent-plugin-droonga", :path => local_fluent_plugin_droonga
else
  gem "fluent-plugin-droonga", :github => "droonga/fluent-plugin-droonga"
end

local_droonga_client_ruby = File.join(base_dir, "..", "droonga-client-ruby")
if File.exist?(local_droonga_client_ruby)
  gem "droonga-client", :path => local_droonga_client_ruby
else
  gem "droonga-client", :github => "droonga/droonga-client-ruby"
end
