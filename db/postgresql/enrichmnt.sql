-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

-- Enriched content by isbn --
drop table IF EXISTS enriched_content_by_isbn;
create table enriched_content_by_isbn (
 isbn          VARCHAR(13) NOT NULL,
 origin        SMALLINT,
 field         SMALLINT NOT NULL,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

-- Enriched content by bibkey --
drop table IF EXISTS enriched_content_by_bibkey;
create table enriched_content_by_bibkey (
 bibkey        VARCHAR(13) NOT NULL,
 origin        SMALLINT,
 field         SMALLINT NOT NULL,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

-- Enriched content by issn --
drop table IF EXISTS enriched_content_by_issn;
create table enriched_content_by_issn (
 issn          VARCHAR(13) NOT NULL,
 origin        SMALLINT,
 field         SMALLINT NOT NULL,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

--  references to all available titles in all databases by specific --
--  identification keys --
drop table IF EXISTS all_titles_by_isbn;
create table all_titles_by_isbn (
 isbn          VARCHAR(13)  NOT NULL,
 dbname        VARCHAR(25)  NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

drop table IF EXISTS all_titles_by_issn;
create table all_titles_by_issn (
 issn          VARCHAR(8)   NOT NULL,
 dbname        VARCHAR(25)  NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

drop table IF EXISTS all_titles_by_bibkey;
create table all_titles_by_bibkey (
 bibkey        VARCHAR(33) NOT NULL,
 dbname        VARCHAR(25) NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

drop table IF EXISTS all_titles_by_workkey;
create table all_titles_by_workkey (
 id            BIGSERIAL,
 workkey       TEXT NOT NULL,
 edition       TEXT,
 dbname        VARCHAR(25) NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 titlecache    TEXT,
 tstamp        TIMESTAMP
);

-- ISBN's belonging to the same WORK (eg. ThingISBN) --
drop table IF EXISTS work_by_isbn;
create table work_by_isbn (
 workid        VARCHAR(255) NOT NULL,
 isbn          VARCHAR(13)  NOT NULL,
 origin        SMALLINT
);

-- ISBN's belonging to the same subject area (eg. ISBNs in the same --
-- Wikipedia Article --
drop table IF EXISTS related_titles_by_isbn;
create table related_titles_by_isbn (
 id            VARCHAR(255) NOT NULL,
 isbn          VARCHAR(13)  NOT NULL,
 origin        SMALLINT
);

-- Data for autocompletion in livesearch --
drop table IF EXISTS livesearch_data;
create table livesearch_data (
 fs            TEXT NOT NULL,
 content       TEXT NOT NULL,
 type          SMALLINT,
 dbname        VARCHAR(25) NOT NULL
);
