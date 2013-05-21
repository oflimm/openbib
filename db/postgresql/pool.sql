-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

-------------------------------------------------
-------------- Autorenstammdatei ----------------
-------------------------------------------------

drop table IF EXISTS person;
create table person (
 id            TEXT,
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS person_fields;
create table person_fields (
 id            BIGSERIAL,
 personid      TEXT        NOT NULL,
 field         SMALLINT    NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT        NOT NULL
);

-------------------------------------------------
------------Koerperschaftsstammdatei ------------
-------------------------------------------------

drop table IF EXISTS corporatebody;
create table corporatebody (
 id            TEXT,
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS corporatebody_fields;
create table corporatebody_fields (
 id               BIGSERIAL,
 corporatebodyid  TEXT        NOT NULL,
 field            SMALLINT    NOT NULL,
 mult             SMALLINT,
 subfield         VARCHAR(2),
 content          TEXT        NOT NULL
);

-------------------------------------------------
------------ Schlagwortstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS subject;
create table subject (
 id            TEXT,
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS subject_fields;
create table subject_fields (
 id            BIGSERIAL,
 subjectid     TEXT       NOT NULL,
 field         SMALLINT   NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT       NOT NULL
);

-------------------------------------------------
-------------- Notationstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS classification;
create table classification (
 id            TEXT,
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS classification_fields;
create table classification_fields (
 id                BIGSERIAL,
 classificationid  TEXT        NOT NULL,
 field             SMALLINT    NOT NULL,
 mult              SMALLINT,
 subfield          VARCHAR(2),
 content           TEXT        NOT NULL
);

-------------------------------------------------
--------------- Titelstammdatei -----------------
-------------------------------------------------

drop table IF EXISTS title;
create table title (
 id            TEXT,
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 titlecache    TEXT,
 popularity    INT
);

drop table IF EXISTS title_fields;
create table title_fields (
 id            BIGSERIAL,
 titleid       TEXT NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

-------------------------------------------------
-------------- Exemplarstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS holding;
create table holding (
 id            TEXT
);

drop table IF EXISTS holding_fields;
create table holding_fields (
 id            BIGSERIAL,
 holdingid     TEXT        NOT NULL,
 field         SMALLINT    NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT        NOT NULL
);

-------Connectoren ---------

drop table IF EXISTS title_title;
create table title_title (
id                BIGSERIAL,
field             SMALLINT,
source_titleid    TEXT     NOT NULL,
target_titleid    TEXT     NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_person;
create table title_person (
id         BIGSERIAL,
field      SMALLINT,
titleid    TEXT         NOT NULL,
personid   TEXT          NOT NULL,
supplement TEXT
);

drop table IF EXISTS title_corporatebody;
create table title_corporatebody (
id                BIGSERIAL,
field             SMALLINT,
titleid           TEXT NOT NULL,
corporatebodyid   TEXT NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_subject;
create table title_subject (
id         BIGSERIAL,
field      SMALLINT,
titleid    TEXT NOT NULL,
subjectid  TEXT NOT NULL,
supplement TEXT
);

drop table IF EXISTS title_classification;
create table title_classification (
id                BIGSERIAL,
field             SMALLINT,
titleid           TEXT NOT NULL,
classificationid  TEXT NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_holding;
create table title_holding (
id         BIGSERIAL,
field      SMALLINT,
titleid    TEXT NOT NULL,
holdingid  TEXT NOT NULL,
supplement TEXT
);
