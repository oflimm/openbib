/*-------------------------------------------------*/
/*-------------- OpenBib System tables ------------*/
/*-------------------------------------------------*/

/* General configuration                           */
/* ----------------------------------------------- */

drop table IF EXISTS databaseinfo;
CREATE TABLE databaseinfo (
 id          BIGSERIAL primary key,

/* Generel Information */
 description TEXT,
 shortdesc   TEXT,
 system      TEXT, 
 dbname      VARCHAR(25) UNIQUE,
 sigel       VARCHAR(20),
 url         TEXT,
 use_libinfo BOOL,
 active      BOOL,

/* Import Configuration */
 protocol           VARCHAR(255),
 host               VARCHAR(255),
 remotepath         TEXT,
 remoteuser         VARCHAR(255),
 remotepassword     VARCHAR(255),
 titlefile          VARCHAR(255),
 personfile         VARCHAR(255),
 corporatebodyfile  VARCHAR(255),
 subjectfile        VARCHAR(255),
 classificationfile VARCHAR(255),
 holdingfile        VARCHAR(255),

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

drop table IF EXISTS libraryinfo;
create table libraryinfo (
 dbid          BIGINT NOT NULL,

 category      SMALLINT  NOT NULL,
 indicator     SMALLINT,
 content       TEXT NOT NULL
);

drop table IF EXISTS rssinfo;
create table rssinfo (
 id            BIGSERIAL primary key,
 dbid          BIGINT NOT NULL,
 type          SMALLINT,
 subtype       SMALLINT,
 subtypedesc   TEXT,
 cache_tstamp  TIMESTAMP,
 cache_content TEXT,

 active        SMALLINT
);

drop table IF EXISTS profileinfo;
CREATE TABLE profileinfo (
 id          BIGSERIAL primary key,

 profilename VARCHAR(20) NOT NULL,
 description TEXT
);

drop table IF EXISTS orgunitinfo;
CREATE TABLE orgunitinfo (
 id          BIGSERIAL primary key,
 profileid   BIGINT NOT NULL,

 orgunitname VARCHAR(20) NOT NULL,
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
 id          BIGSERIAL primary key,

 viewname    VARCHAR(20) NOT NULL,
 description TEXT,
 rssid       BIGINT,
 start_loc   TEXT,
 servername  TEXT,
 profileid   BIGINT NOT NULL,
 stripuri    SMALLINT,
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

DROP TABLE IF EXISTS serverinfo;
CREATE TABLE serverinfo (
 id         BIGSERIAL,
 host       TEXT,
 active     SMALLINT
);


/* Session-Handling                                */
/* ----------------------------------------------- */

drop table IF EXISTS sessioninfo;
CREATE TABLE sessioninfo (
 id            BIGSERIAL,
 sessionid     CHAR(33) NOT NULL,
 createtime    TIMESTAMP,
 lastresultset TEXT,
 username      TEXT,
 userpassword  TEXT,

 queryoptions  TEXT,

 searchform     TEXT,
 searchprofile  TEXT,

 bibsonomy_user TEXT,
 bibsonomy_key  TEXT,
 bibsonomy_sync TEXT
);

drop table IF EXISTS sessioncollection;
CREATE TABLE sessioncollection (
 id         BIGSERIAL primary key,
 sid        BIGINT NOT NULL,

 dbname     TEXT,
 titleid    VARCHAR(255),
 titlecache TEXT
);

drop table IF EXISTS recordhistory;
CREATE TABLE recordhistory (
 sid       BIGINT NOT NULL,

 dbname    TEXT,
 titleid   VARCHAR(255)
);

drop table IF EXISTS eventlog;
CREATE TABLE eventlog (
 sid        BIGINT NOT NULL,

 tstamp     TIMESTAMP,
 type       INT,
 content    VARCHAR(255)
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

 queryid         BIGSERIAL PRIMARY KEY,
 query           TEXT,
 hits            INT,
 searchprofileid BIGINT
);

drop table IF EXISTS searchhistory;
CREATE TABLE searchhistory (
 sid          BIGINT NOT NULL,

 tstamp       TIMESTAMP,

 dbname       VARCHAR(255) NOT NULL,
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
 id         BIGSERIAL primary key,
 lastlogin  TIMESTAMP,

 username  VARCHAR(255),
 password  TEXT,

 /* User informatin from library system */
 nachname   TEXT,
 vorname    TEXT,
 strasse    TEXT,
 ort        TEXT,
 plz        INT,
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
  id        BIGSERIAL primary key,
  name      VARCHAR(255) NOT NULL
);

DROP TABLE IF EXISTS user_role;
CREATE TABLE user_role (
  id        BIGSERIAL primary key,
  userid    BIGINT NOT NULL,
  roleid    BIGINT NOT NULL
);

DROP TABLE IF EXISTS registration;
CREATE TABLE registration (
  id                  VARCHAR(60) primary key,
  tstamp              TIMESTAMP,
 
  username            TEXT,
  password            TEXT
);

DROP TABLE IF EXISTS logintarget;
CREATE TABLE logintarget (
 id          BIGSERIAL primary key,

 hostname    TEXT,
 port        TEXT,
 "user"      TEXT,
 db          TEXT,
 description TEXT,
 type        TEXT
);

DROP TABLE IF EXISTS user_session;
CREATE TABLE user_session (
  id        BIGSERIAL primary key,
  sid       BIGINT NOT NULL,
  userid    BIGINT NOT NULL,
  targetid  BIGINT NOT NULL
);

DROP TABLE IF EXISTS searchprofile;
CREATE TABLE searchprofile (
 id                BIGSERIAL primary key,
 databases_as_json TEXT, -- for quick lookup having database list and initial state --
 own_index         SMALLINT
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
 id                BIGSERIAL primary key,
 searchprofileid   BIGINT NOT NULL,
 userid            BIGINT NOT NULL,

 profilename TEXT
);

DROP TABLE IF EXISTS searchfield;
CREATE TABLE searchfield (
 userid      BIGINT NOT NULL,

 searchfield VARCHAR(255),
 active      BOOL
);

DROP TABLE IF EXISTS livesearch;
CREATE TABLE livesearch (
 userid      BIGINT NOT NULL,
 searchfield VARCHAR(255),
 exact       BOOL,
 active      BOOL
);

DROP TABLE IF EXISTS collection;
CREATE TABLE collection (
 id         BIGSERIAL primary key,
 userid     BIGINT  NOT NULL,

 dbname     TEXT,
 titleid    VARCHAR(255),
 titlecache TEXT
);

DROP TABLE IF EXISTS tag;
CREATE TABLE tag (
 id     BIGSERIAL primary key,
 name   VARCHAR(255) NOT NULL default ''
);

DROP TABLE IF EXISTS tit_tag;
CREATE TABLE tit_tag (
 id         BIGSERIAL primary key,
 tagid      BIGINT      NOT NULL,
 userid     BIGINT       NOT NULL,

 dbname     VARCHAR(25)  NOT NULL,
 titleid    VARCHAR(255) NOT NULL,
 titleisbn  CHAR(14)     NOT NULL default '',

 titlecache TEXT,
 type       SMALLINT       NOT NULL default '1'
);

DROP TABLE IF EXISTS review;
CREATE TABLE review (
 id        BIGSERIAL primary key,
 userid    BIGINT       NOT NULL,
 tstamp    TIMESTAMP,

 nickname   VARCHAR(30)  NOT NULL default '',
 title      VARCHAR(100) NOT NULL default '',
 reviewtext TEXT         NOT NULL default '',
 rating     SMALLINT     NOT NULL default '0',

 dbname    VARCHAR(25)  NOT NULL default '',
 titleid   VARCHAR(255) NOT NULL default '0',
 titleisbn CHAR(14)     NOT NULL default ''
);

DROP TABLE IF EXISTS reviewrating;
CREATE TABLE reviewratings (
 id        BIGSERIAL primary key,
 userid    BIGINT      NOT NULL,
 reviewid  BIGINT     NOT NULL,

 tstamp    TIMESTAMP,
 rating    SMALLINT      NOT NULL default '0'
);

DROP TABLE IF EXISTS litlist;
CREATE TABLE litlist (
 id        BIGSERIAL primary key,
 userid    BIGINT      NOT NULL,

 tstamp    TIMESTAMP,

 title     TEXT        NOT NULL,
 type      SMALLINT      NOT NULL default '1',
 lecture   SMALLINT      NOT NULL default '0'
);

DROP TABLE IF EXISTS litlistitem;
CREATE TABLE litlistitem (
 id        BIGSERIAL primary key,
 litlistid BIGINT     NOT NULL,

 tstamp    TIMESTAMP,

 dbname    VARCHAR(25)  NOT NULL,
 titleid   VARCHAR(255) NOT NULL,
 titleisbn CHAR(14)     NOT NULL default '',

 titlecache  TEXT
);

DROP TABLE IF EXISTS subject;
CREATE TABLE subject (
 id           BIGSERIAL primary key,
 name         TEXT        NOT NULL default '',
 description  TEXT        NOT NULL default ''
);

DROP TABLE IF EXISTS litlist_subject;
CREATE TABLE litlist_subject (
 id           BIGSERIAL primary key,
 litlistid    BIGINT     NOT NULL,
 subjectid    BIGINT     NOT NULL
);

DROP TABLE IF EXISTS subjectclassification;
CREATE TABLE subjectclassification (
 subjectid      BIGINT     NOT NULL,
 classification VARCHAR(20) NOT NULL,
 type           VARCHAR(5)  NOT NULL
);

/* Standard ist Selbstregistrierung */
insert into logintarget values(1,NULL,NULL,NULL,NULL,'Registrierte E-Mail Adresse','self');

/* Standard sind Rollen Admin und Bibliothekar */
insert into role values (1,'admin');
insert into role values (2,'librarian');

/* Standard ist Admin-User mit ID 1 und Passwort 'StrengGeheim' */
insert into userinfo (id,username,password) values (1,'admin','StrengGeheim');
insert into user_role (userid,roleid) values (1,1);

/* Standard-Profil ist openbib */
insert into profileinfo (id,profilename,description) values (1,'openbib','OpenBib Beispiel-Portal');

/* Standard-View ist openbib */
insert into viewinfo (id,viewname,description,start_loc,servername,profileid,stripuri,active) values (1,'openbib','OpenBib Beispiel-Portal','','',1,0,1);
