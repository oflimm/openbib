ALTER TABLE title_title DROP CONSTRAINT fk_titletitle_sourcetitle;
ALTER TABLE title_title DROP CONSTRAINT fk_titletitle_targettitle;

DROP INDEX titletitle_sourcetitleid;
DROP INDEX titletitle_targettitleid;

-------------------------------------------------

ALTER TABLE title_person DROP CONSTRAINT fk_titleperson_person;
ALTER TABLE title_person DROP CONSTRAINT fk_titleperson_title;

DROP INDEX titleperson_personid;
DROP INDEX titleperson_titleid;

-------------------------------------------------

ALTER TABLE title_corporatebody DROP CONSTRAINT fk_titlecorporatebody_corporatebody;
ALTER TABLE title_corporatebody DROP CONSTRAINT fk_titlecorporatebody_title;

DROP INDEX titlecorporatebody_corporatebodyid;
DROP INDEX titlecorporatebody_titleid;

-------------------------------------------------

ALTER TABLE title_subject DROP CONSTRAINT fk_titlesubject_subject;
ALTER TABLE title_subject DROP CONSTRAINT fk_titlesubject_title;

DROP INDEX titlesubject_subjectid;
DROP INDEX titlesubject_titleid;

-------------------------------------------------

ALTER TABLE title_classification DROP CONSTRAINT fk_titleclassification_classification;
ALTER TABLE title_classification DROP CONSTRAINT fk_titleclassification_title;

DROP INDEX titleclassification_classificationid;
DROP INDEX titleclassification_titleid;

-------------------------------------------------

ALTER TABLE title_holding DROP CONSTRAINT fk_titleholding_holding;
ALTER TABLE title_holding DROP CONSTRAINT fk_titleholding_title;

DROP INDEX titleholding_holdingid;
DROP INDEX titleholding_titleid;

-------------------------------------------------

ALTER TABLE person_fields DROP CONSTRAINT fk_person_fields;

DROP INDEX person_fields_personid;
DROP INDEX person_fields_field;
DROP INDEX person_fields_mult;
DROP INDEX person_fields_subfield;
DROP INDEX person_fields_content;

-------------------------------------------------

ALTER TABLE person DROP CONSTRAINT person_pkey;

DROP INDEX person_id;
DROP INDEX person_tstamp_create;
DROP INDEX person_tstamp_update;

-------------------------------------------------

ALTER TABLE corporatebody_fields DROP CONSTRAINT fk_corporatebody_fields;

DROP INDEX corporatebody_fields_corporatebodyid;
DROP INDEX corporatebody_fields_field;
DROP INDEX corporatebody_fields_mult;
DROP INDEX corporatebody_fields_subfield;
DROP INDEX corporatebody_fields_content;

-------------------------------------------------

ALTER TABLE corporatebody DROP CONSTRAINT corporatebody_pkey;

DROP INDEX corporatebody_id;
DROP INDEX corporatebody_tstamp_create;
DROP INDEX corporatebody_tstamp_update;

-------------------------------------------------

ALTER TABLE subject_fields DROP CONSTRAINT fk_subject_fields;

DROP INDEX subject_fields_subjectid;
DROP INDEX subject_fields_field;
DROP INDEX subject_fields_mult;
DROP INDEX subject_fields_subfield;
DROP INDEX subject_fields_content;

-------------------------------------------------

ALTER TABLE subject DROP CONSTRAINT subject_pkey;

DROP INDEX subject_id;
DROP INDEX subject_tstamp_create;
DROP INDEX subject_tstamp_update;

-------------------------------------------------

ALTER TABLE classification_fields DROP CONSTRAINT fk_classification_fields;

DROP INDEX classification_fields_classificationid;
DROP INDEX classification_fields_field;
DROP INDEX classification_fields_mult;
DROP INDEX classification_fields_subfield;
DROP INDEX classification_fields_content;

-------------------------------------------------

ALTER TABLE classification DROP CONSTRAINT classification_pkey;

DROP INDEX classification_id;
DROP INDEX classification_tstamp_create;
DROP INDEX classification_tstamp_update;

-------------------------------------------------

ALTER TABLE title_fields DROP CONSTRAINT fk_title_fields;

DROP INDEX title_fields_titleid;
DROP INDEX title_fields_field;
DROP INDEX title_fields_mult;
DROP INDEX title_fields_subfield;
DROP INDEX title_fields_content;

-------------------------------------------------

ALTER TABLE title DROP CONSTRAINT title_pkey;

DROP INDEX title_id;
DROP INDEX title_tstamp_create;
DROP INDEX title_tstamp_update;
DROP INDEX title_popularity;


-------------------------------------------------

ALTER TABLE holding_fields DROP CONSTRAINT fk_holding_fields;

DROP INDEX holding_fields_holdingid;
DROP INDEX holding_fields_field;
DROP INDEX holding_fields_mult;
DROP INDEX holding_fields_subfield;
DROP INDEX holding_fields_content;

-------------------------------------------------

ALTER TABLE holding DROP CONSTRAINT holding_pkey;

DROP INDEX holding_id;

-------------------------------------------------
