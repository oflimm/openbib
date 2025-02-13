CREATE INDEX datacache_id ON datacache (id);
CREATE INDEX datacache_tstamp ON datacache (tstamp);
CREATE INDEX datacache_subkey ON datacache (subkey);
CREATE INDEX datacache_type ON datacache (type);

ALTER TABLE databaseinfo ADD PRIMARY KEY (id);
ALTER TABLE databaseinfo ADD CONSTRAINT uq_databaseinfo_dbname UNIQUE (dbname);
ALTER TABLE databaseinfo ADD CONSTRAINT fk_databaseinfo_db FOREIGN KEY (parentdbid) REFERENCES databaseinfo (id);
CREATE INDEX databaseinfo_dbname ON databaseinfo (dbname);
CREATE INDEX databaseinfo_active ON databaseinfo (active);
CREATE INDEX databaseinfo_description ON databaseinfo (description);
CREATE INDEX databaseinfo_locationid ON databaseinfo (locationid);
CREATE INDEX databaseinfo_schema ON databaseinfo (schema);

ALTER TABLE databaseinfo_searchengine ADD CONSTRAINT fk_databaseinfo_searchengine_database FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX databaseinfo_searchengine_database ON databaseinfo_searchengine (dbid);


ALTER TABLE locationinfo ADD PRIMARY KEY (id);
CREATE INDEX locationinfo_tstamp_create on locationinfo (tstamp_create);
CREATE INDEX locationinfo_tstamp_update on locationinfo (tstamp_update);
CREATE INDEX locationinfo_identifier ON locationinfo (identifier);
CREATE INDEX locationinfo_type ON locationinfo (type);
ALTER TABLE databaseinfo ADD CONSTRAINT fk_locationinfo FOREIGN KEY (locationid) REFERENCES locationinfo (id);
ALTER TABLE locationinfo ADD CONSTRAINT uq_locationinfo_identifier UNIQUE (identifier);

ALTER TABLE locationinfo_fields ADD CONSTRAINT fk_locationinfo_fields FOREIGN KEY (locationid) REFERENCES locationinfo (id);
CREATE INDEX locationinfo_fields_locationid ON locationinfo_fields (locationid);
CREATE INDEX locationinfo_fields_field ON locationinfo_fields (field);
CREATE INDEX locationinfo_fields_subfield ON locationinfo_fields (subfield);
CREATE INDEX locationinfo_fields_mult ON locationinfo_fields (mult);
CREATE INDEX locationinfo_fields_content ON locationinfo_fields (content);

ALTER TABLE locationinfo_occupancy ADD CONSTRAINT fk_locationinfo_occupancy FOREIGN KEY (locationid) REFERENCES locationinfo (id);
CREATE INDEX locationinfo_occupancy_locationid ON locationinfo_occupancy (locationid);
CREATE INDEX locationinfo_occupancy_tstamp ON locationinfo_occupancy (tstamp);

ALTER TABLE rssinfo ADD PRIMARY KEY (id);
ALTER TABLE rssinfo ADD CONSTRAINT fk_rssinfo_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX rssinfo_type ON rssinfo (type);
CREATE INDEX rssinfo_dbid ON rssinfo (dbid);

ALTER TABLE rsscache ADD PRIMARY KEY (pid);
CREATE INDEX rsscache_rssinfo ON rsscache (rssinfoid);
ALTER TABLE rsscache ADD CONSTRAINT fk_rsscache_rssinfo FOREIGN KEY (rssinfoid) REFERENCES rssinfo (id);
CREATE INDEX rsscache_tstamp ON rsscache (tstamp);

ALTER TABLE profileinfo ADD PRIMARY KEY (id);
ALTER TABLE profileinfo ADD CONSTRAINT uq_profileinfo_profilename UNIQUE (profilename);
CREATE INDEX profileinfo_profilename ON profileinfo (profilename);

ALTER TABLE orgunitinfo ADD PRIMARY KEY (id);
ALTER TABLE orgunitinfo ADD CONSTRAINT fk_orgunitinfo_profile FOREIGN KEY (profileid) REFERENCES profileinfo (id);
CREATE INDEX orgunitinfo_orgunitname ON orgunitinfo (orgunitname);
CREATE INDEX orgunitinfo_profileid ON orgunitinfo (profileid);
CREATE INDEX orgunitinfo_nr ON orgunitinfo (nr);
CREATE INDEX orgunitinfo_own_index ON orgunitinfo (own_index);

