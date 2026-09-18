# A fresh BEAM can trust the private fixture CA without changing the OS trust store.
# This is an offline-only compatibility probe, not a performance ranking.
alias TypeSafe.Bench.{Recordings, Runner, Server}
{opts, [], []} = OptionParser.parse(System.argv(), strict: [output: :string])
ca = Path.expand("../test/fixtures/ca.pem")
:ok = :public_key.cacerts_load(ca)
recordings = Recordings.load()
{:ok, server} = Server.start_link(0, recordings: recordings, observer: self())
{:ok, {_, port}} = ThousandIsland.listener_info(server)

rows =
  try do
    for {id, recording} <- Enum.sort(recordings) do
      client =
        TypeSafeSDK.new_client(
          api_key: "benchmark-only",
          model: recording.request["model"],
          base_url: "https://localhost:#{port}/0/recorded/#{id}",
          retry: false,
          timeout_ms: 1000
        )

      questions =
        Map.new(recording.input[:questions], fn {id, q} ->
          question =
            case q.type do
              :noul -> TypeSafeSDK.noul(q.instructions, criteria: q.criteria)
              :choice -> TypeSafeSDK.choice(q.instructions, Enum.sort(q.criteria))
              :score -> TypeSafeSDK.score(q.instructions, q.criteria)
            end

          {id, question}
        end)

      {:ok, response} = TypeSafeSDK.evaluate(client, recording.input[:state], questions)

      observed =
        receive do
          {:fixture_request, observed} -> observed
        after
          1000 -> raise "missing fixture observation"
        end

      true = Server.canonical_request(observed.body) == recording.request
      true = response.model == recording.response.model
      true = response.usage.input_tokens == recording.response.usage.input_tokens
      true = response.usage.output_tokens == recording.response.usage.output_tokens

      for {key, expected} <- recording.response.answers do
        actual = Map.fetch!(response.answers, key)

        for field <- [:noul, :choice, :score, :confidence, :probabilities] do
          if Map.has_key?(expected, field) do
            value = Map.fetch!(actual, field)

            value =
              if is_map(value),
                do: Map.new(value, fn {k, v} -> {to_string(k), v} end),
                else: value

            true = value == Map.fetch!(expected, field)
          end
        end
      end

      %{
        recording: id,
        outcome: "ok",
        protocol: observed.protocol,
        request_sha256: recording.request_sha256,
        response_sha256: recording.response_sha256
      }
    end
  after
    Supervisor.stop(server)
  end

File.write!(
  Keyword.fetch!(opts, :output),
  JSON.encode!(%{
    kind: "native_sdk_private_ca_probe",
    environment: Runner.environment(),
    rows: rows,
    note:
      "Native SDK transport; VM-local private CA trust only; no OS CA installation and no verification bypass."
  })
)
