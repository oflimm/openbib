/*-------------------------------------------------*/
/*-------------- OpenBib System tables ------------*/
/*-------------------------------------------------*/

/* General configuration                           */
/* ----------------------------------------------- */

drop table IF EXISTS databaseinfo;
CREATE TABLE databaseinfo (
 id          BIGSERIAL,

/* Generel Information */
 description TEXT,
 shortdesc   TEXT,
 system      TEXT, 
 dbname      TEXT,
 sigel       TEXT,
 url         TEXT,
 profileid   BIGINT,
 active      BOOL,
 locationid  BIGINT,

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
 circurl      TEXT,
 circwsurl    TEXT,
 circdb       TEXT,

/* Various Counters */

 allcount      BIGINT DEFAULT 0,
 journalcount  BIGINT DEFAULT 0,
 articlecount  BIGINT DEFAULT 0,
 digitalcount  BIGINT DEFAULT 0
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

drop table IF EXISTS rssinfo;
create table rssinfo (
 id            BIGSERIAL,
 dbid          BIGINT NOT NULL,
 type          SMALLINT,

 active        BOOL
);

drop table IF EXISTS rsscache;
create table rsscache (
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
 nr          INT
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
 active      BOOL
);

drop table IF EXISTS view_db;
CREATE TABLE view_db (
 viewid   BIGINT NOT NULL,
 dbid     BIGINT NOT NULL
);

drop table IF EXISTS view_rss;
CREATE TABLE view_rss (
 viewid    BIGINT NOT NULL,
 rssid     BIGINT NOT NULL
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
 title_journalcount   INT,
 title_articlecount   INT,
 title_digitalcount   INT,
 person_count         INT,
 corporatebody_count  INT,
 classification_count INT,
 subject_count        INT,
 holding_count        INT 
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
 lastresultset  TEXT,
 username       TEXT,
 userpassword   TEXT,

 viewname       TEXT,

 queryoptions   TEXT,

 searchform     TEXT,
 searchprofile  TEXT,

 bibsonomy_user TEXT,
 bibsonomy_key  TEXT,
 bibsonomy_sync TEXT
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

-- Users and user generated data               --   
-------------------------------------------------

DROP TABLE IF EXISTS userinfo;
CREATE TABLE userinfo (
 id         BIGSERIAL,
 lastlogin  TIMESTAMP,

 username  TEXT,
 password  TEXT,

 /* User informatin from library system */
 nachname   TEXT,
 vorname    TEXT,
 strasse    TEXT,
 ort        TEXT,
 plz        TEXT,
 soll       TEXT,
 gut        TEXT,
 avanz      TEXT,
 branz      TEXT,
 bsanz      TEXT,
 vmanz      TEXT,
 maanz      TEXT,
 vlanz      TEXT,
 sperre     TEXT,
 sperrdatum TEXT,
 gebdatum   TEXT,

 email      TEXT,

-- Personalization --
 masktype             TEXT,
 autocompletiontype   TEXT,

 spelling_as_you_type BOOL,
 spelling_resultlist  BOOL,

-- Bibsonomy Credentials for automatic sync --
 bibsonomy_user TEXT,
 bibsonomy_key  TEXT,
 bibsonomy_sync TEXT
);

DROP TABLE IF EXISTS role;
CREATE TABLE role (
  id        BIGSERIAL,
  name      TEXT NOT NULL
);

DROP TABLE IF EXISTS user_role;
CREATE TABLE user_role (
  id        BIGSERIAL,
  userid    BIGINT NOT NULL,
  roleid    BIGINT NOT NULL
);

DROP TABLE IF EXISTS user_view;
CREATE TABLE user_view (
  id        BIGSERIAL,
  userid    BIGINT NOT NULL,
  viewid    BIGINT NOT NULL
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
  templatename TEXT NOT NULL,
  templatetext TEXT
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
 
  username            TEXT,
  password            TEXT
);

DROP TABLE IF EXISTS authenticator;
CREATE TABLE authenticator (
 id          BIGSERIAL,

 hostname    TEXT,
 port        TEXT,
 remoteuser  TEXT,
 dbname      TEXT,
 description TEXT,
 type        TEXT
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
 databases_as_json TEXT, -- for quick lookup having database list and initial state --
 own_index         BOOL
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
