require "rbconfig"
require "shellwords"
require "json"
require "socket"

require "wikipedia-search/downloader"
require "wikipedia-search/path"

module WikipediaSearch
  class Task
    class << self
      def define(languages=nil)
        languages ||= ["ja", "en"]
        languages.each do |language|
          new(language).define
        end
      end
    end
    include Rake::DSL

    def initialize(language)
      @language = language
      @path = Path.new(".", @language)
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

          desc "Download the latest #{@language} Wikipedia pages."
          task @language => path.pages.to_s
        end

        namespace :titles do
          file path.titles.to_s => @path.download_dir.to_s do
            WikipediaSearch::Downloader.download(path.titles_url,
                                                 path.titles)
          end

          desc "Download the latest #{@language} Wikipedia titles."
          task @language => path.titles.to_s
        end
      end
    end

    def define_data_convert_tasks
      directory @path.data_dir.to_s

      namespace :convert do
        define_data_convert_groonga_tasks
        define_data_convert_droonga_tasks
        define_data_convert_sql_tasks
        define_data_convert_csv_tasks
      end
    end

    def define_wikipedia_data_convert_tasks(format, pages_path, all_pages_path)
      base_command_line = [
        "bzcat",
        Shellwords.escape(@path.wikipedia.pages.to_s),
        "|",
        RbConfig.ruby,
        "bin/wikipedia-convert",
        "--format", format,
      ]
      file pages_path.to_s => @path.wikipedia.pages.to_s do
        max_n_records = ENV["MAX_N_RECORDS"]
        if max_n_records.nil? or max_n_records.empty?
          max_n_records = 5000
        end
        max_n_characters = ENV["MAX_N_CHARACTERS"]
        if max_n_characters.nil? or max_n_characters.empty?
          max_n_characters = 1000
        end
        command_line = base_command_line.dup
        command_line << "--max-n-records"
        command_line << max_n_records.to_s
        command_line << "--max-n-characters"
        command_line << max_n_characters.to_s
        command_line << "--output"
        command_line << pages_path.to_s
        sh(command_line.join(" "))
      end

      file all_pages_path.to_s => @path.wikipedia.pages.to_s do
        command_line = base_command_line.dup
        command_line << "--output"
        command_line << all_pages_path.to_s
        sh(command_line.join(" "))
      end
    end

    def define_data_convert_groonga_tasks
      namespace :groonga do
        define_wikipedia_data_convert_tasks("groonga",
                                            @path.groonga.pages,
                                            @path.groonga.all_pages)
        desc "Convert #{@language} Wikipedia page data to Groonga page data."
        task @language => @path.groonga.pages.to_s
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
               "--output", @path.droonga.pages.to_s,
               @path.groonga.pages.to_s)
          end

          file @path.droonga.all_pages.to_s => @path.groonga.all_pages.to_s do
            sh("grn2drn",
               "--output", @path.droonga.all_pages.to_s,
               @path.groonga.all_pages.to_s)
          end

          desc "Convert #{@language} Wikipedia page data to Droonga page data."
          task @language => @path.droonga.pages.to_s
        end
      end
    end

    def define_data_convert_sql_tasks
      namespace :sql do
        define_wikipedia_data_convert_tasks("sql",
                                            @path.sql.pages,
                                            @path.sql.all_pages)
        desc "Convert #{@language} Wikipedia page data to SQL data."
        task @language => @path.sql.pages.to_s

        namespace @language do
          desc "Convert #{@language} Wikipedia all page data to SQL data."
          task :all => @path.sql.all_pages.to_s
        end
      end
    end

    def define_data_convert_csv_tasks
      namespace :csv do
        define_wikipedia_data_convert_tasks("csv",
                                            @path.csv.pages,
                                            @path.csv.all_pages)
        desc "Convert #{@language} Wikipedia page data to CSV data."
        task @language => @path.csv.pages.to_s

        namespace @language do
          desc "Convert #{@language} Wikipedia all page data to CSV data."
          task :all => @path.csv.all_pages.to_s
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
          pids = []
          begin
            node_ids.each do |node_id|
              working_dir = @path.droonga.node_working_dir(node_id)
              rm_rf(working_dir.to_s)
              mkdir_p(working_dir.to_s)

              droonga_generate_catalog(node_id, node_ids)

              pids << droonga_run_engine(node_id)
            end
            node_ids.each do |node_id|
              droonga_wait_engine_ready(node_id)
            end
            front_node_id = node_ids.first
            host = droonga_host(front_node_id)
            port = droonga_port
            sh("droonga-send",
               "--server", "droonga:#{host}:#{port}/droonga",
               "--report-throughput",
               @path.droonga.pages.to_s)
          ensure
            stop_processes(pids)
          end
        end

        desc "Run Droonga cluster."
        task :run do
          pids = []
          begin
            node_ids.each do |node_id|
              pids << droonga_run_engine(node_id)
              host = droonga_host(node_id)
              port = droonga_port
              puts("#{host}:#{port}/droonga")
            end
            front_node_id = node_ids.first
            pids << droonga_run_protocol_adapter(front_node_id)
            droonga_wait_engine_ready(front_node_id)
            $stdin.gets
          ensure
            stop_processes(pids)
          end
        end
      end
    end

    def droonga_host(node_id)
      "127.0.0.#{100 + node_id}"
    end

    def droonga_port
      24000
    end

    def droonga_generate_catalog(node_id, node_ids)
      hosts = node_ids.collect do |node_id|
        droonga_host(node_id)
      end
      sh("droonga-engine-catalog-generate",
         "--output", @path.droonga.catalog(node_id).to_s,
         "--n-workers", "3",
         "--schema", @path.droonga.schema.to_s,
         "--fact", "Pages",
         "--hosts", hosts.join(","),
         "--port", droonga_port.to_s,
         "--n-slices", "4")
    end

    def droonga_run_engine(node_id)
      base_dir = @path.droonga.node_working_dir(node_id)
      pid_file = base_dir + "droonga-engine.pid"
      spawn("droonga-engine",
            "--base-dir", base_dir.to_s,
            "--host", droonga_host(node_id),
            "--port", droonga_port.to_s,
            "--tag", "droonga",
            "--pid-file", pid_file.to_s)
    end

    def droonga_run_protocol_adapter(node_id)
      spawn("droonga-http-server",
            "--droonga-engine-host-name", droonga_host(node_id),
            "--droonga-engine-port", droonga_port.to_s)
    end

    def droonga_wait_engine_ready(node_id)
      host = droonga_host(node_id)
      port = droonga_port
      60.times do
        begin
          TCPSocket.new(host, port)
        rescue SystemCallError
          sleep(1)
        end
      end
    end

    def stop_processes(pids)
      stop_threads = pids.collect do |pid|
        Thread.new do
          stop_process(pid)
        end
      end
      stop_threads.each(&:join)
    end

    def stop_process(pid)
      Process.kill(:TERM, pid)
      Process.waitpid(pid)
    end
  end
end
