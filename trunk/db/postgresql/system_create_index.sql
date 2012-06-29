ALTER TABLE databaseinfo ADD PRIMARY KEY (id);
ALTER TABLE databaseinfo ADD CONSTRAINT uq_databaseinfo_dbname UNIQUE (dbname);
CREATE INDEX databaseinfo_dbname ON databaseinfo (dbname);
CREATE INDEX databaseinfo_active ON databaseinfo (active);
CREATE INDEX databaseinfo_description ON databaseinfo (description);

ALTER TABLE libraryinfo ADD CONSTRAINT fk_libraryinfo_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX libraryinfo_category ON libraryinfo (category);
CREATE INDEX libraryinfo_indicator ON libraryinfo (indicator);
CREATE INDEX libraryinfo_content ON libraryinfo (content);

ALTER TABLE rssinfo ADD PRIMARY KEY (id);
ALTER TABLE rssinfo ADD CONSTRAINT fk_rssinfo_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX rssinfo_type ON rssinfo (type);
CREATE INDEX rssinfo_subtype ON rssinfo (subtype);
CREATE INDEX rssinfo_cachetstamp ON rssinfo (cache_tstamp);

ALTER TABLE profileinfo ADD PRIMARY KEY (id);
ALTER TABLE profileinfo ADD CONSTRAINT uq_profileinfo_profilename UNIQUE (profilename);
CREATE INDEX profileinfo_profilename ON profileinfo (profilename);

ALTER TABLE orgunitinfo ADD PRIMARY KEY (id);
ALTER TABLE orgunitinfo ADD CONSTRAINT fk_orgunitinfo_profile FOREIGN KEY (profileid) REFERENCES profileinfo (id);
CREATE INDEX orgunitinfo_orgunitname ON orgunitinfo (orgunitname);
CREATE INDEX orgunitinfo_nr ON orgunitinfo (nr);

ALTER TABLE orgunit_db ADD CONSTRAINT fk_orgunitdb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
ALTER TABLE orgunit_db ADD CONSTRAINT fk_orgunitdb_orgunit FOREIGN KEY (orgunitid) REFERENCES orgunitinfo (id);

ALTER TABLE viewinfo ADD PRIMARY KEY (id);
ALTER TABLE viewinfo ADD CONSTRAINT uq_viewinfo_viewname UNIQUE (viewname);
ALTER TABLE viewinfo ADD CONSTRAINT fk_viewinfo_profile FOREIGN KEY (profileid) REFERENCES profileinfo (id);
ALTER TABLE viewinfo ADD CONSTRAINT fk_viewinfo_rss FOREIGN KEY (rssid) REFERENCES rssinfo (id);
CREATE INDEX viewinfo_viewname ON viewinfo (viewname);

ALTER TABLE view_db ADD CONSTRAINT fk_viewdb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
ALTER TABLE view_db ADD CONSTRAINT fk_viewdb_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);

ALTER TABLE view_rss ADD CONSTRAINT fk_viewrss_rss FOREIGN KEY (rssid) REFERENCES rssinfo (id);
ALTER TABLE view_rss ADD CONSTRAINT fk_viewrss_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);

ALTER TABLE serverinfo ADD PRIMARY KEY (id);
CREATE INDEX serverinfo_active ON serverinfo (active);

ALTER TABLE sessioninfo ADD PRIMARY KEY (id);
CREATE INDEX sessioninfo_sessionid ON sessioninfo (sessionid);
CREATE INDEX sessioninfo_username ON sessioninfo (username);

ALTER TABLE sessioncollection ADD PRIMARY KEY (id);
ALTER TABLE sessioncollection ADD CONSTRAINT fk_sessioncollection_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX sessioncollection_dbname ON sessioncollection (dbname);
CREATE INDEX sessioncollection_titleid ON sessioncollection (titleid);

ALTER TABLE recordhistory ADD CONSTRAINT fk_recordhistory_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

ALTER TABLE eventlog ADD CONSTRAINT fk_eventlog_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlog_tstamp ON eventlog (tstamp);
CREATE INDEX eventlog_type ON eventlog (type);
CREATE INDEX eventlog_content ON eventlog (content);

ALTER TABLE eventlogjson ADD CONSTRAINT fk_eventlogjson_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlogjson_tstamp ON eventlogjson (tstamp);
CREATE INDEX eventlogjson_type ON eventlogjson (type);

ALTER TABLE queries ADD PRIMARY KEY (queryid);
ALTER TABLE queries ADD CONSTRAINT fk_queries_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE queries ADD CONSTRAINT fk_queries_searchprofile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
CREATE INDEX queries_searchprofileid ON queries (searchprofileid);
CREATE INDEX queries_query ON queries (query);

ALTER TABLE searchhistory ADD CONSTRAINT fk_searchhistory_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX searchhistory_dbname ON searchhistory (dbname);
CREATE INDEX searchhistory_queryid ON searchhistory (queryid);

