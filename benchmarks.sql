-- benchmarks.sql
-- This script runs benchmarks for the pg_search_helper functions.
-- It compares the performance of using the direct functions (e.g., match_query)
-- against executing a query with a WHERE clause that is dynamically built,
-- similar to what the build_*_clause functions would generate.

-- To run this script, use psql:
-- docker-compose exec service psql -f benchmarks.sql employees

-- Enable timing to see the execution time for each query.
\timing

\echo '----------------------------------------------------------------'
\echo 'Benchmark Setup:'
\echo 'The following tests use EXPLAIN ANALYZE to show execution plans and timings.'
\echo 'Lower execution times are better.'
\echo 'Pay attention to whether a "Seq Scan" or "Index Scan" is used.'
\echo '----------------------------------------------------------------'


----------------------------------------------------------------
-- CASE 1: Simple search on a single column (triggers ILIKE)
----------------------------------------------------------------

\echo '\nCASE 1.1: Using match_query() with max_typos = 0'
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE match_query(first_name, 'Georgi', 0);

\echo '\nCASE 1.2: Using a manually constructed ILIKE clause'
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE first_name ILIKE '%Georgi%';


----------------------------------------------------------------
-- CASE 2: Fuzzy search on a single column (triggers word_similarity)
----------------------------------------------------------------

\echo '\nCASE 2.1: Using match_query() with max_typos = 1'
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE match_query(first_name, 'Georgi', 1);

\echo '\nCASE 2.2: Using a manually constructed word_similarity clause'
-- This threshold is what calculate_optimal_similarity_threshold(6, 2) would produce.
-- (length=6, max_typos=1 becomes final_max_typos=2 because length > 5)
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE word_similarity('Georgi', first_name) >= 0.25;


----------------------------------------------------------------
-- CASE 3: Multi-word search on a concatenated column
----------------------------------------------------------------

\echo '\nCASE 3.1: Using match_query() for multiple words'
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE match_query(first_name || ' ' || last_name, 'Georgi Facello', 1, 'AND');

\echo '\nCASE 3.2: Using manually constructed word_similarity clauses with AND'
-- Thresholds calculated for 'Georgi' (len 6) and 'Facello' (len 7) with 1 typo
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE word_similarity('Georgi', first_name || ' ' || last_name) >= 0.25
  AND word_similarity('Facello', first_name || ' ' || last_name) >= 0.33333334;


----------------------------------------------------------------
-- CASE 4: Multi-column search
----------------------------------------------------------------

\echo '\nCASE 4.1: Using multi_match_query()'
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE multi_match_query('Georgi Facello', 1, 'AND', 'OR', first_name, last_name);

\echo '\nCASE 4.2: Using a manually constructed clause for multiple columns'
EXPLAIN ANALYZE SELECT * FROM employees.employee
WHERE
    (word_similarity('Georgi', first_name) >= 0.25 AND word_similarity('Facello', first_name) >= 0.33333334)
 OR (word_similarity('Georgi', last_name) >= 0.25 AND word_similarity('Facello', last_name) >= 0.33333334);

\echo '\n----------------------------------------------------------------'
\echo 'Benchmark complete.'
\echo 'Review the "Execution Time" from the EXPLAIN ANALYZE output.'
\echo 'Generally, manually constructed clauses are faster because the query planner'
\echo 'can better optimize them. The functions are for convenience.'
\echo '----------------------------------------------------------------'
