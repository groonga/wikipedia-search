# -*- ruby -*-

require "pathname"

base_dir_path = Pathname.new(__FILE__).dirname
lib_dir_path = base_dir_path + "lib"

$LOAD_PATH.unshift(lib_dir_path.to_s)

require "wikipedia-search/task"

WikipediaSearch::Task.define

task :default => :test

desc "Run test"
task :test do
  ruby("test/run-test.rb")
end
