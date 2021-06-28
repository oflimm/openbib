drop table IF EXISTS databaseinfo_searchengine;
create table databaseinfo_searchengine (
 id            BIGSERIAL,
 dbid          BIGINT NOT NULL,
 searchengine  TEXT
);

ALTER TABLE databaseinfo_searchengine ADD CONSTRAINT fk_databaseinfo_searchengine_database FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX databaseinfo_searchengine_database ON databaseinfo_searchengine (dbid);

alter TABLE viewinfo add column searchengine TEXT DEFAULT '';

insert into databaseinfo_searchengine (dbid, searchengine) select id,'xapian' from databaseinfo;
