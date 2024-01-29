module Database
  class RolesConfig
    def self.data_labeling
      DataLabeling.from(DataLabelingConfig)
    end

    def self.roles
      {
        looker: {
          password: Config.database_password_looker,
          accessible_labels: %i[normal],
        },
        spy: {
          password: Config.database_password_spy,
          accessible_labels: %i[pii normal],
        },
      }
        .reject { |_role_name, config| config[:password].blank? }
    end
  end
end