ALTER TABLE orgunit_db ADD CONSTRAINT fk_orgunitdb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
ALTER TABLE orgunit_db ADD CONSTRAINT fk_orgunitdb_orgunit FOREIGN KEY (orgunitid) REFERENCES orgunitinfo (id);
CREATE INDEX orgunit_db_dbid ON orgunit_db (dbid);
CREATE INDEX orgunit_db_orgunitid ON orgunit_db (orgunitid);


ALTER TABLE viewinfo ADD PRIMARY KEY (id);
ALTER TABLE viewinfo ADD CONSTRAINT uq_viewinfo_viewname UNIQUE (viewname);
ALTER TABLE viewinfo ADD CONSTRAINT fk_viewinfo_profile FOREIGN KEY (profileid) REFERENCES profileinfo (id);
ALTER TABLE viewinfo ADD CONSTRAINT fk_viewinfo_rss FOREIGN KEY (rssid) REFERENCES rssinfo (id);
CREATE INDEX viewinfo_viewname ON viewinfo (viewname);
CREATE INDEX viewinfo_profileid ON viewinfo (profileid);
CREATE INDEX viewinfo_rssid ON viewinfo (rssid);
CREATE INDEX viewinfo_own_index ON viewinfo (own_index);

ALTER TABLE view_db ADD CONSTRAINT fk_viewdb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
ALTER TABLE view_db ADD CONSTRAINT fk_viewdb_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX view_db_dbid ON view_db (dbid);
CREATE INDEX view_db_viewid ON view_db (viewid);


ALTER TABLE view_rss ADD PRIMARY KEY (id);
ALTER TABLE view_rss ADD CONSTRAINT fk_viewrss_rss FOREIGN KEY (rssid) REFERENCES rssinfo (id);
ALTER TABLE view_rss ADD CONSTRAINT fk_viewrss_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX view_rss_rssid ON view_rss (rssid);
CREATE INDEX view_rss_viewid ON view_rss (viewid);

ALTER TABLE view_location ADD PRIMARY KEY (id);
ALTER TABLE view_location ADD CONSTRAINT fk_viewlocation_location FOREIGN KEY (locationid) REFERENCES locationinfo (id);
ALTER TABLE view_location ADD CONSTRAINT fk_viewlocation_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX view_location_locationid ON view_location (locationid);
CREATE INDEX view_location_viewid ON view_location (viewid);

ALTER TABLE clusterinfo ADD PRIMARY KEY (id);
CREATE INDEX clusterinfo_active ON clusterinfo (active);

ALTER TABLE serverinfo ADD PRIMARY KEY (id);
CREATE INDEX serverinfo_active ON serverinfo (active);
ALTER TABLE serverinfo ADD CONSTRAINT fk_serverinfo_clusterinfo FOREIGN KEY (clusterid) REFERENCES clusterinfo (id);
CREATE INDEX serverinfo_clusterid ON serverinfo (clusterid);

ALTER TABLE updatelog ADD PRIMARY KEY (id);
CREATE INDEX updatelog_database ON updatelog (dbid);
CREATE INDEX updatelog_server ON updatelog (serverid);
CREATE INDEX updatelog_start ON updatelog (tstamp_start);
ALTER TABLE updatelog ADD CONSTRAINT fk_updatelog_serverinfo FOREIGN KEY (serverid) REFERENCES serverinfo (id);
ALTER TABLE updatelog ADD CONSTRAINT fk_updatelog_databaseinfo FOREIGN KEY (dbid) REFERENCES databaseinfo (id);

ALTER TABLE sessioninfo ADD PRIMARY KEY (id);
CREATE INDEX sessioninfo_sessionid ON sessioninfo (sessionid);
CREATE INDEX sessioninfo_createtime ON sessioninfo (createtime);
CREATE INDEX sessioninfo_expiretime ON sessioninfo (expiretime);
CREATE INDEX sessioninfo_username ON sessioninfo (username);
CREATE INDEX sessioninfo_viewname ON sessioninfo (viewname);
CREATE INDEX sessioninfo_network ON sessioninfo USING gist (network inet_ops);

