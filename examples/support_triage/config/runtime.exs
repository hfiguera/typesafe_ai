import Config

if config_env() != :test do
  config :support_triage, api_key: System.get_env("TYPESAFE_API_KEY")
end
