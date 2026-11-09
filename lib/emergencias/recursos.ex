defmodule Emergencias.Recursos do
  @moduledoc """
  GenServer del inventario de recursos.

  Todas las operaciones pasan por el buzón de este único proceso, que las
  atiende de una en una. Por eso, cuando dos solicitudes intentan tomar
  las últimas unidades de un recurso al mismo tiempo, la segunda ve el
  inventario ya descontado y recibe `{:error, :stock_insuficiente}`:
  la cantidad asignada nunca supera la disponible.

  La lógica vive en `Emergencias.Inventario` (funciones puras); este
  módulo mantiene el estado y lo persiste con `Emergencias.Storage`:

    * `recursos.txt`: estado actual, una línea por recurso.
    * `movimientos_recursos.txt`: historial de entradas, salidas y
      transferencias.

  Si falla la escritura en disco se registra un error en el log y el
  proceso sigue atendiendo con el estado en memoria.
  """

  use GenServer
  require Logger

  alias Emergencias.{Inventario, Resultado, Storage}
  alias Emergencias.Dominio.Recurso

  @archivo "recursos.txt"
  @archivo_movimientos "movimientos_recursos.txt"

  # --- API pública ----------------------------------------------------

  @doc "Inicia el servidor. Opción `:name` (por defecto el nombre del módulo)."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec registrar(String.t(), String.t(), String.t(), integer(), String.t(), String.t(), GenServer.server()) ::
          Resultado.t(Recurso.t())
  def registrar(codigo, nombre, categoria, cantidad, unidad, ubicacion, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:registrar, codigo, nombre, categoria, cantidad, unidad, ubicacion})
  end

  @spec entrada(String.t(), integer(), String.t(), GenServer.server()) :: Resultado.t(Recurso.t())
  def entrada(codigo, cantidad, detalle \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:entrada, codigo, cantidad, detalle})
  end

  @spec salida(String.t(), integer(), String.t(), GenServer.server()) :: Resultado.t(Recurso.t())
  def salida(codigo, cantidad, detalle \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:salida, codigo, cantidad, detalle})
  end

  @doc """
  Toma `cantidad` de un recurso por nombre (todo o nada). Devuelve
  `{:ok, [{codigo, cantidad_tomada}]}` o `{:error, :stock_insuficiente}`.
  """
  @spec tomar(String.t(), integer(), String.t(), GenServer.server()) ::
          Resultado.t([{String.t(), pos_integer()}])
  def tomar(nombre, cantidad, motivo \\ "", servidor \\ __MODULE__) do
    GenServer.call(servidor, {:tomar, nombre, cantidad, motivo})
  end

  @spec transferir(String.t(), String.t(), String.t(), integer(), GenServer.server()) ::
          Resultado.t(%{origen: Recurso.t(), destino: Recurso.t()})
  def transferir(codigo, origen, destino, cantidad, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:transferir, codigo, origen, destino, cantidad})
  end

  @spec consultar(String.t(), GenServer.server()) :: Resultado.t(Recurso.t())
  def consultar(codigo, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:consultar, codigo})
  end

  @doc "Lista recursos. Filtros: `:nombre`, `:ubicacion`, `:categoria`."
  @spec listar(keyword(), GenServer.server()) :: Resultado.t([Recurso.t()])
  def listar(filtros \\ [], servidor \\ __MODULE__) do
    GenServer.call(servidor, {:listar, filtros})
  end

  @spec disponible(String.t(), GenServer.server()) :: Resultado.t(non_neg_integer())
  def disponible(nombre, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:disponible, nombre})
  end

  @doc "Recursos con cantidad menor o igual al umbral."
  @spec criticos(non_neg_integer(), GenServer.server()) :: Resultado.t([Recurso.t()])
  def criticos(umbral \\ 20, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:criticos, umbral})
  end

  @doc "Historial de movimientos de un recurso, del más antiguo al más reciente."
  @spec historial(String.t(), GenServer.server()) :: Resultado.t([Recurso.movimiento()])
  def historial(codigo, servidor \\ __MODULE__) do
    GenServer.call(servidor, {:historial, codigo})
  end

  # --- Callbacks ------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, cargar()}

  @impl true
  def handle_call({:registrar, codigo, nombre, categoria, cantidad, unidad, ubicacion}, _from, mapa) do
    mapa
    |> Inventario.registrar(codigo, nombre, categoria, cantidad, unidad, ubicacion)
    |> ejecutar(mapa)
  end

  def handle_call({:entrada, codigo, cantidad, detalle}, _from, mapa) do
    mapa |> Inventario.entrada(codigo, cantidad, detalle) |> ejecutar(mapa)
  end

  def handle_call({:salida, codigo, cantidad, detalle}, _from, mapa) do
    mapa |> Inventario.salida(codigo, cantidad, detalle) |> ejecutar(mapa)
  end

  def handle_call({:tomar, nombre, cantidad, motivo}, _from, mapa) do
    mapa |> Inventario.tomar(nombre, cantidad, motivo) |> ejecutar(mapa)
  end

  def handle_call({:transferir, codigo, origen, destino, cantidad}, _from, mapa) do
    mapa |> Inventario.transferir(codigo, origen, destino, cantidad) |> ejecutar(mapa)
  end

  def handle_call({:consultar, codigo}, _from, mapa) do
    {:reply, Inventario.obtener(mapa, codigo), mapa}
  end

  def handle_call({:listar, filtros}, _from, mapa) do
    {:reply, {:ok, Inventario.listar(mapa, filtros)}, mapa}
  end

  def handle_call({:disponible, nombre}, _from, mapa) do
    {:reply, {:ok, Inventario.disponible(mapa, nombre)}, mapa}
  end

  def handle_call({:criticos, umbral}, _from, mapa) do
    {:reply, {:ok, Inventario.criticos(mapa, umbral)}, mapa}
  end

  def handle_call({:historial, codigo}, _from, mapa) do
    respuesta =
      case Inventario.obtener(mapa, codigo) do
        {:ok, recurso} -> {:ok, Enum.reverse(recurso.historial)}
        error -> error
      end

    {:reply, respuesta, mapa}
  end

  # --- Privadas -------------------------------------------------------

  # Aplica el resultado de una operación pura: si salió bien, guarda el
  # nuevo estado y lo persiste; si no, deja el estado intacto.
  defp ejecutar({:ok, valor, nuevo_mapa, movimientos}, _mapa) do
    case persistir(nuevo_mapa, movimientos) do
      :ok -> :ok
      {:error, razon} -> Logger.error("No se pudo guardar el inventario: #{inspect(razon)}")
    end

    {:reply, {:ok, valor}, nuevo_mapa}
  end

  defp ejecutar({:error, razon}, mapa), do: {:reply, {:error, razon}, mapa}

  defp persistir(mapa, movimientos) do
    filas =
      mapa
      |> Map.values()
      |> Enum.sort_by(& &1.codigo)
      |> Enum.map(&Inventario.a_fila/1)

    fecha = DateTime.utc_now() |> DateTime.to_iso8601()

    with :ok <- Storage.reescribir(@archivo, filas) do
      Enum.reduce_while(movimientos, :ok, fn {codigo, tipo, cantidad, detalle}, :ok ->
        case Storage.agregar(@archivo_movimientos, [codigo, tipo, cantidad, detalle, fecha]) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  # Reconstruye el inventario desde los archivos al arrancar.
  defp cargar do
    mapa =
      case Storage.leer(@archivo) do
        {:ok, filas} ->
          filas
          |> Enum.map(&Inventario.desde_fila/1)
          |> Enum.flat_map(fn
            {:ok, recurso} -> [recurso]
            :error -> []
          end)
          |> Map.new(&{&1.codigo, &1})

        {:error, _razon} ->
          %{}
      end

    case Storage.leer(@archivo_movimientos) do
      {:ok, filas} -> Enum.reduce(filas, mapa, &agregar_historial/2)
      {:error, _razon} -> mapa
    end
  end

  defp agregar_historial(fila, mapa) do
    with {:ok, codigo, movimiento} <- Inventario.desde_fila_movimiento(fila),
                 %{^codigo => %Recurso{} = recurso} <- mapa do
      Map.put(mapa, codigo, %{recurso | historial: [movimiento | recurso.historial]})
    else
      _ -> mapa
    end
  end
end
