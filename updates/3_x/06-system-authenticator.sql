DROP TABLE IF EXISTS authenticatorinfo;
CREATE TABLE authenticatorinfo (
 id          BIGSERIAL,

 name        TEXT,
 description TEXT,
 type        TEXT
);

insert into authenticatorinfo (id,name,description,type) select id,dbname,description,type from authenticator;

SELECT setval('authenticatorinfo_id_seq', (SELECT MAX(id) FROM authenticatorinfo));

ALTER TABLE authenticatorinfo ADD PRIMARY KEY (id);
CREATE INDEX authenticatorinfo_name ON authenticatorinfo (name);
CREATE INDEX authenticatorinfo_type ON authenticatorinfo (type);

ALTER TABLE userinfo ADD COLUMN authenticatorid BIGINT;
ALTER TABLE userinfo ADD CONSTRAINT fk_userinfo_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticatorinfo (id);

update userinfo set authenticatorid = (select id from authenticatorinfo where type='self') where username like '%@%';
update userinfo set authenticatorid = (select id from authenticatorinfo where type='self') where username = 'admin'; 

DROP TABLE IF EXISTS authenticator_view;
CREATE TABLE authenticator_view (
  id        BIGSERIAL,
  authenticatorid    BIGINT NOT NULL,
  viewid    BIGINT NOT NULL
);

ALTER TABLE user_session DROP CONSTRAINT fk_usersession_authenticator;
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticatorinfo (id);

DROP TABLE authenticator;

ALTER TABLE authenticator_view ADD PRIMARY KEY (id);
ALTER TABLE authenticator_view ADD CONSTRAINT fk_authenticatorview_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
ALTER TABLE authenticator_view ADD CONSTRAINT fk_authenticatorview_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticatorinfo (id);
CREATE INDEX authenticator_view_viewid ON authenticator_view (viewid);
CREATE INDEX authenticator_view_authenticatorid ON authenticator_view (authenticatorid);

