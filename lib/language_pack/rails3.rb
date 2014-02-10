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
        if File.exists?("public/assets/manifest.yml")
          puts "Detected manifest.yml, assuming assets were compiled locally"
          return true
        end

        precompile = rake.task("assets:precompile")
        return true unless precompile.is_defined?

        topic("Preparing app for Rails asset pipeline")

        precompile.invoke(env: rake_env)

        if precompile.success?
          log "assets_precompile", :status => "success"
          puts "Asset precompilation completed (#{"%.2f" % precompile.time}s)"

          # If 'turbo-sprockets-rails3' gem is available, run
          # 'assets:clean_expired' and cache assets if task was successful.
          if gem_is_bundled?('turbo-sprockets-rails3')
            log("assets_clean_expired") do
              clean_expired = rake.task('assets:clean_expired')
              return true unless clean_expired.is_defined?

              if clean_expired.success?
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
          cache.clear "public/assets"
          error "Precompiling assets failed."
        end
      end
    end
  end

  def rake_env
    if user_env_hash.empty?
      default_env = {
        "RAILS_GROUPS" => ENV["RAILS_GROUPS"] || "assets",
        "RAILS_ENV"    => ENV["RAILS_ENV"]    || "production",
        "DATABASE_URL" => database_url
      }
    else
      default_env = {
        "RAILS_GROUPS" => "assets",
        "RAILS_ENV"    => "production",
        "DATABASE_URL" => database_url
      }
    end
    default_env.merge(user_env_hash)
  end

  # generate a dummy database_url
  def database_url
    instrument "rails3.setup_database_url_env" do
      # need to use a dummy DATABASE_URL here, so rails can load the environment
      return env("DATABASE_URL") if env("DATABASE_URL")
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
