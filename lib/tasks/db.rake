require 'restclient'
require 'fileutils'
require 'erb'
require 'readline'

namespace :db do
  desc "Seed with data (task manually created during the 3.0 upgrade, as it went missing)"
  task :seed => :environment do
    load(Rails.root.join("db", "seeds.rb"))
  end

  task :migrate => :environment do
    migration_db_name = [COUCHDB_CONFIG[:db_prefix], "migration", COUCHDB_CONFIG[:db_suffix]].join
    db = COUCHDB_SERVER.database!(migration_db_name)
    migration_ids = db.documents["rows"].select{|row| !row["id"].include?("_design")}.map{|row| row["id"]}
    migration_names = migration_ids.map{|id| db.get(id)[:name]}

    migrations_dir = "db/migration"
    Dir.new(Rails.root.join(migrations_dir)).entries.select { |file| file.ends_with? ".rb" }.sort.each do |file|
      if migration_names.include?(file) 
        puts "skipping migration: #{file} - already applied"
      else
        puts "Applying migration: #{file}"
        load(Rails.root.join(migrations_dir, file))
        db.save_doc({:name => file})
      end
    end
  end

  desc "Create system administrator for couchdb. This is needed only if you are interested to test out replications"
  task :create_couch_sysadmin do
    host = "http://127.0.0.1"
    port = "5984"
    puts "
      **************************************************************

        Welcome to RapidFTR couchdb system administrator setup!

      **************************************************************
      RapidFTR uses couchdb _users and _replication database for couchdb master to master replication.
      If you don't want to try the replication feature please hit CTRL + C.

      Else go on...
    "
    is_admin_available = get "Does your couchdb have admin credentials(yes/no) "
    raise "Invalid value #{is_admin_available}. Needed one of yes/no" unless %w[yes no].include?(is_admin_available)
    if is_admin_available == "yes"
      user_name = get "Enter username of your couchdb "
      password = get "Enter password of your couchdb "
    else
      user_name = ENV["COUCHDB_USERNAME"] || "rapidftr"
      password  = ENV["COUCHDB_PASSWORD"] || "rapidftr"
    end

    puts "
        Assuming you are running your couchdb server at http://127.0.0.1:5984/.
        If you are not, please change this @ #{__FILE__ }
         "

    begin
      RestClient.post "#{host}:#{port}/_session", "name=#{user_name}&password=#{password}", {:content_type => 'application/x-www-form-urlencoded'}
    rescue RestClient::Request::Unauthorized
      full_host = "#{host}:#{port}/_config/admins/#{user_name}"
      RestClient.put full_host, "\""+password+"\"", {:content_type => :json}
    end
    Rake::Task["db:create_couchdb_yml"].invoke(user_name, password)
  end

  desc "Create/Copy couchdb.yml from cocuhdb.yml.example"
  task :create_couchdb_yml, :user_name, :password  do |t, args|
    default_env = ENV['RAILS_ENV'] || "development"
    environments = ["development", "test", "cucumber", "production", "uat", "standalone", default_env].uniq
    user_name = ENV['couchdb_user_name'] || args[:user_name] || ""
    password = ENV['couchdb_password'] || args[:password] || ""

    default_config = {
      "host" => "localhost",
      "port" => 5984,
      "https_port" => 6984,
      "database_prefix" => "rapidftr_",
      "username" => user_name,
      "password" => password,
      "ssl" => false
    }

    couchdb_config = {}
    environments.each do |env|
      couchdb_config[env] = default_config.merge("database_suffix" => "_#{env}")
    end

    write_file Rails.root.to_s+"/config/couchdb.yml", couchdb_config.to_yaml
  end
end

def write_file name, content
  puts "Writing #{name}..."
  File.open(name, 'w') do |file|
    file.write content
  end
end

def get prompt
  Readline.readline prompt
end

