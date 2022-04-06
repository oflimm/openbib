CREATE EXTENSION "uuid-ossp";

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

ALTER TABLE authtoken ADD PRIMARY KEY (id);
ALTER TABLE authtoken ADD CONSTRAINT fk_authtoken_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX authtoken_authkey ON authtoken (authkey);
CREATE INDEX authtoken_type ON authtoken (type);
CREATE INDEX authtoken_tstamp ON authtoken (tstamp);
