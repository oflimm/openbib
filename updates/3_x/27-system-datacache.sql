drop table IF EXISTS datacache;
CREATE TABLE datacache (
 id          TEXT,
 tstamp      TIMESTAMP,
 type        INT,
 subkey      TEXT,
 data        TEXT
);

CREATE INDEX datacache_id ON datacache (id);
CREATE INDEX datacache_tstamp ON datacache (tstamp);
CREATE INDEX datacache_subkey ON datacache (subkey);
CREATE INDEX datacache_type ON datacache (type);
