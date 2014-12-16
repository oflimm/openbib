-------------------------------------------------
-------- Indizes / Primary / Foreign Keys -------
-------------------------------------------------
DROP INDEX datacache_id;
DROP INDEX datacache_tstamp;
DROP INDEX datacache_subkey;
DROP INDEX datacache_type;

-------------------------------------------------

ALTER TABLE titleusage DROP CONSTRAINT fk_titleusage_session;
DROP INDEX titleusage_sid;
DROP INDEX titleusage_tstamp;
DROP INDEX titleusage_tstamp_year;
DROP INDEX titleusage_tstamp_month;
DROP INDEX titleusage_tstamp_day;
DROP INDEX titleusage_isbn;
DROP INDEX titleusage_dbname;
DROP INDEX titleusage_id;
DROP INDEX titleusage_origin;

-------------------------------------------------

ALTER TABLE eventlog DROP CONSTRAINT fk_eventlog_session;
DROP INDEX eventlog_sid;
DROP INDEX eventlog_tstamp;
DROP INDEX eventlog_tstamp_year;
DROP INDEX eventlog_tstamp_month;
DROP INDEX eventlog_tstamp_day;
DROP INDEX eventlog_type;
DROP INDEX eventlog_content;

-------------------------------------------------

ALTER TABLE eventlogjson DROP CONSTRAINT fk_eventlogjson_session;
DROP INDEX eventlogjson_sid;
DROP INDEX eventlogjson_tstamp;
DROP INDEX eventlogjson_tstamp_year;
DROP INDEX eventlogjson_tstamp_month;
DROP INDEX eventlogjson_tstamp_day;
DROP INDEX eventlogjson_type;

-------------------------------------------------

ALTER TABLE searchterms DROP CONSTRAINT fk_searchterms_session;
DROP INDEX searchterms_sid;
DROP INDEX searchterms_tstamp;
DROP INDEX searchterms_viewname;
DROP INDEX searchterms_type;
DROP INDEX searchterms_content;

-------------------------------------------------

ALTER TABLE searchfields DROP CONSTRAINT fk_searchfields_session;
DROP INDEX searchfields_sid;
DROP INDEX searchfields_tstamp;
DROP INDEX searchfields_tstamp_year;
DROP INDEX searchfields_tstamp_month;
DROP INDEX searchfields_tstamp_day;
DROP INDEX searchfields_viewname;
DROP INDEX searchfields_freesearch;
DROP INDEX searchfields_title;
DROP INDEX searchfields_person;
DROP INDEX searchfields_corporatebody;
DROP INDEX searchfields_subject;
DROP INDEX searchfields_classification;
DROP INDEX searchfields_isbn;
DROP INDEX searchfields_issn;
DROP INDEX searchfields_mark;
DROP INDEX searchfields_mediatype;
DROP INDEX searchfields_titlestring;
DROP INDEX searchfields_source;
DROP INDEX searchfields_year;

ALTER TABLE sessioninfo DROP CONSTRAINT sessioninfo_pkey;
DROP INDEX sessioninfo_sessionid;
DROP INDEX sessioninfo_createtime;
DROP INDEX sessioninfo_createtime_year;
DROP INDEX sessioninfo_createtime_month;
DROP INDEX sessioninfo_createtime_day;

-------------------------------------------------
