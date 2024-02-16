-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

-------------------------------------------------
-------------- Autorenstammdatei ----------------
-------------------------------------------------

drop table IF EXISTS person;
drop sequence IF EXISTS person_id_seq; 

create sequence person_id_seq;

create table person (
 id            TEXT default nextval('person_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
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
drop sequence IF EXISTS corporatebody_id_seq;

create sequence corporatebody_id_seq;

create table corporatebody (
 id            TEXT default nextval('corporatebody_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
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
drop sequence IF EXISTS subject_id_seq;

create sequence subject_id_seq;

create table subject (
 id            TEXT default nextval('subject_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
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
drop sequence IF EXISTS classification_id_seq;

create sequence classification_id_seq;

create table classification (
 id            TEXT default nextval('classification_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 import_hash   TEXT    
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
drop sequence IF EXISTS title_id_seq; 

create sequence title_id_seq;

create table title (
 id            TEXT default nextval('title_id_seq'::regclass),
 tstamp_create TIMESTAMP,
 tstamp_update TIMESTAMP,
 titlecache    TEXT,
 popularity    INT,
 import_hash   TEXT    
);

drop table IF EXISTS title_fields;
create table title_fields (
 id            BIGSERIAL,
 titleid       TEXT NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 ind           VARCHAR(2) DEFAULT '',
 content       TEXT NOT NULL
);

-------------------------------------------------
-------------- Exemplarstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS holding;
drop sequence IF EXISTS holding_id_seq; 

create sequence holding_id_seq;

create table holding (
 id            TEXT default nextval('holding_id_seq'::regclass),
 import_hash   TEXT    
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
mult              SMALLINT,
source_titleid    TEXT     NOT NULL,
target_titleid    TEXT     NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_person;
create table title_person (
id         BIGSERIAL,
field      SMALLINT,
mult       SMALLINT,
titleid    TEXT         NOT NULL,
personid   TEXT          NOT NULL,
supplement TEXT
);

drop table IF EXISTS title_corporatebody;
create table title_corporatebody (
id                BIGSERIAL,
field             SMALLINT,
mult       SMALLINT,
titleid           TEXT NOT NULL,
corporatebodyid   TEXT NOT NULL,
supplement        TEXT
);

drop table IF EXISTS title_subject;
create table title_subject (
id         BIGSERIAL,
field      SMALLINT,
mult       SMALLINT,
titleid    TEXT NOT NULL,
subjectid  TEXT NOT NULL,
supplement TEXT
);

drop table IF EXISTS title_classification;
create table title_classification (
id                BIGSERIAL,
field             SMALLINT,
mult       SMALLINT,
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
