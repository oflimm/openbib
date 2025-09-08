alter TABLE authenticatorinfo add column mfa TEXT;
update authenticatorinfo set mfa = 'none';

alter TABLE userinfo add column mfa_token TEXT;
