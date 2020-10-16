alter TABLE userinfo add column login_failure BIGINT default 0;
alter TABLE userinfo add column status TEXT;

CREATE INDEX userinfo_status ON userinfo (status);
CREATE INDEX userinfo_login_failure ON userinfo (login_failure);
