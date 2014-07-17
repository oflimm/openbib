-- searchfields
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
DROP INDEX searchfields_content;

alter table searchfields rename to searchfields_without_partitions;

CREATE TABLE searchfields (
 id            BIGSERIAL,
 sid           BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname       TEXT,
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
 source         BOOL,
 year           BOOL,
 content        BOOL
);


ALTER TABLE searchfields ADD PRIMARY KEY (id);
ALTER TABLE searchfields ADD CONSTRAINT fk_searchfields_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX searchfields_sid ON searchfields (sid);
CREATE INDEX searchfields_tstamp ON searchfields (tstamp);
CREATE INDEX searchfields_tstamp_year ON searchfields (tstamp_year);
CREATE INDEX searchfields_tstamp_month ON searchfields (tstamp_month);
CREATE INDEX searchfields_tstamp_day ON searchfields (tstamp_day);
CREATE INDEX searchfields_viewname ON searchfields (viewname);
CREATE INDEX searchfields_freesearch ON searchfields (freesearch);
CREATE INDEX searchfields_title ON searchfields (title);
CREATE INDEX searchfields_person ON searchfields (person);
CREATE INDEX searchfields_corporatebody ON searchfields (corporatebody);
CREATE INDEX searchfields_subject ON searchfields (subject);
CREATE INDEX searchfields_classification ON searchfields (classification);
CREATE INDEX searchfields_isbn ON searchfields (isbn);
CREATE INDEX searchfields_issn ON searchfields (issn);
CREATE INDEX searchfields_mark ON searchfields (mark);
CREATE INDEX searchfields_mediatype ON searchfields (mediatype);
CREATE INDEX searchfields_titlestring ON searchfields (titlestring);
CREATE INDEX searchfields_source ON searchfields (source);
CREATE INDEX searchfields_year ON searchfields (year);
CREATE INDEX searchfields_content ON searchfields (content);

CREATE TRIGGER partition_trg BEFORE INSERT ON searchfields FOR EACH ROW EXECUTE PROCEDURE trg_partition('month');

CREATE INDEX searchfields_without_partitions_tstamp_year ON searchfields_without_partitions (tstamp_year);

INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2007;
INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2008;
INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2009;
INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2010;
INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2011;
INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2012;
INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2013;
INSERT INTO searchfields (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,freesearch,title,person,corporatebody,subject,classification,isbn,issn,mark,mediatype,titlestring,source,year,content) select *  from searchfields_without_partitions where tstamp_year=2014;

SELECT run_on_partitions('searchfields','ALTER TABLE PARTITION ADD CONSTRAINT fk_PARTITION_session FOREIGN KEY (sid) REFERENCES sessioninfo (id)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_sid ON PARTITION USING btree(sid)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_id ON PARTITION USING btree(id)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_tstamp ON PARTITION USING btree(tstamp)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_tstamp_year ON PARTITION USING btree(tstamp_year)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_tstamp_month ON PARTITION USING btree(tstamp_month)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_tstamp_day ON PARTITION USING btree(tstamp_day)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_viewname ON PARTITION USING btree(viewname)');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_freesearch ON PARTITION USING btree(freesearch) WHERE freesearch IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_title ON PARTITION USING btree(title) WHERE title IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_person ON PARTITION USING btree(person) WHERE person IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_corporatebody ON PARTITION USING btree(corporatebody) WHERE corporatebody IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_subject ON PARTITION USING btree(subject) WHERE subject IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_classification ON PARTITION USING btree(classification) WHERE classification IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_isbn ON PARTITION USING btree(isbn) WHERE isbn IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_issn ON PARTITION USING btree(issn) WHERE issn IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_mark ON PARTITION USING btree(mark) WHERE mark IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_mediatype ON PARTITION USING btree(mediatype) WHERE mediatype IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_titlestring ON PARTITION USING btree(titlestring) WHERE titlestring IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_source ON PARTITION USING btree(source) WHERE source IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_year ON PARTITION USING btree(year) WHERE year IS TRUE');
SELECT run_on_partitions('searchfields','CREATE INDEX PARTITION_content ON PARTITION USING btree(content) WHERE content IS TRUE');

-- eventlog
DROP INDEX eventlog_sid;
DROP INDEX eventlog_tstamp;
DROP INDEX eventlog_tstamp_year;
DROP INDEX eventlog_tstamp_month;
DROP INDEX eventlog_tstamp_day;
DROP INDEX eventlog_type;
DROP INDEX eventlog_content;

alter table eventlog rename to eventlog_without_partitions;

CREATE TABLE eventlog (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
);

