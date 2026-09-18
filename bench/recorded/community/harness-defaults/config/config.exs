import Config

# Offline benchmarks always supply a dummy key explicitly.
config :req_llm, load_dotenv: false

# The API's overload response needs a reason phrase on HTTP/1 fixtures.
config :plug, :statuses, %{529 => "Overloaded"}
