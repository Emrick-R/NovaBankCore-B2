-- Fichier de donation des droits sur les schémas et les tables
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/05_bank_owner_role.sql
-- Verification :
-- ```
-- SET ROLE analyste_alice;                      -- on devient analyste_alice
-- SELECT count(*) FROM core.accounts;           -- doit marcher
-- SELECT * FROM core.customers LIMIT 1;         -- doit être refusé : permission denied
-- RESET ROLE;                                   -- on redevient postgres
-- ```

-- arrête le fichier à la première erreur, au lieu d'exécuter la suite sur des données incomplètes
\set ON_ERROR_STOP on

-- On donne les droits sur les schémas selon les groupes
-- grp_analyste, grp_support, grp_auditeur, grp_appli
GRANT USAGE ON SCHEMA core TO grp_analyste, grp_support, grp_auditeur, grp_appli;
-- grp_auditeur
GRANT USAGE ON SCHEMA audit TO grp_auditeur;

-- On donne les droits sur les tables selon les groupes
-- grp_analyste
GRANT SELECT ON core.accounts, core.transactions, core.transfers, core.fraud_alerts TO grp_analyste;
-- grp_support
GRANT SELECT ON core.accounts, core.transactions, core.transfers TO grp_support;
-- grp_auditeur
GRANT SELECT ON core.accounts, core.transactions, core.transfers, core.fraud_alerts, audit.audit_log TO grp_auditeur;

-- les futures fonctions et procédures de bank_owner ne seront exécutables par personne par défaut :
-- chaque droit EXECUTE devra être donné explicitement (à grp_appli en E7)
-- Verification : \ddp
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;