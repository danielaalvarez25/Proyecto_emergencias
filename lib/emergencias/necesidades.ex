defmodule Emergencias.Necesidades do
  @moduledoc """
  GenServer de las necesidades puntuales.

  Mantiene el mapa de necesidades y atiende las solicitudes de una en una,
  lo que impide, por ejemplo, asignar dos veces la misma necesidad. Para
  descontar inventario delega en `Emergencias.Recursos.tomar/4`, que es
  quien garantiza que la cantidad asignada nunca supere la disponible.

  La lógica vive en `Emergencias.Solicitudes` (funciones puras). Este
  módulo mantiene el estado y lo persiste en `necesidades.txt` con
  `Emergencias.Storage`.

  Opciones de `start_link/1`: `:name` (por defecto el nombre del módulo) y
  `:recursos` (servidor de recursos a usar, por defecto `Emergencias.Recursos`).
  """

  use GenServer
  require Logger

  alias Emergencias.{Recursos, Resultado, Solicitudes, Storage}
  alias Emergencias.Dominio.Necesidad

  @archivo "necesidades.txt"

  # --- API pública ----------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Registra una necesidad. Devuelve `{:ok, %Necesidad{}}` con su id (`N001`...)."
  @spec registrar(term(), term(), term(), term(), term(), term()) :: Resultado.t(Necesidad.t())
  def registrar(tipo, cantidad, prioridad, zona, descripcion \\ "", responsable \\ "") do
    GenServer.call(__MODULE__, {:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable})
  end

  @spec consultar(term()) :: Resultado.t(Necesidad.t())
  def consultar(id), do: GenServer.call(__MODULE__, {:consultar, id})

  @doc "Lista necesidades por `:zona`, `:tipo`, `:prioridad` y/o `:estado`, ordenadas por prioridad."
  @spec listar(keyword()) :: Resultado.t([Necesidad.t()])
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Necesidades pendientes, de la más urgente a la menos urgente."
  @spec pendientes() :: Resultado.t([Necesidad.t()])
  def pendientes, do: GenServer.call(__MODULE__, :pendientes)

  @spec cambiar_estado(term(), term()) :: Resultado.t(Necesidad.t())
  def cambiar_estado(id, estado), do: GenServer.call(__MODULE__, {:cambiar_estado, id, estado})

  @doc """
  Asigna `cantidad` del recurso `nombre` a la necesidad (comando `assign_resource`).
  Errores: `:no_existe`, `:necesidad_cerrada`, `:ya_asignada`, `:cantidad_invalida`,
  `:excede_necesidad`, `:stock_insuficiente`.
  """
  @spec asignar(term(), String.t(), term()) :: Resultado.t(Necesidad.t())
  def asignar(id, nombre, cantidad), do: GenServer.call(__MODULE__, {:asignar, id, nombre, cantidad})

  @doc """
  Atiende las pendientes de la más urgente a la menos urgente con el
  inventario disponible. El recurso de cada necesidad es el que se llama
  igual que su tipo (`agua`, `alimentos`...). Devuelve las asignaciones
  hechas: `{:ok, [{id, recurso, cantidad}]}`.
  """
  @spec atender_por_prioridad() :: Resultado.t([{String.t(), String.t(), pos_integer()}])
  def atender_por_prioridad, do: GenServer.call(__MODULE__, :atender_por_prioridad)

  # --- Callbacks ------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok, %{necesidades: cargar(), recursos: Keyword.get(opts, :recursos, Recursos)}}
  end

  @impl true
  def handle_call({:registrar, tipo, cantidad, prioridad, zona, descripcion, responsable}, _from, estado) do
    case Solicitudes.registrar(estado.necesidades, tipo, cantidad, prioridad, zona, descripcion, responsable) do
      {:ok, necesidad, mapa} ->
        guardar(mapa)
        {:reply, {:ok, necesidad}, %{estado | necesidades: mapa}}

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  def handle_call({:consultar, id}, _from, estado) do
    {:reply, Solicitudes.obtener(estado.necesidades, id), estado}
  end

  def handle_call({:listar, filtros}, _from, estado) do
    {:reply, {:ok, Solicitudes.consultar(estado.necesidades, filtros)}, estado}
  end

  def handle_call(:pendientes, _from, estado) do
    {:reply, {:ok, Solicitudes.pendientes(estado.necesidades)}, estado}
  end

  def handle_call({:cambiar_estado, id, nuevo}, _from, estado) do
    case Solicitudes.cambiar_estado(estado.necesidades, id, nuevo) do
      {:ok, necesidad, mapa} ->
        guardar(mapa)
        {:reply, {:ok, necesidad}, %{estado | necesidades: mapa}}

      {:error, razon} ->
        {:reply, {:error, razon}, estado}
    end
  end

  def handle_call({:asignar, id, nombre, cantidad}, _from, estado) do
    case asignar_interno(estado, id, nombre, cantidad) do
      {:ok, necesidad, nuevo} -> {:reply, {:ok, necesidad}, nuevo}
      {:error, razon} -> {:reply, {:error, razon}, estado}
    end
  end

  def handle_call(:atender_por_prioridad, _from, estado) do
    pendientes = Solicitudes.pendientes(estado.necesidades)
    plan = Solicitudes.planificar(pendientes, disponibles_por_tipo(pendientes, estado.recursos))

    {hechas, nuevo} =
      Enum.reduce(plan, {[], estado}, fn {id, recurso, cantidad}, {acumuladas, actual} ->
        case asignar_interno(actual, id, recurso, cantidad) do
          {:ok, _necesidad, siguiente} -> {[{id, recurso, cantidad} | acumuladas], siguiente}
          {:error, _razon} -> {acumuladas, actual}
        end
      end)

    {:reply, {:ok, Enum.reverse(hechas)}, nuevo}
  end

  # --- Privadas -------------------------------------------------------

  # Valida la necesidad, descuenta el inventario y anota la asignación.
  # El orden importa: primero se valida (sin tocar nada) y solo después se
  # toma inventario, así un rechazo nunca deja recursos descontados.
  defp asignar_interno(estado, id, nombre, cantidad) do
    with {:ok, necesidad} <- Solicitudes.puede_asignar(estado.necesidades, id, cantidad),
         {:ok, partes} <- Recursos.tomar(nombre, cantidad, necesidad.id, estado.recursos),
         {:ok, actualizada, mapa} <-
           Solicitudes.aplicar_asignacion(estado.necesidades, necesidad.id, partes) do
      guardar(mapa)
      {:ok, actualizada, %{estado | necesidades: mapa}}
    end
  end

  defp disponibles_por_tipo(pendientes, recursos) do
    pendientes
    |> Enum.map(&Atom.to_string(&1.tipo))
    |> Enum.uniq()
    |> Map.new(fn nombre ->
      {:ok, cantidad} = Recursos.disponible(nombre, recursos)
      {nombre, cantidad}
    end)
  end

  defp guardar(mapa) do
    filas =
      mapa
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&Solicitudes.a_fila/1)

    case Storage.reescribir(@archivo, filas) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudieron guardar las necesidades: #{inspect(razon)}")
    end
  end

  defp cargar do
    case Storage.leer(@archivo) do
      {:ok, filas} ->
        filas
        |> Enum.map(&Solicitudes.desde_fila/1)
        |> Enum.flat_map(fn
          {:ok, necesidad} -> [necesidad]
          :error -> []
        end)
        |> Map.new(&{&1.id, &1})

      {:error, _razon} ->
        %{}
    end
  end
end
