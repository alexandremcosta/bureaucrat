defmodule WebDoc.ApiBlueprintWriter do
  @moduledoc """
  Writes an API blueprint compatible file.
  Copied from Bureaucrat.ApiBlueprintWriter.

  Changes:
  - Remove controller name from action
  - Fix body `&nbsp;&nbsp;` html on code tag
  """

  alias Bureaucrat.JSON

  def write(records, path) do
    file = File.open!(path <> ".md", [:write, :utf8])
    records = group_records(records)
    title = Application.get_env(:bureaucrat, :title)
    puts(file, "# #{title}\n\n")
    write_intro(path, file)
    write_api_doc(records, file)
    File.close(file)
  end

  defp write_intro(path, file) do
    intro_file_path =
      [
        # /path/to/API.md -> /path/to/API_INTRO.md
        String.replace(path, ~r/\.md$/i, "_INTRO\\0"),
        # /path/to/api.md -> /path/to/api_intro.md
        String.replace(path, ~r/\.md$/i, "_intro\\0"),
        # /path/to/API -> /path/to/API_INTRO
        "#{path}_INTRO",
        # /path/to/api -> /path/to/api_intro
        "#{path}_intro"
      ]
      # which one exists?
      |> Enum.find(nil, &File.exists?/1)

    if intro_file_path do
      file
      |> puts(File.read!(intro_file_path))
      |> puts("\n\n## Endpoints\n\n")
    else
      puts(file, "# API Documentation\n")
    end
  end

  defp write_api_doc(records, file) do
    Enum.each(records, fn {controller, actions} ->
      %{request_path: path} = actions |> Enum.at(0) |> elem(1) |> List.first()
      puts(file, "\n# Group #{controller}")
      puts(file, "## #{controller} [#{path}]")

      Enum.each(actions, fn {action, records} ->
        write_action(action, controller, Enum.reverse(records), file)
      end)
    end)

    puts(file, "")
  end

  defp write_action(action, _controller, records, file) do
    test_description = "#{action}"
    record_request = Enum.at(records, 0)
    method = record_request.method

    file
    |> puts("### #{test_description} [#{method} #{anchor(record_request)}]")
    |> puts("\n\n #{Keyword.get(record_request.assigns.bureaucrat_opts, :detail, "")}")

    write_parameters(record_request.path_params, file)

    records
    |> sort_by_status_code
    |> Enum.each(&write_example(&1, file))
  end

  defp write_parameters(path_params, _file) when map_size(path_params) == 0, do: nil

  defp write_parameters(path_params, file) do
    puts(file, "\n+ Parameters\n#{formatted_params(path_params)}")

    Enum.each(path_params, fn {param, value} ->
      puts(file, indent_lines(12, "#{param}: #{value}"))
    end)
  end

  defp sort_by_status_code(records) do
    Enum.sort_by(records, & &1.status)
  end

  defp write_example(record, file) do
    puts(file, "\n\n+ Request #{record.assigns.bureaucrat_desc}")
    puts(file, "**#{record.method}** `#{get_request_path(record)}`\n")
    puts(file, indent_lines(4, "+ Headers\n"))
    write_headers(record.req_headers, file)
    puts(file, indent_lines(4, "+ Body\n"))
    write_body(record.body_params, file)

    puts(file, "\n+ Response #{record.status}\n")
    puts(file, indent_lines(4, "+ Body\n"))
    write_body(record.resp_body, file)
  end

  defp get_request_path(record) do
    case record.query_string do
      "" -> record.request_path
      str -> "#{record.request_path}?#{str}"
    end
  end

  defp write_headers(headers, file) do
    Enum.each(headers, fn {header, value} ->
      puts(file, indent_lines(12, "#{header}: #{value}"))
    end)
  end

  defp write_body(body, file) do
    cond do
      body == "" or body == %{} or body == [] or is_nil(body) ->
        nil

      is_binary(body) ->
        body |> JSON.decode!() |> write_body(file)

      is_map(body) or is_list(body) ->
        puts(file, indent_lines(12, JSON.encode!(body, pretty: true)))
    end
  end

  defp indent_lines(number_of_spaces, string) do
    string
    |> String.split("\n")
    |> Enum.map_join("\n", fn a -> String.pad_leading("", number_of_spaces) <> a end)
  end

  defp formatted_params(uri_params) do
    Enum.map_join(uri_params, "\n", &format_param/1)
  end

  defp format_param(param) do
    "    + #{URI.encode(elem(param, 0))}: `#{URI.encode(elem(param, 1))}`"
  end

  defp anchor(record = %{path_params: path_params}) when map_size(path_params) == 0 do
    record.request_path
  end

  defp anchor(record) do
    Enum.join([""] ++ set_params(record), "/")
  end

  defp set_params(record) do
    Enum.flat_map(record.path_info, fn value ->
      find_params_key(record.path_params, value)
    end)
  end

  defp find_params_key(params, target) do
    Enum.find_value(params, [target], fn {key, val} ->
      if val == target, do: ["{#{key}}"]
    end)
  end

  defp puts(file, string) do
    IO.puts(file, string)
    file
  end

  defp group_records(records) do
    by_controller = Bureaucrat.Util.stable_group_by(records, &get_controller/1)

    Enum.map(by_controller, fn {c, recs} ->
      {c, Bureaucrat.Util.stable_group_by(recs, &get_action/1)}
    end)
  end

  defp strip_ns(module) do
    case to_string(module) do
      "Elixir." <> rest -> rest
      other -> other
    end
  end

  defp get_controller({_, opts}),
    do: opts[:group_title] || String.replace_suffix(strip_ns(opts[:module]), "Test", "")

  defp get_controller(conn),
    do: conn.assigns.bureaucrat_opts[:group_title] || strip_ns(conn.private.phoenix_controller)

  defp get_action({_, opts}), do: opts[:description]
  defp get_action(conn), do: conn.private.phoenix_action
end
