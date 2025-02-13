DROP TABLE IF EXISTS networkinfo;

CREATE TABLE networkinfo (
    id BIGSERIAL,
    network CIDR NOT NULL,
    country TEXT,
    continent TEXT,
    is_eu INT
);

ALTER TABLE networkinfo ADD PRIMARY KEY (id);
CREATE INDEX networkinfo_network ON networkinfo USING gist (network inet_ops);

ALTER TABLE sessioninfo ADD COLUMN network cidr;
CREATE INDEX sessioninfo_network ON sessioninfo USING gist (network inet_ops);
