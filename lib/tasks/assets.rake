# Prevent assets:precompile in development environment
if Rails.env.development?
  Rake::Task['assets:precompile'].clear

  namespace :assets do
    task :precompile do
      puts "assets:precompile is not supported in development environment"
      puts "To check js/css issues, please use: npm run build"
    end
  end
end

# Enhance db:seed task to create a marker file after execution
Rake::Task['db:seed'].enhance do
  marker_file = Rails.root.join('tmp/seeds_executed')
  File.write(marker_file, Time.now.to_s)
  puts "✓ Seeds executed at #{Time.now}"
end
