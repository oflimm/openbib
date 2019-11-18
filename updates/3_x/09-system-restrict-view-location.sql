drop table IF EXISTS view_location;
CREATE TABLE view_location (
 id         BIGSERIAL,
 viewid     BIGINT NOT NULL,
 locationid BIGINT NOT NULL
);

ALTER TABLE view_location ADD PRIMARY KEY (id);
ALTER TABLE view_location ADD CONSTRAINT fk_viewlocation_location FOREIGN KEY (locationid) REFERENCES locationinfo (id);
ALTER TABLE view_location ADD CONSTRAINT fk_viewlocation_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX view_location_locationid ON view_location (locationid);
CREATE INDEX view_location_viewid ON view_location (viewid);
