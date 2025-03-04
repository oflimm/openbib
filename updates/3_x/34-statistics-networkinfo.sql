DROP TABLE IF EXISTS networkinfo;

CREATE TABLE networkinfo (
    id BIGSERIAL,
    network CIDR NOT NULL,
    country TEXT,
    country_name TEXT,
    continent TEXT,
    subdivision TEXT,
    subsubdivision TEXT,
    city TEXT,
    is_eu INT
);

ALTER TABLE networkinfo ADD PRIMARY KEY (id);
CREATE INDEX networkinfo_network ON networkinfo USING gist (network inet_ops);
CREATE INDEX networkinfo_country ON networkinfo (country);
CREATE INDEX networkinfo_country_name ON networkinfo (country_name);
CREATE INDEX networkinfo_continent ON networkinfo (continent);
CREATE INDEX networkinfo_is_eu ON networkinfo (is_eu);

ALTER TABLE sessioninfo ADD COLUMN network cidr;
CREATE INDEX sessioninfo_network ON sessioninfo USING gist (network inet_ops);
