#!/usr/bin/env python3
"""Comprehensive test suite for ASL SQL query builder, multi-dialect renderer, and DDL engine."""

import pytest
from tools.sql_cli import parse_sql_sexpr, AslSqlRenderer, render_ddl_table, run_sql_cli
from argparse import Namespace
import json


def test_parse_simple_select():
    s = '(select ["id" "name"] (from "users"))'
    tree = parse_sql_sexpr(s)
    assert tree[0] == "select"
    assert tree[1] == ["id", "name"]
    assert tree[2] == ["from", "users"]


def test_postgres_parameterized_emission():
    s = '(select ["id" "name"] (from "users") (where (and (= "status" "active") (> "total" 100))) (order-by "created_at" desc) (limit 10))'
    tree = parse_sql_sexpr(s)
    renderer = AslSqlRenderer(dialect="postgres")
    sql, params = renderer.render_query_tree(tree)

    assert 'SELECT "id", "name" FROM "users"' in sql
    assert '("status" = $1) AND ("total" > $2)' in sql
    assert 'ORDER BY "created_at" DESC' in sql
    assert "LIMIT 10" in sql
    assert params == ["active", 100]


def test_sqlite_parameterized_emission():
    s = '(select ["id" "total"] (from "orders") (where (< "total" 50)) (limit 5))'
    tree = parse_sql_sexpr(s)
    renderer = AslSqlRenderer(dialect="sqlite")
    sql, params = renderer.render_query_tree(tree)

    assert 'SELECT "id", "total" FROM "orders"' in sql
    assert '"total" < ?' in sql
    assert "LIMIT 5" in sql
    assert params == [50]


def test_mysql_quoting_and_placeholders():
    s = '(select ["id" "title"] (from "posts") (where (= "status" "draft")))'
    tree = parse_sql_sexpr(s)
    renderer = AslSqlRenderer(dialect="mysql")
    sql, params = renderer.render_query_tree(tree)

    assert "SELECT `id`, `title` FROM `posts`" in sql
    assert "`status` = ?" in sql
    assert params == ["draft"]


def test_joins_rendering():
    s = '(select ["u.name" "o.total"] (from "users") (join "orders" (= "u.id" "o.user_id")) (where (> "o.total" 200)))'
    tree = parse_sql_sexpr(s)
    renderer = AslSqlRenderer(dialect="postgres")
    sql, params = renderer.render_query_tree(tree)

    assert 'SELECT "u"."name", "o"."total" FROM "users"' in sql
    assert 'INNER JOIN "orders" ON "u"."id" = "o"."user_id"' in sql
    assert '"o"."total" > $1' in sql
    assert params == [200]


def test_ddl_table_postgres():
    fields = [
        ("id", "int64", True),
        ("email", "text", False),
        ("active", "bool", False),
        ("created_at", "timestamp", False)
    ]
    ddl = render_ddl_table("accounts", fields, dialect="postgres")
    assert 'CREATE TABLE "accounts"' in ddl
    assert '"id" BIGINT PRIMARY KEY' in ddl
    assert '"email" TEXT NOT NULL' in ddl
    assert '"active" BOOLEAN NOT NULL' in ddl
    assert '"created_at" TIMESTAMPTZ NOT NULL' in ddl


def test_ddl_table_sqlite():
    fields = [
        ("id", "int64", True),
        ("score", "float64", False),
        ("created_at", "timestamp", False)
    ]
    ddl = render_ddl_table("scores", fields, dialect="sqlite")
    assert 'CREATE TABLE "scores"' in ddl
    assert '"id" INTEGER PRIMARY KEY' in ddl
    assert '"score" REAL NOT NULL' in ddl
    assert '"created_at" TEXT NOT NULL' in ddl


def test_cli_json_mode(capsys):
    args = Namespace(action="render", dialect="postgres", query='(select ["id"] (from "items") (where (= "id" 42)))', json=True)
    rc = run_sql_cli(args)
    assert rc == 0
    captured = capsys.readouterr()
    data = json.loads(captured.out)
    assert data["dialect"] == "postgres"
    assert "$1" in data["sql"]
    assert data["params"] == [42]


def test_json_extract_polyfills():
    s = '(select ["id" (json-get "payload" "user_id")] (from "events"))'
    tree = parse_sql_sexpr(s)

    r_pg = AslSqlRenderer(dialect="postgres")
    sql_pg, _ = r_pg.render_query_tree(tree)
    assert '"payload"->>\'user_id\'' in sql_pg

    r_sqlite = AslSqlRenderer(dialect="sqlite")
    sql_sqlite, _ = r_sqlite.render_query_tree(tree)
    assert "json_extract(\"payload\", '$.user_id')" in sql_sqlite

    r_mysql = AslSqlRenderer(dialect="mysql")
    sql_mysql, _ = r_mysql.render_query_tree(tree)
    assert "JSON_UNQUOTE(JSON_EXTRACT(`payload`, '$.user_id'))" in sql_mysql

    r_ch = AslSqlRenderer(dialect="clickhouse")
    sql_ch, _ = r_ch.render_query_tree(tree)
    assert "JSONExtractString(`payload`, 'user_id')" in sql_ch


def test_raw_sql_escape_hatch():
    s = '(select ["id" (raw "RANK() OVER (PARTITION BY dept)")] (from "staff"))'
    tree = parse_sql_sexpr(s)
    r = AslSqlRenderer(dialect="postgres")
    sql, _ = r.render_query_tree(tree)
    assert "RANK() OVER (PARTITION BY dept)" in sql


def test_upsert_polyfills():
    from tools.sql_cli import render_upsert_query
    # Postgres
    pg_sql = render_upsert_query("users", ["id", "name", "visits"], ["1", "'Alice'", "10"], ["id"], ["name", "visits"], dialect="postgres")
    assert "ON CONFLICT (\"id\") DO UPDATE SET \"name\" = EXCLUDED.\"name\", \"visits\" = EXCLUDED.\"visits\"" in pg_sql

    # SQLite
    sqlite_sql = render_upsert_query("users", ["id", "name", "visits"], ["1", "'Alice'", "10"], ["id"], ["name", "visits"], dialect="sqlite")
    assert "ON CONFLICT (\"id\") DO UPDATE SET \"name\" = EXCLUDED.\"name\", \"visits\" = EXCLUDED.\"visits\"" in sqlite_sql

    # MySQL
    mysql_sql = render_upsert_query("users", ["id", "name", "visits"], ["1", "'Alice'", "10"], ["id"], ["name", "visits"], dialect="mysql")
    assert "ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `visits` = VALUES(`visits`)" in mysql_sql

    # MSSQL
    mssql_sql = render_upsert_query("users", ["id", "name", "visits"], ["1", "'Alice'", "10"], ["id"], ["name", "visits"], dialect="mssql")
    assert "MERGE INTO [users] WITH (HOLDLOCK) AS [t]" in mssql_sql
    assert "WHEN MATCHED THEN\n  UPDATE SET [name] = [s].[name], [visits] = [s].[visits]" in mssql_sql

    # Oracle
    oracle_sql = render_upsert_query("users", ["id", "name", "visits"], ["1", "'Alice'", "10"], ["id"], ["name", "visits"], dialect="oracle")
    assert 'MERGE INTO "users" "t"' in oracle_sql
    assert 'USING (SELECT 1 AS "id", \'Alice\' AS "name", 10 AS "visits" FROM dual) "s"' in oracle_sql
    assert 'WHEN MATCHED THEN\n  UPDATE SET "t"."name" = "s"."name", "t"."visits" = "s"."visits"' in oracle_sql
