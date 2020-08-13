DROP TABLE IF EXISTS user_searchlocation;
CREATE TABLE user_searchlocation (
  id         BIGSERIAL,
  userid     BIGINT NOT NULL,
  locationid BIGINT NOT NULL
);

ALTER TABLE user_searchlocation ADD PRIMARY KEY (id);
ALTER TABLE user_searchlocation ADD CONSTRAINT fk_usersearchlocation_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_searchlocation ADD CONSTRAINT fk_usersearchlocation_location FOREIGN KEY (locationid) REFERENCES locationinfo (id);
CREATE INDEX usersearchlocation_userid ON user_searchlocation (userid);
CREATE INDEX usersearchlocation_searchlocationid ON user_searchlocation (locationid);
