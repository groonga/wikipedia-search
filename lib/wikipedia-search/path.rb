require "pathname"

module WikipediaSearch
  class Path
    def initialize(base, language)
      @base = Pathname.new(base)
      @language = language
    end

    def data_dir
      @base + "data"
    end

    def download_dir
      data_dir + "download"
    end

    def config_dir
      @base + "config"
    end

    def wikipedia
      WikipediaPath.new(self, @language)
    end

    def groonga
      GroongaPath.new(self, @language)
    end

    def droonga
      DroongaPath.new(self, @language)
    end
  end

  class WikipediaPath
    def initialize(base_path, language)
      @base_path = base_path
      @language = language
    end

    def download_base_url
      "http://dumps.wikimedia.org/#{@language}wiki/latest"
    end

    def pages
      @base_path.download_dir + pages_base_name
    end

    def pages_base_name
      "#{@language}wiki-latest-pages-articles.xml.bz2"
    end

    def pages_url
      "#{download_base_url}/#{pages_base_name}"
    end

    def titles
      @base_path.download_dir + titles_base_name
    end

    def titles_base_name
      "#{@language}wiki-latest-all-titles.gz"
    end

    def titles_url
      "#{download_base_url}/#{titles_base_name}"
    end
  end

  class GroongaPath
    def initialize(base_path, language)
      @base_path = base_path
      @language = language
    end

    def config_dir
      @base_path.config_dir + "groonga"
    end

    def data_dir
      @base_path.data_dir + "groonga"
    end

    def schema
      config_dir + "schema.grn"
    end

    def indexes
      config_dir + "indexes.grn"
    end

    def pages
      data_dir + "#{@language}-pages.grn"
    end

    def database_dir
      data_dir + "db"
    end

    def database
      database_dir + "wikipedia"
    end

    def log
      database_dir + "groonga.log"
    end

    def query_log
      database_dir + "query.log"
    end
  end

  class DroongaPath
    def initialize(base_path, language)
      @base_path = base_path
      @language = language
    end

    def config_dir
      @base_path.config_dir + "droonga"
    end

    def data_dir
      @base_path.data_dir + "droonga"
    end

    def pages
      data_dir + "#{@language}-pages.jsons"
    end

    def schema
      data_dir + "schema.json"
    end

    def working_dir
      data_dir + "wikipedia"
    end

    def node_working_dir(node_id)
      working_dir + node_id.to_s
    end

    def catalog(node_id)
      node_working_dir(node_id) + "catalog.json"
    end
  end
end
