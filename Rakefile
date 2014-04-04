# -*- ruby -*-

require "pathname"
require "open-uri"

def format_size(size)
  if size < 1024
    "%d" % size
  elsif size < (1024 ** 2)
    "%7.2fKiB" % (size.to_f / 1024)
  elsif size < (1024 ** 3)
    "%7.2fMiB" % (size.to_f / (1024 ** 2))
  elsif size < (1024 ** 4)
    "%7.2fGiB" % (size.to_f / (1024 ** 3))
  else
    "%.2fTiB" % (size.to_f / (1024 ** 4))
  end
end

def download(url, output_path)
  base_name = File.basename(url)
  max = nil
  content_length_proc = lambda do |content_length|
    max = content_length
  end
  progress_proc = lambda do |current|
    if max
      percent = (current / max.to_f) * 100
      formatted_size = "[%s/%s]" % [format_size(current), format_size(max)]
      print("\r%s - %06.2f%% %s" % [base_name, percent, formatted_size])
      puts if current == max
    end
  end
  options = {
    :content_length_proc => content_length_proc,
    :progress_proc => progress_proc,
  }

  open(url, options) do |input|
    output_path.open("wb") do |output|
      chunk = ""
      chunk_size = 8192
      while input.read(chunk_size, chunk)
        output.print(chunk)
      end
    end
  end
end

namespace :data do
  data_dir_path = Pathname.new("data")
  directory data_dir_path.to_s

  namespace :download do
    base_name = "jawiki-latest-pages-articles.xml.bz2"
    ja_data_path = data_dir_path + base_name
    file ja_data_path.to_s => data_dir_path.to_s do
      download("http://dumps.wikimedia.org/jawiki/latest/#{base_name}",
               ja_data_path)
    end

    desc "Download the latest Japanese Wikipedia data."
    task :ja => ja_data_path.to_s
  end
end
