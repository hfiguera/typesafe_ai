defmodule TypeSafe.Config do
  @moduledoc false
  alias TypeSafe.{Error, Retry}

  @derive {Inspect, only: [:model, :timeout, :max_concurrency, :max_queue]}
  defstruct [
    :api_key,
    :uri,
    :name,
    model: "jev-latest",
    timeout: 30_000,
    connect_timeout: 5_000,
    pool_size: 1,
    max_concurrency: 10,
    max_queue: 100,
    max_response_bytes: 8_388_608,
    protocols: [:http1, :http2],
    transport_opts: [],
    retry: %Retry{}
  ]

  @spec new(term()) :: {:ok, struct()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    allowed = [:base_url | Map.keys(%__MODULE__{}) -- [:__struct__, :uri]]

    with true <- Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in allowed)),
         {:ok, retry} <- Retry.new(Keyword.get(opts, :retry, [])),
         {:ok, uri} <- endpoint(Keyword.get(opts, :base_url, "https://api.typesafe.ai")) do
      config = struct(__MODULE__, Keyword.drop(opts, [:base_url, :retry]))
      config = %{config | uri: uri, retry: retry}
      if valid?(config), do: {:ok, config}, else: invalid()
    else
      _invalid -> invalid()
    end
  end

  def new(_opts), do: invalid()

  @spec connect_options(struct()) :: keyword()
  def connect_options(config) do
    tls = if config.uri.scheme == "https", do: tls_options(config.transport_opts), else: []

    [
      mode: :passive,
      protocols: config.protocols,
      client_settings: [enable_push: false],
      transport_opts:
        [
          timeout: config.connect_timeout,
          send_timeout: 1_000,
          send_timeout_close: true,
          nodelay: true
        ] ++ tls
    ]
  end

  defp endpoint(url) when is_binary(url) do
    with {:ok, uri} <- URI.new(url),
         true <-
           uri.scheme in ["https", "http"] and is_binary(uri.host) and uri.host != "" and
             is_nil(uri.userinfo) and is_nil(uri.query) and is_nil(uri.fragment) and
             is_integer(uri.port) and uri.port in 1..65_535 do
      {:ok, uri}
    else
      _invalid -> invalid()
    end
  end

  defp endpoint(_url), do: invalid()

  defp valid?(c) do
    key?(c.api_key) and model?(c.model) and
      Enum.all?(
        [c.timeout, c.connect_timeout, c.pool_size, c.max_concurrency, c.max_response_bytes],
        &positive?/1
      ) and
      is_integer(c.max_queue) and c.max_queue >= 0 and
      c.protocols in [[:http1], [:http2], [:http1, :http2], [:http2, :http1]] and
      Keyword.keyword?(c.transport_opts) and
      Enum.all?(Keyword.keys(c.transport_opts), &(&1 in [:cacerts, :cacertfile, :versions]))
  end

  defp key?(key) when is_binary(key),
    do: key != "" and not String.contains?(key, ["\r", "\n", <<0>>])

  defp key?(_key), do: false
  defp model?(model), do: is_binary(model) and model != "" and String.valid?(model)
  defp positive?(value), do: is_integer(value) and value > 0

  defp tls_options(opts) do
    if Keyword.has_key?(opts, :cacerts) or Keyword.has_key?(opts, :cacertfile) do
      opts
    else
      Keyword.put(opts, :cacerts, :public_key.cacerts_get())
    end
  end

  defp invalid, do: {:error, Error.new(:configuration, "Invalid client configuration")}
end
