#!/usr/bin/env ruby

require "pathname"
require "optparse"

base_dir_path = Pathname.new(__FILE__).dirname
lib_dir_path = base_dir_path + "lib"

$LOAD_PATH.unshift(lib_dir_path.to_s)

require "wikipedia-search/groonga-converter"

options = {
  :max_n_records => -1,
}
parser = OptionParser.new
parser.on("--max-n-records=N", Integer,
          "The number of maximum records. -1 means unlimited.",
          "(#{options[:max_n_records]})") do |n|
  options[:max_n_records] = n
end
parser.parse!(ARGV)

converter = WikipediaSearch::GroongaConverter.new(ARGF, options)
converter.convert($stdout)
