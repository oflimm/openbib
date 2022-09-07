/* Ausweise beginnend mit A sind Studenten und erhalten die Rolle student (intern: roleid=11) */
insert into user_role (userid,roleid) select id,11 from userinfo where username ~ '^A[0-9]+#' and id not in (select userid from user_role where roleid=11);

/* Ausweise beginnend mit B sind Mitarbeiter der UzK und erhalten die Rolle uzk (intern: roleid=10) */
insert into user_role (userid,roleid) select id,10 from userinfo where username ~ '^B[0-9]+#' and id not in (select userid from user_role where roleid=10);

/* Ausweise beginnend mit C sind Benutzer der Stadt und erhalten die Rolle stadt (intern: roleid=13) */
insert into user_role (userid,roleid) select id,13 from userinfo where username ~ '^C[0-9]+#' and id not in (select userid from user_role where roleid=13);
