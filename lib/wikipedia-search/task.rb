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
      namespace :data do
        directory data_dir_path.to_s
        define_download_tasks
        define_convert_tasks
      end
    end

    private
    def define_download_tasks
      namespace :download do
        file ja_data_path.to_s => data_dir_path.to_s do
          url = "http://dumps.wikimedia.org/jawiki/latest/#{ja_data_base_name}"
          WikipediaSearch::Downloader.download(url, ja_data_path)
        end

        desc "Download the latest Japanese Wikipedia data."
        task :ja => ja_data_path.to_s
      end
    end

    def define_convert_tasks
      namespace :convert do
        namespace :ja do
          file ja_groonga_data_path.to_s => ja_data_path.to_s do
            command_line = []
            command_line << "bzcat"
            command_line << Shellwords.escape(ja_data_path.to_s)
            command_line << "|"
            command_line << RbConfig.ruby
            command_line << "bin/wikipedia-to-groonga.rb"
            command_line << "--max-n-records"
            command_line << "5000"
            command_line << "--max-n-characters"
            command_line << "1000"
            command_line << "--output"
            command_line << ja_groonga_data_path.to_s
            sh(command_line.join(" "))
          end

          desc "Convert Japanese Wikipedia data to Groonga data."
          task :groonga => ja_groonga_data_path.to_s

          file ja_droonga_data_path.to_s => ja_groonga_data_path.to_s do
            sh("grn2drn",
               "--dataset", "Wikipedia",
               "--output", ja_droonga_data_path.to_s,
               ja_groonga_data_path.to_s)
          end

          desc "Convert Japanese Wikipedia data to Droonga data."
          task :droonga => ja_droonga_data_path.to_s
        end
      end
    end

    def data_dir_path
      @data_dir_path ||= Pathname.new("data")
    end

    def ja_data_path
      @ja_data_path ||= data_dir_path + ja_data_base_name
    end

    def ja_data_base_name
      "jawiki-latest-pages-articles.xml.bz2"
    end

    def ja_groonga_data_path
      @ja_groonga_data_path ||= data_dir_path + "ja-data.grn"
    end

    def ja_droonga_data_path
      @ja_droonga_data_path ||= data_dir_path + "ja-data.jsons"
    end
  end
end
