alter table all_titles_by_isbn add column location varchar(255);
alter table all_titles_by_issn add column location varchar(255);
alter table all_titles_by_bibkey add column location varchar(255);
alter table all_titles_by_workkey add column location varchar(255);


create table all_titles_by_isbn_tmp (
 isbn          VARCHAR(13)  NOT NULL,
 dbname        VARCHAR(25)  NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

INSERT INTO all_titles_by_isbn_tmp (isbn,dbname,titleid,location,tstamp,titlecache) select isbn,dbname,titleid,location,tstamp,titlecache from all_titles_by_isbn; 

DROP TABLE all_titles_by_isbn;

alter table all_titles_by_isbn_tmp rename to all_titles_by_isbn;

CREATE INDEX alltitlesisbn_isbn ON all_titles_by_isbn (isbn);
CREATE INDEX alltitlesisbn_dbname ON all_titles_by_isbn (dbname);
CREATE INDEX alltitlesisbn_location ON all_titles_by_isbn (location);
CREATE INDEX alltitlesisbn_titleid ON all_titles_by_isbn (titleid);

create table all_titles_by_issn_tmp (
 issn          VARCHAR(8)  NOT NULL,
 dbname        VARCHAR(25)  NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

INSERT INTO all_titles_by_issn_tmp (issn,dbname,titleid,location,tstamp,titlecache) select issn,dbname,titleid,location,tstamp,titlecache from all_titles_by_issn; 

DROP TABLE all_titles_by_issn;

alter table all_titles_by_issn_tmp rename to all_titles_by_issn;

CREATE INDEX alltitlesissn_issn ON all_titles_by_issn (issn);
CREATE INDEX alltitlesissn_dbname ON all_titles_by_issn (dbname);
CREATE INDEX alltitlesissn_location ON all_titles_by_issn (location);
CREATE INDEX alltitlesissn_titleid ON all_titles_by_issn (titleid);

create table all_titles_by_bibkey_tmp (
 bibkey        VARCHAR(33)  NOT NULL,
 dbname        VARCHAR(25)  NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
 tstamp        TIMESTAMP,
 titlecache    TEXT
);

INSERT INTO all_titles_by_bibkey_tmp (bibkey,dbname,titleid,location,tstamp,titlecache) select bibkey,dbname,titleid,location,tstamp,titlecache from all_titles_by_bibkey; 

DROP TABLE all_titles_by_bibkey;

alter table all_titles_by_bibkey_tmp rename to all_titles_by_bibkey;

CREATE INDEX alltitlesbibkey_bibkey ON all_titles_by_bibkey (bibkey);
CREATE INDEX alltitlesbibkey_dbname ON all_titles_by_bibkey (dbname);
CREATE INDEX alltitlesbibkey_location ON all_titles_by_bibkey (location);
CREATE INDEX alltitlesbibkey_titleid ON all_titles_by_bibkey (titleid);

create table all_titles_by_workkey_tmp (
 id            BIGSERIAL,
 workkey       TEXT NOT NULL,
 edition       TEXT,
 dbname        VARCHAR(25) NOT NULL,
 titleid       VARCHAR(255) NOT NULL,
 location      VARCHAR(255),
 titlecache    TEXT,
 tstamp        TIMESTAMP
);

INSERT INTO all_titles_by_workkey_tmp (workkey,edition,dbname,titleid,location,titlecache,tstamp) select workkey,edition,dbname,titleid,location,titlecache,tstamp from all_titles_by_workkey; 

DROP TABLE all_titles_by_workkey;

alter table all_titles_by_workkey_tmp rename to all_titles_by_workkey;

ALTER TABLE all_titles_by_workkey ADD PRIMARY KEY (id);
CREATE INDEX alltitlesworkkey_workkey ON all_titles_by_workkey (workkey);
CREATE INDEX alltitlessworkkey_dbname ON all_titles_by_workkey (dbname);
CREATE INDEX alltitlessworkkey_titleid ON all_titles_by_workkey (titleid);
CREATE INDEX alltitlessworkkey_location ON all_titles_by_workkey (location);
CREATE INDEX alltitlessworkkey_edition ON all_titles_by_workkey (edition);
