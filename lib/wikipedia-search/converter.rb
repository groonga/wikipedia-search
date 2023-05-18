require "datasets"

module WikipediaSearch
  class Converter
    def initialize(input, **options)
      @input = input
      @options = options
      @max_n_records = @options[:max_n_records] || -1
      @max_n_records = nil if @max_n_records < 0
      @max_n_characters = @options[:max_n_characters] || -1
      @max_n_characters = nil if @max_n_characters < 0
    end

    def convert(output)
      dataset = Datasets::Wikipedia.new(language: :ja)
      @output = output
      @n_records = 0
      @first_page = true
      catch do |tag|
        @abort_tag = tag
        convert_start
        dataset.each do |page|
          if @max_n_records and @n_records >= @max_n_records
            throw(@abort_tag)
          end
          next unless target_page?(page)
          convert_page(page)
          @first_page = false
          @n_records += 1
        end
      end
      convert_finish
      @abort_tag = nil
      @output = nil
    end

    private
    def target_page?(page)
      page.redirect.nil? and page.namespace == 0
    end

    def shorten_text(text)
      if @max_n_characters
        text[0, @max_n_characters]
      else
        text
      end
    end

    def extract_categories(text)
      return [] if text.nil?

      categories = []
      text.scan(/\[\[(.+?)\]\]/) do |link,|
        case link
        when /\ACategory:(.+?)(?:\|.*)?\z/
          categories << $1
        end
      end
      categories
    end
  end
end
