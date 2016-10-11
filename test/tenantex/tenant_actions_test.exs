defmodule Tenantex.TenantActionsTest do
  use ExUnit.Case

  import Tenantex.Queryable
  alias Tenantex.Note
  alias Tenantex.TestPostgresRepo

  @migration_version 20160711125401
  @wrong_migration_version 20160711125402
  @repo TestPostgresRepo
  @tenant_id 2

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(@repo)
  end

  test ".migrate_tenant/4 migrates the tenant forward by default" do
    create_tenant_schema

    assert_creates_notes_table fn ->
      {status, prefix, versions} = Tenantex.migrate_tenant(@repo, @tenant_id)

      assert status == :ok
      assert prefix == "tenant_#{@tenant_id}"
      assert versions == [@migration_version]
    end
  end

  test ".migrate_tenant/4 returns an error tuple when it fails" do
    create_and_migrate_tenant

    force_migration_failure fn(expected_postgres_error) ->
      {status, prefix, error_message} = Tenantex.migrate_tenant(@repo, @tenant_id)

      assert status == :error
      assert prefix == "tenant_#{@tenant_id}"
      assert error_message == expected_postgres_error
    end
  end

  test ".migrate_tenant/4 can rollback and return metadata" do
    create_and_migrate_tenant

    assert_drops_notes_table fn ->
      {status, prefix, versions} =
        Tenantex.migrate_tenant(@repo, @tenant_id, :down, to: @migration_version)

      assert status == :ok
      assert prefix == "tenant_#{@tenant_id}"
      assert versions == [@migration_version]
    end
  end

  test ".migrate_tenant/4 returns a tuple when it fails to rollback" do
    create_and_migrate_tenant

    force_rollback_failure fn(expected_postgres_error) ->
      {status, prefix, error_message} =
        Tenantex.migrate_tenant(@repo, @tenant_id, :down, to: @migration_version)

      assert status == :error
      assert prefix == "tenant_#{@tenant_id}"
      assert error_message == expected_postgres_error
    end
  end

  defp assert_creates_notes_table(fun) do
    assert_notes_table_is_dropped
    fun.()
    assert_notes_table_is_present
  end

  defp assert_drops_notes_table(fun) do
    assert_notes_table_is_present
    fun.()
    assert_notes_table_is_dropped
  end

  defp assert_notes_table_is_dropped do
    assert_raise Postgrex.Error, fn ->
      find_tenant_notes
    end
  end

  defp assert_notes_table_is_present do
    assert find_tenant_notes == []
  end

  defp create_and_migrate_tenant do
    Tenantex.new_tenant(@repo, @tenant_id)
  end

  defp create_tenant_schema do
    Tenantex.TenantActions.create_schema(@repo, @tenant_id)
  end

  defp find_tenant_notes do
    Note
    |> set_tenant(@tenant_id)
    |> @repo.all
    # Tenantex.all(@repo, Note, @tenant_id)
  end

  defp force_migration_failure(migration_function) do
    sql = """
    DELETE FROM "tenant_#{@tenant_id}"."schema_migrations"
    """

    @repo |> Ecto.Adapters.SQL.query(sql, [])

    migration_function.("ERROR (duplicate_table): relation \"notes\" already exists")
  end

  defp force_rollback_failure(rollback_function) do
    sql = """
    DROP TABLE "tenant_#{@tenant_id}"."notes";
    """

    @repo |> Ecto.Adapters.SQL.query(sql, [])

    rollback_function.("ERROR (undefined_table): table \"notes\" does not exist")
  end
end
