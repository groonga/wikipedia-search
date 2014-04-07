require "rbconfig"
require "shellwords"

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

    def define_local_tasks
      namespace :local do
        define_local_groonga_tasks
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
  end
end