ALTER TABLE cartitem ADD PRIMARY KEY (id);
CREATE INDEX cartitem_dbname ON cartitem (dbname);
CREATE INDEX cartitem_titleid ON cartitem (titleid);
CREATE INDEX cartitem_tstamp ON cartitem (tstamp);

ALTER TABLE session_cartitem ADD CONSTRAINT fk_sessioncartitem_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE session_cartitem ADD CONSTRAINT fk_sessioncartitem_cartitem FOREIGN KEY (cartitemid) REFERENCES cartitem (id);
CREATE INDEX sessioncartitem_sid ON session_cartitem (sid);
CREATE INDEX sessioncartitem_cartitemid ON session_cartitem (cartitemid);

ALTER TABLE recordhistory ADD CONSTRAINT fk_recordhistory_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX recordhistory_sid ON recordhistory (sid);

ALTER TABLE eventlog ADD CONSTRAINT fk_eventlog_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlog_tstamp ON eventlog (tstamp);
CREATE INDEX eventlog_type ON eventlog (type);
CREATE INDEX eventlog_content ON eventlog (content);
CREATE INDEX eventlog_sid ON eventlog (sid);

ALTER TABLE eventlogjson ADD CONSTRAINT fk_eventlogjson_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX eventlogjson_tstamp ON eventlogjson (tstamp);
CREATE INDEX eventlogjson_type ON eventlogjson (type);
CREATE INDEX eventlogjson_sid ON eventlogjson (sid);

ALTER TABLE searchhistory ADD CONSTRAINT fk_searchhistory_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX searchhistory_dbname ON searchhistory (dbname);
CREATE INDEX searchhistory_queryid ON searchhistory (queryid);
CREATE INDEX searchhistory_sid ON searchhistory (sid);

ALTER TABLE userinfo ADD PRIMARY KEY (id);
ALTER TABLE userinfo ADD CONSTRAINT uq_userinfo_username UNIQUE (username,viewid,authenticatorid);
ALTER TABLE userinfo ADD CONSTRAINT fk_userinfo_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
ALTER TABLE userinfo ADD CONSTRAINT fk_userinfo_location FOREIGN KEY (locationid) REFERENCES locationinfo (id);
ALTER TABLE userinfo ADD CONSTRAINT fk_userinfo_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticatorinfo (id);
CREATE INDEX userinfo_username ON userinfo (username);
CREATE INDEX userinfo_nachname ON userinfo (nachname);
CREATE INDEX userinfo_vorname ON userinfo (vorname);
CREATE INDEX userinfo_password ON userinfo (password);
CREATE INDEX userinfo_status ON userinfo (status);
CREATE INDEX userinfo_login_failure ON userinfo (login_failure);

ALTER TABLE user_searchlocation ADD PRIMARY KEY (id);
ALTER TABLE user_searchlocation ADD CONSTRAINT fk_usersearchlocation_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_searchlocation ADD CONSTRAINT fk_usersearchlocation_location FOREIGN KEY (locationid) REFERENCES locationinfo (id);
CREATE INDEX usersearchlocation_userid ON user_searchlocation (userid);
CREATE INDEX usersearchlocation_searchlocationid ON user_searchlocation (locationid);

ALTER TABLE roleinfo ADD PRIMARY KEY (id);

ALTER TABLE role_view ADD PRIMARY KEY (id);
ALTER TABLE role_view ADD CONSTRAINT fk_roleview_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
ALTER TABLE role_view ADD CONSTRAINT fk_roleview_role FOREIGN KEY (roleid) REFERENCES roleinfo (id);
CREATE INDEX role_view_viewid ON role_view (viewid);
CREATE INDEX role_view_roleid ON role_view (roleid);

ALTER TABLE role_right ADD PRIMARY KEY (id);
ALTER TABLE role_right ADD CONSTRAINT fk_roleright_role FOREIGN KEY (roleid) REFERENCES roleinfo (id);
CREATE INDEX role_right_roleid ON role_right (roleid);

