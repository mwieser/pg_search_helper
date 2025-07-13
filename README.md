# pg_search_helper - Enhanced PostgreSQL Search

## Overview
This repository provides a set of PostgreSQL functions designed to enhance text search capabilities, particularly for metadata like names, emails, or titles where traditional full-text search (like `ts_vector`) might not be ideal. It simplifies fuzzy searching for multiple words across multiple fields, which would otherwise require complex manual SQL query construction.

While `pg_trgm` offers fuzzy matching, these helper methods builds upon it to provide more powerful, ready-to-use search functions, at the cost of some performance for simple cases. For performance-critical queries, it also provides helper functions to generate the `WHERE` clause, giving you more control.

**This is a work in progress!**

## Features
- Fuzzy matching with tolerance for typos.
- Search for multiple keywords with `AND`/`OR` logic.
- Search across multiple columns with `AND`/`OR` logic.
- Helper functions to generate dynamic `WHERE` clauses for use in your application code.
- Simple setup using Docker Compose for a ready-to-use development environment.

## ⚠️ Security Warning: SQL Injection
The `build_*_clause` functions are helpers designed to generate SQL query fragments. The generated fragments are **not inherently safe** from SQL injection if user input is not properly sanitized before being passed to these functions.

**Always sanitize and validate user-provided input in your application layer** before using it to construct queries with these helper functions. The non-`build_` functions are generally safer as they pass parameters correctly, but caution is always advised.

## Requirements
- PostgreSQL (v12+ recommended)
- The `pg_trgm` extension must be enabled in your database.

## Quick Start

This project includes a Docker Compose setup for a consistent development environment.

1.  **Start the services:**
    ```bash
    docker-compose up -d
    ```
    This will start a PostgreSQL 17 container and a service container with all necessary tools. The PostgreSQL port `5432` is exposed to your host machine.

2.  **Connect to the database and set it up:**
    You can use any PostgreSQL client to connect to `postgresql://dbuser:dbpass@localhost:5432/development`.

    Alternatively, you can use `psql` within the service container:
    ```bash
    docker-compose exec service psql
    ```

3.  **Inside `psql`, run the following commands:**

    ```sql
    -- Enable the pg_trgm extension
    CREATE EXTENSION IF NOT EXISTS pg_trgm;

    -- Load the search helper functions
    \i /app/pg_search_helper--1.0.sql
    ```

4.  **(Optional) Load test data for local development:**
    The repository includes a sample dataset of employees. To load it, run this command from your host shell:
    ```sql
    CREATE DATABASE employees;
    \c employees
    CREATE SCHEMA employees;
    ```
    ```bash
    wget https://raw.githubusercontent.com/neondatabase/postgres-sample-dbs/main/employees.sql.gz

    pg_restore -d postgres://dbuser:dbpass@postgres/employees -Fc employees.sql.gz -c -v --no-owner --no-privileges
    ```
    This will create and populate an `employees` table.

## Usage Examples

Here are some examples of how to use the search functions. These examples assume you have loaded the sample `employees` data.

### Simple Search in a Single Column
To find employees with "John" in their `first_name`:

```sql
SELECT * FROM employees
WHERE match_query(first_name, 'John', 1, 'AND');
```
- `first_name`: The column to search in.
- `'John'`: The search query.
- `1`: Maximum allowed typos.
- `'AND'`: Logic for multiple keywords in the query (if any).

### Multi-word Search in a Single Column
To find employees with "John" and "Doe" in their full name (first and last name concatenated):

```sql
SELECT * FROM employees.employee
WHERE match_query(first_name || ' ' || last_name, 'Chriss Gid', 0, 'AND');
```

### Search Across Multiple Columns
To find employees where the query "Sales Manager" matches in either the `title` OR the `email`:

```sql
SELECT * FROM  employees.employee
WHERE multi_match_query(
    'Chriss Gid', -- query
    1,               -- max_typos
    'OR',           -- column_match_logic (for words within the query)
    'AND',            -- overall_match_logic (for matching across columns)
    first_name,      -- column 1
    last_name        -- column 2
);
```

### Building Dynamic WHERE Clauses
For more control, you can generate the `WHERE` clause as a string. This is useful in application code where you build queries dynamically.

```sql
SELECT build_multi_match_query_clause(
    ARRAY['title', 'email'], -- column names
    'Chriss Gid',            -- query
    1,                       -- max_typos
    'OR',                   -- column_match_logic
    'AND'                     -- overall_match_logic
);
```

This will return a string like:
`((word_similarity('Chriss', title) >= 0.25 OR word_similarity('Gid', title) >= 0.4) AND (word_similarity('Chriss', email) >= 0.25 OR word_similarity('Gid', email) >= 0.4))`

You can then incorporate this string into your application's query-building logic. **Remember the SQL injection warning.**

## Function Reference
A brief overview of the available functions. For details on parameters, see the comments in the `pg_search_helper--1.0.sql` file.

| Function | Description |
|---|---|
| `match_query` | Searches a single column for one or more words. |
| `multi_match_query` | Searches multiple columns for one or more words. |
| `build_match_query_clause` | Builds a `WHERE` clause for a single column search. |
| `build_multi_match_query_clause` | Builds a `WHERE` clause for a multi-column search. |
| `calculate_optimal_similarity_threshold` | Helper to determine the `pg_trgm` similarity threshold based on typos. |

## Development
The included `Dockerfile` and `docker-compose.yml` are configured for use with VS Code Remote - Containers. This provides a consistent development environment. Simply open the folder in a container and you're ready to go.

## Test Data
The test data used is the `employees` sample database from [Neon](https://github.com/neondatabase-labs/postgres-sample-dbs).