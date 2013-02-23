alter table litlistitem alter column dbname drop not null; 
alter table litlistitem alter column titleisbn drop not null; 
alter table litlistitem alter column titleid drop not null; 
alter table litlistitem alter column titleid type text; 
alter table litlistitem alter column dbname type text; 
alter table litlistitem alter column titleisbn type text;
alter table collection add column tstamp timestamp;
alter table sessioncollection add column tstamp timestamp;
alter table sessioncollection add column comment text default '';
alter table collection add column comment text default '';
alter table litlistitem add column comment text default '';
alter table collection rename to usercollection;
 alter table databaseinfo alter column dbname type text;
alter table databaseinfo alter column sigel type text; 
 alter table databaseinfo alter column protocol type text; 
alter table databaseinfo alter column host type text; 
alter table databaseinfo alter column remoteuser type text; 
alter table databaseinfo alter column remotepassword type text; 
 alter table databaseinfo alter column titlefile type text; 
alter table databaseinfo alter column personfile type text; 
alter table databaseinfo alter column corporatebodyfile type text; 
alter table databaseinfo alter column subjectfile type text; 
alter table databaseinfo alter column classificationfile type text; 
alter table databaseinfo alter column holdingfile type text; 
alter table sessioncollection alter column titleid type text;
alter table recordhistory alter column titleid type text;
alter table eventlog alter column content type text;
alter table searchhistory alter column dbname type text;
alter table userinfo alter column username type text;
alter table role alter column name type text;
alter table searchfield alter column searchfield type text;
alter table livesearch alter column searchfield type text;
alter table usercollection alter column titleid type text;
alter table tag alter column name type text;
alter table tit_tag alter column dbname type text;
alter table tit_tag alter column titleid type text;
alter table tit_tag alter column titleisbn type text;
alter table review alter column titleid type text;
alter table review alter column titleisbn type text;
alter table review alter column dbname type text;
alter table review alter column nickname type text;
alter table review alter column title type text;
alter table profileinfo alter column profilename type text;
alter table orgunitinfo alter column orgunitname type text;
alter table profileinfo alter column profilename type 
alter table registration alter column id type text;
alter table subjectclassification alter column classification type text;
alter table subjectclassification alter column type type text;
alter table sessioninfo alter column sessionid type text;
alter table libraryinfo rename column indicator to mult;
alter table libraryinfo rename column category to field;
alter table libraryinfo add column subfield varchar(2);

alter table subject rename to topic;
alter table litlist_subject rename to litlist_topic;
alter table subjectclassification rename to topicclassification;
alter table litlist_topic rename column subjectid  to topicid;
alter table topicclassification rename column subjectid  to topicid;
alter table logintarget rename to authenticator;
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_authenticator FOREIGN KEY (targetid) REFERENCES authenticator (id);
alter table user_session drop constraint fk_usersession_logintarget;
alter table logintarget_id_seq rename to authenticator_id_seq;
ALTER TABLE topicclassification ADD CONSTRAINT fk_topicclassification_topic FOREIGN KEY (topicid) REFERENCES topic (id);
ALTER TABLE topicclassification DROP CONSTRAINT fk_subjectclassification_subject;
ALTER TABLE litlist_topic ADD CONSTRAINT fk_litlisttopic_litlist FOREIGN KEY (litlistid) REFERENCES litlist (id);
ALTER TABLE litlist_topic ADD CONSTRAINT fk_litlisttopic_topic FOREIGN KEY (topicid) REFERENCES topic (id);
ALTER TABLE litlist_topic DROP CONSTRAINT fk_litlistsubject_litlist;
ALTER TABLE litlist_topic DROP CONSTRAINT fk_litlistsubject_subject;
alter table litlist_subject_id_seq rename to litlist_topic_id_seq;

alter table serverinfo rename column host to hostip;
alter table serverinfo add column description text;
alter table serverinfo add column status text;
alter table serverinfo add column clusterid BIGINT;

CREATE TABLE clusterinfo (
 id           BIGSERIAL,
 clustername  TEXT,
 description  TEXT,
 status       TEXT,
 active       BOOL
);

ALTER TABLE serverinfo ADD CONSTRAINT fk_serverinfo_clusterinfo FOREIGN KEY (clusterid) REFERENCES clusterinfo (id);

alter table databaseinfo drop column use_libinfo; 

alter table databaseinfo add column locationid bigint;
ALTER TABLE databaseinfo ADD CONSTRAINT fk_databaseinfo_locationinfo FOREIGN KEY (locationid) REFERENCES locationinfo (id);

alter table locationinfo add column description text;

alter table authenticator rename to authenticator;

alter table tit_tag add column tstamp timestamp;
alter table authenticator rename remotedb to dbname;

alter table sessioninfo add column viewname text;
