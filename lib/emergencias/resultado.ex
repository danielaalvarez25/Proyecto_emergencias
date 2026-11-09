defmodule Emergencias.Resultado do
  @moduledoc """
  Contrato de retorno compartido por las dos personas del equipo.

  Las situaciones esperadas (id repetido, cantidad negativa, stock
  insuficiente, transición de estado inválida) NO lanzan excepciones:
  devuelven `{:error, razon}` con una razón en forma de átomo.
  """

  @type razon :: atom() | {atom(), term()}
  @type t(valor) :: {:ok, valor} | {:error, razon()}
  @type t :: t(term())
end
