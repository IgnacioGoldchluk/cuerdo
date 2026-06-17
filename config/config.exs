import Config

config :rock_solid, cache_enabled: false

import_config "#{config_env()}.exs"
