-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

drop table IF EXISTS datacache;
CREATE TABLE datacache (
 id          VARCHAR(100) primary key,
 tstamp      TIMESTAMP,
 type        INT,
 subkey      VARCHAR(50),
 data        TEXT
);

create index datacache_id on datacache (id);
create index datacache_tstamp on datacache (tstamp);
create index datacache_subkey on datacache (subkey);
create index datacache_type on datacache (type);

drop table IF EXISTS sessioninfo;
CREATE TABLE sessioninfo (
 id            BIGINT primary key,
 sessionid     VARCHAR(70),
 createtime    BIGINT,

 createtime_year   SMALLINT,
 createtime_month  SMALLINT,
 createtime_day    SMALLINT
);

create index sessioninfo_id on sessioninfo (id);
create index sessioninfo_sessionid on sessioninfo (sessionid);
create index sessioninfo_createtime on sessioninfo (createtime);
create index sessioninfo_createtime_year on sessioninfo (createtime_year);
create index sessioninfo_createtime_month on sessioninfo (createtime_month);
create index sessioninfo_createtime_day on sessioninfo (createtime_day);

drop table IF EXISTS titleusage;
CREATE TABLE titleusage (
 sid          BIGINT,

 tstamp       BIGINT,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 isbn         VARCHAR(15),
 dbname       VARCHAR(25),
 id           VARCHAR(255) NOT NULL,
 origin       SMALLINT
);

ALTER TABLE titleusage ADD CONSTRAINT fk_titleusage_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

create index titleusage_sid on titleusage (sid);
create index titleusage_tstamp on titleusage (tstamp);
create index titleusage_tstamp_year on titleusage (tstamp_year);
create index titleusage_tstamp_month on titleusage (tstamp_month);
create index titleusage_tstamp_day on titleusage (tstamp_day);
create index titleusage_isbn on titleusage (isbn);
create index titleusage_dbname on titleusage (dbname);
create index titleusage_id on titleusage (id);
create index titleusage_origin on titleusage (origin);


drop table IF EXISTS eventlog;
CREATE TABLE eventlog (
 sid          BIGINT,

 tstamp       BIGINT,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
);

ALTER TABLE eventlog ADD CONSTRAINT fk_eventlog_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

create index eventlog_sid on eventlog (sid);
create index eventlog_tstamp on eventlog (tstamp);
create index eventlog_tstamp_year on eventlog (tstamp_year);
create index eventlog_tstamp_month on eventlog (tstamp_month);
create index eventlog_tstamp_day on eventlog (tstamp_day);
create index eventlog_type on eventlog (type);
create index eventlog_content on eventlog (content text_pattern_ops);

drop table IF EXISTS eventlogjson;
CREATE TABLE eventlogjson (
 sid          BIGINT,

 tstamp       BIGINT,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
);

ALTER TABLE eventlogjson ADD CONSTRAINT fk_eventlogjson_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

create index eventlogjson_sid on eventlogjson (sid);
create index eventlogjson_tstamp on eventlogjson (tstamp);
create index eventlogjson_tstamp_year on eventlogjson (tstamp_year);
create index eventlogjson_tstamp_month on eventlogjson (tstamp_month);
create index eventlogjson_tstamp_day on eventlogjson (tstamp_day);
create index eventlogjson_type on eventlogjson (type);

drop table IF EXISTS searchterms;
CREATE TABLE searchterms (
 sid          BIGINT references sessioninfo(id),

 tstamp       BIGINT,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname   VARCHAR(20),
 type       INT,
 content    VARCHAR(40)
);

ALTER TABLE searchterms ADD CONSTRAINT fk_searchterms_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

create index searchterms_sid on searchterms (sid);
create index searchterms_tstamp on searchterms (tstamp);
create index searchterms_viewname on searchterms (viewname);
create index searchterms_type on searchterms (type);
create index searchterms_content on searchterms (content);

drop table IF EXISTS searchfields;
CREATE TABLE searchfields (
 sid          BIGINT,

 tstamp       BIGINT,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname       VARCHAR(20),
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

ALTER TABLE searchfields ADD CONSTRAINT fk_searchfields_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

create index searchfields_sid on searchfields (sid);
create index searchfields_tstamp on searchfields (tstamp);
create index searchfields_tstamp_year on searchfields (tstamp_year);
create index searchfields_tstamp_month on searchfields (tstamp_month);
create index searchfields_tstamp_day on searchfields (tstamp_day);
create index searchfields_viewname on searchfields (viewname);
create index searchfields_freesearch on searchfields (freesearch);
create index searchfields_title on searchfields (title);
create index searchfields_person on searchfields (person);
create index searchfields_corporatebody on searchfields (corporatebody);
create index searchfields_subject on searchfields (subject);
create index searchfields_classification on searchfields (classification);
create index searchfields_isbn on searchfields (isbn);
create index searchfields_issn on searchfields (issn);
create index searchfields_mark on searchfields (mark);
create index searchfields_mediatype on searchfields (mediatype);
create index searchfields_titlestring on searchfields (titlestring);
create index searchfields_source on searchfields (source);
create index searchfields_year on searchfields (year);
