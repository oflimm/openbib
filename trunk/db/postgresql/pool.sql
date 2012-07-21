-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

-------------------------------------------------
-------------- Autorenstammdatei ----------------
-------------------------------------------------

drop table IF EXISTS person;
create table person (
 id            VARCHAR(255),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS person_fields;
create table person_fields (
 personid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL,
 content_norm  TEXT
);

-------------------------------------------------
------------Koerperschaftsstammdatei ------------
-------------------------------------------------

drop table IF EXISTS corporatebody;
create table corporatebody (
 id            VARCHAR(255),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS corporatebody_fields;
create table corporatebody_fields (
 corporatebodyid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL,
 content_norm  TEXT
);

-------------------------------------------------
------------ Schlagwortstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS subject;
create table subject (
 id            VARCHAR(255),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS subject_fields;
create table subject_fields (
 subjectid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL,
 content_norm  TEXT
);

-------------------------------------------------
-------------- Notationstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS classification;
create table classification (
 id            VARCHAR(255),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP
);

drop table IF EXISTS classification_fields;
create table classification_fields (
 classificationid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL,
 content_norm  TEXT
);

-------------------------------------------------
--------------- Titelstammdatei -----------------
-------------------------------------------------

drop table IF EXISTS title;
create table title (
 id            VARCHAR(255),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 titlecache    TEXT,
 popularity    INT
);

drop table IF EXISTS title_fields;
create table title_fields (
 titleid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL,
 content_norm  TEXT
);

-------------------------------------------------
-------------- Exemplarstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS holding;
create table holding (
 id            VARCHAR(255)
);

drop table IF EXISTS holding_fields;
create table holding_fields (
 holdingid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL,
 content_norm  TEXT
);

-------Connectoren ---------

drop table IF EXISTS title_title;
create table title_title (
field             SMALLINT,
source_titleid    VARCHAR(255) NOT NULL,
target_titleid    VARCHAR(255) NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_person;
create table title_person (
field      SMALLINT,
titleid    VARCHAR(255) NOT NULL,
personid   VARCHAR(255) NOT NULL,
supplement TEXT
);

drop table IF EXISTS title_corporatebody;
create table title_corporatebody (
field             SMALLINT,
titleid           VARCHAR(255) NOT NULL,
corporatebodyid   VARCHAR(255) NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_subject;
create table title_subject (
field      SMALLINT,
titleid    VARCHAR(255) NOT NULL,
subjectid  VARCHAR(255) NOT NULL,
supplement TEXT
);

drop table IF EXISTS title_classification;
create table title_classification (
field             SMALLINT,
titleid           VARCHAR(255) NOT NULL,
classificationid  VARCHAR(255) NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_holding;
create table title_holding (
field      SMALLINT,
titleid    VARCHAR(255) NOT NULL,
holdingid  VARCHAR(255) NOT NULL,
supplement TEXT
);
