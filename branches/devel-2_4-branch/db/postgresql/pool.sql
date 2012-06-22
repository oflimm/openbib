-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

-------------------------------------------------
-------------- Autorenstammdatei ----------------
-------------------------------------------------

drop table IF EXISTS person;
create table person (
 id            VARCHAR(255) primary key,
 tstamp_create BIGINT,
 tstamp_update BIGINT
);

create index person_id on person (id);
create index person_tstamp_create on person (tstamp_create);
create index person_tstamp_update on person (tstamp_update);

drop table IF EXISTS person_fields;
create table person_fields (
 personid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

ALTER TABLE person_fields ADD CONSTRAINT fk_person_fields FOREIGN KEY (personid) REFERENCES person (id);

create index person_fields_personid on person_fields (personid);
create index person_fields_field on person_fields (field);
create index person_fields_mult on person_fields (mult);
create index person_fields_subfield on person_fields (subfield);
create index person_fields_content on person_fields (content);

drop table IF EXISTS person_normfields;
create table person_normfields (
 personid      VARCHAR(255) NOT NULL,
 field         SMALLINT NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT
);

ALTER TABLE person_normfields ADD CONSTRAINT fk_person_normfields FOREIGN KEY (personid) REFERENCES person (id);

create index person_normfields_personid on person_normfields (personid);
create index person_normfields_field on person_normfields (field);
create index person_normfields_mult on person_normfields (mult);
create index person_normfields_subfield on person_normfields (subfield);
create index person_normfields_content on person_normfields (content);

-------------------------------------------------
------------Koerperschaftsstammdatei ------------
-------------------------------------------------

drop table IF EXISTS corporatebody;
create table corporatebody (
 id            VARCHAR(255) primary key,
 tstamp_create BIGINT,
 tstamp_update BIGINT
);

create index corporatebody_id on corporatebody (id);
create index corporatebody_tstamp_create on corporatebody (tstamp_create);
create index corporatebody_tstamp_update on corporatebody (tstamp_update);

drop table IF EXISTS corporatebody_fields;
create table corporatebody_fields (
 corporatebodyid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

ALTER TABLE corporatebody_fields ADD CONSTRAINT fk_corporatebody_fields FOREIGN KEY (corporatebodyid) REFERENCES corporatebody (id);

create index corporatebody_fields_corporatebodyid on corporatebody_fields (corporatebodyid);
create index corporatebody_fields_field on corporatebody_fields (field);
create index corporatebody_fields_mult on corporatebody_fields (mult);
create index corporatebody_fields_subfield on corporatebody_fields (subfield);
create index corporatebody_fields_content on corporatebody_fields (content);

drop table IF EXISTS corporatebody_normfields;
create table corporatebody_normfields (
 corporatebodyid      VARCHAR(255) NOT NULL,
 field         SMALLINT NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT
);

ALTER TABLE corporatebody_normfields ADD CONSTRAINT fk_corporatebody_normfields FOREIGN KEY (corporatebodyid) REFERENCES corporatebody (id);

create index corporatebody_normfields_corporatebodyid on corporatebody_normfields (corporatebodyid);
create index corporatebody_normfields_field on corporatebody_normfields (field);
create index corporatebody_normfields_mult on corporatebody_normfields (mult);
create index corporatebody_normfields_subfield on corporatebody_normfields (subfield);
create index corporatebody_normfields_content on corporatebody_normfields (content);


-------------------------------------------------
------------ Schlagwortstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS subject;
create table subject (
 id            VARCHAR(255) primary key,
 tstamp_create BIGINT,
 tstamp_update BIGINT
);

create index subject_id on subject (id);
create index subject_tstamp_create on subject (tstamp_create);
create index subject_tstamp_update on subject (tstamp_update);

drop table IF EXISTS subject_fields;
create table subject_fields (
 subjectid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

ALTER TABLE subject_fields ADD CONSTRAINT fk_subject_fields FOREIGN KEY (subjectid) REFERENCES subject (id);

create index subject_fields_subjectid on subject_fields (subjectid);
create index subject_fields_field on subject_fields (field);
create index subject_fields_mult on subject_fields (mult);
create index subject_fields_subfield on subject_fields (subfield);
create index subject_fields_content on subject_fields (content);

drop table IF EXISTS subject_normfields;
create table subject_normfields (
 subjectid      VARCHAR(255) NOT NULL,
 field         SMALLINT NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT
);

ALTER TABLE subject_normfields ADD CONSTRAINT fk_subject_normfields FOREIGN KEY (subjectid) REFERENCES subject (id);

create index subject_normfields_subjectid on subject_normfields (subjectid);
create index subject_normfields_field on subject_normfields (field);
create index subject_normfields_mult on subject_normfields (mult);
create index subject_normfields_subfield on subject_normfields (subfield);
create index subject_normfields_content on subject_normfields (content);


-------------------------------------------------
-------------- Notationstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS classification;
create table classification (
 id            VARCHAR(255) primary key,
 tstamp_create BIGINT,
 tstamp_update BIGINT
);

create index classification_id on classification (id);
create index classification_tstamp_create on classification (tstamp_create);
create index classification_tstamp_update on classification (tstamp_update);

drop table IF EXISTS classification_fields;
create table classification_fields (
 classificationid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

ALTER TABLE classification_fields ADD CONSTRAINT fk_classification_fields FOREIGN KEY (classificationid) REFERENCES classification (id);

create index classification_fields_classificationid on classification_fields (classificationid);
create index classification_fields_field on classification_fields (field);
create index classification_fields_mult on classification_fields (mult);
create index classification_fields_subfield on classification_fields (subfield);
create index classification_fields_content on classification_fields (content);

drop table IF EXISTS classification_normfields;
create table classification_normfields (
 classificationid      VARCHAR(255) NOT NULL,
 field         SMALLINT NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT
);

ALTER TABLE classification_normfields ADD CONSTRAINT fk_classification_normfields FOREIGN KEY (classificationid) REFERENCES classification (id);

create index classification_normfields_classificationid on classification_normfields (classificationid);
create index classification_normfields_field on classification_normfields (field);
create index classification_normfields_mult on classification_normfields (mult);
create index classification_normfields_subfield on classification_normfields (subfield);
create index classification_normfields_content on classification_normfields (content);

-------------------------------------------------
--------------- Titelstammdatei -----------------
-------------------------------------------------

drop table IF EXISTS title;
create table title (
 id            VARCHAR(255) primary key,
 tstamp_create BIGINT,
 tstamp_update BIGINT,
 titlecache    TEXT,
 popularity    INT
);

create index title_id on title (id);
create index title_tstamp_create on title (tstamp_create);
create index title_tstamp_update on title (tstamp_update);
create index title_popularity on title (popularity);

drop table IF EXISTS title_fields;
create table title_fields (
 titleid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

ALTER TABLE title_fields ADD CONSTRAINT fk_title_fields FOREIGN KEY (titleid) REFERENCES title (id);

create index title_fields_titleid on title_fields (titleid);
create index title_fields_field on title_fields (field);
create index title_fields_mult on title_fields (mult);
create index title_fields_subfield on title_fields (subfield);
create index title_fields_content on title_fields (content);

drop table IF EXISTS title_normfields;
create table title_normfields (
 titleid      VARCHAR(255) NOT NULL,
 field         SMALLINT NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT
);

ALTER TABLE title_normfields ADD CONSTRAINT fk_title_normfields FOREIGN KEY (titleid) REFERENCES title (id);

create index title_normfields_titleid on title_normfields (titleid);
create index title_normfields_field on title_normfields (field);
create index title_normfields_mult on title_normfields (mult);
create index title_normfields_subfield on title_normfields (subfield);
create index title_normfields_content on title_normfields (content);

-------------------------------------------------
-------------- Exemplarstammdatei ---------------
-------------------------------------------------

drop table IF EXISTS holding;
create table holding (
 id            VARCHAR(255) primary key
);

create index holding_id on holding (id);

drop table IF EXISTS holding_fields;
create table holding_fields (
 holdingid      VARCHAR(255) NOT NULL,
 field         SMALLINT  NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT NOT NULL
);

ALTER TABLE holding_fields ADD CONSTRAINT fk_holding_fields FOREIGN KEY (holdingid) REFERENCES holding (id);

create index holding_fields_holdingid on holding_fields (holdingid);
create index holding_fields_field on holding_fields (field);
create index holding_fields_mult on holding_fields (mult);
create index holding_fields_subfield on holding_fields (subfield);
create index holding_fields_content on holding_fields (content);

drop table IF EXISTS holding_normfields;
create table holding_normfields (
 holdingid      VARCHAR(255) NOT NULL,
 field         SMALLINT NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT
);

ALTER TABLE holding_normfields ADD CONSTRAINT fk_holding_normfields FOREIGN KEY (holdingid) REFERENCES holding (id);

create index holding_normfields_holdingid on holding_normfields (holdingid);
create index holding_normfields_field on holding_normfields (field);
create index holding_normfields_mult on holding_normfields (mult);
create index holding_normfields_subfield on holding_normfields (subfield);
create index holding_normfields_content on holding_normfields (content);

-------Connectoren ---------

drop table IF EXISTS title_title;
create table title_title (
field             SMALLINT,
source_titleid    VARCHAR(255) NOT NULL,
target_titleid    VARCHAR(255) NOT NULL,
supplement        TEXT
);

ALTER TABLE title_title ADD CONSTRAINT fk_titletitle_sourcetitle FOREIGN KEY (source_titleid) REFERENCES title(id);
ALTER TABLE title_title ADD CONSTRAINT fk_titletitle_targettitle FOREIGN KEY (target_titleid) REFERENCES title(id);

create index titletitle_sourcetitleid on title_title (source_titleid);
create index titletitle_targettitleid on title_title (target_titleid);


drop table IF EXISTS title_person;
create table title_person (
field   SMALLINT,
titleid    VARCHAR(255) NOT NULL,
personid   VARCHAR(255) NOT NULL,
supplement TEXT
);

ALTER TABLE title_person ADD CONSTRAINT fk_titleperson_person FOREIGN KEY (personid) REFERENCES person(id);
ALTER TABLE title_person ADD CONSTRAINT fk_titleperson_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titleperson_personid on title_person (personid);
create index titleperson_titleid on title_person (titleid);

drop table IF EXISTS title_corporatebody;
create table title_corporatebody (
field   SMALLINT,
titleid    VARCHAR(255) NOT NULL,
corporatebodyid   VARCHAR(255) NOT NULL,
supplement TEXT
);

ALTER TABLE title_corporatebody ADD CONSTRAINT fk_titlecorporatebody_corporatebody FOREIGN KEY (corporatebodyid) REFERENCES corporatebody(id);
ALTER TABLE title_corporatebody ADD CONSTRAINT fk_titlecorporatebody_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titlecorporatebody_corporatebodyid on title_corporatebody (corporatebodyid);
create index titlecorporatebody_titleid on title_corporatebody (titleid);

drop table IF EXISTS title_subject;
create table title_subject (
field   SMALLINT,
titleid    VARCHAR(255) NOT NULL,
subjectid   VARCHAR(255) NOT NULL,
supplement TEXT
);

ALTER TABLE title_subject ADD CONSTRAINT fk_titlesubject_subject FOREIGN KEY (subjectid) REFERENCES subject(id);
ALTER TABLE title_subject ADD CONSTRAINT fk_titlesubject_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titlesubject_subjectid on title_subject (subjectid);
create index titlesubject_titleid on title_subject (titleid);

drop table IF EXISTS title_classification;
create table title_classification (
field   SMALLINT,
titleid    VARCHAR(255) NOT NULL,
classificationid   VARCHAR(255) NOT NULL,
supplement TEXT
);

ALTER TABLE title_classification ADD CONSTRAINT fk_titleclassification_classification FOREIGN KEY (classificationid) REFERENCES classification(id);
ALTER TABLE title_classification ADD CONSTRAINT fk_titleclassification_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titleclassification_classificationid on title_classification (classificationid);
create index titleclassification_titleid on title_classification (titleid);

drop table IF EXISTS title_holding;
create table title_holding (
field   SMALLINT,
titleid    VARCHAR(255) NOT NULL,
holdingid   VARCHAR(255) NOT NULL,
supplement TEXT
);

ALTER TABLE title_holding ADD CONSTRAINT fk_titleholding_holding FOREIGN KEY (holdingid) REFERENCES holding(id);
ALTER TABLE title_holding ADD CONSTRAINT fk_titleholding_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titleholding_holdingid on title_holding (holdingid);
create index titleholding_titleid on title_holding (titleid);
