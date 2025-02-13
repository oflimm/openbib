/*-------------------------------------------------*/
/*-------------- OpenBib System tables ------------*/
/*-------------------------------------------------*/

CREATE EXTENSION pgcrypto;
CREATE EXTENSION "uuid-ossp";

/* General configuration                           */
/* ----------------------------------------------- */

drop table IF EXISTS datacache;
CREATE TABLE datacache (
 id          TEXT,
 tstamp      TIMESTAMP,
 type        INT,
 subkey      TEXT,
 data        TEXT
);

drop table IF EXISTS databaseinfo;
CREATE TABLE databaseinfo (
 id          BIGSERIAL,

/* Generel Information */
 description TEXT,
 shortdesc   TEXT,
 system      TEXT, 
 schema      TEXT, 
 dbname      TEXT,
 sigel       TEXT,
 url         TEXT,
 profileid   BIGINT,
 active      BOOL,
 locationid  BIGINT,
 parentdbid  BIGINT,

/* Import Configuration */
 protocol           TEXT,
 host               TEXT,
 remotepath         TEXT,
 remoteuser         TEXT,
 remotepassword     TEXT,
 titlefile          TEXT,
 personfile         TEXT,
 corporatebodyfile  TEXT,
 subjectfile        TEXT,
 classificationfile TEXT,
 holdingfile        TEXT,

 autoconvert  BOOL,
 circ         BOOL,
 circtype     TEXT,
 circurl      TEXT,
 circwsurl    TEXT,
 circdb       TEXT,

/* Various Counters */

 allcount      BIGINT DEFAULT 0,
 journalcount  BIGINT DEFAULT 0,
 articlecount  BIGINT DEFAULT 0,
 digitalcount  BIGINT DEFAULT 0
);

drop table IF EXISTS databaseinfo_searchengine;
create table databaseinfo_searchengine (
 id            BIGSERIAL,
 dbid          BIGINT NOT NULL,
 searchengine  TEXT
);

drop table IF EXISTS locationinfo;
create table locationinfo (
 id              BIGSERIAL,

 identifier      TEXT,
 type            TEXT,
 description     TEXT,

 tstamp_create   TIMESTAMP,
 tstamp_update   TIMESTAMP
);

drop table IF EXISTS locationinfo_fields;
create table locationinfo_fields (
 locationid    BIGINT      NOT NULL,
 field         SMALLINT    NOT NULL,
 mult          SMALLINT,
 subfield      VARCHAR(2),
 content       TEXT        NOT NULL,
 content_norm  TEXT
);

drop table IF EXISTS locationinfo_occupancy;
create table locationinfo_occupancy (
 id            BIGSERIAL,
 locationid    BIGINT      NOT NULL,

 tstamp        TIMESTAMP,
 num_entries   INT DEFAULT 0,
 num_exits     INT DEFAULT 0,
 num_occupancy INT DEFAULT 0
);

drop table IF EXISTS rssinfo;
create table rssinfo (
 id            BIGSERIAL,
 dbid          BIGINT NOT NULL,
 type          SMALLINT,

 active        BOOL
);

drop table IF EXISTS rsscache;
create table rsscache (
 pid           BIGSERIAL,
 rssinfoid     BIGINT NOT NULL,
 id            TEXT,
 tstamp        TIMESTAMP,
 content       TEXT
);

drop table IF EXISTS profileinfo;
CREATE TABLE profileinfo (
 id          BIGSERIAL,

 profilename TEXT NOT NULL,
 description TEXT
);

drop table IF EXISTS orgunitinfo;
CREATE TABLE orgunitinfo (
 id          BIGSERIAL,
 profileid   BIGINT NOT NULL,

 orgunitname TEXT NOT NULL,
 description TEXT,
 nr          INT,
 own_index   BOOL
);

drop table IF EXISTS orgunit_db;
CREATE TABLE orgunit_db (
 orgunitid   BIGINT NOT NULL,
 dbid        BIGINT NOT NULL
);

