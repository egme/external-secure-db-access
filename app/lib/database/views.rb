module Database
  class Views
    class RebuildError < StandardError; end

    VIEWS_DIR = Rails.root.join("db", "views").freeze
    VIEW_COMMENT = "VERSIONED".freeze

    class << self
      def rebuild!(views)
        ActiveRecord::Base.transaction do
          drop_views

          views.each { |view| setup_view(view) }

          views.each { |view| check_view(view) }
        end
      rescue ActiveRecord::StatementInvalid => e
        raise RebuildError, e.to_s
      end

      def defined_views
        Dir.entries(VIEWS_DIR)
          .map { |f| parse_view(f.to_s) }
          .compact
          .sort_by(&:order)
      end

      def setup_looker!
        ActiveRecord::Base.transaction do
          execute_query("DROP SCHEMA IF EXISTS looker CASCADE")
          execute_query("CREATE SCHEMA looker")

          looker_columns.each_pair do |table, columns|
            execute_query(<<~SQL)
              CREATE VIEW looker.#{table} AS SELECT #{columns.join(", ")} FROM public.#{table}
            SQL
          end
        end
      end

      private

      def looker_columns
        @looker_columns ||= Database::DataLabelingConfig.tables_labeling
          .to_a
          .filter { |(column, type)| column.first == "public" && type == :normal }
          .map(&:first)
          .map { |column| column.drop(1) }
          .each_with_object({}) do |el, memo|
            memo[el.first] ||= []
            memo[el.first] << el.last
          end
      end

      def drop_views
        ActiveRecord::Base.transaction do
          views = execute_query(<<~SQL).values.map(&:first)
            SELECT table_schema || '.' || table_name
            FROM information_schema.views
            WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
            AND obj_description((table_schema || '.' || table_name)::regclass) = '#{VIEW_COMMENT}'
          SQL
          views.each do |view|
            execute_query("DROP VIEW IF EXISTS #{view} CASCADE")
          end
        end
      end

      def parse_view(file)
        matches = /^(\d+)\.((\w+)\.)?(\w+)\.sql$/.match(file)

        return unless matches

        query = File.read(
          VIEWS_DIR.join(matches[0]),
        ).chomp

        OpenStruct.new(
          order: matches[1],
          schema: matches[3] || "public",
          name: matches[4],
          query: query,
        )
      end

      def setup_view(view)
        execute_query("CREATE SCHEMA IF NOT EXISTS #{view.schema}")

        return if view.query.empty?

        execute_query("CREATE VIEW #{view.schema}.#{view.name} AS #{view.query}")
        execute_query("COMMENT ON VIEW #{view.schema}.#{view.name} IS '#{VIEW_COMMENT}'")
      end

      def check_view(view)
        return if view.query.empty?

        execute_query("SELECT '#{view.schema}.#{view.name}'::regclass")
      end

      def execute_query(query)
        ActiveRecord::Base
          .connection
          .execute(query)
          .tap do |result|
            Rails.logger.info("VIEWS: #{query.chomp.gsub(/(\n|\s+)/, " ")} -> #{result.inspect}")
          end
      end
    end
  end
end
