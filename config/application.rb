require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Gemotion
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # Set default locale to French and available locales to French and English
    config.i18n.default_locale = :fr
    config.i18n.available_locales = %i[fr en]

    config.active_job.queue_adapter = :sidekiq
    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.active_storage.previewers += [ActiveStorage::Previewer::VideoPreviewer]
    config.active_storage.content_types_allowed_inline += %w[audio/mpeg audio/mp3 audio/mp4 audio/wav audio/x-wav]
    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Default values for texts and transitions
    config.transition_duration = 1
    config.text_start_time = 1
    config.text_duration = 3
  end
end