drop table IF EXISTS viewinfo;
CREATE TABLE viewinfo (
 id          BIGSERIAL,

 viewname    TEXT   NOT NULL,
 description TEXT,
 rssid       BIGINT,
 start_loc   TEXT,
 servername  TEXT,
 profileid   BIGINT NOT NULL,
 stripuri    BOOL,
 active      BOOL,
 own_index   BOOL,
 force_login BOOL DEFAULT FALSE,
 restrict_intranet TEXT DEFAULT '',
 searchengine TEXT DEFAULT ''
);

drop table IF EXISTS view_db;
CREATE TABLE view_db (
 viewid   BIGINT NOT NULL,
 dbid     BIGINT NOT NULL
);

drop table IF EXISTS view_rss;
CREATE TABLE view_rss (
 id        BIGSERIAL,
 viewid    BIGINT NOT NULL,
 rssid     BIGINT NOT NULL
);

drop table IF EXISTS view_location;
CREATE TABLE view_location (
 id         BIGSERIAL,
 viewid     BIGINT NOT NULL,
 locationid BIGINT NOT NULL
);

DROP TABLE IF EXISTS clusterinfo;
CREATE TABLE clusterinfo (
 id           BIGSERIAL,
 clustername  TEXT,
 description  TEXT,
 status       TEXT,
 active       BOOL
);

DROP TABLE IF EXISTS serverinfo;
CREATE TABLE serverinfo (
 id           BIGSERIAL,
 hostip       TEXT,
 description  TEXT,
 status       TEXT,
 clusterid    BIGINT,
 active       BOOL
);

DROP TABLE IF EXISTS updatelog;
CREATE TABLE updatelog (
 id           BIGSERIAL,
 dbid         BIGINT,
 serverid     BIGINT,
 tstamp_start TIMESTAMP,
 duration     INTERVAL,
 title_count          INT,
 title_count_xapian   INT,
 title_count_es       INT,
 title_journalcount   INT,
 title_articlecount   INT,
 title_digitalcount   INT,
 person_count         INT,
 corporatebody_count  INT,
 classification_count INT,
 subject_count        INT,
 holding_count        INT,
 is_incremental       INT,
 duration_stage_collect     INTERVAL,
 duration_stage_unpack      INTERVAL,
 duration_stage_convert     INTERVAL,
 duration_stage_load_db          INTERVAL,
 duration_stage_load_index       INTERVAL,
 duration_stage_load_authorities INTERVAL,
 duration_stage_switch            INTERVAL,
 duration_stage_analyze           INTERVAL,
 duration_stage_update_enrichment INTERVAL
);

drop table IF EXISTS cartitem;
CREATE TABLE cartitem (
 id         BIGSERIAL,

 tstamp     TIMESTAMP,

 dbname     TEXT,
 titleid    TEXT,
 titlecache TEXT,

 comment    TEXT default ''
);


/* Session-Handling                                */
/* ----------------------------------------------- */

drop table IF EXISTS sessioninfo;
CREATE TABLE sessioninfo (
 id             BIGSERIAL,
 sessionid      TEXT        NOT NULL,
 createtime     TIMESTAMP,
 expiretime     TIMESTAMP, 
 lastresultset  TEXT,
 username       TEXT,

 viewname       TEXT,
 network        CIDR,
 
 queryoptions   TEXT,

 searchform     TEXT,
 searchprofile  TEXT,

 bibsonomy_user TEXT,
 bibsonomy_key  TEXT,
 bibsonomy_sync TEXT,
 datacache      TEXT
);

drop table IF EXISTS session_cartitem;
CREATE TABLE session_cartitem (
 id               BIGSERIAL,
 sid              BIGINT NOT NULL,
 cartitemid       BIGINT NOT NULL
);

drop table IF EXISTS recordhistory;
CREATE TABLE recordhistory (
 sid       BIGINT NOT NULL,

 dbname    TEXT,
 titleid   TEXT
);

drop table IF EXISTS eventlog;
CREATE TABLE eventlog (
 sid        BIGINT NOT NULL,

 tstamp     TIMESTAMP,
 type       INT,
 content    TEXT
);

