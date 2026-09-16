defmodule TypeSafeTest do
  use ExUnit.Case, async: true

  alias TypeSafe.Answer.{Choice, Noul, Score}
  alias TypeSafe.{Error, Question, Request, Response, Retry}

  test "encodes all primitives and structured criteria without atomizing labels" do
    questions = %{
      "topic" => TypeSafe.choice(%{question: "Which?"}, %{"a" => %{what: "A"}, "b" => nil}),
      "severity" => TypeSafe.score("How severe?", ["minor", ["major"]]),
      "flag" => TypeSafe.noul("Urgent?", %{"true" => "yes", "false" => "no"})
    }

    assert {:ok, request} = Request.prepare(state: %{text: "Olá 👩‍💻"}, questions: questions)
    body = request |> Request.body("jev-latest") |> IO.iodata_to_binary() |> JSON.decode!()
    assert body["state"] == %{"text" => "Olá 👩‍💻"}
    assert body["questions"]["topic"]["criteria"]["a"] == %{"what" => "A"}
    assert body["model"] == "jev-latest"
  end

  test "invalid options and non-JSON data return redacted errors before contacting a client" do
    for opts <- [
          nil,
          [state: "x"],
          [state: 1, questions: %{}],
          [state: "x", questions: %{a: TypeSafe.noul("?")}],
          [state: %{secret: self()}, questions: %{"q" => TypeSafe.noul("?")}],
          [state: "x", questions: %{"q" => TypeSafe.noul("?")}, timeout: 0],
          [state: "x", questions: %{"q" => TypeSafe.noul("?")}, api_key: "secret"]
        ] do
      assert {:error, %Error{kind: :validation} = error} = TypeSafe.system_one(:absent, opts)
      refute inspect(error) =~ "secret"
    end
  end

  test "question limits and complete Noul criteria are validated" do
    for question <- [
          TypeSafe.choice("?", %{}),
          TypeSafe.choice("?", Map.new(1..256, &{Integer.to_string(&1), nil})),
          TypeSafe.noul(nil),
          TypeSafe.score("?", ["one"]),
          TypeSafe.score("?", List.duplicate("level", 11)),
          TypeSafe.noul("?", %{"yes" => nil}),
          %Question{type: :unknown, instructions: "?"}
        ] do
      assert {:error, %Error{kind: :validation}} = Question.to_wire(%{"q" => question})
    end
  end

  test "responses decode into typed answers and preserve question and level keys" do
    {:ok, schema} =
      Question.to_wire(%{
        "choice" => TypeSafe.choice("?", %{"x" => nil, "y" => nil}),
        "score" => TypeSafe.score("?", ["low", "high"]),
        "noul" => TypeSafe.noul("?")
      })

    response = %{
      model: "jev",
      usage: %{input_tokens: 1, output_tokens: 2},
      answers: %{
        choice: %{type: "choice", choice: "x", probabilities: %{x: 0.8, y: 0.2}, confidence: 0.5},
        score: %{
          type: "score",
          score: 0.8,
          probabilities: %{"0" => 0.2, "1" => 0.8},
          legend: %{"0" => "low", "1" => "high"},
          confidence: 0.5
        },
        noul: %{type: "noul", noul: 0.9}
      }
    }

    assert {:ok, result} = Response.decode(JSON.encode!(response), schema)
    assert %Choice{choice: "x"} = result.answers["choice"]
    assert %Score{score: 0.8, probabilities: %{"0" => 0.2}} = result.answers["score"]
    assert %Noul{noul: 0.9} = result.answers["noul"]
    assert result.usage == %{input_tokens: 1, output_tokens: 2}
  end

  test "invalid JSON, missing answers and out-of-range values are rejected" do
    {:ok, schema} = Question.to_wire(%{"check" => TypeSafe.noul("?")})

    for body <- [
          "<html>no</html>",
          "{}",
          TypeSafe.TestServer.success(1.5),
          JSON.encode!(%{model: "x", answers: %{}, usage: %{input_tokens: 0, output_tokens: 0}})
        ] do
      assert {:error, %Error{kind: :invalid_response}} = Response.decode(body, schema)
    end
  end

  test "retry delay honors seconds and HTTP dates and bounds jitter" do
    {:ok, policy} = Retry.new(base_delay: 10, max_delay: 20)
    assert Retry.delay(policy, 1, [{"retry-after", "2"}]) == 2_000
    assert Retry.delay(policy, 1, [{"retry-after", "Wed, 01 Jan 2020 00:00:00 GMT"}]) == 0
    assert Retry.delay(policy, 5, [{"retry-after", "invalid"}]) in 0..20
    assert {:error, _} = Retry.new(max_attempts: 0)
  end
end
