module Database
  class Analytics < Struct.new(:service_name)
    def setup!
      return unless analytics_cfg

      activate_fdw!
      setup_foreign_server!
      setup_user_mapping!
    end

    private

    def activate_fdw!
      remote_exec("CREATE EXTENSION IF NOT EXISTS postgres_fdw")
    end

    def setup_foreign_server!
      host, port, dbname = local_cfg.values_at(:host, :port, :dbname)

      remote_exec(<<~SQL)
        CREATE SERVER IF NOT EXISTS #{service_name} FOREIGN DATA WRAPPER postgres_fdw OPTIONS (
          host '#{host}',
          port '#{port}',
          dbname '#{dbname}'
        )
      SQL

      remote_exec(<<~SQL)
        ALTER SERVER #{service_name} OPTIONS (
          SET host '#{host}',
          SET port '#{port}',
          SET dbname '#{dbname}'
        )
      SQL
    end

    def setup_user_mapping!
      remote_exec(<<~SQL)
        CREATE USER MAPPING IF NOT EXISTS FOR #{analytics_cfg.fetch(:user)}
        SERVER #{service_name}
        OPTIONS (
          user 'looker',
          password '#{Config.database_password_looker}'
        )
      SQL

      remote_exec(<<~SQL)
        ALTER USER MAPPING FOR #{analytics_cfg.fetch(:user)}
        SERVER #{service_name}
        OPTIONS (
          SET user 'looker',
          SET password '#{Config.database_password_looker}'
        )
      SQL
    end

    def parse_dsn(dsn)
      matches = %r{^postgres:\/\/([^:]+):([^@]+)@([^\/]+)\/(\w+)(\?(.*))?$}.match(dsn)

      return unless matches

      {
        host: matches[3].split(":")[0],
        port: matches[3].split(":")[1] || 5432,
        dbname: matches[4],
        user: matches[1],
        password: matches[2],
      }
    end

    def analytics_cfg
      @analytics_cfg ||= parse_dsn(Config.analytics_dsn)
    end

    def local_cfg
      @local_cfg ||= parse_dsn(Config.database_url)
    end

    def remote_exec(query)
      @conn ||= PG.connect(analytics_cfg)
      result = @conn.exec(query)

      Rails.logger.info("ANALYTICS: #{query.chomp.gsub(/(\n|\s+)/, " ")} -> #{result.inspect}")

      result
    end
  end
end