drop table IF EXISTS eventlogjson;
CREATE TABLE eventlogjson (
 sid        BIGINT NOT NULL,

 tstamp     TIMESTAMP,
 type       INT,
 content    TEXT
);

drop table IF EXISTS queries;
CREATE TABLE queries (
 sid             BIGINT NOT NULL,

 tstamp          TIMESTAMP,

 queryid         BIGSERIAL,
 query           TEXT,
 hits            INT,
 searchprofileid BIGINT
);

drop table IF EXISTS searchhistory;
CREATE TABLE searchhistory (
 sid          BIGINT NOT NULL,

 tstamp       TIMESTAMP,

 dbname       TEXT NOT NULL,
 "offset"       INT,
 hitrange     INT,
 searchresult TEXT,
 hits         INT,
 queryid      BIGINT
);

-------------------------------------------------
-- Users and user generated data               --   
-------------------------------------------------

DROP TABLE IF EXISTS userinfo;
CREATE TABLE userinfo (
 id           BIGSERIAL,
 creationdate TIMESTAMP,
 lastlogin    TIMESTAMP,

 viewid          BIGINT,
 locationid      BIGINT,
 authenticatorid BIGINT,
 username        TEXT,
 password        TEXT,
 external_id     TEXT,
 external_group  TEXT,
 token           TEXT,
 login_failure   BIGINT default 0,
 status          TEXT,
 
 /* User information from library system */
 nachname   TEXT,
 vorname    TEXT,
 sperre     TEXT,
 sperrdatum TEXT,

 email      TEXT,

-- Personalization --
 masktype             TEXT,
 autocompletiontype   TEXT,

 spelling_as_you_type BOOL,
 spelling_resultlist  BOOL,

-- Bibsonomy Credentials for automatic sync --
 bibsonomy_user TEXT,
 bibsonomy_key  TEXT,
 bibsonomy_sync TEXT,

-- Additional unspecified content - json encoded --

 mixed_bag      JSONB
 
);

DROP TABLE IF EXISTS user_searchlocation;
CREATE TABLE user_searchlocation (
  id         BIGSERIAL,
  userid     BIGINT NOT NULL,
  locationid BIGINT NOT NULL
);

DROP TABLE IF EXISTS roleinfo;
CREATE TABLE roleinfo (
  id           BIGSERIAL,
  rolename     TEXT NOT NULL,
  description  TEXT NOT NULL
);

--- Access to view viewid is restricted to membership of roleid
DROP TABLE IF EXISTS role_view;
CREATE TABLE role_view (
  id        BIGSERIAL,
  roleid    BIGINT NOT NULL,
  viewid    BIGINT NOT NULL
);

--- Role roleid can be administered by viewadmin of view viewid
DROP TABLE IF EXISTS role_viewadmin;
CREATE TABLE role_viewadmin (
  id        BIGSERIAL,
  roleid    BIGINT NOT NULL,
  viewid    BIGINT NOT NULL
);

DROP TABLE IF EXISTS role_right;
CREATE TABLE role_right (
  id              BIGSERIAL,
  roleid          BIGINT NOT NULL,
  scope           TEXT default '', /* eg admin, admin_clusters, all_scopes */
  right_create    BOOL default false,
  right_read      BOOL default false,
  right_update    BOOL default false,
  right_delete    BOOL default false
);

DROP TABLE IF EXISTS user_role;
CREATE TABLE user_role (
  id        BIGSERIAL,
  userid    BIGINT NOT NULL,
  roleid    BIGINT NOT NULL
);


DROP TABLE IF EXISTS user_db;
CREATE TABLE user_db (
  id        BIGSERIAL,
  userid    BIGINT NOT NULL,
  dbid      BIGINT NOT NULL
);

DROP TABLE IF EXISTS templateinfo;
CREATE TABLE templateinfo (
  id         BIGSERIAL,
  viewid     BIGINT NOT NULL,
  templatedesc TEXT,
  templatename TEXT NOT NULL,
  templatepart TEXT,
  templatetext TEXT,
  templatelang TEXT
);

DROP TABLE IF EXISTS user_template;
CREATE TABLE user_template (
  id         BIGSERIAL,
  userid     BIGINT NOT NULL,
  templateid BIGINT NOT NULL
);


