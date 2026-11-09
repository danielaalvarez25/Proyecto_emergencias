defmodule Emergencias.Dominio.Zona do
  @moduledoc "Zona afectada. Jerarquía: zona -> sectores -> puntos de atención."

  alias Emergencias.Dominio.Sector

  @type nivel :: :critico | :alto | :medio | :bajo

  @type t :: %__MODULE__{
          codigo: String.t(),
          nombre: String.t(),
          nivel: nivel(),
          personas_estimadas: non_neg_integer(),
          sectores: [Sector.t()]
        }

  @enforce_keys [:codigo, :nombre, :nivel]
  defstruct codigo: nil,
            nombre: "",
            nivel: :medio,
            personas_estimadas: 0,
            sectores: []
end
