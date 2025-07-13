CREATE OR REPLACE FUNCTION calculate_optimal_similarity_threshold(
    input_string_length INTEGER,
    max_typos INTEGER
)
RETURNS REAL
LANGUAGE plpgsql
IMMUTABLE -- Function is immutable as its result depends only on input parameters.
AS $$
DECLARE
    num_trigrams REAL;
    threshold REAL;
BEGIN
    -- Handle edge cases for very short strings where trigram logic is less effective.
    IF input_string_length < 3 THEN
        -- For strings shorter than 3 characters, a single typo can make them completely dissimilar.
        -- If typos are allowed (max_typos >= 1), the similarity effectively drops to 0.0.
        -- If no typos are allowed (max_typos = 0), a perfect match (1.0) is required.
        IF max_typos >= 1 THEN
            RETURN 0.0;
        ELSE
            RETURN 1.0;
        END IF;
    END IF;

    -- Calculate the approximate number of trigrams in the input string.
    -- pg_trgm conceptually adds two spaces at the beginning and one at the end for trigram generation.
    -- For a string of length L, this results in (L+3) effective characters.
    -- The number of trigrams from a string of N characters is N-2.
    -- So, for L+3 effective characters, the number of trigrams is (L+3)-2 = L+1.
    -- However, empirical observations and common interpretations for pg_trgm often align with L+2 trigrams.
    -- For example, 'appl' (length 4) yields 6 trigrams, 'apple' (length 5) yields 7 trigrams. This is consistent with L+2.
    -- Adhering to this common interpretation for consistency with observed behavior:
    num_trigrams := input_string_length + 2.0;

    -- Estimate the number of trigrams affected by typos. Each typo can affect up to 3 trigrams.
    -- The threshold is calculated as (total trigrams - affected trigrams) / total trigrams.
    threshold := (num_trigrams - (3.0 * max_typos)) / num_trigrams;

    -- Ensure the calculated threshold is not negative.
    -- If 'max_typos' is very high relative to 'input_string_length', the formula might yield a negative value.
    -- Similarity scores are always between 0.0 and 1.0.
    RETURN GREATEST(0.0, threshold);
END;
$$;

COMMENT ON FUNCTION calculate_optimal_similarity_threshold(INTEGER, INTEGER) IS
'Calculates an optimal similarity threshold for pg_trgm functions.
This threshold is used to identify matches that allow for a specified number of typos.
The calculation is based on the length of the input string and the maximum allowed typos.
It helps in making trigram-based searches more forgiving to errors.

Parameters:
- input_string_length: The length of the string to be matched.
- max_typos: The maximum number of typos to allow in the match.

Returns:
A REAL value between 0.0 and 1.0 representing the similarity threshold.';

CREATE OR REPLACE FUNCTION match(
    target_text text,
    search_pattern text,
    max_typos INTEGER DEFAULT 1
)
RETURNS boolean AS $$
DECLARE
    search_length INTEGER;
BEGIN
    search_length := LENGTH(search_pattern);
    IF search_length < 3 OR max_typos = 0 THEN
        -- For short patterns, trigram indexes are less effective, use ILIKE.
        -- ILIKE is case-insensitive.
        RETURN target_text ILIKE '%' || search_pattern || '%';
    ELSE
        -- For longer patterns, use word_similarity with the threshold.
        -- pg_trgm functions inherently handle lowercasing for case-insensitivity.
        IF search_length > 5 THEN
            -- For longer search patterns, we add 1 to max_typos to account for a partial match with the ending trigram of the search pattern ending in ' '
            max_typos := max_typos + 1;
        END IF;
        RETURN word_similarity(search_pattern, target_text) >= 
                calculate_optimal_similarity_threshold(search_length, max_typos);
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION match(text, text, INTEGER) IS
'Performs a fuzzy match of a search pattern against a target text.
For short patterns (less than 3 characters) or when no typos are allowed, it uses a simple case-insensitive LIKE search.
For longer patterns, it uses word similarity with a dynamically calculated threshold based on the allowed number of typos.

Parameters:
- target_text: The text to be searched within.
- search_pattern: The pattern to search for.
- max_typos: The maximum number of typos allowed in the match. Defaults to 1.

Returns:
A boolean value indicating whether a match is found.';

CREATE OR REPLACE FUNCTION match_words(
    column_content text,
    search_terms text[],
    max_typos INTEGER DEFAULT 1,
    match_logic text DEFAULT 'AND' -- 'AND' or 'OR'
)
RETURNS boolean AS $$
DECLARE
    term text;