ALTER TABLE eventlog ADD PRIMARY KEY (id);
ALTER TABLE eventlog ADD CONSTRAINT fk_eventlog_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlog_sid ON eventlog (sid);
CREATE INDEX eventlog_tstamp ON eventlog (tstamp);
CREATE INDEX eventlog_tstamp_year ON eventlog (tstamp_year);
CREATE INDEX eventlog_tstamp_month ON eventlog (tstamp_month);
CREATE INDEX eventlog_tstamp_day ON eventlog (tstamp_day);
CREATE INDEX eventlog_type ON eventlog (type);
CREATE INDEX eventlog_content ON eventlog (content text_pattern_ops);

CREATE TRIGGER partition_trg BEFORE INSERT ON eventlog FOR EACH ROW EXECUTE PROCEDURE trg_partition('month');

CREATE INDEX eventlog_without_partitions_tstamp_year ON eventlog_without_partitions (tstamp_year);

INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2007;
INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2008;
INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2009;
INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2010;
INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2011;
INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2012;
INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2013;
INSERT INTO eventlog (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlog_without_partitions where tstamp_year=2014;

SELECT run_on_partitions('eventlog','ALTER TABLE PARTITION ADD CONSTRAINT fk_PARTITION_session FOREIGN KEY (sid) REFERENCES sessioninfo (id)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_id ON PARTITION USING btree(id)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_sid ON PARTITION USING btree(sid)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_tstamp ON PARTITION USING btree(tstamp)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_tstamp_year ON PARTITION USING btree(tstamp_year)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_tstamp_month ON PARTITION USING btree(tstamp_month)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_tstamp_day ON PARTITION USING btree(tstamp_day)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_type ON PARTITION USING btree(type)');
SELECT run_on_partitions('eventlog','CREATE INDEX PARTITION_content ON PARTITION USING btree(content text_pattern_ops)');

-- eventlogjson
DROP INDEX eventlogjson_sid;
DROP INDEX eventlogjson_tstamp;
DROP INDEX eventlogjson_tstamp_year;
DROP INDEX eventlogjson_tstamp_month;
DROP INDEX eventlogjson_tstamp_day;
DROP INDEX eventlogjson_type;

alter table eventlogjson rename to eventlogjson_without_partitions;

CREATE TABLE eventlogjson (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 type         INT,
 content      TEXT
);

ALTER TABLE eventlogjson ADD PRIMARY KEY (id);
ALTER TABLE eventlogjson ADD CONSTRAINT fk_eventlogjson_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlogjson_sid ON eventlogjson (sid);
CREATE INDEX eventlogjson_tstamp ON eventlogjson (tstamp);
CREATE INDEX eventlogjson_tstamp_year ON eventlogjson (tstamp_year);
CREATE INDEX eventlogjson_tstamp_month ON eventlogjson (tstamp_month);
CREATE INDEX eventlogjson_tstamp_day ON eventlogjson (tstamp_day);
CREATE INDEX eventlogjson_type ON eventlogjson (type);

CREATE TRIGGER partition_trg BEFORE INSERT ON eventlogjson FOR EACH ROW EXECUTE PROCEDURE trg_partition('month');

CREATE INDEX eventlogjson_without_partitions_tstamp_year ON eventlogjson_without_partitions (tstamp_year);

INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2007;
INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2008;
INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2009;
INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2010;
INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2011;
INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2012;
INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2013;
INSERT INTO eventlogjson (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,type,content) select *  from eventlogjson_without_partitions where tstamp_year=2014;

SELECT run_on_partitions('eventlogjson','ALTER TABLE PARTITION ADD CONSTRAINT fk_PARTITION_session FOREIGN KEY (sid) REFERENCES sessioninfo (id)');
SELECT run_on_partitions('eventlogjson','CREATE INDEX PARTITION_id ON PARTITION USING btree(id)');
SELECT run_on_partitions('eventlogjson','CREATE INDEX PARTITION_sid ON PARTITION USING btree(sid)');
SELECT run_on_partitions('eventlogjson','CREATE INDEX PARTITION_type ON PARTITION USING btree(type)');
SELECT run_on_partitions('eventlogjson','CREATE INDEX PARTITION_tstamp ON PARTITION USING btree(tstamp)');
SELECT run_on_partitions('eventlogjson','CREATE INDEX PARTITION_tstamp_year ON PARTITION USING btree(tstamp_year)');
SELECT run_on_partitions('eventlogjson','CREATE INDEX PARTITION_tstamp_month ON PARTITION USING btree(tstamp_month)');
SELECT run_on_partitions('eventlogjson','CREATE INDEX PARTITION_tstamp_day ON PARTITION USING btree(tstamp_day)');

-- titleusage

DROP INDEX titleusage_sid;
DROP INDEX titleusage_tstamp;
DROP INDEX titleusage_tstamp_year;
DROP INDEX titleusage_tstamp_month;
DROP INDEX titleusage_tstamp_day;
DROP INDEX titleusage_viewname;
DROP INDEX titleusage_isbn;
DROP INDEX titleusage_dbname;
DROP INDEX titleusage_id;
DROP INDEX titleusage_origin;

alter table titleusage rename to titleusage_without_partitions;

CREATE TABLE titleusage (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname     TEXT,
 isbn         TEXT,
 dbname       TEXT NOT NULL,
 id           TEXT NOT NULL,
 origin       SMALLINT
);

ALTER TABLE titleusage ADD PRIMARY KEY (id);
ALTER TABLE titleusage ADD CONSTRAINT fk_titleusage_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX titleusage_sid ON titleusage (sid);
CREATE INDEX titleusage_tstamp ON titleusage (tstamp);
CREATE INDEX titleusage_tstamp_year ON titleusage (tstamp_year);
CREATE INDEX titleusage_tstamp_month ON titleusage (tstamp_month);
CREATE INDEX titleusage_tstamp_day ON titleusage (tstamp_day);
CREATE INDEX titleusage_viewname ON titleusage (viewname);
CREATE INDEX titleusage_isbn ON titleusage (isbn);
CREATE INDEX titleusage_dbname ON titleusage (dbname);
CREATE INDEX titleusage_id ON titleusage (id);
CREATE INDEX titleusage_origin ON titleusage (origin);

CREATE TRIGGER partition_trg BEFORE INSERT ON titleusage FOR EACH ROW EXECUTE PROCEDURE trg_partition('month');

CREATE INDEX titleusage_without_partitions_tstamp_year ON titleusage_without_partitions (tstamp_year);

INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2007;
INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2008;
INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2009;
INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2010;
INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2011;
INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2012;
INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2013;
INSERT INTO titleusage (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,isbn,dbname,id,origin) select *  from titleusage_without_partitions where tstamp_year=2014;

SELECT run_on_partitions('titleusage','ALTER TABLE PARTITION ADD CONSTRAINT fk_PARTITION_session FOREIGN KEY (sid) REFERENCES sessioninfo (id)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_sid ON PARTITION USING btree(sid)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_tstamp ON PARTITION USING btree(tstamp)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_tstamp_year ON PARTITION USING btree(tstamp_year)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_tstamp_month ON PARTITION USING btree(tstamp_month)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_tstamp_day ON PARTITION USING btree(tstamp_day)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_viewname ON PARTITION USING btree(viewname)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_isbn ON PARTITION USING btree(isbn)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_dbname ON PARTITION USING btree(dbname)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_id ON PARTITION USING btree(id)');
SELECT run_on_partitions('titleusage','CREATE INDEX PARTITION_origin ON PARTITION USING btree(origin)');

-- searchterms

DROP INDEX searchterms_sid;
DROP INDEX searchterms_tstamp;
DROP INDEX searchterms_viewname;
DROP INDEX searchterms_type;
DROP INDEX searchterms_content;

alter table searchterms rename to searchterms_without_partitions;

CREATE TABLE searchterms (
 id           BIGSERIAL,
 sid          BIGINT,

 tstamp       TIMESTAMP,
 tstamp_year  SMALLINT,
 tstamp_month SMALLINT,
 tstamp_day   SMALLINT,

 viewname   TEXT,
 type       INT,
 content    TEXT
);

ALTER TABLE searchterms ADD PRIMARY KEY (id);
ALTER TABLE searchterms ADD CONSTRAINT fk_searchterms_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX searchterms_sid ON searchterms (sid);
CREATE INDEX searchterms_tstamp ON searchterms (tstamp);
CREATE INDEX searchterms_viewname ON searchterms (viewname);
CREATE INDEX searchterms_type ON searchterms (type);
CREATE INDEX searchterms_content ON searchterms (content);

CREATE TRIGGER partition_trg BEFORE INSERT ON searchterms FOR EACH ROW EXECUTE PROCEDURE trg_partition('month');

CREATE INDEX searchterms_without_partitions_tstamp_year ON searchterms_without_partitions (tstamp_year);

INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2007;
INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2008;
INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2009;
INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2010;
INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2011;
INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2012;
INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2013;
INSERT INTO searchterms (sid,tstamp,tstamp_year,tstamp_month,tstamp_day,viewname,type,content) select *  from searchterms_without_partitions where tstamp_year=2014;

SELECT run_on_partitions('searchterms','ALTER TABLE PARTITION ADD CONSTRAINT fk_PARTITION_session FOREIGN KEY (sid) REFERENCES sessioninfo (id)');
SELECT run_on_partitions('searchterms','CREATE INDEX PARTITION_sid ON PARTITION USING btree(sid)');
SELECT run_on_partitions('searchterms','CREATE INDEX PARTITION_tstamp ON PARTITION USING btree(tstamp)');
SELECT run_on_partitions('searchterms','CREATE INDEX PARTITION_viewname ON PARTITION USING btree(viewname)');
SELECT run_on_partitions('searchterms','CREATE INDEX PARTITION_type ON PARTITION USING btree(type)');
SELECT run_on_partitions('searchterms','CREATE INDEX PARTITION_content ON PARTITION USING btree(content)');

