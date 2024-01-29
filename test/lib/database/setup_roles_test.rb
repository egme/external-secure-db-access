require "test_helper"

class Database::SetupRolesTest < ActiveSupport::TestCase
  let(:password) { "such'S3cr3t" }

  test "example usage" do
    assert_equal(
      [
        [
          <<~SQL.strip,
            DO
            $do$
            BEGIN
              IF NOT EXISTS (
                SELECT FROM pg_catalog.pg_roles WHERE rolname = 'rouser'
              ) THEN
                CREATE ROLE rouser WITH
                  NOSUPERUSER
                  NOREPLICATION
                ;
              END IF;

              ALTER ROLE rouser WITH
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
        ],
        [
          <<~SQL.strip,
            GRANT USAGE ON SCHEMA public TO rouser
          SQL
        ],
        [
          <<~SQL.strip,
            REVOKE SELECT (email, password_hash)
            ON TABLE public.users
            FROM rouser
          SQL
        ],
        [
          <<~SQL.strip,
            GRANT SELECT (name)
            ON TABLE public.tags
            TO rouser
          SQL
        ],
        [
          <<~SQL.strip,
            GRANT SELECT (id)
            ON TABLE public.users
            TO rouser
          SQL
        ],
      ],
      Database::SetupRoles.new(
        roles: {
          rouser: {
            password: password,
            accessible_labels: [:normal],
          },
        },
        data_labeling: Database::DataLabeling.new(
          columns: [
            %w[public users id],
            %w[public users email],
            %w[public users password_hash],
            %w[public tags name],
          ],
          labeling: {
            %w[public users id] => :normal,
            %w[public users email] => :pii,
            %w[public users password_hash] => :secret,
            %w[public tags name] => :normal,
          },
        ),
      )
        .all_queries
        .to_a,
    )
  end
end
