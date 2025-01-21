alter TABLE sessioninfo add column expiretime TIMESTAMP;
CREATE INDEX sessioninfo_expiretime ON sessioninfo (expiretime);
