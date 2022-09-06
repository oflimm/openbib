-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

-- Enriched content by isbn --
drop table IF EXISTS enriched_content_by_isbn;
create table enriched_content_by_isbn (
 isbn          VARCHAR(13) NOT NULL,
 origin        SMALLINT,
 field         SMALLINT NOT NULL,
 subfield      VARCHAR(3),
 content       TEXT NOT NULL
);

-- Enriched content by bibkey --
drop table IF EXISTS enriched_content_by_bibkey;
create table enriched_content_by_bibkey (
 bibkey        VARCHAR(33) NOT NULL,
 origin        SMALLINT,
 field         SMALLINT NOT NULL,
 subfield      VARCHAR(3),
 content       TEXT NOT NULL
);

-- Enriched content by issn --
drop table IF EXISTS enriched_content_by_issn;
create table enriched_content_by_issn (
 issn          VARCHAR(8) NOT NULL,
 origin        SMALLINT,
 field         SMALLINT NOT NULL,
 subfield      VARCHAR(3),
 content       TEXT NOT NULL
);

-- Enriched content by title --
drop table IF EXISTS enriched_content_by_title;
create table enriched_content_by_title (
 titleid       TEXT NOT NULL,
 dbname        TEXT NOT NULL,
 origin        SMALLINT,
 field         SMALLINT NOT NULL,
 subfield      VARCHAR(3),
 content       TEXT NOT NULL
);

--  references to all available titles in all databases by specific --
--  identification keys --
drop table IF EXISTS all_titles_by_isbn;
create table all_titles_by_isbn (
 id            BIGSERIAL,
 isbn          VARCHAR(13)  NOT NULL,
 dbname        VARCHAR(25)  NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

drop table IF EXISTS all_titles_by_issn;
create table all_titles_by_issn (
 id            BIGSERIAL,
 issn          VARCHAR(8)   NOT NULL,
 dbname        VARCHAR(25)  NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

drop table IF EXISTS all_titles_by_bibkey;
create table all_titles_by_bibkey (
 id            BIGSERIAL,
 bibkey        VARCHAR(33) NOT NULL,
 dbname        VARCHAR(25) NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
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
 location      VARCHAR(255),
 titlecache    TEXT,
 tstamp        TIMESTAMP
);

drop table IF EXISTS all_titles_by_location;
create table all_titles_by_location (
 location      VARCHAR(255) NOT NULL,
 dbname        VARCHAR(25) NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 tstamp        TIMESTAMP,
 titlecache    TEXT
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

-- Wikipedia Article --
drop table IF EXISTS wikiarticles_by_isbn;
create table wikiarticles_by_isbn (
 id            BIGSERIAL,
 article       TEXT, 
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