DROP TABLE IF EXISTS templateinforevision;
CREATE TABLE templateinforevision (
  id         BIGSERIAL,
  tstamp       TIMESTAMP,

  templateid  BIGINT NOT NULL,
  templatetext TEXT
);

DROP TABLE IF EXISTS registration;
CREATE TABLE registration (
  id                  TEXT,
  tstamp              TIMESTAMP,

  viewid              BIGINT,

  username            TEXT,
  password            TEXT
);

DROP TABLE IF EXISTS authtoken;
CREATE TABLE authtoken (
  id                  UUID,
  tstamp              TIMESTAMP,

  viewid              BIGINT,
  type                TEXT,

  authkey             TEXT,
  
-- Additional unspecified content - json encoded --

  mixed_bag           JSONB
);

DROP TABLE IF EXISTS authenticatorinfo;
CREATE TABLE authenticatorinfo (
 id          BIGSERIAL,

 name        TEXT,
 description TEXT,
 type        TEXT
);

DROP TABLE IF EXISTS authenticator_view;
CREATE TABLE authenticator_view (
  id        BIGSERIAL,
  authenticatorid    BIGINT NOT NULL,
  viewid    BIGINT NOT NULL
);


DROP TABLE IF EXISTS user_session;
CREATE TABLE user_session (
  id               BIGSERIAL,
  sid              BIGINT NOT NULL,
  userid           BIGINT NOT NULL,
  authenticatorid  BIGINT NOT NULL
);

DROP TABLE IF EXISTS searchprofile;
CREATE TABLE searchprofile (
 id                BIGSERIAL,
 own_index         BOOL,
 databases_as_json TEXT -- for quick lookup having database list and initial state --
);

drop table IF EXISTS searchprofile_db;
CREATE TABLE searchprofile_db (
 searchprofileid   BIGINT NOT NULL,
 dbid              BIGINT NOT NULL
);

drop table IF EXISTS session_searchprofile;
CREATE TABLE session_searchprofile (
 sid             BIGINT NOT NULL,
 searchprofileid BIGINT NOT NULL
);

DROP TABLE IF EXISTS user_searchprofile;
CREATE TABLE user_searchprofile (
 id                BIGSERIAL,
 searchprofileid   BIGINT NOT NULL,
 userid            BIGINT NOT NULL,

 profilename TEXT
);

DROP TABLE IF EXISTS searchfield;
CREATE TABLE searchfield (
 userid      BIGINT NOT NULL,

 searchfield TEXT,
 active      BOOL
);

DROP TABLE IF EXISTS livesearch;
CREATE TABLE livesearch (
 userid      BIGINT NOT NULL,
 searchfield TEXT,
 exact       BOOL,
 active      BOOL
);

DROP TABLE IF EXISTS user_cartitem;
CREATE TABLE user_cartitem (
 id         BIGSERIAL,
 userid     BIGINT NOT NULL,
 cartitemid BIGINT NOT NULL
);

DROP TABLE IF EXISTS tag;
CREATE TABLE tag (
 id     BIGSERIAL,
 name   TEXT NOT NULL default ''
);

DROP TABLE IF EXISTS tit_tag;
CREATE TABLE tit_tag (
 id         BIGSERIAL,
 tagid      BIGINT      NOT NULL,
 userid     BIGINT      NOT NULL,

 tstamp     TIMESTAMP,

 dbname     TEXT        NOT NULL,
 titleid    TEXT        NOT NULL,
 titleisbn  TEXT        NOT NULL default '',

 srt_person TEXT,
 srt_title  TEXT,
 srt_year   TEXT,

 titlecache TEXT,
 type       SMALLINT       NOT NULL default '1'
);

DROP TABLE IF EXISTS review;
CREATE TABLE review (
 id         BIGSERIAL,
 userid     BIGINT       NOT NULL,
 tstamp     TIMESTAMP,

 nickname   TEXT         NOT NULL default '',
 title      TEXT         NOT NULL default '',
 reviewtext TEXT         NOT NULL default '',
 rating     SMALLINT     NOT NULL default '0',

 dbname     TEXT         NOT NULL default '',
 titleid    TEXT         NOT NULL default '0',
 titleisbn  TEXT         NOT NULL default ''
);

