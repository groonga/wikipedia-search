#!/usr/bin/env ruby

require "pathname"
require "ostruct"
require "optparse"

base_dir_path = Pathname.new(__FILE__).dirname
lib_dir_path = base_dir_path + "lib"

$LOAD_PATH.unshift(lib_dir_path.to_s)

require "wikipedia-search/groonga-converter"

options = OpenStruct.new
options.output = "-"
converter_options = {
  :max_n_records => -1,
  :max_n_characters => -1,
}
parser = OptionParser.new
parser.on("--max-n-records=N", Integer,
          "The number of maximum records. -1 means unlimited.",
          "(#{converter_options[:max_n_records]})") do |n|
  converter_options[:max_n_records] = n
end
parser.on("--max-n-characters=N", Integer,
          "The number of maximum characters in a record. -1 means unlimited.",
          "(#{converter_options[:max_n_characters]})") do |n|
  converter_options[:max_n_characters] = n
end
parser.on("--output=PATH",
          "Output to PATH. '-' means the standard output.",
          "(#{options.output})") do |path|
  options.output = path
end
parser.parse!(ARGV)

converter = WikipediaSearch::GroongaConverter.new(ARGF, converter_options)
if options.output == "-"
  output = $stdout
  converter.convert(output)
else
  File.open(options.output, "w") do |output|
    converter.convert(output)
  end
end
