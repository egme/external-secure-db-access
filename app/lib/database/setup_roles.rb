module Database
  class SetupRoles
    def self.from(source)
      new(data_labeling: source.data_labeling, roles: source.roles)
    end

    attr_reader :data_labeling, :roles

    def initialize(data_labeling:, roles:)
      @data_labeling = data_labeling
      @roles = roles
    end

    def all_queries(&blk)
      return enum_for(:all_queries) unless block_given?

      roles.each do |(role, config)|
        yield ensure_user_configured_sql(role, config[:password])

        allowed_columns, disallowed_columns = data_labeling.partition_by_labels(
          config[:accessible_labels],
        )

        grant_schema_usage_sql(role, allowed_columns).each(&blk)

        revoke_select_columns_sql(role, disallowed_columns).each(&blk)

        grant_select_columns_sql(role, allowed_columns).each(&blk)
      end
    end

    def grant_schema_usage_sql(role, schema_table_columns)
      schemas = schema_table_columns.map(&:first).uniq.join(", ")

      [["GRANT USAGE ON SCHEMA #{schemas} TO #{role}"]]
    end

    def grant_select_columns_sql(role, schema_table_columns)
      generate_privs_query(<<~SQL.strip, role, schema_table_columns)
        GRANT SELECT (%<comma_separated_columns>s)
        ON TABLE %<table>s
        TO %<role>s
      SQL
    end

    def revoke_select_columns_sql(role, schema_table_columns)
      generate_privs_query(<<~SQL.strip, role, schema_table_columns)
        REVOKE SELECT (%<comma_separated_columns>s)
        ON TABLE %<table>s
        FROM %<role>s
      SQL
    end

    def ensure_user_configured_sql(role, password)
      [
        <<~SQL.strip,
          DO
          $do$
          BEGIN
            IF NOT EXISTS (
              SELECT FROM pg_catalog.pg_roles WHERE rolname = '#{role}'
            ) THEN
              CREATE ROLE #{role} WITH
                NOSUPERUSER
                NOREPLICATION
              ;
            END IF;

            ALTER ROLE #{role} WITH
              NOCREATEDB
              NOCREATEROLE
              NOINHERIT
              NOBYPASSRLS
              LOGIN
              PASSWORD ?
              VALID UNTIL 'infinity'
            ;
          END
          $do$
        SQL
        password,
      ]
    end

    private

    def generate_privs_query(query_template, role, schema_table_columns)
      schema_table_columns
        .group_by { |vs| vs[0..1].join(".") }
        .transform_values { |l| l.map(&:last).sort }
        .sort
        .map do |(table, columns)|
          [
            format(
              query_template,
              role: role,
              table: table,
              comma_separated_columns: columns.join(", "),
            ),
          ]
        end
    end
  end
end
