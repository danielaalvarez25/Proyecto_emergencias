defmodule Emergencias.Dominio.Persona do
  @moduledoc "Persona afectada, localizable por documento, nombre, zona o estado."

  @type estado ::
          :sin_informacion
          | :reportada
          | :localizada
          | :trasladada
          | :en_albergue
          | :reunificada

  @type t :: %__MODULE__{
          id: String.t(),
          documento: String.t(),
          nombre: String.t(),
          edad: non_neg_integer() | nil,
          zona: String.t(),
          estado: estado(),
          historial: [{estado(), String.t()}]
        }

  @enforce_keys [:id, :documento, :nombre]
  defstruct id: nil,
            documento: nil,
            nombre: "",
            edad: nil,
            zona: "",
            estado: :sin_informacion,
            historial: []
end
