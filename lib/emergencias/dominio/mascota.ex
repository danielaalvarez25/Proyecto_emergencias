defmodule Emergencias.Dominio.Mascota do
  @moduledoc "Reporte de mascota perdida o encontrada."

  @type tipo :: :perdida | :encontrada
  @type estado :: :activa | :posible_coincidencia | :resuelta

  @type t :: %__MODULE__{
          id: String.t(),
          tipo: tipo(),
          especie: String.t(),
          nombre: String.t(),
          caracteristicas: String.t(),
          color: String.t(),
          tamano: String.t(),
          zona: String.t(),
          contacto: String.t(),
          estado: estado(),
          coincidencia: String.t() | nil
        }

  @enforce_keys [:id, :tipo, :especie, :zona]
  defstruct id: nil,
            tipo: :perdida,
            especie: "",
            nombre: "desconocido",
            caracteristicas: "",
            color: "",
            tamano: "",
            zona: nil,
            contacto: "",
            estado: :activa,
            coincidencia: nil
end