ALTER TABLE role_viewadmin ADD PRIMARY KEY (id);
ALTER TABLE role_viewadmin ADD CONSTRAINT fk_roleviewadmin_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
ALTER TABLE role_viewadmin ADD CONSTRAINT fk_roleviewadmin_role FOREIGN KEY (roleid) REFERENCES roleinfo (id);
CREATE INDEX role_viewadmin_viewid ON role_viewadmin (viewid);
CREATE INDEX role_viewadmin_roleid ON role_viewadmin (roleid);

ALTER TABLE user_role ADD PRIMARY KEY (id);
ALTER TABLE user_role ADD CONSTRAINT fk_userrole_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_role ADD CONSTRAINT fk_userrole_role FOREIGN KEY (roleid) REFERENCES roleinfo (id);
CREATE INDEX user_role_userid ON user_role (userid);
CREATE INDEX user_role_roleid ON user_role (roleid);

ALTER TABLE templateinfo ADD PRIMARY KEY (id);
ALTER TABLE templateinfo ADD CONSTRAINT fk_templateinfo_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX templateinfo_templatename ON templateinfo (templatename);
CREATE INDEX templateinfo_viewid ON templateinfo (viewid);
CREATE INDEX templateinfo_templatelang ON templateinfo (templatelang);

ALTER TABLE templateinforevision ADD PRIMARY KEY (id);
ALTER TABLE templateinforevision ADD CONSTRAINT fk_templateinforevision_templateinfo FOREIGN KEY (templateid) REFERENCES templateinfo (id);
CREATE INDEX templateinforevision_templateid ON templateinforevision (templateid);
CREATE INDEX templateinforevision_tstamp ON templateinforevision (templateid);

ALTER TABLE user_template ADD PRIMARY KEY (id);
ALTER TABLE user_template ADD CONSTRAINT fk_user_template_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_template ADD CONSTRAINT fk_user_template_template FOREIGN KEY (templateid) REFERENCES templateinfo (id);
CREATE INDEX user_template_userid ON user_template (userid);
CREATE INDEX user_template_templateid ON user_template (templateid);

ALTER TABLE user_db ADD PRIMARY KEY (id);
ALTER TABLE user_db ADD CONSTRAINT fk_userdb_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_db ADD CONSTRAINT fk_userdb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX user_db_userid ON user_db (userid);
CREATE INDEX user_db_dbid ON user_db (dbid);

ALTER TABLE registration ADD PRIMARY KEY (id);

ALTER TABLE authtoken ADD PRIMARY KEY (id);
ALTER TABLE authtoken ADD CONSTRAINT fk_authtoken_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX authtoken_authkey ON authtoken (authkey);
CREATE INDEX authtoken_type ON authtoken (type);
CREATE INDEX authtoken_tstamp ON authtoken (tstamp);

ALTER TABLE authenticatorinfo ADD PRIMARY KEY (id);
CREATE INDEX authenticatorinfo_name ON authenticatorinfo (name);
CREATE INDEX authenticatorinfo_type ON authenticatorinfo (type);

ALTER TABLE authenticator_view ADD PRIMARY KEY (id);
ALTER TABLE authenticator_view ADD CONSTRAINT fk_authenticatorview_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
ALTER TABLE authenticator_view ADD CONSTRAINT fk_authenticatorview_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticatorinfo (id);
CREATE INDEX authenticator_view_viewid ON authenticator_view (viewid);
CREATE INDEX authenticator_view_authenticatorid ON authenticator_view (authenticatorid);