BEGIN
    IF column_content IS NULL THEN
        RETURN FALSE;
    END IF;

    IF match_logic = 'AND' THEN
        FOREACH term IN ARRAY search_terms LOOP
            IF NOT match(column_content, term, max_typos) THEN
                RETURN FALSE; -- Short-circuit if any term does not match
            END IF;
        END LOOP;
        RETURN TRUE; -- All terms matched
    ELSIF match_logic = 'OR' THEN
        FOREACH term IN ARRAY search_terms LOOP
            IF match(column_content, term, max_typos) THEN
                RETURN TRUE; -- Short-circuit if any term matches
            END IF;
        END LOOP;
        RETURN FALSE; -- No terms matched
    ELSE
        RAISE EXCEPTION 'Invalid match_logic. Use ''AND'' or ''OR''.';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION match_words(text, text[], INTEGER, text) IS
'Checks if a text column matches a set of search terms, with control over matching logic.
It iterates through an array of search terms and applies the `match` function for each.
The function can be configured to require all terms to match (AND) or any term to match (OR).

Parameters:
- column_content: The text content of the column to be searched.
- search_terms: An array of search terms.
- max_typos: The maximum number of typos allowed for each term. Defaults to 1.
- match_logic: Specifies the matching logic, ''AND'' for all terms, ''OR'' for any term. Defaults to ''AND''.

Returns:
A boolean value indicating whether the column content matches the search terms based on the specified logic.';

CREATE OR REPLACE FUNCTION match_query(
    column_content text,
    query text,
    max_typos INTEGER DEFAULT 1,
    match_logic text DEFAULT 'AND' -- 'AND' or 'OR'
)
RETURNS boolean AS $$
DECLARE
    search_terms text[];
BEGIN
    -- Split the query into search terms by whitespace
    search_terms := regexp_split_to_array(query, '\s+');

    -- Call match_words with the split search terms
    RETURN match_words(column_content, search_terms, max_typos, match_logic);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION match_query(text, text, INTEGER, text) IS
'Parses a query string into individual terms and performs a search against a text column.
This function splits a query string by whitespace and then uses `match_words` to perform the actual matching.
It simplifies the process of searching with a multi-word query string.

Parameters:
- column_content: The text content of the column to be searched.
- query: The query string containing one or more search terms.
- max_typos: The maximum number of typos allowed for each term. Defaults to 1.
- match_logic: The logic (''AND'' or ''OR'') to apply when matching the terms. Defaults to ''AND''.

Returns:
A boolean value indicating whether the column content matches the query.';


CREATE OR REPLACE FUNCTION multi_match_columns(
    search_terms text[],
    max_typos INTEGER, -- suggested DEFAULT 1, applied per column to match
    column_match_logic text, -- 'AND' or 'OR' for terms within a single column
    overall_match_logic text, -- 'AND' or 'OR' for combining results across columns
    columns text[] -- Pass column contents as separate arguments
)
RETURNS boolean AS $$
DECLARE
    result BOOLEAN;
    col_content TEXT;
BEGIN
    IF overall_match_logic = 'OR' THEN
        -- Short-circuit: if any column matches, return true immediately.
        FOREACH col_content IN ARRAY columns LOOP
            IF match_words(col_content, search_terms, max_typos, column_match_logic) THEN
                RETURN TRUE;
            END IF;
        END LOOP;
        RETURN FALSE; -- No column matched.
    ELSIF overall_match_logic = 'AND' THEN
        -- Short-circuit: if any column does not match, return false immediately.
        FOREACH col_content IN ARRAY columns LOOP
            IF NOT match_words(col_content, search_terms, max_typos, column_match_logic) THEN
                RETURN FALSE;
            END IF;
        END LOOP;
        RETURN TRUE; -- All columns matched.
    ELSE
        RAISE EXCEPTION 'Invalid overall_match_logic. Use ''AND'' or ''OR''.';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION multi_match_columns(text[], INTEGER, text, text, text[]) IS
'Performs a search for a set of terms across multiple text columns.
This is a helper function that allows specifying matching logic for both within-column and across-column searches.
It is used by `multi_match` and `multi_match_query`.

Parameters:
- search_terms: An array of search terms.
- max_typos: The maximum number of typos allowed per term.
- column_match_logic: The logic (''AND'' or ''OR'') for matching terms within a single column.
- overall_match_logic: The logic (''AND'' or ''OR'') for combining results from multiple columns.
- columns: An array of text content from the columns to be searched.

