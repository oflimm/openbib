DROP TABLE IF EXISTS authenticator_view;
CREATE TABLE authenticator_view (
  id        BIGSERIAL,
  authenticatorid    BIGINT NOT NULL,
  viewid    BIGINT NOT NULL
);


ALTER TABLE authenticator_view ADD PRIMARY KEY (id);
ALTER TABLE authenticator_view ADD CONSTRAINT fk_authenticatorview_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
ALTER TABLE authenticator_view ADD CONSTRAINT fk_authenticatorview_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticator (id);
CREATE INDEX authenticator_view_viewid ON authenticator_view (viewid);
CREATE INDEX authenticator_view_authenticatorid ON authenticator_view (authenticatorid);
