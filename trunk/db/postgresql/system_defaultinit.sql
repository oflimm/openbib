/* Standard ist Selbstregistrierung */
insert into logintarget values(1,NULL,NULL,NULL,NULL,'Registrierte E-Mail Adresse','self');

/* Standard sind Rollen Admin und Bibliothekar */
insert into role values (1,'admin');
insert into role values (2,'librarian');

/* Standard ist Admin-User mit ID 1 und Passwort 'StrengGeheim' */
insert into userinfo (id,username,password) values (1,'admin','StrengGeheim');
insert into user_role (userid,roleid) values (1,1);

/* Standard-Profil ist openbib */
insert into profileinfo (id,profilename,description) values (1,'openbib','OpenBib Beispiel-Portal');

/* Standard-View ist openbib */
insert into viewinfo (id,viewname,description,start_loc,servername,profileid,stripuri,active) values (1,'openbib','OpenBib Beispiel-Portal','','',1,'false','true');