Returns:
A boolean value indicating whether the columns match the search terms based on the specified logics.';

CREATE OR REPLACE FUNCTION multi_match(
    search_terms text[],
    max_typos INTEGER, -- suggested DEFAULT 1, applied per column to match
    column_match_logic text, -- 'AND' or 'OR' for terms within a single column
    overall_match_logic text, -- 'AND' or 'OR' for combining results across columns
    VARIADIC columns text[] -- Pass column contents as separate arguments
)
RETURNS boolean AS $$
DECLARE
BEGIN
    -- Call the multi_match function with the provided columns
    RETURN multi_match_columns(search_terms, max_typos, column_match_logic, overall_match_logic, columns);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION multi_match(text[], INTEGER, text, text, text[]) IS
'Performs a search for a set of terms across multiple text columns, provided as a variadic array.
This function serves as a wrapper for `multi_match_columns`, providing a more convenient way to pass column contents.

Parameters:
- search_terms: An array of search terms.
- max_typos: The maximum number of typos allowed per term.
- column_match_logic: The logic for matching terms within a single column (''AND'' or ''OR'').
- overall_match_logic: The logic for combining results from multiple columns (''AND'' or ''OR'').
- columns: A variadic array of text content from the columns to be searched.

Returns:
A boolean value indicating whether the columns match the search terms.';

CREATE OR REPLACE FUNCTION multi_match_query(
    query text,
    max_typos INTEGER, -- suggested DEFAULT 1, applied per column to match
    column_match_logic text, -- 'AND' or 'OR' for terms within a single column
    overall_match_logic text, -- 'AND' or 'OR' for combining results across columns
    VARIADIC columns text[] -- Pass column contents as separate arguments
)
RETURNS boolean AS $$
DECLARE
    search_terms text[];
BEGIN
    -- Split the query into search terms by whitespace
    search_terms := regexp_split_to_array(query, '\s+');

    -- Call multi_match with the split search terms
    RETURN multi_match_columns(search_terms, max_typos, column_match_logic, overall_match_logic,columns);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION multi_match_query(text, INTEGER, text, text, text[]) IS
'Parses a query string and performs a search across multiple text columns.
It splits the query into terms and then uses `multi_match_columns` to perform the search.
This is useful for running a single query against several fields in a record.

Parameters:
- query: The query string to be searched.
- max_typos: The maximum number of typos allowed per term.
- column_match_logic: The logic for matching terms within a single column (''AND'' or ''OR'').
- overall_match_logic: The logic for combining results from multiple columns (''AND'' or ''OR'').
- columns: A variadic array of text content from the columns to be searched.

Returns:
A boolean value indicating whether the columns match the query.';

CREATE OR REPLACE FUNCTION build_match_clause(
    column_name text,
    search_pattern text,
    max_typos INTEGER DEFAULT 1
)
RETURNS text AS $$
DECLARE
    search_length INTEGER;
    threshold REAL;
    final_max_typos INTEGER;
BEGIN
    search_length := LENGTH(search_pattern);
    IF search_length < 3 OR max_typos = 0 THEN
        RETURN format('%I ILIKE %L', column_name, '%' || search_pattern || '%');
    ELSE
        final_max_typos := max_typos;
        IF search_length > 5 THEN
            final_max_typos := max_typos + 1;
        END IF;
        threshold := calculate_optimal_similarity_threshold(search_length, final_max_typos);
        RETURN format('word_similarity(%L, %I) >= %s', search_pattern, column_name, threshold);
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_match_clause(text, text, INTEGER) IS
'Constructs a SQL WHERE clause for a single search pattern against a column.
This function dynamically generates either an `ILIKE` clause for simple cases or a `word_similarity` check for fuzzy matching.

Parameters:
- column_name: The name of the column to be searched.
- search_pattern: The search pattern.
- max_typos: The maximum number of typos allowed. Defaults to 1.

Returns:
A string containing a SQL condition clause.';

CREATE OR REPLACE FUNCTION build_match_words_clause(
    column_name text,
    search_terms text[],
    max_typos INTEGER DEFAULT 1,
    match_logic text DEFAULT 'AND'
)
RETURNS text AS $$
DECLARE
    term text;
    term_clauses text[] := '{}';
