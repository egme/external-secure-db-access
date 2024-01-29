module Database
  class DataLabelingConfig
    LABELED_COLUMNS = {
      normal: %w[
        ar_internal_metadata.key
        ar_internal_metadata.value
        ar_internal_metadata.created_at
        ar_internal_metadata.updated_at

        schema_migrations.version

        secret_keyphrases.id
        secret_keyphrases.user_id
        secret_keyphrases.created_at
        secret_keyphrases.updated_at

        users.id
        users.role
        users.preferred_language
        users.created_at
        users.updated_at

        login_attempts.id
        login_attempts.user_id
        login_attempts.created_at
        login_attempts.success
      ],
      pii: %w[
        users.email
      ],
      secret: %w[
        secret_keyphrases.keyphrase
      ],
    }.freeze

    class << self
      def labeling
        tables_labeling
          .merge(views_labeling)
      end

      def columns
        execute_query(<<~SQL)
          SELECT table_schema, table_name, column_name
          FROM information_schema.columns
          WHERE
            table_schema NOT IN ('information_schema', 'pg_catalog') -- internals
          ORDER BY 1, 2, 3;
        SQL
      end

      def tables_labeling
        LABELED_COLUMNS
          .flat_map do |(label, schema_table_columns)|
            schema_table_columns.map do |stc|
              stc = stc.split(".")
              stc.unshift("public") if stc.length == 2
              [stc, label]
            end
          end.to_h
      end

      def views_labeling
        enforced_labels = view_enforced_labels

        view_columns
          .map do |c|
            [
              c,
              enforced_labels.fetch(c.slice(0, 2)),
            ]
          end.to_h
      end

      private

      def views
        execute_query(<<~SQL)
          SELECT table_schema, table_name
          FROM information_schema.views
          WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
        SQL
      end

      def view_columns
        execute_query(<<~SQL)
          SELECT c.table_schema, c.table_name, c.column_name
          FROM information_schema.columns c
          INNER JOIN information_schema.views v
              ON c.table_catalog = v.table_catalog
              AND c.table_schema = v.table_schema
              AND c.table_name = v.table_name
          WHERE c.table_schema NOT IN ('information_schema', 'pg_catalog')
          ORDER BY 1, 2, 3
        SQL
      end

      def view_column_usage
        execute_query(<<~SQL)
          SELECT c.view_schema, c.view_name, c.table_schema, c.table_name, c.column_name
          FROM information_schema.view_column_usage c
          INNER JOIN information_schema.tables t
              ON t.table_catalog = c.table_catalog
              AND t.table_schema = c.table_schema
              AND t.table_name = c.table_name
              AND t.table_type = 'BASE TABLE'
          WHERE c.table_schema NOT IN ('information_schema', 'pg_catalog')
        SQL
      end

      def view_dependencies
        execute_query(<<~SQL)
          SELECT DISTINCT c.view_schema, c.view_name, c.table_schema, c.table_name
          FROM information_schema.view_column_usage c
          INNER JOIN information_schema.tables t
              ON t.table_catalog = c.table_catalog
              AND t.table_schema = c.table_schema
              AND t.table_name = c.table_name
              AND t.table_type = 'VIEW'
          WHERE c.table_schema NOT IN ('information_schema', 'pg_catalog')
        SQL
      end

      def view_direct_parents
        view_dependencies
          .each_with_object({}) do |dep, result|
            child = dep.slice(0, 2)
            parent = dep.slice(2, 2)

            result[child] ||= Set[]
            result[child].add(parent)
          end
      end

      def view_used_column_labels
        view_column_usage
          .each_with_object({}) do |row, result|
            view = row.slice(0, 2)
            used_column_label = tables_labeling.fetch(row.slice(2, 3))

            result[view] ||= Set[]
            result[view].add(used_column_label)
          end
      end

      def view_enforced_labels
        used_column_labels = view_used_column_labels
        direct_parents = view_direct_parents
        label_sensivity_order = LABELED_COLUMNS.keys

        views.map do |view|
          labeling = Set[label_sensivity_order.first]

          with_ancestors(view, direct_parents).each do |parent|
            labeling |= used_column_labels.fetch(parent, [])
          end

          label = labeling.max_by { |l| label_sensivity_order.find_index(l) }

          [view, label]
        end.to_h
      end

      def with_ancestors(view, deps)
        all = Set[view]

        deps[view].to_a.each do |parent|
          all += with_ancestors(parent, deps)
        end

        all
      end

      def execute_query(query)
        ActiveRecord::Base.connection_pool.with_connection do |c|
          c.execute(query).values
        end
      end
    end
  end
end
