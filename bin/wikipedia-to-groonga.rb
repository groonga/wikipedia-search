#!/usr/bin/env ruby

require "pathname"

base_dir_path = Pathname.new(__FILE__).dirname
lib_dir_path = base_dir_path + "lib"

$LOAD_PATH.unshift(lib_dir_path.to_s)

require "wikipedia-search/groonga-converter"

converter = WikipediaSearch::GroongaConverter.new(ARGF)
converter.convert($stdout)
