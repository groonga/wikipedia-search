require "open-uri"

module WikipediaSearch
  class Downloader
    class << self
      def download(url, output_path)
        new(url, output_path).download
      end
    end

    def initialize(url, output_path)
      @url = url
      @output_path = output_path
    end

    def download
      base_name = File.basename(@url)
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

      open(@url, options) do |input|
        @output_path.open("wb") do |output|
          chunk = ""
          chunk_size = 8192
          while input.read(chunk_size, chunk)
            output.print(chunk)
          end
        end
      end
    end

    private
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
  end
end
