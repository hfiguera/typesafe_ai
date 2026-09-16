import Config

if config_env() in [:dev, :test] do
  config :credence, assumptions: :strict
end
