alter TABLE databaseinfo add column schema TEXT DEFAULT '';
CREATE INDEX databaseinfo_schema ON databaseinfo (schema);
UPDATE databaseinfo SET schema='mab2';
