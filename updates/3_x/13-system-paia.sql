DROP TABLE IF EXISTS paia;
CREATE TABLE paia (
  id                  BIGSERIAL,
  tstamp              TIMESTAMP,

  username            TEXT,
  token               TEXT

);

ALTER TABLE paia ADD PRIMARY KEY (id);

CREATE INDEX paia_username ON paia (username);
CREATE INDEX paia_token ON paia (token);
CREATE INDEX paia_tstamp ON paia (tstamp);

ALTER TABLE paia ALTER COLUMN tstamp SET DEFAULT now();

ALTER TABLE sessioninfo DROP COLUMN userpassword;

ALTER TABLE userinfo ADD COLUMN token TEXT;
