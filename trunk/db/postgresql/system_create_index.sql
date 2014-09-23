CREATE EXTENSION pgcrypto;

ALTER TABLE databaseinfo ADD PRIMARY KEY (id);
ALTER TABLE databaseinfo ADD CONSTRAINT uq_databaseinfo_dbname UNIQUE (dbname);
CREATE INDEX databaseinfo_dbname ON databaseinfo (dbname);
CREATE INDEX databaseinfo_active ON databaseinfo (active);
CREATE INDEX databaseinfo_description ON databaseinfo (description);
CREATE INDEX databaseinfo_locationid ON databaseinfo (locationid);

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

ALTER TABLE rssinfo ADD PRIMARY KEY (id);
ALTER TABLE rssinfo ADD CONSTRAINT fk_rssinfo_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX rssinfo_type ON rssinfo (type);
CREATE INDEX rssinfo_dbid ON rssinfo (dbid);

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

ALTER TABLE view_db ADD CONSTRAINT fk_viewdb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
ALTER TABLE view_db ADD CONSTRAINT fk_viewdb_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX view_db_dbid ON view_db (dbid);
CREATE INDEX view_db_viewid ON view_db (viewid);


ALTER TABLE view_rss ADD CONSTRAINT fk_viewrss_rss FOREIGN KEY (rssid) REFERENCES rssinfo (id);
ALTER TABLE view_rss ADD CONSTRAINT fk_viewrss_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX view_rss_rssid ON view_rss (rssid);
CREATE INDEX view_rss_viewid ON view_rss (viewid);

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
CREATE INDEX sessioninfo_username ON sessioninfo (username);
CREATE INDEX sessioninfo_viewname ON sessioninfo (viewname);

ALTER TABLE cartitem ADD PRIMARY KEY (id);
CREATE INDEX cartitem_dbname ON cartitem (dbname);
CREATE INDEX cartitem_titleid ON cartitem (titleid);

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
ALTER TABLE userinfo ADD CONSTRAINT uq_userinfo_username UNIQUE (username);
CREATE INDEX userinfo_nachname ON userinfo (nachname);
CREATE INDEX userinfo_vorname ON userinfo (vorname);
CREATE INDEX userinfo_password ON userinfo (password);

ALTER TABLE role ADD PRIMARY KEY (id);

ALTER TABLE user_role ADD PRIMARY KEY (id);
ALTER TABLE user_role ADD CONSTRAINT fk_userrole_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_role ADD CONSTRAINT fk_userrole_role FOREIGN KEY (roleid) REFERENCES role (id);
CREATE INDEX user_role_userid ON user_role (userid);
CREATE INDEX user_role_roleid ON user_role (roleid);

ALTER TABLE templateinfo ADD PRIMARY KEY (id);
ALTER TABLE templateinfo ADD CONSTRAINT fk_templateinfo_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX templateinfo_templatename ON templateinfo (templatename);
CREATE INDEX templateinfo_viewid ON templateinfo (viewid);

ALTER TABLE templateinforevision ADD PRIMARY KEY (id);
ALTER TABLE templateinforevision ADD CONSTRAINT fk_templateinforevision_templateinfo FOREIGN KEY (templateid) REFERENCES templateinfo (id);
CREATE INDEX templateinforevision_templateid ON templateinforevision (templateid);
CREATE INDEX templateinforevision_tstamp ON templateinforevision (templateid);

ALTER TABLE user_templateinfo ADD PRIMARY KEY (id);
ALTER TABLE user_templateinfo ADD CONSTRAINT fk_templateinfo_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_templateinfo ADD CONSTRAINT fk_templateinfo_templateinfo FOREIGN KEY (templateid) REFERENCES templateinfo (id);
CREATE INDEX user_templateinfo_userid ON user_templateinfo (userid);
CREATE INDEX user_templateinfo_templateid ON user_templateinfo (templateid);

ALTER TABLE user_view ADD PRIMARY KEY (id);
ALTER TABLE user_view ADD CONSTRAINT fk_userview_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_view ADD CONSTRAINT fk_userview_view FOREIGN KEY (viewid) REFERENCES viewinfo (id);
CREATE INDEX user_view_userid ON user_view (userid);
CREATE INDEX user_view_viewid ON user_view (viewid);

ALTER TABLE user_db ADD PRIMARY KEY (id);
ALTER TABLE user_db ADD CONSTRAINT fk_userdb_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_db ADD CONSTRAINT fk_userdb_db FOREIGN KEY (dbid) REFERENCES databaseinfo (id);
CREATE INDEX user_db_userid ON user_db (userid);
CREATE INDEX user_db_dbid ON user_db (dbid);

ALTER TABLE registration ADD PRIMARY KEY (id);

ALTER TABLE authenticator ADD PRIMARY KEY (id);

ALTER TABLE user_session ADD PRIMARY KEY (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_user FOREIGN KEY (userid) REFERENCES userinfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_session FOREIGN KEY (sid) REFERENCES sessioninfo (id);
ALTER TABLE user_session ADD CONSTRAINT fk_usersession_authenticator FOREIGN KEY (authenticatorid) REFERENCES authenticator (id);
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

