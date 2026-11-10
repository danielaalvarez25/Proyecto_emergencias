defmodule Emergencias.Albergues do
  @moduledoc """
  GenServer de los albergues.

  Atiende las solicitudes de una en una, así que aunque lleguen muchos
  ingresos a la vez, la ocupación nunca supera la capacidad máxima: cada
  ingreso ve la ocupación ya actualizada por el anterior.

  La lógica vive en `Emergencias.Cupos` (funciones puras). Este módulo
  mantiene el estado y lo persiste en `albergues.txt` con
  `Emergencias.Storage`.

  Para asociar recursos y necesidades comprueba que existan consultando a
  `Emergencias.Recursos` y `Emergencias.Necesidades`; por eso deben
  arrancar antes que este proceso.

  Opciones de `start_link/1`: `:name` (por defecto el nombre del módulo) y
  `:recursos` (servidor de recursos a consultar, por defecto `Emergencias.Recursos`).
  """

  use GenServer
  require Logger

  alias Emergencias.{Cupos, Necesidades, Recursos, Resultado, Storage}
  alias Emergencias.Dominio.Albergue

  @archivo "albergues.txt"

  # --- API pública ----------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Registra un albergue (comando `register_shelter`)."
  @spec registrar(term(), term(), term(), term(), term()) :: Resultado.t(Albergue.t())
  def registrar(codigo, nombre, zona, capacidad, ocupacion \\ 0) do
    GenServer.call(__MODULE__, {:registrar, codigo, nombre, zona, capacidad, ocupacion})
  end

  @doc "Datos del albergue (comando `check_shelter`). Usa `Cupos.resumen/1` para mostrarlo."
  @spec consultar(term()) :: Resultado.t(Albergue.t())
  def consultar(codigo), do: GenServer.call(__MODULE__, {:consultar, codigo})

  @doc "Lista albergues. Filtro opcional: `zona: \"...\"`."
  @spec listar(keyword()) :: Resultado.t([Albergue.t()])
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Ingreso de una persona (comando `register_entry`)."
  @spec ingresar(term(), term()) :: Resultado.t(Albergue.t())
  def ingresar(codigo, documento), do: GenServer.call(__MODULE__, {:ingresar, codigo, documento})

  @doc "Salida de una persona (comando `register_exit`)."
  @spec salir(term(), term()) :: Resultado.t(Albergue.t())
  def salir(codigo, documento), do: GenServer.call(__MODULE__, {:salir, codigo, documento})

  @doc "Albergues con mayor porcentaje de ocupación."
  @spec reporte_ocupacion(pos_integer()) :: Resultado.t([Albergue.t()])
  def reporte_ocupacion(limite \\ 3), do: GenServer.call(__MODULE__, {:reporte_ocupacion, limite})

  @doc "Albergue donde está alojada una persona, si lo está."
  @spec donde_esta(term()) :: Resultado.t(String.t())
  def donde_esta(documento), do: GenServer.call(__MODULE__, {:donde_esta, documento})

  @doc "Asocia un recurso existente (por código) al albergue."
  @spec asociar_recurso(term(), term()) :: Resultado.t(Albergue.t())
  def asociar_recurso(codigo, recurso), do: GenServer.call(__MODULE__, {:asociar_recurso, codigo, recurso})

  @doc "Asocia una necesidad existente (por id) al albergue."
  @spec asociar_necesidad(term(), term()) :: Resultado.t(Albergue.t())
  def asociar_necesidad(codigo, necesidad),
    do: GenServer.call(__MODULE__, {:asociar_necesidad, codigo, necesidad})

  # --- Callbacks ------------------------------------------------------

  @impl true
  def init(opts) do
    {:ok, %{albergues: cargar(), recursos: Keyword.get(opts, :recursos, Recursos)}}
  end

  @impl true
  def handle_call({:registrar, codigo, nombre, zona, capacidad, ocupacion}, _from, estado) do
    estado.albergues
    |> Cupos.registrar(codigo, nombre, zona, capacidad, ocupacion)
    |> aplicar(estado)
  end

  def handle_call({:consultar, codigo}, _from, estado) do
    {:reply, Cupos.obtener(estado.albergues, codigo), estado}
  end

  def handle_call({:listar, filtros}, _from, estado) do
    {:reply, {:ok, Cupos.listar(estado.albergues, filtros)}, estado}
  end

  def handle_call({:ingresar, codigo, documento}, _from, estado) do
    estado.albergues |> Cupos.ingresar(codigo, documento) |> aplicar(estado)
  end

  def handle_call({:salir, codigo, documento}, _from, estado) do
    estado.albergues |> Cupos.salir(codigo, documento) |> aplicar(estado)
  end

  def handle_call({:reporte_ocupacion, limite}, _from, estado) do
    {:reply, {:ok, Cupos.mayor_ocupacion(estado.albergues, limite)}, estado}
  end

  def handle_call({:donde_esta, documento}, _from, estado) do
    respuesta =
      case Cupos.donde_esta(estado.albergues, documento) do
        {:ok, codigo} -> {:ok, codigo}
        :ninguno -> {:error, :no_alojada}
      end

    {:reply, respuesta, estado}
  end

  def handle_call({:asociar_recurso, codigo, recurso}, _from, estado) do
    case Recursos.consultar(to_string(recurso), estado.recursos) do
      {:ok, _recurso} ->
        estado.albergues |> Cupos.asociar_recurso(codigo, recurso) |> aplicar(estado)

      {:error, _razon} ->
        {:reply, {:error, :recurso_no_existe}, estado}
    end
  end

  def handle_call({:asociar_necesidad, codigo, necesidad}, _from, estado) do
    case Necesidades.consultar(necesidad) do
      {:ok, encontrada} ->
        estado.albergues |> Cupos.asociar_necesidad(codigo, encontrada.id) |> aplicar(estado)

      {:error, _razon} ->
        {:reply, {:error, :necesidad_no_existe}, estado}
    end
  end

  # --- Privadas -------------------------------------------------------

  # Si la operación pura salió bien, guarda el nuevo estado y lo persiste;
  # si no, deja el estado intacto.
  defp aplicar({:ok, albergue, mapa}, estado) do
    guardar(mapa)
    {:reply, {:ok, albergue}, %{estado | albergues: mapa}}
  end

  defp aplicar({:error, razon}, estado), do: {:reply, {:error, razon}, estado}

  defp guardar(mapa) do
    filas =
      mapa
      |> Map.values()
      |> Enum.sort_by(& &1.codigo)
      |> Enum.map(&Cupos.a_fila/1)

    case Storage.reescribir(@archivo, filas) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudieron guardar los albergues: #{inspect(razon)}")
    end
  end

  defp cargar do
    case Storage.leer(@archivo) do
      {:ok, filas} ->
        filas
        |> Enum.map(&Cupos.desde_fila/1)
        |> Enum.flat_map(fn
          {:ok, albergue} -> [albergue]
          :error -> []
        end)
        |> Map.new(&{&1.codigo, &1})

      {:error, _razon} ->
        %{}
    end
  end
end
