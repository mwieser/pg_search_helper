-- Test script for setting up the employees database with pg_trgm extension

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- https://github.com/neondatabase-labs/postgres-sample-dbs/tree/main?tab=readme-ov-file#employees-database
/*
CREATE DATABASE employees;
\c employees
CREATE SCHEMA employees;

pg_restore -d postgres://<user>:<password>@<hostname>/employees -Fc employees.sql.gz -c -v --no-owner --no-privileges
*/

CREATE INDEX idx_employee_first_name_trgm ON employees.employee USING GIN (first_name gin_trgm_ops);
CREATE INDEX idx_employee_last_name_trgm ON employees.employee USING GIN (last_name gin_trgm_ops);


