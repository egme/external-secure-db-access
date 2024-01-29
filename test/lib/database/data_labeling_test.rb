require "test_helper"

class Database::DataLabelingTest < ActiveSupport::TestCase
  let(:columns) do
    [
      %w[public users id],
      %w[public users email],
      %w[public users password_hash],
      %w[public tags name],
    ]
  end
  let(:labeling) do
    {
      %w[public users id] => :normal,
      %w[public users email] => :pii,
      %w[public users password_hash] => :secret,
      %w[public tags name] => :normal,
    }
  end
  let(:data_labeling) do
    Database::DataLabeling.new(
      columns: columns,
      labeling: labeling,
    )
  end

  describe "#errors" do
    it "has none on the base scenario" do
      assert_equal(
        { unknown: [], unlabeled: [] },
        data_labeling.errors,
      )
    end

    describe "when a column is added without being labeled" do
      let(:new_field) { %w[public new_table new_column] }

      before { columns.push(new_field) }

      it "identifies the new column" do
        assert_equal(
          { unknown: [], unlabeled: [new_field] },
          data_labeling.errors,
        )
      end
    end

    describe "when a column is removed without removing the label" do
      let(:removed_field) { %w[public users password_hash] }

      before { columns.delete(removed_field) }

      it "identifies the removed column" do
        assert_equal(
          { unknown: [removed_field], unlabeled: [] },
          data_labeling.errors,
        )
      end
    end
  end

  describe "#partition_by_labels" do
    it "works" do
      assert_equal(
        [
          [
            %w[public users id],
            %w[public users email],
            %w[public tags name],
          ],
          [
            %w[public users password_hash],
          ],
        ],
        data_labeling.partition_by_labels([:normal, :pii]),
      )
    end
  end
end
