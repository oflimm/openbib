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

 viewname       TEXT,
 network        CIDR,

 createtime_year   SMALLINT,
 createtime_month  SMALLINT,
 createtime_day    SMALLINT
);

drop table IF EXISTS titleusage;
CREATE TABLE titleusage (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname     TEXT,
 isbn         TEXT,
 dbname       TEXT NOT NULL,
 titleid           TEXT NOT NULL,
 origin       SMALLINT
) PARTITION BY RANGE (tstamp);

drop table IF EXISTS eventlog;
CREATE TABLE eventlog (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
) PARTITION BY RANGE (tstamp);

drop table IF EXISTS eventlogjson;
CREATE TABLE eventlogjson (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
) PARTITION BY RANGE (tstamp);

drop table IF EXISTS searchterms;
CREATE TABLE searchterms (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname   TEXT,
 type       INT,
 content    TEXT
) PARTITION BY RANGE (tstamp);

drop table IF EXISTS searchfields;
CREATE TABLE searchfields (
 id           BIGSERIAL,
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
 source         BOOL,
 year           BOOL,
 content        BOOL
) PARTITION BY RANGE (tstamp);

drop table IF EXISTS loans;
CREATE TABLE loans (
 id           BIGSERIAL,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 anon_userid   VARCHAR(33),
 groupid       VARCHAR(1),
 isbn          VARCHAR(13),
 dbname        TEXT,
 titleid       TEXT	
) PARTITION BY RANGE (tstamp);

DROP TABLE IF EXISTS networkinfo;

CREATE TABLE networkinfo (
    id BIGSERIAL,
    network CIDR NOT NULL,
    country TEXT,
    continent TEXT,
    is_eu INT
);
