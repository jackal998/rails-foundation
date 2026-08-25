require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  #
  # READ THIS BEFORE ADDING AN UPLOAD. This container has no persistent volume,
  # and every deployment replaces it. :local therefore means uploaded files
  # survive until the next deploy and then vanish, while their attachment rows
  # stay in the database pointing at nothing -- a broken download rather than a
  # missing feature, and no error at the moment the data is lost. Nothing in
  # this application uploads anything yet, which is the only reason this is
  # safe today. The first feature that does needs an object-storage service
  # here, not a bigger disk.
  config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # This application can send exactly one kind of mail -- a password reset --
  # and until a domain and a mail provider exist it cannot deliver it. What was
  # actually wrong with the generated defaults was TWO things, not three: links
  # were built for example.com, and delivery went to localhost:25 where nothing
  # listens. A user would have been told to check their inbox and nothing would
  # ever arrive.
  #
  # The commit that changed this claimed a third fault -- that delivery errors
  # were swallowed -- and that was wrong. Action Mailer defaults
  # raise_delivery_errors to TRUE, and the generated line setting it to false
  # was commented out, so failures were already raising. The line below is
  # therefore explicit rather than corrective, and saying so here matters more
  # than the line does: an audit of this repository's own claims caught it, in
  # the commit whose subject was about statements not surviving being checked.
  #
  # Reset mail is sent with deliver_later, so a raised error fails that job and
  # is recorded in solid_queue_failed_executions. The web request is unaffected.
  config.action_mailer.raise_delivery_errors = true

  # No fake host. Rails raises "Missing host to link to" when a mail is
  # rendered without this, which is a visible failure; a link to example.com is
  # a wrong answer that looks like a right one.
  if ENV["APP_HOST"].present?
    config.action_mailer.default_url_options = { host: ENV["APP_HOST"], protocol: "https" }
  end

  # Driven by the environment rather than by editing this file, so that adding
  # a provider later is a deployment change and not a commit. Absent these,
  # Action Mailer keeps its default SMTP transport and fails loudly per above.
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SMTP_ADDRESS"),
      port: Integer(ENV.fetch("SMTP_PORT", 587)),
      user_name: ENV.fetch("SMTP_USER_NAME"),
      password: ENV.fetch("SMTP_PASSWORD"),
      authentication: :plain,
      enable_starttls_auto: true
    }
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
