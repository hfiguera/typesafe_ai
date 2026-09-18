defmodule TypeSafe.Bench.Recordings do
  @moduledoc false
  alias TypeSafe.{Question, Request, Response}
  def default_path, do: Path.expand("../fixtures/system_one", __DIR__)

  def load(directory \\ default_path()) do
    manifest = directory |> Path.join("manifest.json") |> File.read!() |> JSON.decode!()
    true = manifest["complete"] and manifest["kind"] == "live_system_one_captures"

    Map.new(manifest["cases"], fn entry ->
      request_body = verified_file(directory, entry["request_file"], entry["request_sha256"])
      response_body = verified_file(directory, entry["response_file"], entry["response_sha256"])
      request = JSON.decode!(request_body)
      input = input(request)
      {:ok, prepared} = Request.prepare(input)
      {:ok, response} = Response.decode(response_body, prepared.schema)
      true = response.model == entry["response_model"]

      {entry["id"],
       %{
         id: entry["id"],
         request: request,
         input: input,
         response_body: response_body,
         response: response,
         request_bytes: byte_size(request_body),
         response_bytes: byte_size(response_body),
         request_sha256: entry["request_sha256"],
         response_sha256: entry["response_sha256"]
       }}
    end)
  end

  def input(%{"state" => state, "questions" => questions, "model" => model}) do
    questions =
      Map.new(questions, fn {id, q} ->
        type = Map.fetch!(%{"choice" => :choice, "score" => :score, "noul" => :noul}, q["type"])

        {id,
         %Question{
           type: type,
           instructions: Map.fetch!(q, "instructions"),
           criteria: q["criteria"]
         }}
      end)

    [state: state, questions: questions, model: model]
  end

  def digest(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  defp verified_file(directory, name, hash) do
    true = Path.basename(name) == name
    body = directory |> Path.join(name) |> File.read!()
    true = digest(body) == hash
    body
  end
end
