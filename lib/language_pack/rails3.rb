require "language_pack"
require "language_pack/rails2"

# Rails 3 Language Pack. This is for all Rails 3.x apps.
class LanguagePack::Rails3 < LanguagePack::Rails2
  # detects if this is a Rails 3.x app
  # @return [Boolean] true if it's a Rails 3.x app
  def self.use?
    instrument "rails3.use" do
      rails_version = bundler.gem_version('railties')
      return false unless rails_version
      is_rails3 = rails_version >= Gem::Version.new('3.0.0') &&
                  rails_version <  Gem::Version.new('4.0.0')
      return is_rails3
    end
  end

  def name
    "Ruby/Rails"
  end

  def default_process_types
    instrument "rails3.default_process_types" do
      # let's special case thin here
      web_process = bundler.has_gem?("thin") ?
        "bundle exec thin start -R config.ru -e $RAILS_ENV -p $PORT" :
        "bundle exec rails server -p $PORT"

      super.merge({
        "web" => web_process,
        "console" => "bundle exec rails console"
      })
    end
  end

  def compile
    instrument "rails3.compile" do
      super
    end
  end

private

  def install_plugins
    instrument "rails3.install_plugins" do
      return false if bundler.has_gem?('rails_12factor')
      plugins = {"rails_log_stdout" => "rails_stdout_logging", "rails3_serve_static_assets" => "rails_serve_static_assets" }.
                 reject { |plugin, gem| bundler.has_gem?(gem) }
      return false if plugins.empty?
      plugins.each do |plugin, gem|
        warn "Injecting plugin '#{plugin}'"
      end
      warn "Add 'rails_12factor' gem to your Gemfile to skip plugin injection"
      LanguagePack::Helpers::PluginsInstaller.new(plugins.keys).install
    end
  end

  # runs the tasks for the Rails 3.1 asset pipeline
  def run_assets_precompile_rake_task
    instrument "rails3.run_assets_precompile_rake_task" do
      log("assets_precompile") do
        setup_database_url_env

        if File.exists?("public/assets/manifest.yml")
          puts "Detected manifest.yml, assuming assets were compiled locally"
        else
          FileUtils.mkdir_p('public')
          cache.load "public/assets"

          ENV["RAILS_GROUPS"] ||= "assets"
          ENV["RAILS_ENV"]    ||= "production"

          precompile = rake.task("assets:precompile")
          return true unless precompile.is_defined?
          time = Benchmark.realtime { pipe("env PATH=$PATH:bin bundle exec rake assets:precompile 2>&1") }

          if $?.success?
            log "assets_precompile", :status => "success"
            puts "Asset precompilation completed (#{"%.2f" % time}s)"

            # If 'turbo-sprockets-rails3' gem is available, run 'assets:clean_expired' and
            # cache assets if task was successful.
            if bundler.has_gem?('turbo-sprockets-rails3')
              log("assets_clean_expired") do
                run("env PATH=$PATH:bin bundle exec rake assets:clean_expired 2>&1")
                if $?.success?
                  log "assets_clean_expired", :status => "success"
                  cache.store "public/assets"
                else
                  log "assets_clean_expired", :status => "failure"
                  cache.clear "public/assets"
                end
              end
            else
              cache.clear "public/assets"
            end
          else
            log "assets_precompile", :status => "failure"
            puts "Precompiling assets failed, enabling runtime asset compilation"
            install_plugin("rails31_enable_runtime_asset_compilation")
            puts "Please see this article for troubleshooting help:"
            puts "http://devcenter.heroku.com/articles/rails31_heroku_cedar#troubleshooting"
          end
        end
      end
    end
  end

  # setup the database url as an environment variable
  def setup_database_url_env
    instrument "rails3.setup_database_url_env" do
      ENV["DATABASE_URL"] ||= begin
        # need to use a dummy DATABASE_URL here, so rails can load the environment
        scheme =
          if bundler.has_gem?("pg") || bundler.has_gem?("jdbc-postgres")
            "postgres"
          elsif bundler.has_gem?("mysql")
            "mysql"
          elsif bundler.has_gem?("mysql2")
            "mysql2"
          elsif bundler.has_gem?("sqlite3") || bundler.has_gem?("sqlite3-ruby")
            "sqlite3"
          end
        "#{scheme}://user:pass@127.0.0.1/dbname"
      end
    end
  end
end
