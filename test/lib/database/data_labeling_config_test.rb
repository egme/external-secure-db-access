require "test_helper"

class Database::DataLabelingConfigTest < ActiveSupport::TestCase
  def should_be_labeled_with(column, label)
    assert_equal label, Database::DataLabelingConfig.labeling.fetch(column)
  end

  test "all columns should be labeled" do
    assert_equal(
      {
        unknown: [],
        unlabeled: [],
      },
      Database::DataLabeling
        .from(Database::DataLabelingConfig)
        .errors
        .transform_values { |stcs| stcs.map { |stc| stc.join(".") } },
    )
  end

  describe "with views" do
    let(:views) { Database::Views.defined_views }

    before do
      Database::Views.rebuild!(views)
    end

    test "all columns should be labeled" do
      assert_equal(
        {
          unknown: [],
          unlabeled: [],
        },
        Database::DataLabeling
          .from(Database::DataLabelingConfig)
          .errors
          .transform_values { |stcs| stcs.map { |stc| stc.join(".") } },
      )
    end

    describe "with views referencing pii or secret columns" do
      let(:pii_column) do
        Database::DataLabelingConfig.tables_labeling
          .filter { |_, l| l == :pii }
          .keys
          .first
      end
      let(:secret_column) do
        Database::DataLabelingConfig.tables_labeling
          .filter { |_, l| l == :secret }
          .keys
          .first
      end
      let(:views) do
        [
          OpenStruct.new(
            order: "1",
            schema: "test",
            name: "pii_referencing_view",
            query: "
              SELECT #{pii_column.last} as col, 1 as other
              FROM #{pii_column.first}.#{pii_column.second}
            ",
          ),
          OpenStruct.new(
            order: "1",
            schema: "test",
            name: "secret_referencing_view",
            query: "
              SELECT #{secret_column.last} as col, 1 as other
              FROM #{secret_column.first}.#{secret_column.second}
            ",
          ),
          OpenStruct.new(
            order: "2",
            schema: "test",
            name: "pii_and_secret_referencing_view",
            query: "
              SELECT * from test.secret_referencing_view
              UNION
              SELECT * from test.pii_referencing_view
            ",
          ),
        ]
      end

      test "all columns of view referencing secret data labeled as :secret" do
        should_be_labeled_with(%w[test secret_referencing_view col], :secret)
        should_be_labeled_with(%w[test secret_referencing_view other], :secret)
      end

      test "all columns of view referencing pii data labeled as :pii" do
        should_be_labeled_with(%w[test pii_referencing_view col], :pii)
        should_be_labeled_with(%w[test pii_referencing_view other], :pii)
      end

      test "all columns of view referencing both pii and secret data labeled as :secret" do
        should_be_labeled_with(%w[test pii_and_secret_referencing_view col], :secret)
        should_be_labeled_with(%w[test pii_and_secret_referencing_view other], :secret)
      end
    end
  end
end
