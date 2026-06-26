-- ============================================================
-- Every view referencing project1.dataset1.table1 directly OR
-- transitively (view1 -> view2 -> ... -> project1.dataset1.table1).
-- ============================================================

DECLARE input_table STRING DEFAULT 'project1.dataset1.table1';

DECLARE proj STRING DEFAULT SPLIT(input_table, '.')[OFFSET(0)];
DECLARE ds   STRING DEFAULT SPLIT(input_table, '.')[OFFSET(1)];
DECLARE tbl  STRING DEFAULT SPLIT(input_table, '.')[OFFSET(2)];

DECLARE proj_re STRING DEFAULT REGEXP_REPLACE(proj, r'([.\-\\])', r'\\\1');
DECLARE ds_re   STRING DEFAULT REGEXP_REPLACE(ds,   r'([.\-\\])', r'\\\1');
DECLARE tbl_re  STRING DEFAULT REGEXP_REPLACE(tbl,  r'([.\-\\])', r'\\\1');

DECLARE table_re STRING DEFAULT CONCAT(
  r'(?:^|[^A-Za-z0-9_.\-])(?:', proj_re, r'\.)?', ds_re, r'\.', tbl_re,
  r'(?:$|[^A-Za-z0-9_])');

CREATE TEMP TABLE all_views AS
SELECT
  table_catalog AS project,
  table_schema  AS dataset,
  table_name    AS view_name,
  CONCAT(table_catalog, '.', table_schema, '.', table_name) AS full_name,
  REGEXP_REPLACE(table_catalog, r'([.\-\\])', r'\\\1') AS proj_re,
  REGEXP_REPLACE(table_schema,  r'([.\-\\])', r'\\\1') AS ds_re,
  REGEXP_REPLACE(table_name,    r'([.\-\\])', r'\\\1') AS name_re,
  REGEXP_REPLACE(REGEXP_REPLACE(view_definition, r'`', ''), r'\s*\.\s*', '.') AS def_norm
FROM `project1`.`region-us`.INFORMATION_SCHEMA.VIEWS;   -- <<< change region if not US

WITH RECURSIVE deps AS (

  -- Hop 1: views referencing the table directly.
  SELECT
    v.project, v.dataset, v.view_name, v.full_name,
    v.proj_re, v.ds_re, v.name_re,
    1 AS hops,
    CONCAT(v.full_name, ' -> ', input_table) AS path
  FROM all_views v
  WHERE REGEXP_CONTAINS(v.def_norm, table_re)

  UNION ALL

  -- Hop n+1: views referencing a view already discovered.
  SELECT
    v.project, v.dataset, v.view_name, v.full_name,
    v.proj_re, v.ds_re, v.name_re,
    d.hops + 1,
    CONCAT(v.full_name, ' -> ', d.path)
  FROM all_views v
  JOIN deps d
    ON v.full_name != d.full_name
   AND d.hops < 50
   AND REGEXP_CONTAINS(
         v.def_norm,
         CONCAT(r'(?:^|[^A-Za-z0-9_.\-])(?:', d.proj_re, r'\.)?',
                d.ds_re, r'\.', d.name_re, r'(?:$|[^A-Za-z0-9_])'))
)

SELECT
  project, dataset, view_name,
  MIN(hops)       AS min_hops,     -- 1 = direct, 2 = via one intermediate view, ...
  COUNT(*)        AS paths_found,
  ANY_VALUE(path) AS example_path
FROM deps
GROUP BY project, dataset, view_name
ORDER BY min_hops, project, dataset, view_name;
