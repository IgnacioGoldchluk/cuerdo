import Config

config :rock_solid, cache_enabled: false

config :cuerdo, :screen, Cuerdo.CLI.Screen.Terminal

import_config "#{config_env()}.exs"
