namespace :analytics do
  desc "Setup analytics bindings"
  task :setup_bindings, [] => [:environment, "db:migrate"] do |_task, _args|
    Database::Analytics.new("identity_service").setup!
  end
end
