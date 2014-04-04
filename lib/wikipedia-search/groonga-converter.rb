require "json"
require "rexml/streamlistener"
require "rexml/parsers/baseparser"
require "rexml/parsers/streamparser"

module WikipediaSearch
  class GroongaConverter
    def initialize(input, options={})
      @input = input
      @options = options
    end

    def convert(output)
      listener = Listener.new(output, @options)
      catch do |tag|
        parser = REXML::Parsers::StreamParser.new(@input, listener)
        listener.start(tag)
        parser.parse
      end
      listener.finish
    end

    class Listener
      include REXML::StreamListener

      def initialize(output, options)
        @output = output
        @options = options
        @text_stack = [""]
        @first_page = true
        @n_records = 0
        @max_n_records = @options[:max_n_records] || -1
        @max_n_records = nil if @max_n_records < 0
        @max_n_characters = @options[:max_n_characters] || -1
        @max_n_characters = nil if @max_n_characters < 0
      end

      def start(abort_tag)
        @abort_tag = abort_tag
        @output.puts("load --table Pages")
        @output.puts("[")
      end

      def finish
        @output.puts unless @first_page
        @output.puts("]")
      end

      def tag_start(name, attributes)
        push_stacks
        case name
        when "page"
          @page = Page.new
        end
      end

      def tag_end(name)
        case name
        when "page"
          if @max_n_records and @n_records >= @max_n_records
            throw(@abort_tag)
          end
          if @first_page
            @first_page = false
          else
            @output.puts(",")
          end
          page = {
            "_key"  => @page.id,
            "title" => @page.title,
            "text"  => shorten_text(@page.text),
            "categories" => @page.extract_categories,
          }
          @output.print(JSON.generate(page))
          @n_records += 1
        when "title"
          @page.title = @text_stack.last
        when "id"
          @page.id ||= Integer(@text_stack.last)
        when "text"
          @page.text = @text_stack.last
        end
        pop_stacks
      end

      def text(data)
        @text_stack.last << data
      end

      def cdata(contnet)
        @text_stack.last << content
      end

      private
      def push_stacks
        @text_stack << ""
      end

      def pop_stacks
        @text_stack.pop
      end

      def shorten_text(text)
        if @max_n_characters
          text[0, @max_n_characters]
        else
          text
        end
      end

      class Page
        attr_accessor :id, :title, :text
        def initialize
          @id = nil
          @title = nil
          @text = nil
        end

        def extract_categories
          return [] if @text.nil?

          categories = []
          @text.scan(/\[\[(.+?)\]\]/) do |link,|
            case link
            when /\ACategory:(.+?)(?:\|.*)?\z/
              categories << $1
            end
          end
          categories
        end
      end
    end
  end
end
