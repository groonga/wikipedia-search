require "wikipedia-search/downloader"

namespace :data do
  data_dir_path = Pathname.new("data")
  directory data_dir_path.to_s

  namespace :download do
    base_name = "jawiki-latest-pages-articles.xml.bz2"
    ja_data_path = data_dir_path + base_name
    file ja_data_path.to_s => data_dir_path.to_s do
      url = "http://dumps.wikimedia.org/jawiki/latest/#{base_name}"
      WikipediaSearch::Downloader.download(url, ja_data_path)
    end

    desc "Download the latest Japanese Wikipedia data."
    task :ja => ja_data_path.to_s
  end
end
