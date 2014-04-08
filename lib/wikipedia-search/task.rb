require "rbconfig"
require "shellwords"
require "json"

require "wikipedia-search/downloader"
require "wikipedia-search/path"

module WikipediaSearch
  class Task
    class << self
      def define
        new.define
      end
    end
    include Rake::DSL

    def initialize
      @path = Path.new(".", "ja")
    end

    def define
      define_data_tasks
      define_local_tasks
    end

    private
    def define_data_tasks
      namespace :data do
        define_data_download_tasks
        define_data_convert_tasks
      end
    end

    def define_data_download_tasks
      path = @path.wikipedia
      directory @path.download_dir.to_s

      namespace :download do
        namespace :pages do
          file path.pages.to_s => @path.download_dir.to_s do
            WikipediaSearch::Downloader.download(path.pages_url, path.pages)
          end

          desc "Download the latest Japanese Wikipedia pages."
          task :ja => path.pages.to_s
        end

        namespace :titles do
          file path.titles.to_s => @path.download_dir.to_s do
            WikipediaSearch::Downloader.download(path.titles_url,
                                                 path.titles)
          end

          desc "Download the latest Japanese Wikipedia titles."
          task :ja => path.titles.to_s
        end
      end
    end

    def define_data_convert_tasks
      directory @path.data_dir.to_s

      namespace :convert do
        define_data_convert_groonga_tasks
        define_data_convert_droonga_tasks
      end
    end

    def define_data_convert_groonga_tasks
      namespace :groonga do
        file @path.groonga.pages.to_s => @path.wikipedia.pages.to_s do
          command_line = []
          command_line << "bzcat"
          command_line << Shellwords.escape(@path.wikipedia.pages.to_s)
          command_line << "|"
          command_line << RbConfig.ruby
          command_line << "bin/wikipedia-to-groonga.rb"
          command_line << "--max-n-records"
          command_line << "5000"
          command_line << "--max-n-characters"
          command_line << "1000"
          command_line << "--output"
          command_line << @path.groonga.pages.to_s
          sh(command_line.join(" "))
        end

        desc "Convert Japanese Wikipedia page data to Groonga page data."
        task :ja => @path.groonga.pages.to_s
      end
    end

    def define_data_convert_droonga_tasks
      namespace :droonga do
        schema_dependencies = [
          @path.groonga.schema.to_s,
          @path.groonga.indexes.to_s,
        ]
        file @path.droonga.schema.to_s => schema_dependencies do
          sh("grn2drn-schema",
             "--output", @path.droonga.schema.to_s,
             @path.groonga.schema.to_s,
             @path.groonga.indexes.to_s)
        end

        desc "Convert Groonga schema to Droonga schema."
        task :schema => @path.droonga.schema.to_s

        namespace :pages do
          file @path.droonga.pages.to_s => @path.groonga.pages.to_s do
            sh("grn2drn",
               "--dataset", "Wikipedia",
               "--output", @path.droonga.pages.to_s,
               @path.groonga.pages.to_s)
          end

          desc "Convert Japanese Wikipedia page data to Droonga page data."
          task :ja => @path.droonga.pages.to_s
        end
      end
    end

    def define_local_tasks
      namespace :local do
        define_local_groonga_tasks
        define_local_droonga_tasks
      end
    end

    def define_local_groonga_tasks
      namespace :groonga do
        desc "Load data."
        task :load => @path.groonga.pages.to_s do
          rm_rf(@path.groonga.database_dir.to_s)
          mkdir_p(@path.groonga.database_dir.to_s)
          groonga_run(@path.groonga.schema.to_s)
          groonga_run(@path.groonga.pages.to_s)
          groonga_run(@path.groonga.indexes.to_s)
        end
      end
    end

    def groonga_run(input)
      command_line = [
        "groonga",
        "--log-path", @path.groonga.log.to_s,
        "--query-log-path", @path.groonga.query_log.to_s,
        "--file", input,
      ]
      unless @path.groonga.database.exist?
        command_line << "-n"
      end
      command_line << @path.groonga.database.to_s
      sh(*command_line)
    end

    def define_local_droonga_tasks
      namespace :droonga do
        node_ids = [0, 1]

        load_dependencies = [
          @path.droonga.pages.to_s,
          @path.droonga.schema.to_s,
        ]
        desc "Load data."
        task :load => load_dependencies do
          rm_rf(@path.droonga.working_dir.to_s)
          mkdir_p(@path.droonga.working_dir.to_s)

          node_ids.each do |node_id|
            droonga_generate_fluentd_conf(node_id)
          end

          droonga_generate_catalog(node_ids)

          begin
            node_ids.each do |node_id|
              droonga_run_engine(node_id)
            end
            front_node_id = node_ids.first
            droonga_wait_engine_ready(front_node_id)
            port = droonga_port(front_node_id)
            sh("droonga-send",
               "--server", "droonga:127.0.0.1:#{port}/droonga",
               "--report-throughput",
               @path.droonga.pages.to_s)
          ensure
            node_ids.each do |node_id|
              droonga_stop_engine(node_id)
            end
          end
        end

        desc "Run Droonga cluster."
        task :run do
          begin
            node_ids.each do |node_id|
              droonga_run_engine(node_id)
              port = droonga_port(node_id)
              puts("127.0.0.1:#{port}/droonga")
            end
            front_node_id = node_ids.first
            droonga_wait_engine_ready(front_node_id)
            $stdin.gets
          ensure
            node_ids.each do |node_id|
              droonga_stop_engine(node_id)
            end
          end
        end
      end
    end

    def droonga_port(node_id)
      24000 + node_id
    end

    def droonga_generate_fluentd_conf(node_id)
      fluend_conf_path = @path.droonga.fluentd_conf(node_id)
      fluend_conf_path.open("w") do |fluend_conf|
        port = droonga_port(node_id)
        fluend_conf.puts(<<-CONF)