DROP TABLE IF EXISTS reviewrating;
CREATE TABLE reviewrating (
 id        BIGSERIAL,
 userid    BIGINT        NOT NULL,
 reviewid  BIGINT        NOT NULL,

 tstamp    TIMESTAMP,
 rating    SMALLINT      NOT NULL default '0'
);

DROP TABLE IF EXISTS litlist;
CREATE TABLE litlist (
 id        BIGSERIAL,
 userid    BIGINT      NOT NULL,

 tstamp    TIMESTAMP,

 title     TEXT        NOT NULL,
 type      SMALLINT    NOT NULL default '1',
 lecture   BOOL        NOT NULL default 'false'
);

DROP TABLE IF EXISTS litlistitem;
CREATE TABLE litlistitem (
 id        BIGSERIAL,
 litlistid BIGINT     NOT NULL,

 tstamp    TIMESTAMP,

 dbname    TEXT,
 titleid   TEXT,
 titleisbn TEXT,

 comment   TEXT default '',

 titlecache  TEXT
);

DROP TABLE IF EXISTS topic;
CREATE TABLE topic (
 id           BIGSERIAL,
 name         TEXT      NOT NULL default '',
 description  TEXT      NOT NULL default ''
);

DROP TABLE IF EXISTS litlist_topic;
CREATE TABLE litlist_topic (
 id           BIGSERIAL,
 litlistid    BIGINT    NOT NULL,
 topicid      BIGINT    NOT NULL
);

DROP TABLE IF EXISTS topicclassification;
CREATE TABLE topicclassification (
 topicid        BIGINT  NOT NULL,
 classification TEXT    NOT NULL,
 type           TEXT    NOT NULL
);

DROP TABLE IF EXISTS dbrtopic;
CREATE TABLE dbrtopic (
 id           SERIAL NOT NULL,
 topic        TEXT   NOT NULL,
 description  TEXT   NOT NULL
);

DROP TABLE IF EXISTS dbistopic;
CREATE TABLE dbistopic (
 id           SERIAL NOT NULL,
 topic        TEXT   NOT NULL,
 description  TEXT   NOT NULL
);

DROP TABLE IF EXISTS dbrtopic_dbistopic;
CREATE TABLE dbrtopic_dbistopic (
 id               SERIAL    NOT NULL,
 dbrtopicid        BIGINT    NOT NULL,
 dbistopicid       BIGINT    NOT NULL
);

DROP TABLE IF EXISTS dbisdb;
CREATE TABLE dbisdb (
 id           BIGINT    NOT NULL,
 description  TEXT      NOT NULL,
 url          TEXT      NOT NULL
);

DROP TABLE IF EXISTS dbistopic_dbisdb;
CREATE TABLE dbistopic_dbisdb (
 id           SERIAL    NOT NULL,
 dbistopicid  BIGINT    NOT NULL,
 dbisdbid     BIGINT    NOT NULL,
 rank         INT
);

DROP TABLE IF EXISTS paia;
CREATE TABLE paia (
  id                  BIGSERIAL,
  tstamp              TIMESTAMP,

  username            TEXT,
  token               TEXT

);

DROP TABLE IF EXISTS classifications;
CREATE TABLE classifications (
  id                  BIGSERIAL,
  tstamp              TIMESTAMP,

  type                TEXT,
  name                TEXT,
  description         TEXT
);

DROP TABLE IF EXISTS classificationshierarchy;
CREATE TABLE classificationshierarchy (
  id                  BIGSERIAL,
  tstamp              TIMESTAMP,

  type                TEXT,
  name                TEXT,
  number              INT,
  subname             TEXT
);

DROP TABLE IF EXISTS networkinfo;

CREATE TABLE networkinfo (
    id BIGSERIAL,
    network CIDR NOT NULL,
    country TEXT,
    continent TEXT,
    is_eu INT
);
