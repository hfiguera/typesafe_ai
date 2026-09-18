defmodule TypeSafe.Bench.Capture do
  @moduledoc false
  alias TypeSafe.Bench.Recordings
  alias TypeSafe.{Request, Response}

  # Fixed synthetic inputs and origin; never save credentials or failed bodies.
  def cases do
    ticket = %{
      "message" =>
        "The café terminal charged invoice INV-104 twice. Please refund the duplicate.",
      "amount" => 42.5,
      "currency" => "USD",
      "service_available" => true,
      "tags" => ["billing", "duplicate", "synthetic"],
      "customer_note" => nil
    }

    choice =
      TypeSafe.choice("Which team should handle this?", %{
        "billing" => "Payments and refunds",
        "technical" => "Software and hardware problems",
        "account" => "Login and account settings"
      })

    wide =
      TypeSafe.choice(
        "Which numbered warehouse bin contains the requested item?",
        Map.new(1..32, fn n -> {"bin_#{n}", "Bin #{n} contains item SKU-#{1000 + n}."} end)
      )

    score =
      TypeSafe.score("How urgent is this request?", [
        "Routine",
        "Needs attention today",
        "Service unavailable"
      ])

    score_ten =
      TypeSafe.score(
        "Estimate severity on this ordered scale.",
        Enum.map(0..9, fn n ->
          "Severity #{n}: #{n * 10} percent of users unable to use the service."
        end)
      )

    noul =
      TypeSafe.noul("Is a duplicate-charge refund requested?", %{
        "true" => "The customer asks to reverse a duplicate payment.",
        "false" => "There is no duplicate-payment refund request."
      })

    mixed = %{
      "team" => choice,
      "urgency" => score,
      "refund" => noul,
      "technical" =>
        TypeSafe.noul(%{
          "task" => "Does the ticket report a software failure?",
          "context" => ["Ignore payment-only problems."]
        }),
      "action" =>
        TypeSafe.choice("What should happen next?", %{
          "refund" => "Investigate duplicate payment",
          "repair" => "Repair device"
        }),
      "impact" =>
        TypeSafe.score("Assess operational impact.", [
          "No outage",
          "Partial outage",
          "Complete outage"
        ])
    }

    batch =
      Map.new(1..32, fn n ->
        question =
          case rem(n, 3) do
            0 -> wide
            1 -> score_ten
            2 -> noul
          end

        {"q#{n}", question}
      end)

    history =
      Enum.map_join(1..700, "\n", fn n ->
        "Event #{n}: synthetic terminal check completed; network healthy; no duplicate payment observed."
      end)

    [
      %{
        id: "noul_small",
        state: "Invoice INV-104 was charged twice. Please refund the duplicate.",
        questions: %{"refund" => TypeSafe.noul("Is a refund requested?")}
      },
      %{id: "choice_small", state: ticket, questions: %{"team" => choice}},
      %{id: "choice_wide", state: %{"requested_item" => "SKU-1017"}, questions: %{"bin" => wide}},
      %{id: "score_short", state: ticket, questions: %{"urgency" => score}},
      %{
        id: "score_ten",
        state: "About 70 percent of users cannot access the application.",
        questions: %{"severity" => score_ten}
      },
      %{id: "mixed_batch", state: ticket, questions: mixed},
      %{id: "batch_32", state: Map.put(ticket, "requested_item", "SKU-1017"), questions: batch},
      %{
        id: "large_state",
        state: history <> "\nLatest ticket:\n" <> JSON.encode!(ticket),
        questions: %{"team" => choice, "urgency" => score, "refund" => noul}
      }
    ]
  end

  def run(args) do
    {opts, [], []} = OptionParser.parse(args, strict: [live: :boolean, output: :string])
    if opts[:live] != true, do: raise("Capture requires --live; at most eight service requests")
    key = System.fetch_env!("TYPESAFE_API_KEY")
    if key == "", do: raise("A non-empty API key is required")
    directory = Keyword.fetch!(opts, :output)
    File.mkdir_p!(Path.dirname(directory))
    if File.mkdir(directory) != :ok, do: raise("Use a fresh output directory")

    inputs =
      Enum.map(cases(), fn c ->
        {:ok, request} =
          Request.prepare(state: c.state, questions: c.questions, model: "jev-latest")

        body = request |> Request.body("jev-latest") |> IO.iodata_to_binary()
        true = byte_size(body) < 130_000
        {c.id, request, body}
      end)

    manifest = %{
      kind: "live_system_one_captures",
      complete: false,
      captured_at: DateTime.to_iso8601(DateTime.utc_now()),
      origin: "https://api.typesafe.ai",
      protocol: "http2",
      requested_model: "jev-latest",
      planned_requests: length(inputs),
      submitted_requests: 0,
      cases: [],
      note:
        "Synthetic inputs; one request per case; retries disabled. Exact JSON entity bodies; only content-type/content-encoding headers retained. Capture durations include network/service work and possibly connection setup; one sample per shape is not a latency estimate."
    }

    save(directory, manifest)

    {:ok, pool} =
      Finch.start_link(name: __MODULE__, pools: %{:default => [protocols: [:http2], count: 1]})

    try do
      # HTTP/2 pools connect asynchronously. Wait using an unauthenticated HEAD,
      # so readiness polling never repeats a billable evaluation.
      {:ok, _} =
        TypeSafe.Bench.Transport.ready(
          fn _ -> Finch.request(Finch.build(:head, "https://api.typesafe.ai/"), __MODULE__) end,
          []
        )

      manifest =
        Enum.reduce(inputs, manifest, fn {id, prepared, body}, acc ->
          acc = %{acc | submitted_requests: acc.submitted_requests + 1}
          save(directory, acc)

          headers = [
            {"authorization", "Bearer " <> key},
            {"content-type", "application/json"},
            {"accept", "application/json"},
            {"accept-encoding", "identity"}
          ]

          request = Finch.build(:post, "https://api.typesafe.ai/v1/systemone", headers, body)

          {duration, result} =
            :timer.tc(fn ->
              Finch.request(request, __MODULE__,
                pool_timeout: 30_000,
                receive_timeout: 30_000,
                request_timeout: 30_000
              )
            end)

          {response_body, response_headers} =
            case result do
              {:ok, %{status: 200, body: response_body, headers: response_headers}} ->
                {response_body, response_headers}

              {:ok, %{status: status}} ->
                save(directory, Map.put(acc, :failure, %{kind: "http", status: status}))
                raise("Capture stopped at HTTP #{status}; failed response not saved")

              {:error, reason} ->
                kind =
                  if match?(%{reason: :pool_not_available}, reason),
                    do: "pool_not_available",
                    else: "transport"

                save(directory, Map.put(acc, :failure, %{kind: kind}))
                raise("Capture stopped after a transport failure; usage may be unknown")
            end

          true = byte_size(response_body) < 8_388_608
          false = String.contains?(body, key) or String.contains?(response_body, key)

          safe_headers =
            Enum.filter(response_headers, fn {name, _} ->
              name in ["content-type", "content-encoding"]
            end)

          true =
            Enum.all?(safe_headers, fn {name, value} ->
              name != "content-encoding" or value == "identity"
            end)

          {:ok, decoded} = Response.decode(response_body, prepared.schema)
          request_file = id <> ".request.json"
          response_file = id <> ".response.json"
          File.write!(Path.join(directory, request_file), body, [:exclusive])
          File.write!(Path.join(directory, response_file), response_body, [:exclusive])

          entry = %{
            id: id,
            status: 200,
            request_file: request_file,
            response_file: response_file,
            request_sha256: Recordings.digest(body),
            response_sha256: Recordings.digest(response_body),
            request_bytes: byte_size(body),
            response_bytes: byte_size(response_body),
            response_headers: Enum.map(safe_headers, fn {k, v} -> [k, v] end),
            response_model: decoded.model,
            usage: decoded.usage,
            capture_duration_ms: duration / 1000,
            questions: map_size(prepared.schema),
            question_types: Enum.frequencies_by(prepared.schema, fn {_, q} -> q.type end)
          }

          acc = %{acc | cases: acc.cases ++ [entry]}
          save(directory, acc)

          IO.puts(
            "Captured #{id}: #{entry.request_bytes} request bytes / #{entry.response_bytes} response bytes / #{entry.questions} questions"
          )

          acc
        end)

      save(directory, %{manifest | complete: true})
      IO.puts("Saved #{length(manifest.cases)} captures; no credentials saved")
    after
      Supervisor.stop(pool)
    end
  rescue
    _ ->
      raise(
        "Capture stopped; inspect the partial manifest for submitted request count. No automatic retries; failed requests may have unreported usage."
      )
  end

  defp save(directory, manifest),
    do: File.write!(Path.join(directory, "manifest.json"), JSON.encode!(manifest))
end
