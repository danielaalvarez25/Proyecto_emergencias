defmodule Emergencias.Dominio.Albergue do
  @moduledoc "Albergue con capacidad máxima y registro de personas alojadas."

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          zona: String.t(),
          capacidad: non_neg_integer(),
          ocupacion: non_neg_integer(),
          personas: MapSet.t(String.t()),
          recursos: [String.t()],
          necesidades: [String.t()]
        }

  @enforce_keys [:codigo, :nombre, :zona, :capacidad]
  defstruct codigo: nil,
            nombre: "",
            zona: nil,
            capacidad: 0,
            ocupacion: 0,
            personas: MapSet.new(),
            recursos: [],
            necesidades: []
end
