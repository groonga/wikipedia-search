require_relative "converter"

module WikipediaSearch
  class SQLConverter < Converter
    def initialize(*, **)
      super
      @bulk = @options[:bulk]
    end

    private
    def escape_string(string)
      escaped_content = string.gsub(/['\\\n]/) do |special_character|
        case special_character
        when "\n"
          "\\n"
        when "'"
          "''"
        else
          "\\#{special_character}"
        end
      end
      "'#{escaped_content}'"
    end

    def convert_start
      if @bulk
        @output.puts("INSERT INTO wikipedia (id, title, text) VALUES")
      end
    end

    def convert_finish
      if @bulk
        @output.puts unless @first_page
        @output.puts(";")
      end
    end

    def convert_page(page)
      text = @page.revision.text
      if @bulk
        @output.puts(",") unless @first_page
        record_values = [
          @page.id,
          escape_string(@page.title),
          escape_string(shorten_text(@page.revision.text)),
        ]
        @output.print("(#{record_values.join(', ')})")
      else
        record_values = [
          @page.id,
          escape_string(@page.title),
          escape_string(shorten_text(@page.revision.text)),
        ]
        @output.print("INSERT INTO wikipedia (id, title, text) VALUES ")
        @output.puts("(#{record_values.join(', ')});")
      end
    end
  end
end
