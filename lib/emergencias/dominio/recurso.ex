defmodule Emergencias.Dominio.Recurso do
  @moduledoc "Recurso disponible en un centro de acopio, albergue o punto de atención."

  @type movimiento :: {:entrada | :salida | :transferencia, non_neg_integer(), String.t()}

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          categoria: String.t(),
          cantidad: non_neg_integer(),
          unidad: String.t(),
          ubicacion: String.t(),
          historial: [movimiento()]
        }

  @enforce_keys [:codigo, :nombre, :cantidad, :unidad, :ubicacion]
  defstruct codigo: nil,
            nombre: "",
            categoria: "",
            cantidad: 0,
            unidad: "",
            ubicacion: "",
            historial: []
end
