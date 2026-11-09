defmodule Emergencias.Dominio.Usuario do
  @moduledoc "Usuario que participa en la coordinación de la emergencia."

  @type tipo :: :ciudadano | :voluntario | :coordinador | :administrador

  @type t :: %__MODULE__{
          username: String.t(),
          password: String.t(),
          nombre: String.t(),
          tipo: tipo(),
          zona: String.t(),
          conectado: boolean(),
          actividad: [String.t()]
        }

  @enforce_keys [:username, :password, :tipo]
  defstruct username: nil,
            password: nil,
            nombre: "",
            tipo: :ciudadano,
            zona: "",
            conectado: false,
            actividad: []
end
