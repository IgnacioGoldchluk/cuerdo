import Config

config :cuerdo, run_cli: false, stdio_enabled: false
config :cuerdo, client_options: [plug: {Req.Test, Cuerdo.Client}, retry: false]
config :cuerdo, resolver_options: [plug: {Req.Test, Cuerdo.Resolver}, retry: false]
config :cuerdo, :screen, Cuerdo.CLI.Screen.Dummy

config :logger, :default_handler, false
config :ex_unit, exclude: [:integration]
