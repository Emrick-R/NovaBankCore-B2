-- Fichier de création des rôles par postgres
-- Lancé avec l'user postgres :
-- ```sudo -u postgres psql -d bankdb < ~/SQL/04_postgre_role.sql```
-- Vérifications : ```\du``` ```\drg```

-- arrête le fichier à la première erreur, au lieu d'exécuter la suite sur des données incomplètes
\set ON_ERROR_STOP on

-- On crée les 4 groupes de la db :
CREATE ROLE grp_analyste NOLOGIN;

CREATE ROLE grp_support NOLOGIN;

CREATE ROLE grp_appli NOLOGIN;

CREATE ROLE grp_auditeur NOLOGIN;

-- On crée les 4 utilisateurs de la db :
CREATE ROLE analyste_alice LOGIN IN ROLE grp_analyste;
-- Dans l'invite de commande de psql en tant que postgres, on créer le mdp de analyste_alice:
-- \password analyste_alice

CREATE ROLE support_bob LOGIN IN ROLE grp_support;
-- Dans l'invite de commande de psql en tant que postgres, on créer le mdp de support_bob:
-- \password support_bob

CREATE ROLE app_novabank LOGIN IN ROLE grp_appli;
-- Dans l'invite de commande de psql en tant que postgres, on créer le mdp de app_novabank:
-- \password app_novabank

CREATE ROLE auditeur_chloe LOGIN IN ROLE grp_auditeur;
-- Dans l'invite de commande de psql en tant que postgres, on créer le mdp de auditeur_chloe:
-- \password auditeur_chloe

-- On donne à l'analyste un timeout afin d'éviter la surcharge sur la db
ALTER ROLE analyste_alice SET statement_timeout = 30000; -- 30 sec

-- On enlève la possibilité de se connecter à la db à tous
REVOKE CONNECT ON DATABASE bankdb FROM PUBLIC;
-- On donne l'accès qu'au groupes et à bank_owner
GRANT CONNECT ON DATABASE bankdb TO bank_owner, grp_analyste, grp_support, grp_appli, grp_auditeur;