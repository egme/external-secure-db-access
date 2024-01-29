module Database
  class DataLabeling
    def self.from(source)
      new(labeling: source.labeling, columns: source.columns)
    end

    attr_reader :labeling, :columns

    def initialize(labeling:, columns:)
      @labeling = labeling
      @columns = columns
    end

    def errors
      labeled_columns = labeling.keys
      {
        unknown: labeled_columns - columns,
        unlabeled: columns - labeled_columns,
      }
    end

    def partition_by_labels(labels)
      columns.partition do |table_column|
        labels.include? labeling.fetch(table_column)
      end
    end
  end
end