<source>
  type forward
  port #{port}
</source>
<match droonga.message>
  type droonga
  name 127.0.0.1:#{port}/droonga
</match>
        CONF
      end
    end

    def droonga_generate_catalog(node_ids)
      replicas_path = @path.droonga.working_dir + "replicas.json"
      replicas_path.open("w") do |replicas_file|
        replicas = 2.times.collect do |i|
          slices = node_ids.collect do |node_id|
            port = droonga_port(node_id)
            {
              "volume" => {
                "address" => "127.0.0.1:#{port}/droonga.#{i}#{node_id}"
              }
            }
          end
          {
            "slices" => slices,
          }
        end
        replicas_file.puts(JSON.pretty_generate(replicas))
      end
      sh("droonga-catalog-generate",
         "--output", @path.droonga.catalog.to_s,
         "--dataset", "Wikipedia",
         "--n-workers", "3",
         "--schema", @path.droonga.schema.to_s,
         "--fact", "Pages",
         "--replicas", replicas_path.to_s)
    end

    def droonga_run_engine(node_id)
      system("fluentd",
             "--config", @path.droonga.fluentd_conf(node_id).expand_path.to_s,
             "--log", @path.droonga.log(node_id).expand_path.to_s,
             "--daemon", @path.droonga.pid(node_id).expand_path.to_s,
             :chdir => @path.droonga.working_dir.to_s)
    end

    def droonga_wait_engine_ready(node_id)
      port = droonga_port(node_id)
      3.times do
        begin
          TCPSocket.new("127.0.0.1", port)
        rescue SystemCallError
          sleep(1)
        end
      end
    end

    def droonga_stop_engine(node_id)
      pid_path = @path.droonga.pid(node_id)
      Process.kill(:TERM, Integer(pid_path.read)) if pid_path.exist?
    end
  end
end
