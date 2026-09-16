defmodule SupportTriage.Application do
  @moduledoc "Supervises the shared TypeSafe connection; tickets use Jido's immutable agents."
  use Application

  @impl true
  def start(_type, _args) do
    children = client(Application.get_env(:support_triage, :api_key))
    Supervisor.start_link(children, strategy: :one_for_one, name: SupportTriage.Supervisor)
  end

  defp client(nil), do: []

  defp client(key) do
    [
      {TypeSafe.Client,
       name: SupportTriage.Client,
       api_key: key,
       max_concurrency: 4,
       max_queue: 12,
       retry: [max_attempts: 1]}
    ]
  end
end
