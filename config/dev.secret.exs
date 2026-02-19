# Development secrets file
# This file is not checked into version control
import Config

# Configure your database
config :scr, SCR.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "scr_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Phoenix secret key base
secret_key_base =
  "development_secret_key_at_least_64_bytes_long_for_phoenix_security_12345678"

config :scr, SCRWeb.Endpoint,
  secret_key_base: secret_key_base
