/* Standard ist Selbstregistrierung */
insert into authenticatorinfo values(1,'selfreg','Registrierte E-Mail Adresse','self');

/* Standard sind Rollen Admin und Bibliothekar */
insert into roleinfo values (1,'admin','Administrator');
insert into roleinfo values (2,'librarian','Bibliothekar');
insert into roleinfo values (3,'viewadmin','Portal-Administrator');

/* Standard ist Admin-User mit ID 1 und Passwort 'top_secret' */
insert into userinfo (id,username,password,authenticatorid) values (1,'admin',crypt('top_secret', gen_salt('bf', 4)),1);
insert into user_role (userid,roleid) values (1,1);

/* Standard-Profil ist openbib */
insert into profileinfo (id,profilename,description) values (1,'unikatalog','Universitätskatalog');

/* Standard-View ist openbib */
insert into viewinfo (id,viewname,description,start_loc,servername,profileid,stripuri,active) values (1,'openbib','OpenBib Beispiel-Portal','','',1,'false','true');
insert into authenticator_view (viewid,authenticatorid) values (1,1);

/* elib Datenbank Recommender */
insert into dbrtopic (id,topic,description) values
(1, 'agr', 'Land- und Forstwirtschaft, Gartenbau, Fischereiwirtschaft, Hauswi'),
(2, 'etn', 'Ethnologie (Volks- und Völkerkunde) '),
(3, 'vol', 'Ethnologie (Volks- und Völkerkunde) '),
(4, 'kun', 'Architektur, Bauingenieur- und Vermessungswesen, Kunstgeschichte'),
(5, 'kla', 'Klassische Philologie, Theologie und Religionswissenschaft'),
(6, 'phi', 'Philosophie'),
(7, 'the', 'Theologie und Religionswissenschaft'),
(8, 'asl', 'Allgemeine und vergleichende Sprach- und Literaturwissenschaft'),
(9, 'ssl', 'Allgemeine und vergleichende Sprach- und Literaturwissenschaft'),
(10, 'oze', '?'),
(11, 'puz', 'Medien- und Kommunikationswissenschaften, Publizistik, Film- und '),
(12, 'ger', 'Germanistik, Niederländische Philologie, Skandinavistik'),
(13, 'ang', 'Anglistik, Amerikanistik'),
(14, 'rom', 'Romanistik'),
(15, 'ska', 'Germanistik, Niederländische Philologie, Skandinavistik'),
(16, 'bio', 'Biologie'),
(17, 'spo', 'Sport'),
(18, 'vwl', 'Wirtschaftswissenschaften'),
(19, 'bwl', 'Wirtschaftswissenschaften'),
(20, 'ver', 'Wirtschaftswissenschaften'),
(21, 'sow', 'Wissenschaftskunde, Forschungs-, Hochschul-, Museumswesen'),
(22, 'soz', 'Soziologie'),
(23, 'kli', 'Medizin'),
(24, 'pae', 'Pädagogik'),
(25, 'ggr', 'Geographie'),
(26, 'geo', 'Geowissenschaften'),
(27, 'hil', 'Geschichte'),
(28, 'his', 'Geschichte'),
(29, 'hit', 'Geschichte'),
(30, 'inf', 'Informatik'),
(31, 'ing', 'Technik allgemein, Maschinenwesen, Werkstoffwissenschaften, Ferti'),
(32, 'phy', 'Physik'),
(33, 'elt', 'Elektrotechnik, Mess- und Regelungstechnik'),
(34, 'jur', 'Rechtswissenschaft'),
(35, 'bub', 'Informations-, Buch- und Bibliothekswesen, Handschriftenkunde'),
(36, 'med', 'Medizin'),
(37, 'sla', 'Slavistik'),
(38, 'all', 'Allgemein / Fachübergreifend'),
(39, 'pub', '?'),
(40, 'pol', 'Politologie'),
(41, 'psy', 'Psychologie'),
(42, 'mus', 'Musikwissenschaft'),
(43, 'not', '?'),
(44, 'che', 'Chemie'),
(45, 'bot', 'Botanik'),
(46, 'hbi', 'Verfahrenstechnik, Biotechnologie, Lebensmitteltechnologie'),
(47, 'mat', 'Mathematik'),
(48, 'bcp', 'Verfahrenstechnik, Biotechnologie, Lebensmitteltechnologie'),
(49, 'nat', 'Energie, Umweltschutz, Kerntechnik'),
(50, 'rel', '?'),
(51, 'arc', 'Archäologie'),
(52, 'swl', 'Wirtschaftszweiglehren');

insert into dbistopic (id,topic,description) values 
(1,'OR','Orientalistik und sonstige Sprachen'),
(2,'1','Physik'),
(3,'2','Mathematik'),
(4,'3','Chemie'),
(5,'5','Biologie'),
(6,'6','Geographie'),
(7,'7','Geowissenschaften'),
(8,'9','Klassische Philologie'),
(9,'10','Romanistik'),
(10,'11','Germanistik, Niederl&auml;ndische Philologie, Skandinavistik'),
(11,'12','Anglistik, Amerikanistik'),
(12,'13','Allgemeine und vergleichende Sprach- und Literaturwissenschaft'),
(13,'15','Rechtswissenschaft'),
(14,'16','Wirtschaftswissenschaften'),
(15,'17','Politologie'),
(16,'18','Soziologie'),
(17,'19','Theologie und Religionswissenschaft'),
(18,'21','Philosophie'),
(19,'22','Psychologie'),
(20,'23','P&auml;dagogik'),
(21,'24','Kunstgeschichte'),
(22,'25','Musikwissenschaft'),
(23,'26','Geschichte'),
(24,'27','Arch&auml;ologie'),
(25,'28','Allgemein / Fach&uuml;bergreifend'),
(26,'29','Ethnologie (Volks- und V&ouml;lkerkunde)'),
(27,'30','Informatik'),
(28,'44','Technik allgemein'),
(29,'50','Naturwissenschaft allgemein'),
(30,'51','Slavistik'),
(31,'53','Medien- und Kommunikationswissenschaften, Publizistik, Film- und Theaterwissenschaft'),
(32,'54','Informations-, Buch- und Bibliothekswesen, Handschriftenkunde'),
(33,'55','Wissenschaftskunde, Forschungs-, Hochschul-, Museumswesen');

insert into dbrtopic_dbistopic (dbrtopicid,dbistopicid) values
(2,26),
(3,26),
(5,17),
(5,8),
(6,18),
(7,17),
(8,12),
(9,12),
(11,31),
(12,10),
(13,11),
(14,9),
(15,10),
(16, 5),
(18, 14),
(19, 14),
(20, 14),
(21, 33),
(22, 16),
(24, 20),
(25, 6),
(26, 7),
(27, 23),
(28, 23),
(29, 23),
(30, 27),
(31, 28),
(32, 2),
(34, 13),
(35, 32),
(37, 30),
(38, 25),
(40, 15),
(41, 19),
(42, 22),
(44, 4),
(45, 5),
(47, 3),
(51, 24),
(52, 14);

