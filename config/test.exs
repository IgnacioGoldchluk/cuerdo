import Config

config :cuerdo, client_options: [plug: {Req.Test, Cuerdo.Client}, retry: false]
config :cuerdo, resolver_options: [plug: {Req.Test, Cuerdo.Resolver}, retry: false]
config :logger, :default_handler, false
config :ex_unit, exclude: [:integration]
