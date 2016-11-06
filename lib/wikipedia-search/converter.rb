require "rexml/streamlistener"
require "rexml/parsers/baseparser"
require "rexml/parsers/streamparser"

module WikipediaSearch
  class Converter
    def initialize(input, options={})
      @input = input
      @options = options
    end

    def convert(output)
      listener = create_listener(output)
      catch do |tag|
        parser = REXML::Parsers::StreamParser.new(@input, listener)
        listener.start(tag)
        parser.parse
      end
      listener.finish
    end

    private
    def create_listener(output)
      Listener.new(output, @options)
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
        on_start
      end

      def finish
        on_finish
      end

      def tag_start(name, attributes)
        push_stacks
        case name
        when "page"
          @page = Page.new
        when "redirect"
          @page.redirect = attributes["title"]
        end
      end

      def tag_end(name)
        case name
        when "page"
          if @max_n_records and @n_records >= @max_n_records
            throw(@abort_tag)
          end
          if target_page?
            on_page(@page)
            @first_page = false
            @n_records += 1
          end
        when "title"
          @page.title = @text_stack.last
        when "ns"
          @page.namespace = Integer(@text_stack.last)
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
      def target_page?
        @page.redirect.nil? and @page.namespace == 0
      end

      def first_page?
        @first_page
      end

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
        attr_accessor :namespace
        attr_accessor :id
        attr_accessor :redirect
        attr_accessor :title
        attr_accessor :text
        def initialize
          @namespace = nil
          @id = nil
          @redirect = nil
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
