#!/usr/bin/env ruby

require "pathname"

require "bundler/setup"
require "test-unit"

base_dir_path = Pathname.new(__FILE__).dirname.parent
lib_dir_path = base_dir_path + "lib"
test_dir_path = base_dir_path + "test"

$LOAD_PATH.unshift(lib_dir_path.to_s)

exit(Test::Unit::AutoRunner.run(true, test_dir_path.to_s))
