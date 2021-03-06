require File.expand_path('../boot', __FILE__)

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Fromthepage
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    config.i18n.available_locales = [:en, :es, :it, :pt,:fr]

    config.neato = '/usr/bin/env neato'
    config.encoding = 'utf-8'

    config.active_record.raise_in_transactional_callbacks = true

    config.api_only = false

    
    config.action_mailer.preview_path = "#{Rails.root}/lib/mailer_previews"

    # config.action_dispatch.default_headers = {
    #   'Access-Control-Allow-Origin' => '*',
    #   'Access-Control-Allow-Methods' => "*",
    #   'Access-Control-Request-Method' => "*",
    #   'Access-Control-Allow-Headers' => "*"
    # }

    #CORS requests
    config.middleware.use Rack::Cors

    #Cache store
    # config.cache_store = :memory_store, { size: 64.megabytes }
    config.cache_store = :file_store, "#{root}/tmp/cache/"

    config.action_view.field_error_proc = Proc.new { |html_tag, instance|
      class_attr_index = html_tag.index 'class="'

      if class_attr_index
        html_tag.insert class_attr_index+7, 'invalid '
      else
        html_tag.insert html_tag.index('>'), ' class="invalid"'
      end
    }

    if config.respond_to?(:sass)
      require File.expand_path('../../lib/sass_functions.rb', __FILE__)
    end
  end
end
