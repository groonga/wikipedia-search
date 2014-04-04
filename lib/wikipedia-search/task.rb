require "rbconfig"
require "shellwords"

require "wikipedia-search/downloader"

module WikipediaSearch
  class Task
    class << self
      def define
        new.define
      end
    end
    include Rake::DSL

    def define
      define_data_tasks
      define_groonga_tasks
    end

    private
    def define_data_tasks
      namespace :data do
        directory data_dir_path.to_s
        define_data_download_tasks
        define_data_convert_tasks
      end
    end

    def define_data_download_tasks
      namespace :download do
        namespace :pages do
          file ja_pages_path.to_s => data_dir_path.to_s do
            url = "#{ja_download_base_url}/#{ja_pages_base_name}"
            WikipediaSearch::Downloader.download(url, ja_pages_path)
          end

          desc "Download the latest Japanese Wikipedia pages."
          task :ja => ja_pages_path.to_s
        end

        namespace :titles do
          file ja_titles_path.to_s => data_dir_path.to_s do
            url = "#{ja_download_base_url}/#{ja_titles_base_name}"
            WikipediaSearch::Downloader.download(url, ja_titles_path)
          end

          desc "Download the latest Japanese Wikipedia titles."
          task :ja => ja_titles_path.to_s
        end
      end
    end

    def define_data_convert_tasks
      namespace :convert do
        define_data_convert_groonga_tasks
        define_data_convert_droonga_tasks
      end
    end

    def define_data_convert_groonga_tasks
      namespace :groonga do
        file ja_groonga_pages_path.to_s => ja_pages_path.to_s do
          command_line = []
          command_line << "bzcat"
          command_line << Shellwords.escape(ja_pages_path.to_s)
          command_line << "|"
          command_line << RbConfig.ruby
          command_line << "bin/wikipedia-to-groonga.rb"
          command_line << "--max-n-records"
          command_line << "5000"
          command_line << "--max-n-characters"
          command_line << "1000"
          command_line << "--output"
          command_line << ja_groonga_pages_path.to_s
          sh(command_line.join(" "))
        end

        desc "Convert Japanese Wikipedia page data to Groonga page data."
        task :ja => ja_groonga_pages_path.to_s
      end
    end

    def define_data_convert_droonga_tasks
      namespace :droonga do
        file ja_droonga_pages_path.to_s => ja_groonga_pages_path.to_s do
          sh("grn2drn",
             "--dataset", "Wikipedia",
             "--output", ja_droonga_pages_path.to_s,
             ja_groonga_pages_path.to_s)
        end

        desc "Convert Japanese Wikipedia page data to Droonga page data."
        task :ja => ja_droonga_pages_path.to_s
      end
    end

    def define_groonga_tasks
      namespace :groonga do
        desc "Load data."
        task :load do
          rm_rf(groonga_database_dir_path.to_s)
          mkdir_p(groonga_database_dir_path.to_s)
          groonga_run(groonga_schema_path.to_s)
          groonga_run(ja_groonga_pages_path.to_s.to_s)
          groonga_run(groonga_indexes_path.to_s)
        end
      end
    end

    def groonga_run(input)
      command_line = [
        "groonga",
        "--log-path", (groonga_database_dir_path + "groonga.log").to_s,
        "--query-log-path", (groonga_database_dir_path + "query.log").to_s,
        "--file", input,
      ]
      unless groonga_database_path.exist?
        command_line << "-n"
      end
      command_line << groonga_database_path.to_s
      sh(*command_line)
    end

    def download_base_url(language)
      "http://dumps.wikimedia.org/#{language}wiki/latest"
    end

    def ja_download_base_url
      download_base_url("ja")
    end

    def data_dir_path
      @data_dir_path ||= Pathname.new("data")
    end

    def ja_pages_path
      @ja_pages_path ||= data_dir_path + ja_pages_base_name
    end

    def ja_pages_base_name
      "jawiki-latest-pages-articles.xml.bz2"
    end

    def ja_groonga_pages_path
      @ja_groonga_pages_path ||= data_dir_path + "ja-pages.grn"
    end

    def ja_droonga_pages_path
      @ja_droonga_pages_path ||= data_dir_path + "ja-pages.jsons"
    end

    def ja_titles_path
      @ja_titles_path ||= data_dir_path + ja_titles_base_name
    end

    def ja_titles_base_name
      "jawiki-latest-all-titles.gz"
    end

    def config_dir
      Pathname.new("config")
    end

    def groonga_schema_path
      config_dir + "groonga" + "schema.grn"
    end

    def groonga_indexes_path
      config_dir + "groonga" + "indexes.grn"
    end

    def groonga_database_dir_path
      data_dir_path + "groonga"
    end

    def groonga_database_path
      groonga_database_dir_path + "db"
    end
  end
end
