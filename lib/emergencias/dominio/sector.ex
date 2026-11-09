defmodule Emergencias.Dominio.Sector do
  @moduledoc "Sector de una zona; contiene puntos de atención."

  alias Emergencias.Dominio.PuntoAtencion

  @type t :: %__MODULE__{
          nombre: String.t(),
          personas_estimadas: non_neg_integer(),
          puntos: [PuntoAtencion.t()]
        }

  @enforce_keys [:nombre]
  defstruct nombre: nil,
            personas_estimadas: 0,
            puntos: []
end
