if Code.ensure_loaded?(Ecto.ParameterizedType) do
  defmodule TypeID.Ecto do
    @behaviour Ecto.ParameterizedType
    @moduledoc false

    @doc false
    @impl true
    def init(opts), do: validate_opts!(opts)

    @doc false
    @impl true
    def type(%{column_type: column_type}), do: column_type

    @doc false
    @impl true
    def autogenerate(params) do
      params
      |> find_prefix()
      |> TypeID.new()
    end

    @doc false
    @impl true
    def cast(nil, _params), do: {:ok, nil}

    def cast(%TypeID{prefix: prefix} = tid, params) do
      if prefix == find_prefix(params) do
        {:ok, tid}
      else
        :error
      end
    end

    def cast(str, params) when is_binary(str) do
      prefix = find_prefix(params)

      if String.starts_with?(str, prefix) do
        TypeID.from_string(str)
      else
        with {:ok, uuid} <- Ecto.UUID.cast(str) do
          TypeID.from_uuid(prefix, uuid)
        end
      end
    end

    def cast(_, _), do: :error

    @doc false
    @impl true
    def dump(nil, _dumper, _params), do: {:ok, nil}

    def dump(%TypeID{} = tid, _, %{column_type: column_type} = params) do
      prefix = find_prefix(params)

      case {tid.prefix, column_type} do
        {^prefix, :string} -> {:ok, TypeID.to_string(tid)}
        {^prefix, :uuid} -> {:ok, TypeID.uuid_bytes(tid)}
        _ -> :error
      end
    end

    def dump(_, _, _), do: :error

    @impl true
    def embed_as(_format, _params) do
      :self
    end

    @impl true
    def equal?(term1, term2, _params), do: term1 == term2

    @doc false
    @impl true
    def load(nil, _, _), do: {:ok, nil}

    def load(str, _, %{column_type: :string} = params) do
      prefix = find_prefix(params)

      with {:ok, %TypeID{prefix: ^prefix}} = loaded <- TypeID.from_string(str) do
        loaded
      end
    end

    def load(<<_::128>> = uuid, _, %{column_type: :uuid} = params) do
      prefix = find_prefix(params)
      TypeID.from_uuid_bytes(prefix, uuid)
    end

    def load(<<_::288>> = uuid, _, %{column_type: :uuid} = params) do
      prefix = find_prefix(params)
      TypeID.from_uuid(prefix, uuid)
    rescue
      _ -> :error
    end

    def load(_, _, _), do: :error

    defp validate_opts!(opts) do
      primary_key = Keyword.get(opts, :primary_key, false)
      schema = Keyword.fetch!(opts, :schema)
      field = Keyword.fetch!(opts, :field)
      default_column_type = Application.get_env(:typeid_elixir, :default_column_type, :string)
      column_type = Keyword.get(opts, :column_type, default_column_type)
      prefix = Keyword.get(opts, :prefix)

      if primary_key do
        TypeID.validate_prefix!(prefix)
      end

      unless column_type in ~w[string uuid]a do
        raise ArgumentError, "`column_type` must be `:string` or `:uuid`"
      end

      if primary_key do
        %{
          primary_key: primary_key,
          schema: schema,
          field: field,
          prefix: prefix,
          column_type: column_type
        }
      else
        %{schema: schema, field: field, column_type: column_type, prefix: prefix}
      end
    end

    defp find_prefix(%{prefix: prefix}) when not is_nil(prefix), do: prefix

    defp find_prefix(%{schema: schema, field: field}) do
      %{related: schema, related_key: field} = schema.__schema__(:association, field)

      prefix =
        case schema.__schema__(:type, field) do
          {:parameterized, {TypeID, %{prefix: prefix}}} -> prefix
          {:parameterized, TypeID, %{prefix: prefix}} -> prefix
          _ -> nil
        end

      prefix
    end
  end
end
