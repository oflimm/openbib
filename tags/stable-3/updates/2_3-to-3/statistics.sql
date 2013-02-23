alter table datacache alter column id type text;
alter table datacache alter column subkey type text;
 alter table titleusage alter column isbn type text;
alter table titleusage alter column dbname type text;
alter table titleusage alter column id type text;
alter table searchterms alter column viewname type text;
 alter table searchterms alter column content type text;
alter table searchfields alter column viewname type text;

alter table sessioninfo add column viewname text;
alter table titleusage add column viewname text;