ALTER TABLE user_session ADD PRIMARY KEY (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticatorinfo (id);
CREATE INDEX user_session_userid ON user_session (userid);
CREATE INDEX user_session_sid ON user_session (sid);
CREATE INDEX user_session_authenticatorid ON user_session (authenticatorid);

ALTER TABLE searchprofile ADD PRIMARY KEY (id);
CREATE INDEX searchprofile_dbases_as_json ON searchprofile (databases_as_json);

ALTER TABLE searchprofile_db ADD CONSTRAINT fk_searchprofiledb_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE searchprofile_db ADD CONSTRAINT fk_searchprofiledb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX searchprofile_db_searchprofileid ON searchprofile_db (searchprofileid);
CREATE INDEX searchprofile_db_dbid ON searchprofile_db (dbid);

ALTER TABLE session_searchprofile ADD CONSTRAINT fk_sessionsearchprofile_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE session_searchprofile ADD CONSTRAINT fk_sessionsearchprofile_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
CREATE INDEX session_searchprofile_searchprofileid ON session_searchprofile (searchprofileid);
CREATE INDEX session_searchprofile_sid ON session_searchprofile (sid);

ALTER TABLE user_searchprofile ADD PRIMARY KEY (id);
ALTER TABLE user_searchprofile ADD CONSTRAINT fk_usersearchprofile_profile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
ALTER TABLE user_searchprofile ADD CONSTRAINT fk_usersearchprofile_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX user_searchprofile_searchprofileid ON user_searchprofile (searchprofileid);
CREATE INDEX user_searchprofile_userid ON user_searchprofile (userid);

ALTER TABLE queries ADD PRIMARY KEY (queryid);
ALTER TABLE queries ADD CONSTRAINT fk_queries_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE queries ADD CONSTRAINT fk_queries_searchprofile FOREIGN KEY (searchprofileid) REFERENCES searchprofile (id);
CREATE INDEX queries_searchprofileid ON queries (searchprofileid);
CREATE INDEX queries_sid ON queries (sid);
CREATE INDEX queries_query ON queries (query);

ALTER TABLE searchfield ADD CONSTRAINT fk_searchfield_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX searchfield_searchfield ON searchfield (searchfield);
CREATE INDEX searchfield_userid ON searchfield (userid);

ALTER TABLE livesearch ADD CONSTRAINT fk_livesearch_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX livesearch_userid ON livesearch (userid);

ALTER TABLE user_cartitem ADD CONSTRAINT fk_usercartitem_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_cartitem ADD CONSTRAINT fk_usercartitem_cartitem FOREIGN KEY (cartitemid) REFERENCES cartitem (id);
CREATE INDEX usercartitem_userid ON user_cartitem (userid);
CREATE INDEX usercartitem_cartitemid ON user_cartitem (cartitemid);

ALTER TABLE tag ADD PRIMARY KEY (id);
CREATE INDEX tag_name ON tag (name);

ALTER TABLE tit_tag ADD PRIMARY KEY (id);
ALTER TABLE tit_tag ADD CONSTRAINT fk_tittag_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE tit_tag ADD CONSTRAINT fk_tittag_tag FOREIGN KEY (tagid) REFERENCES tag (id);
CREATE INDEX tittag_titleid ON tit_tag (titleid);
CREATE INDEX tittag_userid ON tit_tag (userid);
CREATE INDEX tittag_tagid ON tit_tag (tagid);
CREATE INDEX tittag_dbname ON tit_tag (dbname);
CREATE INDEX tittag_type ON tit_tag (type);
CREATE INDEX tittag_srt_person ON tit_tag (srt_person);
CREATE INDEX tittag_srt_title ON tit_tag (srt_title);
CREATE INDEX tittag_srt_year ON tit_tag (srt_year);
CREATE INDEX tittag_tstamp ON tit_tag (tstamp);

ALTER TABLE review ADD PRIMARY KEY (id);
ALTER TABLE review ADD CONSTRAINT fk_review_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX review_titleid ON review (titleid);
CREATE INDEX review_userid ON review (userid);
CREATE INDEX review_dbname ON review (dbname);
CREATE INDEX review_titleisbn ON review (titleisbn);

ALTER TABLE reviewrating ADD PRIMARY KEY (id);
ALTER TABLE reviewrating ADD CONSTRAINT fk_reviewrating_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE reviewrating ADD CONSTRAINT fk_reviewrating_review FOREIGN KEY (reviewid) REFERENCES review (id);
CREATE INDEX reviewrating_userid ON reviewrating (userid);
CREATE INDEX reviewrating_reviewid ON reviewrating (reviewid);

ALTER TABLE litlist ADD PRIMARY KEY (id);
ALTER TABLE litlist ADD CONSTRAINT fk_litlist_user FOREIGN KEY (userid) REFERENCES userinfo (id);
CREATE INDEX litlist_title ON litlist (title);
CREATE INDEX litlist_userid ON litlist (userid);
CREATE INDEX litlist_type ON litlist (type);

ALTER TABLE litlistitem ADD PRIMARY KEY (id);
ALTER TABLE litlistitem ADD CONSTRAINT fk_litlistitem_litlist FOREIGN KEY (litlistid) REFERENCES litlist (id);
CREATE INDEX litlistitem_litlistid ON litlistitem (litlistid);
CREATE INDEX litlistitem_dbname ON litlistitem (dbname);
CREATE INDEX litlistitem_titleid ON litlistitem (titleid);
CREATE INDEX litlistitem_titleisbn ON litlistitem (titleisbn);

ALTER TABLE topic ADD PRIMARY KEY (id);

ALTER TABLE litlist_topic ADD PRIMARY KEY (id);
ALTER TABLE litlist_topic ADD CONSTRAINT fk_litlisttopic_litlist FOREIGN KEY (litlistid) REFERENCES litlist (id);
ALTER TABLE litlist_topic ADD CONSTRAINT fk_litlisttopic_topic FOREIGN KEY (topicid) REFERENCES topic (id);
CREATE INDEX litlist_topic_litlistid ON litlist_topic (litlistid);
CREATE INDEX litlist_topic_topicid ON litlist_topic (topicid);

ALTER TABLE topicclassification ADD CONSTRAINT fk_topicclassification_topic FOREIGN KEY (topicid) REFERENCES topic (id);
CREATE INDEX topicclassification_topicid ON topicclassification (topicid);
CREATE INDEX topicclassification_type ON topicclassification (type);
CREATE INDEX topicclassification_classification ON topicclassification (classification);

ALTER TABLE dbrtopic ADD PRIMARY KEY (id);
CREATE INDEX dbrtopic_topic ON dbrtopic (topic);

ALTER TABLE dbistopic ADD PRIMARY KEY (id);
CREATE INDEX dbistopic_topic ON dbistopic (topic);

ALTER TABLE dbisdb ADD PRIMARY KEY (id);

ALTER TABLE dbrtopic_dbistopic ADD PRIMARY KEY (id);
ALTER TABLE dbrtopic_dbistopic ADD CONSTRAINT fk_dbrtopicdbistopic_dbrtopic FOREIGN KEY (dbrtopicid) REFERENCES dbrtopic (id);
ALTER TABLE dbrtopic_dbistopic ADD CONSTRAINT fk_dbrtopicdbistopic_dbistopic FOREIGN KEY (dbistopicid) REFERENCES dbistopic (id);
CREATE INDEX dbrtopicdbistopic_dbistopic ON dbrtopic_dbistopic (dbistopicid);
CREATE INDEX dbrtopicdbistopic_dbrtopic ON dbrtopic_dbistopic (dbrtopicid);

ALTER TABLE dbistopic_dbisdb ADD PRIMARY KEY (id);
ALTER TABLE dbistopic_dbisdb ADD CONSTRAINT fk_dbistopic_dbisdb_dbistopic FOREIGN KEY (dbistopicid) REFERENCES dbistopic (id);
ALTER TABLE dbistopic_dbisdb ADD CONSTRAINT fk_dbistopic_dbisdb_dbisdb FOREIGN KEY (dbisdbid) REFERENCES dbisdb (id);
CREATE INDEX dbistopicdbisdb_dbistopic ON dbistopic_dbisdb (dbistopicid);
CREATE INDEX dbistopicdbisdb_dbisdb ON dbistopic_dbisdb (dbisdbid);

ALTER TABLE paia ADD PRIMARY KEY (id);
CREATE INDEX paia_username ON paia (username);
CREATE INDEX paia_token ON paia (token);
CREATE INDEX paia_tstamp ON paia (tstamp);

ALTER TABLE paia ALTER COLUMN tstamp SET DEFAULT now();

ALTER TABLE classifications ADD PRIMARY KEY (id);
CREATE INDEX classifications_type ON classifications (type);
CREATE INDEX classifications_name ON classifications (name);

ALTER TABLE classificationshierarchy ADD PRIMARY KEY (id);
CREATE INDEX classificationshierarchy_type ON classificationshierarchy (type);
CREATE INDEX classificationshierarchy_name ON classificationshierarchy (name);
CREATE INDEX classificationshierarchy_number ON classificationshierarchy (number);
CREATE INDEX classificationshierarchy_subname ON classificationshierarchy (subname);	

ALTER TABLE networkinfo ADD PRIMARY KEY (id);
CREATE index networkinfo_network ON networkinfo USING gist (network inet_ops);
