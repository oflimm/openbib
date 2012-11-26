ALTER TABLE databaseinfo ADD PRIMARY KEY (id);
ALTER TABLE databaseinfo ADD CONSTRAINT uq_databaseinfo_dbname UNIQUE (dbname);
ALTER TABLE databaseinfo ADD CONSTRAINT fk_locationinfo FOREIGN KEY (locationid) REFERENCES locationinfo (id);
CREATE INDEX databaseinfo_dbname ON databaseinfo (dbname);
CREATE INDEX databaseinfo_active ON databaseinfo (active);
CREATE INDEX databaseinfo_description ON databaseinfo (description);

ALTER TABLE locationinfo ADD PRIMARY KEY (id);
CREATE INDEX locationinfo_tstamp_create on locationinfo (tstamp_create);
CREATE INDEX locationinfo_tstamp_update on locationinfo (tstamp_update);
CREATE INDEX locationinfo_identifier ON locationinfo (identifier);
CREATE INDEX locationinfo_type ON locationinfo (type);

ALTER TABLE locationinfo_fields ADD CONSTRAINT fk_locationinfo_fields FOREIGN KEY (locationid) REFERENCES locationinfo (id);
CREATE INDEX locationinfo_fields_locationid ON locationinfo_fields (locationid);
CREATE INDEX locationinfo_fields_field ON locationinfo_fields (field);
CREATE INDEX locationinfo_fields_subfield ON locationinfo_fields (subfield);
CREATE INDEX locationinfo_fields_mult ON locationinfo_fields (mult);
CREATE INDEX locationinfo_fields_content ON locationinfo_fields (content);

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

ALTER TABLE clusterinfo ADD PRIMARY KEY (id);
CREATE INDEX clusterinfo_active ON clusterinfo (active);

ALTER TABLE serverinfo ADD PRIMARY KEY (id);
CREATE INDEX serverinfo_active ON serverinfo (active);
ALTER TABLE serverinfo ADD CONSTRAINT fk_serverinfo_clusterinfo FOREIGN KEY (clusterid) REFERENCES clusterinfo (id);

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

ALTER TABLE authenticator ADD PRIMARY KEY (id);

ALTER TABLE user_session ADD PRIMARY KEY (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_authenticator FOREIGN KEY (targetid) REFERENCES authenticator (id);

ALTER TABLE searchprofile ADD PRIMARY KEY (id);
CREATE INDEX searchprofile_dbases_as_json ON searchprofile (databases_as_json);

ALTER TABLE searchprofile_db ADD CONSTRAINT fk_searchprofiledb_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE searchprofile_db ADD CONSTRAINT fk_searchprofiledb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);

ALTER TABLE session_searchprofile ADD CONSTRAINT fk_sessionsearchprofile_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE session_searchprofile ADD CONSTRAINT fk_sessionsearchprofile_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);

ALTER TABLE user_searchprofile ADD PRIMARY KEY (id);
ALTER TABLE user_searchprofile ADD CONSTRAINT fk_usersearchprofile_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE user_searchprofile ADD CONSTRAINT fk_usersearchprofile_user FOREIGN KEY (userid) REFERENCES userinfo (id);

ALTER TABLE queries ADD PRIMARY KEY (queryid);
ALTER TABLE queries ADD CONSTRAINT fk_queries_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE queries ADD CONSTRAINT fk_queries_searchprofile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
CREATE INDEX queries_searchprofileid ON queries (searchprofileid);
CREATE INDEX queries_query ON queries (query);

ALTER TABLE searchfield ADD CONSTRAINT fk_searchfield_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX searchfield_searchfield ON searchfield (searchfield);

ALTER TABLE livesearch ADD CONSTRAINT fk_livesearch_user FOREIGN KEY (userid) REFERENCES userinfo (id);

ALTER TABLE usercollection ADD PRIMARY KEY (id);
ALTER TABLE usercollection ADD CONSTRAINT fk_usercollection_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX usercollection_dbname ON usercollection (dbname);
CREATE INDEX usercollection_titleid ON usercollection (titleid);

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

ALTER TABLE topic ADD PRIMARY KEY (id);

ALTER TABLE litlist_topic ADD PRIMARY KEY (id);
ALTER TABLE litlist_topic ADD CONSTRAINT fk_litlisttopic_litlist FOREIGN KEY (litlistid) REFERENCES litlist (id);
ALTER TABLE litlist_topic ADD CONSTRAINT fk_litlisttopic_topic FOREIGN KEY (topicid) REFERENCES topic (id);

ALTER TABLE topicclassification ADD CONSTRAINT fk_topicclassification_topic FOREIGN KEY (topicid) REFERENCES topic (id);
CREATE INDEX topicclassification_type ON topicclassification (type);
CREATE INDEX topicclassification_classification ON topicclassification (classification);

ALTER TABLE clusterinfo ADD PRIMARY KEY (id);
ALTER TABLE serverinfo ADD CONSTRAINT fk_serverinfo_clusterinfo FOREIGN KEY (clusterid) REFERENCES clusterinfo (id);
