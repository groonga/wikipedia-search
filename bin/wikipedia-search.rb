#!/usr/bin/env ruby

require "pathname"
require "ostruct"
require "optparse"

require "coolio"
require "droonga/client"

base_dir_path = Pathname.new(__FILE__).dirname
lib_dir_path = base_dir_path + "lib"

$LOAD_PATH.unshift(lib_dir_path.to_s)

require "wikipedia-search/groonga-converter"

options = OpenStruct.new
options.protocol = "droonga"
options.host = "127.0.0.1"
options.port = 24000
options.max_n_connections = 10
options.show_response = false

protocols = ["droonga", "droonga-http", "groonga-http"]
parser = OptionParser.new
parser.on("--protocol=PROTOCOL", protocols,
          "Use PROTOCOL for search.",
          "(#{protocols.join(', ')})") do |protocol|
  options.protocol = protocol
end
parser.on("--host=HOST",
          "Search against HOST.",
          "(#{options.host})") do |host|
  options.host = host
end
parser.on("--port=PORT", Integer,
          "Use PORT as the server port number.",
          "(#{options.port})") do |port|
  options.port = port
end
parser.on("--max-n-connections=N", Integer,
          "Use N connections for search.",
          "(#{options.max_n_connections})") do |n|
  options.max_n_connections = n
end
parser.parse!(ARGV)

def build_droonga_message(query)
  {
    "type" => "search",
    "dataset" => "Wikipedia",
    "body" => {
      "queries" => {
        "pages" => {
          "source" => "Pages",
          "condition" => {
            "matchTo" => ["title", "text"],
            "query" => query,
          },
          "output" => {
            "elements" => ["count", "records"],
            "attributes" => [
              "_key",
              "title",
              "text",
            ],
            "limit" => 10,
          },
        },
      },
    },
  }
end

def send_request(query, client, options)
  start = Time.now
  client.request(build_droonga_message(query)) do |response|
    elapsed = Time.now - start
    status_code = response["statusCode"]
    if status_code == 200
      n_hits = response["body"]["pages"]["count"]
    else
      n_hits = 0
    end
    p [elapsed, query, status_code, n_hits]
    yield
  end
end

def run_request(queries, client, options)
  if queries.empty?
    client.close
    return
  end

  query = queries.pop
  send_request(query, client, options) do
    run_request(queries, client, options)
  end
end

queries = ARGF.each_line.collect do |line|
  line.strip
end

loop = Coolio::Loop.default
options.max_n_connections.times do
  client_options = {
    :host => options.host,
    :port => options.port,
    :tag  => "droonga",
    :protocol => :droonga,
    :backend => :coolio,
    :loop => loop,
  }
  client = Droonga::Client.new(client_options)
  run_request(queries, client, options)
end
loop.run
