# -*- ruby -*-

source "https://rubygems.org/"

gem "rake"
gem "bundler"
gem "grn2drn"
gem "droonga-client"
gem "test-unit", :require => false

base_dir = File.dirname(__FILE__)
local_fluent_plugin_droonga = File.join(base_dir, "..", "fluent-plugin-droonga")
if File.exist?(local_fluent_plugin_droonga)
  gem "fluent-plugin-droonga", :path => local_fluent_plugin_droonga
else
  gem "fluent-plugin-droonga", :github => "droonga/fluent-plugin-droonga"
end
