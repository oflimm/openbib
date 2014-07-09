CREATE OR REPLACE FUNCTION trg_partition()
  RETURNS TRIGGER AS
$BODY$
DECLARE
prefix text := '';
timeformat text;
selector text;
_interval INTERVAL;
tablename text;
startdate text;
enddate text;
indexfield text;
i int;
maxargs int;
create_table_part text;
create_index_part text;
BEGIN
 
selector = TG_ARGV[0];
maxargs = TG_NARGS;

IF selector = 'day' THEN
timeformat := 'YYYY_MM_DD';
ELSIF selector = 'month' THEN
timeformat := 'YYYY_MM';
ELSIF selector = 'year' THEN
timeformat := 'YYYY';
END IF;
 
_interval := '1 ' || selector;
tablename :=  TG_TABLE_NAME || '_p' || TO_CHAR(NEW.tstamp, timeformat);
 
EXECUTE 'INSERT INTO ' || prefix || quote_ident(tablename) || ' SELECT ($1).*' USING NEW;
RETURN NULL;
 
EXCEPTION
WHEN undefined_table THEN
 
startdate := EXTRACT(epoch FROM date_trunc(selector, NEW.tstamp));
enddate := EXTRACT(epoch FROM date_trunc(selector, NEW.tstamp + _interval ));
 
-- create table
create_table_part:= 'CREATE TABLE IF NOT EXISTS '|| prefix || quote_ident(tablename) || ' (CHECK ((tstamp >= ' || quote_literal(to_timestamp(startdate::int)) || ' AND tstamp < ' || quote_literal(to_timestamp(enddate::int)) || '))) INHERITS ('|| TG_TABLE_NAME || ')';
RAISE NOTICE 'A partition table has been created %',create_table_part;
EXECUTE create_table_part;

--create index accordning to args
i:= 1;

while i < maxargs
LOOP
  indexfield = TG_ARGV[i];
  create_index_part:= 'CREATE INDEX '|| quote_ident(tablename) || '_' || quote_ident(indexfield) || ' on ' || quote_ident(tablename) || ' USING btree (' || quote_ident(indexfield) || ')';
  RAISE NOTICE 'An index has been created %',create_index_part;
  EXECUTE create_index_part;
  i:= i + 1;
END LOOP;
 
--insert it again
EXECUTE 'INSERT INTO ' || prefix || quote_ident(tablename) || ' SELECT ($1).*' USING NEW;
RETURN NULL;
 
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;

ALTER FUNCTION trg_partition()
  OWNER TO postgres;

CREATE OR REPLACE FUNCTION run_on_partitions(text,text) RETURNS INTEGER AS $$
DECLARE
 partition RECORD;
 tablename TEXT = $1;
 sql TEXT = $2;
 sqlReplaced TEXT;
BEGIN
FOR partition IN 
 SELECT pg_class.relname as rel 
 FROM pg_catalog.pg_inherits 
  INNER JOIN pg_catalog.pg_class ON (pg_inherits.inhrelid = pg_class.oid) 
  INNER JOIN pg_catalog.pg_namespace ON (pg_class.relnamespace = pg_namespace.oid) 
 WHERE inhparent = tablename::regclass 
LOOP
 sqlReplaced := replace(sql, 'PARTITION',partition.rel);
 RAISE NOTICE 'Executing: %', sqlReplaced;
 BEGIN
   EXECUTE  sqlReplaced;
   exception when others then 
    RAISE NOTICE 'Ignored Error: % %', SQLERRM, SQLSTATE ;
 END ;
END LOOP;
RETURN 1;
END;
$$ LANGUAGE plpgsql;
