ALTER TABLE person ADD PRIMARY KEY (id);

create index person_tstamp_create on person (tstamp_create);
create index person_tstamp_update on person (tstamp_update);

-------------------------------------------------
ALTER TABLE person_fields ADD PRIMARY KEY (id);
ALTER TABLE person_fields ADD CONSTRAINT fk_person_fields FOREIGN KEY (personid) REFERENCES person (id);

create index person_fields_personid on person_fields (personid);
create index person_fields_field on person_fields (field);
create index person_fields_mult on person_fields (mult);
create index person_fields_subfield on person_fields (subfield);
create index person_fields_content on person_fields (content);

-------------------------------------------------

ALTER TABLE corporatebody ADD PRIMARY KEY (id);

create index corporatebody_tstamp_create on corporatebody (tstamp_create);
create index corporatebody_tstamp_update on corporatebody (tstamp_update);

-------------------------------------------------
ALTER TABLE corporatebody_fields ADD PRIMARY KEY (id);
ALTER TABLE corporatebody_fields ADD CONSTRAINT fk_corporatebody_fields FOREIGN KEY (corporatebodyid) REFERENCES corporatebody (id);

create index corporatebody_fields_corporatebodyid on corporatebody_fields (corporatebodyid);
create index corporatebody_fields_field on corporatebody_fields (field);
create index corporatebody_fields_mult on corporatebody_fields (mult);
create index corporatebody_fields_subfield on corporatebody_fields (subfield);
create index corporatebody_fields_content on corporatebody_fields (content);

-------------------------------------------------

ALTER TABLE subject ADD PRIMARY KEY (id);

create index subject_tstamp_create on subject (tstamp_create);
create index subject_tstamp_update on subject (tstamp_update);

-------------------------------------------------
ALTER TABLE subject_fields ADD PRIMARY KEY (id);
ALTER TABLE subject_fields ADD CONSTRAINT fk_subject_fields FOREIGN KEY (subjectid) REFERENCES subject (id);

create index subject_fields_subjectid on subject_fields (subjectid);
create index subject_fields_field on subject_fields (field);
create index subject_fields_mult on subject_fields (mult);
create index subject_fields_subfield on subject_fields (subfield);
create index subject_fields_content on subject_fields (content);

-------------------------------------------------

ALTER TABLE classification ADD PRIMARY KEY (id);

create index classification_tstamp_create on classification (tstamp_create);
create index classification_tstamp_update on classification (tstamp_update);

-------------------------------------------------
ALTER TABLE classification_fields ADD PRIMARY KEY (id);
ALTER TABLE classification_fields ADD CONSTRAINT fk_classification_fields FOREIGN KEY (classificationid) REFERENCES classification (id);

create index classification_fields_classificationid on classification_fields (classificationid);
create index classification_fields_field on classification_fields (field);
create index classification_fields_mult on classification_fields (mult);
create index classification_fields_subfield on classification_fields (subfield);
create index classification_fields_content on classification_fields (content);

-------------------------------------------------

ALTER TABLE title ADD PRIMARY KEY (id);

create index title_tstamp_create on title (tstamp_create);
create index title_tstamp_update on title (tstamp_update);
create index title_popularity on title (popularity);

-------------------------------------------------
ALTER TABLE title_fields ADD PRIMARY KEY (id);
ALTER TABLE title_fields ADD CONSTRAINT fk_title_fields FOREIGN KEY (titleid) REFERENCES title (id);

create index title_fields_titleid on title_fields (titleid);
create index title_fields_field on title_fields (field);
create index title_fields_mult on title_fields (mult);
create index title_fields_subfield on title_fields (subfield);
create index title_fields_content on title_fields (substring(content,0,1000));

-------------------------------------------------

ALTER TABLE holding ADD PRIMARY KEY (id);

-------------------------------------------------
ALTER TABLE holding_fields ADD PRIMARY KEY (id);
ALTER TABLE holding_fields ADD CONSTRAINT fk_holding_fields FOREIGN KEY (holdingid) REFERENCES holding (id);

create index holding_fields_holdingid on holding_fields (holdingid);
create index holding_fields_field on holding_fields (field);
create index holding_fields_mult on holding_fields (mult);
create index holding_fields_subfield on holding_fields (subfield);
create index holding_fields_content on holding_fields (content);

-------------------------------------------------

ALTER TABLE title_title ADD PRIMARY KEY (id);

ALTER TABLE title_title ADD CONSTRAINT fk_titletitle_sourcetitle FOREIGN KEY (source_titleid) REFERENCES title(id);
ALTER TABLE title_title ADD CONSTRAINT fk_titletitle_targettitle FOREIGN KEY (target_titleid) REFERENCES title(id);

create index titletitle_sourcetitleid on title_title (source_titleid);
create index titletitle_targettitleid on title_title (target_titleid);

-------------------------------------------------

ALTER TABLE title_person ADD PRIMARY KEY (id);

ALTER TABLE title_person ADD CONSTRAINT fk_titleperson_person FOREIGN KEY (personid) REFERENCES person(id);
ALTER TABLE title_person ADD CONSTRAINT fk_titleperson_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titleperson_personid on title_person (personid);
create index titleperson_titleid on title_person (titleid);

-------------------------------------------------

ALTER TABLE title_corporatebody ADD PRIMARY KEY (id);

ALTER TABLE title_corporatebody ADD CONSTRAINT fk_titlecorporatebody_corporatebody FOREIGN KEY (corporatebodyid) REFERENCES corporatebody(id);
ALTER TABLE title_corporatebody ADD CONSTRAINT fk_titlecorporatebody_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titlecorporatebody_corporatebodyid on title_corporatebody (corporatebodyid);
create index titlecorporatebody_titleid on title_corporatebody (titleid);

-------------------------------------------------

ALTER TABLE title_subject ADD PRIMARY KEY (id);

ALTER TABLE title_subject ADD CONSTRAINT fk_titlesubject_subject FOREIGN KEY (subjectid) REFERENCES subject(id);
ALTER TABLE title_subject ADD CONSTRAINT fk_titlesubject_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titlesubject_subjectid on title_subject (subjectid);
create index titlesubject_titleid on title_subject (titleid);

-------------------------------------------------

ALTER TABLE title_classification ADD PRIMARY KEY (id);

ALTER TABLE title_classification ADD CONSTRAINT fk_titleclassification_classification FOREIGN KEY (classificationid) REFERENCES classification(id);
ALTER TABLE title_classification ADD CONSTRAINT fk_titleclassification_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titleclassification_classificationid on title_classification (classificationid);
create index titleclassification_titleid on title_classification (titleid);

-------------------------------------------------

ALTER TABLE title_holding ADD PRIMARY KEY (id);

ALTER TABLE title_holding ADD CONSTRAINT fk_titleholding_holding FOREIGN KEY (holdingid) REFERENCES holding(id);
ALTER TABLE title_holding ADD CONSTRAINT fk_titleholding_title FOREIGN KEY (titleid) REFERENCES title(id);

create index titleholding_holdingid on title_holding (holdingid);
create index titleholding_titleid on title_holding (titleid);
