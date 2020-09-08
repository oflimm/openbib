--- Role roleid can be administered by viewadmin of view viewid
DROP TABLE IF EXISTS role_viewadmin;
CREATE TABLE role_viewadmin (
  id        BIGSERIAL,
  roleid    BIGINT NOT NULL,
  viewid    BIGINT NOT NULL
);

ALTER TABLE role_viewadmin ADD PRIMARY KEY (id);
ALTER TABLE role_viewadmin ADD CONSTRAINT fk_roleviewadmin_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
ALTER TABLE role_viewadmin ADD CONSTRAINT fk_roleviewadmin_role FOREIGN KEY (roleid) REFERENCES roleinfo (id);
CREATE INDEX role_viewadmin_viewid ON role_viewadmin (viewid);
CREATE INDEX role_viewadmin_roleid ON role_viewadmin (roleid);
