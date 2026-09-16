key =
  case System.argv() do
    ["--keychain"] ->
      case System.cmd("/usr/bin/security", [
             "find-generic-password",
             "-s",
             "typesafe_ai",
             "-a",
             "api_key",
             "-w"
           ]) do
        {value, 0} -> String.replace_suffix(value, "\n", "")
        _failure -> Mix.raise("Could not read the development Keychain item")
      end

    ["--env"] ->
      System.fetch_env!("TYPESAFE_API_KEY")

    _other ->
      Mix.raise("Usage: mix run scripts/smoke.exs --keychain | --env")
  end

{:ok, client} = TypeSafe.Client.start_link(api_key: key, retry: [max_attempts: 1])

try do
  result =
    TypeSafe.system_one(client,
      state: "I was charged twice. Please refund the extra payment.",
      questions: %{
        "team" => TypeSafe.choice("Which team?", %{"billing" => nil, "technical" => nil}),
        "urgency" => TypeSafe.score("How urgent?", ["Routine", "Urgent"]),
        "refund" => TypeSafe.noul("Is a refund requested?")
      }
    )

  case result do
    {:ok, response} ->
      IO.puts("Live smoke passed: #{map_size(response.answers)} typed answers")
      IO.puts("Token usage: #{inspect(response.usage)}")

    {:error, error} ->
      Mix.raise("Live smoke failed: #{error.kind}, HTTP status #{inspect(error.status)}")
  end
after
  GenServer.stop(client)
end
