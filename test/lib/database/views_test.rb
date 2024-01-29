require "test_helper"

class Database::ViewsTest < ActiveSupport::TestCase
  describe "#rebuild!" do
    let(:views) { Database::Views.defined_views }

    describe "with defined views" do
      it "should not raise error" do
        assert_nothing_raised do
          Database::Views.rebuild!(views)
        end
      end
    end

    describe "with incorrectly defined view" do
      let(:views) do
        [
          OpenStruct.new(
            order: "1",
            schema: "test",
            name: "incorrect_view",
            query: "SELECT * FROM non_existing_table",
          ),
        ]
      end

      it "raises an error" do
        assert_raises Database::Views::RebuildError do
          Database::Views.rebuild!(views)
        end
      end
    end

    describe "with dependent views" do
      let(:views) do
        [
          OpenStruct.new(
            schema: "test",
            name: "parent_view",
            query: "SELECT * FROM information_schema.tables",
          ),
          OpenStruct.new(
            schema: "test",
            name: "dependent_view",
            query: "SELECT * FROM test.parent_view",
          ),
        ]
      end

      it "does not raise error with correct order" do
        assert_nothing_raised do
          Database::Views.rebuild!(views)
        end
      end

      it "raises an error with incorrect order" do
        assert_raises Database::Views::RebuildError do
          Database::Views.rebuild!(views.reverse)
        end
      end
    end

    describe "with absent view definition" do
      let(:create_view) do
        [
          OpenStruct.new(
            schema: "test",
            name: "view",
            query: "SELECT * FROM information_schema.tables",
          ),
        ]
      end
      let(:drop_view) { [] }

      before do
        Database::Views.rebuild!(create_view)

        assert_nothing_raised do
          ActiveRecord::Base.connection.execute("SELECT * FROM test.view")
        end
      end

      it "drops existing view" do
        Database::Views.rebuild!(drop_view)

        err = assert_raises ActiveRecord::StatementInvalid do
          ActiveRecord::Base.connection.execute("SELECT * FROM test.view")
        end

        assert_includes err.message, "relation \"test.view\" does not exist"
      end

      describe "with views created manually" do
        before do
          ActiveRecord::Base.connection.execute("COMMENT ON VIEW test.view IS 'CREATED MANUALLY'")
        end

        it "does not drop the view" do
          assert_nothing_raised do
            ActiveRecord::Base.connection.execute("SELECT * FROM test.view")
          end
        end
      end
    end
  end
end
