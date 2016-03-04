CREATE INDEX enrichedcontentisbn_isbn ON enriched_content_by_isbn (isbn);
CREATE INDEX enrichedcontentisbn_origin ON enriched_content_by_isbn (origin);
CREATE INDEX enrichedcontentisbn_field ON enriched_content_by_isbn (field);
CREATE INDEX enrichedcontentisbn_content ON enriched_content_by_isbn (content);

-------------------------------------------------

CREATE INDEX enrichedcontentbibkey_bibkey ON enriched_content_by_bibkey (bibkey);
CREATE INDEX enrichedcontentbibkey_origin ON enriched_content_by_bibkey (origin);
CREATE INDEX enrichedcontentbibkey_field ON enriched_content_by_bibkey (field);
CREATE INDEX enrichedcontentbibkey_content ON enriched_content_by_bibkey (content);

-------------------------------------------------

CREATE INDEX enrichedcontentissn_issn ON enriched_content_by_issn (issn);
CREATE INDEX enrichedcontentissn_origin ON enriched_content_by_issn (origin);
CREATE INDEX enrichedcontentissn_field ON enriched_content_by_issn (field);
CREATE INDEX enrichedcontentissn_content ON enriched_content_by_issn (content);

-------------------------------------------------

CREATE INDEX alltitlesisbn_isbn ON all_titles_by_isbn (isbn);
CREATE INDEX alltitlesisbn_dbname ON all_titles_by_isbn (dbname);
CREATE INDEX alltitlesisbn_location ON all_titles_by_isbn (location);
CREATE INDEX alltitlesisbn_titleid ON all_titles_by_isbn (titleid);

-------------------------------------------------

CREATE INDEX alltitlesissn_issn ON all_titles_by_issn (issn);
CREATE INDEX alltitlesissn_dbname ON all_titles_by_issn (dbname);
CREATE INDEX alltitlesissn_location ON all_titles_by_issn (location);
CREATE INDEX alltitlesissn_titleid ON all_titles_by_issn (titleid);

-------------------------------------------------

CREATE INDEX alltitlesbibkey_bibkey ON all_titles_by_bibkey (bibkey);
CREATE INDEX alltitlesbibkey_dbname ON all_titles_by_bibkey (dbname);
CREATE INDEX alltitlesbibkey_location ON all_titles_by_bibkey (location);
CREATE INDEX alltitlesbibkey_titleid ON all_titles_by_bibkey (titleid);

-------------------------------------------------

ALTER TABLE all_titles_by_workkey ADD PRIMARY KEY (id);
CREATE INDEX alltitlesworkkey_workkey ON all_titles_by_workkey (workkey);
CREATE INDEX alltitlessworkkey_dbname ON all_titles_by_workkey (dbname);
CREATE INDEX alltitlessworkkey_titleid ON all_titles_by_workkey (titleid);
CREATE INDEX alltitlessworkkey_location ON all_titles_by_workkey (location);
CREATE INDEX alltitlessworkkey_edition ON all_titles_by_workkey (edition);

-------------------------------------------------

CREATE INDEX workisbn_isbn ON work_by_isbn (isbn);
CREATE INDEX workisbn_workid ON work_by_isbn (workid);

-------------------------------------------------

CREATE INDEX relatedtitles_isbn ON related_titles_by_isbn (isbn);
CREATE INDEX relatedtitles_id ON related_titles_by_isbn (id);

-------------------------------------------------

CREATE INDEX livesearchdata_fs ON livesearch_data (fs);
CREATE INDEX livesearchdata_dbname ON livesearch_data (dbname);
CREATE INDEX livesearchdata_content ON livesearch_data (content);
