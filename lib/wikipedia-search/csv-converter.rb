require "csv"

require_relative "converter"

module WikipediaSearch
  class CSVConverter < Converter
    private
    def convert_start
      @csv = CSV.new(@output)
    end

    def convert_finish
      @csv.close
    end

    def convert_page(page)
      record_values = [
        @page.id,
        escape_string(@page.title),
        escape_string(shorten_text(@page.revision.text)),
      ]
      @csv << record_values
    end

    def escape_string(string)
      string.gsub(/[\\\r\n]/) do |special_character|
        case special_character
        when "\r"
          "\\r"
        when "\n"
          "\\n"
        else
          "\\#{special_character}"
        end
      end
    end
  end
end
