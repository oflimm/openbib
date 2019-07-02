ALTER TABLE user_view DROP CONSTRAINT fk_userview_user;
DROP TABLE user_view;

ALTER TABLE userinfo ADD COLUMN viewid BIGINT;
ALTER TABLE userinfo ADD CONSTRAINT fk_userinfo_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);

ALTER TABLE userinfo DROP CONSTRAINT uq_userinfo_username;
ALTER TABLE userinfo ADD CONSTRAINT uq_userinfo_username UNIQUE (username,viewid);

ALTER TABLE registration ADD COLUMN viewid BIGINT;
ALTER TABLE registration ADD CONSTRAINT fk_registration_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
