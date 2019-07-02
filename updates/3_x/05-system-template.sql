alter TABLE templateinfo add column templatedesc TEXT;
alter TABLE templateinfo add column templatepart TEXT;

CREATE INDEX templateinfo_templatepart ON templateinfo (templatepart);
