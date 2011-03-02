-------------------------------------------------
--------------- T A B E L L E N -----------------
-------------------------------------------------

drop table IF EXISTS databaseinfo;
CREATE TABLE databaseinfo (
 description TEXT,
 shortdesc   TEXT,
 system      TEXT, 
 dbname      VARCHAR(25) PRIMARY KEY,
 sigel       VARCHAR(20),
 url         TEXT,
 use_libinfo BOOL,
 active      BOOL,

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
 holdingsfile       VARCHAR(255),

 autoconvert  BOOL,
 circ         BOOL,
 circurl      TEXT,
 circwsurl    TEXT,
 circdb       TEXT
);

create index databaseinfo_dbname on databaseinfo (dbname);
create index databaseinfo_active on databaseinfo (active);
create index databaseinfo_description on databaseinfo (description);


drop table IF EXISTS libraryinfo;
create table libraryinfo (
 dbname        VARCHAR(255) NOT NULL,
 category      SMALLINT  NOT NULL,
 indicator     SMALLINT,
 content       TEXT NOT NULL
);

create index libraryinfo_dbname on libraryinfo (dbname);
create index libraryinfo_category on libraryinfo (category);
create index libraryinfo_indicator on libraryinfo (indicator);
create index libraryinfo_content on libraryinfo (content);
create index libraryinfo_dbcat on libraryinfo (dbname,category);


drop table IF EXISTS titcount;
create table titcount (
 dbname VARCHAR(255),
 count  BIGINT,
 type   SMALLINT
);

create index titcount_dbname on titcount (dbname);
create index titcount_type on titcount (type);

drop table IF EXISTS profileinfo;
CREATE TABLE profileinfo (
 profilename VARCHAR(20),
 description TEXT
);

create index profileinfo_profilename on profileinfo (profilename);

drop table IF EXISTS profiledbs;
CREATE TABLE profiledbs (
 profilename VARCHAR(20) NOT NULL,
 orgunitname VARCHAR(20),
 dbname      VARCHAR(255) NOT NULL
);

create index profiledbs_profilename on profiledbs (profilename);
create index profiledbs_proforg on profiledbs (profilename,orgunitname);
create index profiledbs_dbname on profiledbs (dbname);


drop table IF EXISTS orgunitinfo;
CREATE TABLE orgunitinfo (
 orgunitname VARCHAR(20) NOT NULL,
 profilename VARCHAR(20) NOT NULL,
 description TEXT,
 nr          INT
);

create index orgunitinfo_profilename on orgunitinfo (profilename);
create index orgunitinfo_orgunitname on orgunitinfo (orgunitname);
create index orgunitinfo_nr on orgunitinfo (nr);

drop table IF EXISTS viewinfo;
CREATE TABLE viewinfo (
 viewname    VARCHAR(20),
 description TEXT,
 rssfeed     BIGINT,
 start_loc   TEXT,
 start_stid  TEXT,
 profilename VARCHAR(20),
 active      BOOL
);

create index viewinfo_viewname on viewinfo (viewname);
create index viewinfo_profilename on viewinfo (profilename);

drop table IF EXISTS viewdbs;
CREATE TABLE viewdbs (
 viewname VARCHAR(20),
 dbname   VARCHAR(255)
);

create index viewdbs_viewname on viewdbs (viewname);
create index viewdbs_dbname on viewdbs (dbname);

drop table IF EXISTS viewrssfeeds;
CREATE TABLE viewrssfeeds (
 viewname VARCHAR(20),
 rssfeed   BIGINT NOT NULL
);

create index viewrssfeeds_viewname on viewrssfeeds (viewname);
create index viewrssfeeds_rssfeed on viewrssfeeds (rssfeed);

drop table IF EXISTS rssfeeds;
create table rssfeeds (
 id          SERIAL PRIMARY KEY,
 dbname      VARCHAR(255) NOT NULL,
 type        SMALLINT,
 subtype     SMALLINT,
 subtypedesc TEXT,
 active      BOOL
);

create index rssfeeds_dbname on rssfeeds (dbname);
create index rssfeeds_type on rssfeeds (type);
create index rssfeeds_subtype on rssfeeds (subtype);

drop table IF EXISTS rsscache;
create table rsscache (
dbname  VARCHAR(255) NOT NULL,
tstamp  TIMESTAMP,
type    SMALLINT  NOT NULL,
subtype SMALLINT,
content TEXT
);

create index rsscache_dbname on rsscache (dbname);
create index rsscache_tstamp on rsscache (tstamp);
create index rsscache_type on rsscache (type);
create index rsscache_subtype on rsscache (subtype);

DROP TABLE IF EXISTS loadbalancertargets;
CREATE TABLE loadbalancertargets (
 id         SERIAL PRIMARY KEY,
 host       TEXT,
 active     BOOL
);

create index loadbalancertargets_idactive on loadbalancertargets (id,active);



