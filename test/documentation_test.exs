defmodule TypeSafe.DocumentationTest do
  use ExUnit.Case, async: true

  doctest TypeSafe
  doctest TypeSafe.Client
  doctest TypeSafe.Error
  doctest TypeSafe.Question
  doctest TypeSafe.Response
  doctest TypeSafe.Retry
end
