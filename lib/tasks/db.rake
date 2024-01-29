namespace :db do
  desc "Setup extra roles' configuration"
  task :setup_roles, [] => [:environment, "db:migrate"] do |_task, _args|
    Database::SetupRoles
      .from(Database::RolesConfig)
      .all_queries
      .each do |query|
        ActiveRecord::Base.connection_pool.with_connection do |c| 
          c.execute(ActiveRecord::Base.sanitize_sql(query))
        end
      end
  end

  desc "Re-build views"
  task :rebuild_views, [] => [:environment] do |_task, _args|
    Database::Views.setup_looker!

    Database::Views.rebuild!(
      Database::Views.defined_views,
    )
  end
end

Rake::Task["db:migrate"].enhance do
  Rake::Task["db:rebuild_views"].invoke
end
