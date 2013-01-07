-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

drop table IF EXISTS datacache;
CREATE TABLE datacache (
 id          TEXT,
 tstamp      TIMESTAMP,
 type        INT,
 subkey      TEXT,
 data        TEXT
);

drop table IF EXISTS sessioninfo;
CREATE TABLE sessioninfo (
 id            BIGSERIAL,
 sessionid     VARCHAR(70),
 createtime    TIMESTAMP,

 createtime_year   SMALLINT,
 createtime_month  SMALLINT,
 createtime_day    SMALLINT,
 viewname TEXT
);

drop table IF EXISTS titleusage;
CREATE TABLE titleusage (
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname     TEXT,
 isbn         TEXT,
 dbname       TEXT NOT NULL,
 id           TEXT NOT NULL,
 origin       SMALLINT
);

drop table IF EXISTS eventlog;
CREATE TABLE eventlog (
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
);

drop table IF EXISTS eventlogjson;
CREATE TABLE eventlogjson (
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
);

drop table IF EXISTS searchterms;
CREATE TABLE searchterms (
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname   TEXT,
 type       INT,
 content    TEXT
);

drop table IF EXISTS searchfields;
CREATE TABLE searchfields (
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname       TEXT,
 freesearch     BOOL,
 title          BOOL,
 person         BOOL,
 corporatebody  BOOL,
 subject        BOOL,
 classification BOOL,
 isbn           BOOL,
 issn           BOOL,
 mark           BOOL,
 mediatype      BOOL,
 titlestring    BOOL,
 content        BOOL,
 source         BOOL,
 year           BOOL
);

