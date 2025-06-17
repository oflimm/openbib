alter TABLE all_titles_by_isbn add column id BIGSERIAL;

ALTER TABLE all_titles_by_isbn ADD PRIMARY KEY (id);

