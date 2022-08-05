drop table IF EXISTS locationinfo_occupancy;
create table locationinfo_occupancy (
 id            BIGSERIAL,
 locationid    BIGINT      NOT NULL,

 tstamp        TIMESTAMP,
 num_entries   INT DEFAULT 0,
 num_exits     INT DEFAULT 0,
 num_occupancy INT DEFAULT 0
);

ALTER TABLE locationinfo_occupancy ADD CONSTRAINT fk_locationinfo_occupancy FOREIGN KEY (locationid) REFERENCES locationinfo (id);
CREATE INDEX locationinfo_occupancy_locationid ON locationinfo_occupancy (locationid);
CREATE INDEX locationinfo_occupancy_tstamp ON locationinfo_occupancy (tstamp);