ALTER TABLE userinfo ADD PRIMARY KEY (id);
ALTER TABLE userinfo ADD CONSTRAINT uq_userinfo_username UNIQUE (username);

ALTER TABLE role ADD PRIMARY KEY (id);

ALTER TABLE user_role ADD PRIMARY KEY (id);
ALTER TABLE user_role ADD CONSTRAINT fk_userrole_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_role ADD CONSTRAINT fk_userrole_role FOREIGN KEY (roleid) REFERENCES role (id);

ALTER TABLE registration ADD PRIMARY KEY (id);

ALTER TABLE logintarget ADD PRIMARY KEY (id);

ALTER TABLE user_session ADD PRIMARY KEY (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_logintarget FOREIGN KEY (targetid) REFERENCES logintarget (id);

ALTER TABLE searchprofile ADD PRIMARY KEY (id);
CREATE INDEX searchprofile_dbases_as_json ON searchprofile (databases_as_json);

ALTER TABLE searchprofile_db ADD CONSTRAINT fk_searchprofiledb_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE searchprofile_db ADD CONSTRAINT fk_searchprofiledb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);

ALTER TABLE session_searchprofile ADD CONSTRAINT fk_sessionsearchprofile_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE session_searchprofile ADD CONSTRAINT fk_sessionsearchprofile_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

ALTER TABLE user_searchprofile ADD PRIMARY KEY (id);
ALTER TABLE user_searchprofile ADD CONSTRAINT fk_usersearchprofile_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE user_searchprofile ADD CONSTRAINT fk_usersearchprofile_user FOREIGN KEY (userid) REFERENCES userinfo (id);

ALTER TABLE searchfield ADD CONSTRAINT fk_searchfield_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX searchfield_searchfield ON searchfield (searchfield);

ALTER TABLE livesearch ADD CONSTRAINT fk_livesearch_user FOREIGN KEY (userid) REFERENCES userinfo (id);

ALTER TABLE collection ADD PRIMARY KEY (id);
ALTER TABLE collection ADD CONSTRAINT fk_collection_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX collection_dbname ON collection (dbname);
CREATE INDEX collection_titleid ON collection (titleid);

ALTER TABLE tag ADD PRIMARY KEY (id);
CREATE INDEX tag_name ON tag (name);

ALTER TABLE tit_tag ADD PRIMARY KEY (id);
ALTER TABLE tit_tag ADD CONSTRAINT fk_tittag_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE tit_tag ADD CONSTRAINT fk_tittag_tag FOREIGN KEY (tagid) REFERENCES tag (id);
CREATE INDEX tittag_titleid ON tit_tag (titleid);
CREATE INDEX tittag_dbname ON tit_tag (dbname);
CREATE INDEX tittag_type ON tit_tag (type);

ALTER TABLE review ADD PRIMARY KEY (id);
ALTER TABLE review ADD CONSTRAINT fk_review_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX review_titleid ON review (titleid);
CREATE INDEX review_dbname ON review (dbname);
CREATE INDEX review_titleisbn ON review (titleisbn);

ALTER TABLE reviewrating ADD PRIMARY KEY (id);
ALTER TABLE reviewrating ADD CONSTRAINT fk_reviewrating_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE reviewrating ADD CONSTRAINT fk_reviewrating_review FOREIGN KEY (reviewid) REFERENCES review (id);

ALTER TABLE litlist ADD PRIMARY KEY (id);
ALTER TABLE litlist ADD CONSTRAINT fk_litlist_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX litlist_title ON litlist (title);
CREATE INDEX litlist_type ON litlist (type);

ALTER TABLE litlistitem ADD PRIMARY KEY (id);
ALTER TABLE litlistitem ADD CONSTRAINT fk_litlistitem_litlist FOREIGN KEY (litlistid) REFERENCES litlist (id);
CREATE INDEX litlistitem_dbname ON litlistitem (dbname);
CREATE INDEX litlistitem_titleid ON litlistitem (titleid);
CREATE INDEX litlistitem_titleisbn ON litlistitem (titleisbn);

ALTER TABLE subject ADD PRIMARY KEY (id);

ALTER TABLE litlist_subject ADD PRIMARY KEY (id);
ALTER TABLE litlist_subject ADD CONSTRAINT fk_litlistsubject_litlist FOREIGN KEY (litlistid) REFERENCES litlist (id);
ALTER TABLE litlist_subject ADD CONSTRAINT fk_litlistsubject_subject FOREIGN KEY (subjectid) REFERENCES subject (id);

ALTER TABLE subjectclassification ADD CONSTRAINT fk_subjectclassification_subject FOREIGN KEY (subjectid) REFERENCES subject (id);
CREATE INDEX subjectclassification_type ON subjectclassification (type);
CREATE INDEX subjectclassification_classification ON subjectclassification (classification);