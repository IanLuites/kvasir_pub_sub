defmodule Kvasir.PubSub.Server do
  @type t :: %__MODULE__{authorization: module, source: module}

  defstruct [:authorization, :source]
end
