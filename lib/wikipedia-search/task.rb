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

    def data_dir_path
      @data_dir_path ||= Pathname.new("data")
    end

    def ja_data_path
      @ja_data_path ||= data_dir_path + ja_data_base_name
    end

    def ja_data_base_name
      "jawiki-latest-pages-articles.xml.bz2"
    end
  end
end