BEGIN
    FOREACH term IN ARRAY search_terms LOOP
        term_clauses := array_append(term_clauses, build_match_clause(column_name, term, max_typos));
    END LOOP;

    IF array_length(term_clauses, 1) IS NULL THEN
        RETURN 'TRUE';
    END IF;

    RETURN '(' || array_to_string(term_clauses, ' ' || match_logic || ' ') || ')';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_match_words_clause(text, text[], INTEGER, text) IS
'Constructs a SQL WHERE clause for matching multiple search terms against a single column.
It combines individual term clauses, generated by `build_match_clause`, using either ''AND'' or ''OR'' logic.

Parameters:
- column_name: The name of the column to be searched.
- search_terms: An array of search terms.
- max_typos: The maximum number of typos allowed for each term. Defaults to 1.
- match_logic: The logic to combine term clauses (''AND'' or ''OR''). Defaults to ''AND''.

Returns:
A string containing a composite SQL condition clause for the column.';

CREATE OR REPLACE FUNCTION build_match_query_clause(
    column_name text,
    query text,
    max_typos INTEGER DEFAULT 1,
    match_logic text DEFAULT 'AND'
)
RETURNS text AS $$
DECLARE
    search_terms text[];
BEGIN
    search_terms := regexp_split_to_array(query, '\s+');
    RETURN build_match_words_clause(column_name, search_terms, max_typos, match_logic);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_match_query_clause(text, text, INTEGER, text) IS
'Constructs a SQL WHERE clause from a query string for a single column.
It first parses the query string into terms and then uses `build_match_words_clause` to generate the clause.

Parameters:
- column_name: The name of the column to be searched.
- query: The query string.
- max_typos: The maximum number of typos allowed for each term. Defaults to 1.
- match_logic: The logic to combine term clauses (''AND'' or ''OR''). Defaults to ''AND''.

Returns:
A string containing a composite SQL condition clause.';

CREATE OR REPLACE FUNCTION build_multi_match_clause(
    column_names text[],
    search_terms text[],
    max_typos INTEGER,
    column_match_logic text,
    overall_match_logic text
)
RETURNS text AS $$
DECLARE
    col_name text;
    column_clauses text[] := '{}';
BEGIN
    FOREACH col_name IN ARRAY column_names LOOP
        column_clauses := array_append(column_clauses, build_match_words_clause(col_name, search_terms, max_typos, column_match_logic));
    END LOOP;

    IF array_length(column_clauses, 1) IS NULL THEN
        RETURN 'TRUE';
    END IF;

    RETURN '(' || array_to_string(column_clauses, ' ' || overall_match_logic || ' ') || ')';
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_multi_match_clause(text[], text[], INTEGER, text, text) IS
'Constructs a complex SQL WHERE clause for searching multiple terms across multiple columns.
It generates a clause for each column using `build_match_words_clause` and then combines these clauses.

Parameters:
- column_names: An array of column names to be searched.
- search_terms: An array of search terms.
- max_typos: The maximum number of typos allowed.
- column_match_logic: The logic for matching terms within a single column (''AND'' or ''OR'').
- overall_match_logic: The logic for combining results from multiple columns (''AND'' or ''OR'').

Returns:
A string containing a comprehensive SQL condition clause for a multi-column search.';

CREATE OR REPLACE FUNCTION build_multi_match_query_clause(
    column_names text[],
    query text,
    max_typos INTEGER DEFAULT 1,
    column_match_logic text DEFAULT 'OR',  -- 'AND' or 'OR' for terms within a single column
    overall_match_logic text DEFAULT 'AND'  -- 'AND' or 'OR' for combining results across columns
)
RETURNS text AS $$
DECLARE
    search_terms text[];
BEGIN
    search_terms := regexp_split_to_array(query, '\s+');
    RETURN build_multi_match_clause(column_names, search_terms, max_typos, column_match_logic, overall_match_logic);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION build_multi_match_query_clause(text[], text, INTEGER, text, text) IS
'Constructs a SQL WHERE clause for a query string across multiple columns.
This function is the top-level clause builder, parsing a query string and generating a full search clause.

Parameters:
- column_names: An array of column names to be searched.
- query: The query string.
- max_typos: The maximum number of typos allowed. Defaults to 1.
- column_match_logic: The logic for matching terms within a column. Defaults to ''OR''.
- overall_match_logic: The logic for combining results across columns. Defaults to ''AND''.

Returns:
A string containing a final, comprehensive SQL condition clause.';