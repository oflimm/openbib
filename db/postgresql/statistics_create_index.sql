-------------------------------------------------
-------- Indizes / Primary / Foreign Keys -------
-------------------------------------------------
CREATE INDEX datacache_id ON datacache (id);
CREATE INDEX datacache_tstamp ON datacache (tstamp);
CREATE INDEX datacache_subkey ON datacache (subkey);
CREATE INDEX datacache_type ON datacache (type);

-------------------------------------------------

ALTER TABLE sessioninfo ADD PRIMARY KEY (id);
CREATE INDEX sessioninfo_sessionid ON sessioninfo (sessionid);
CREATE INDEX sessioninfo_createtime ON sessioninfo (createtime);
CREATE INDEX sessioninfo_createtime_year ON sessioninfo (createtime_year);
CREATE INDEX sessioninfo_createtime_month ON sessioninfo (createtime_month);
CREATE INDEX sessioninfo_createtime_day ON sessioninfo (createtime_day);
CREATE INDEX sessioninfo_viewname ON sessioninfo (viewname);
CREATE INDEX sessioninfo_network ON sessioninfo USING gist (network inet_ops);

-------------------------------------------------

ALTER TABLE titleusage ADD PRIMARY KEY (id,tstamp);
ALTER TABLE titleusage ADD CONSTRAINT fk_titleusage_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX titleusage_sid ON titleusage (sid);
CREATE INDEX titleusage_tstamp ON titleusage (tstamp);
CREATE INDEX titleusage_tstamp_year ON titleusage (tstamp_year);
CREATE INDEX titleusage_tstamp_month ON titleusage (tstamp_month);
CREATE INDEX titleusage_tstamp_day ON titleusage (tstamp_day);
CREATE INDEX titleusage_viewname ON titleusage (viewname);
CREATE INDEX titleusage_isbn ON titleusage (isbn);
CREATE INDEX titleusage_dbname ON titleusage (dbname);
CREATE INDEX titleusage_id ON titleusage (id);
CREATE INDEX titleusage_origin ON titleusage (origin);

-------------------------------------------------

ALTER TABLE eventlog ADD PRIMARY KEY (id,tstamp);
ALTER TABLE eventlog ADD CONSTRAINT fk_eventlog_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlog_sid ON eventlog (sid);
CREATE INDEX eventlog_tstamp ON eventlog (tstamp);
CREATE INDEX eventlog_tstamp_year ON eventlog (tstamp_year);
CREATE INDEX eventlog_tstamp_month ON eventlog (tstamp_month);
CREATE INDEX eventlog_tstamp_day ON eventlog (tstamp_day);
CREATE INDEX eventlog_type ON eventlog (type);
CREATE INDEX eventlog_content ON eventlog (content text_pattern_ops);

-------------------------------------------------

ALTER TABLE eventlogjson ADD PRIMARY KEY (id,tstamp);
ALTER TABLE eventlogjson ADD CONSTRAINT fk_eventlogjson_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlogjson_sid ON eventlogjson (sid);
CREATE INDEX eventlogjson_tstamp ON eventlogjson (tstamp);
CREATE INDEX eventlogjson_tstamp_year ON eventlogjson (tstamp_year);
CREATE INDEX eventlogjson_tstamp_month ON eventlogjson (tstamp_month);
CREATE INDEX eventlogjson_tstamp_day ON eventlogjson (tstamp_day);
CREATE INDEX eventlogjson_type ON eventlogjson (type);

-------------------------------------------------

ALTER TABLE searchterms ADD PRIMARY KEY (id,tstamp);
ALTER TABLE searchterms ADD CONSTRAINT fk_searchterms_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX searchterms_sid ON searchterms (sid);
CREATE INDEX searchterms_tstamp ON searchterms (tstamp);
CREATE INDEX searchterms_viewname ON searchterms (viewname);
CREATE INDEX searchterms_type ON searchterms (type);
CREATE INDEX searchterms_content ON searchterms (content);

-------------------------------------------------

ALTER TABLE searchfields ADD PRIMARY KEY (id,tstamp);
ALTER TABLE searchfields ADD CONSTRAINT fk_searchfields_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX searchfields_sid ON searchfields (sid);
CREATE INDEX searchfields_tstamp ON searchfields (tstamp);
CREATE INDEX searchfields_tstamp_year ON searchfields (tstamp_year);
CREATE INDEX searchfields_tstamp_month ON searchfields (tstamp_month);
CREATE INDEX searchfields_tstamp_day ON searchfields (tstamp_day);
CREATE INDEX searchfields_viewname ON searchfields (viewname);
CREATE INDEX searchfields_freesearch ON searchfields (freesearch);
CREATE INDEX searchfields_title ON searchfields (title);
CREATE INDEX searchfields_person ON searchfields (person);
CREATE INDEX searchfields_corporatebody ON searchfields (corporatebody);
CREATE INDEX searchfields_subject ON searchfields (subject);
CREATE INDEX searchfields_classification ON searchfields (classification);
CREATE INDEX searchfields_isbn ON searchfields (isbn);
CREATE INDEX searchfields_issn ON searchfields (issn);
CREATE INDEX searchfields_mark ON searchfields (mark);
CREATE INDEX searchfields_mediatype ON searchfields (mediatype);
CREATE INDEX searchfields_titlestring ON searchfields (titlestring);
CREATE INDEX searchfields_source ON searchfields (source);
CREATE INDEX searchfields_year ON searchfields (year);

-------------------------------------------------

ALTER TABLE loans ADD PRIMARY KEY (id,tstamp);
CREATE INDEX loans_tstamp ON loans (tstamp);
CREATE INDEX loans_tstamp_year ON loans (tstamp_year);
CREATE INDEX loans_tstamp_month ON loans (tstamp_month);
CREATE INDEX loans_tstamp_day ON loans (tstamp_day);
CREATE INDEX loans_anon_userid ON loans (anon_userid);
CREATE INDEX loans_groupid ON loans (groupid);
CREATE INDEX loans_titleid ON loans (titleid);
CREATE INDEX loans_dbname ON loans (dbname);
CREATE INDEX loans_isbn ON loans (isbn);

-------------------------------------------------

ALTER TABLE networkinfo ADD PRIMARY KEY (id);
CREATE INDEX networkinfo_network ON networkinfo USING gist (network inet_ops);
CREATE INDEX networkinfo_country ON networkinfo (country);
CREATE INDEX networkinfo_country_name ON networkinfo (country_name);
CREATE INDEX networkinfo_continent ON networkinfo (continent);
CREATE INDEX networkinfo_is_eu ON networkinfo (is_eu);

vacuum analyze;
