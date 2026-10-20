-- Fichier de tests : pour chaque règle, un test qui réussit et un test qui doit échouer
-- Lancé avec postgres : sudo -u postgres psql -d bankdb < ~/SQL/tests/tests.sql
-- Les tests qui modifient la base sont dans un BEGIN … ROLLBACK : rien n'est conservé
-- Vérifications :
sudo -u postgres psql -d bankdb < ~/SQL/tests/tests.sql > ~/resultats_tests.txt 2>&1
grep -c 'RESULTAT: OK' ~/resultats_tests.txt
grep -c 'RESULTAT: KO' ~/resultats_tests.txt
-- grep 'ERROR' ~/resultats_tests.txt

-- Nb Test : 57

-- continue après une erreur : les échecs attendus ne doivent pas arrêter le fichier
\set ON_ERROR_STOP off

-- modèle pour un test qui doit RÉUSSIR : une erreur = KO
-- BEGIN;
-- <la commande testée>;
-- \if :ERROR
-- \echo 'RESULTAT: KO'
-- \else
-- \echo 'RESULTAT: OK'
-- \endif
-- ROLLBACK;


-- modèle pour un test qui doit ÉCHOUER : une erreur = OK
-- \echo '--- doit ÉCHOUER : …'
-- BEGIN;
-- <la commande testée>;
-- \if :ERROR
-- \echo 'RESULTAT: OK'
-- \else
-- \echo 'RESULTAT: KO'
-- \endif
-- ROLLBACK;

-- Étape	            Règles
-- E2 · Contraintes	    Client majeur ; email valide ; risk_level entre 1 et 5 ; solde jamais négatif ; montant d’un virement positif ; comptes d’un virement différents ; signe d’une écriture cohérent avec son type
-- E3 · Droits	        Pour chaque profil, une lecture permise et une lecture interdite, avec SET ROLE
-- E4 · Vues	        Vue masquée lisible par le support ; fermeture refusée par la CHECK OPTION ; vue enregistrée lisible par l’analyste
-- E6 · Triggers	    Grand livre immuable ; solde mis à jour et refus si négatif ; alertes de fraude ; audit
-- E7 · Procédures	    Ouverture, virement et relevé : un appel réussi et un appel refusé chacun, en tant qu’app_novabank
-- Cohérence	        La requête de contrôle des soldes : 0 ligne

\echo '=== E2 · Contraintes : 21 tests totaux'
\echo '=== E2 · Contraintes : client majeur ==='

\echo '--- doit RÉUSSIR : client majeur (dans une transaction annulée)'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
VALUES ('Test', 'Majeur', 'test.majeur@exemple.fr', '0600000000', '1990-01-01', 1);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : client mineur (ck_customers_majeur)'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
VALUES ('Test', 'Mineur', 'test.mineur@exemple.fr', '0600000000', '2015-01-01', 1);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== E2 · Contraintes : email valide ==='

\echo '--- doit RÉUSSIR : email valide (dans une transaction annulée)'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
VALUES ('Test', 'Email-Val', 'test.emailvalide@exemple.fr', '0600000000', '1990-01-01', 1);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : email invalide sans @ (ck_customers_email)'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
VALUES ('Test', 'Email-Inval', 'test.emailinvalideexemple.fr', '0600000000', '1990-01-01', 1);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : email invalide sans . (ck_customers_email)'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
VALUES ('Test', 'Email-Inval', 'test.emailinvalide@exemplefr', '0600000000', '1990-01-01', 1);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== E2 · Contraintes : risk_level valide ==='

\echo '--- doit RÉUSSIR : risk level entre 1 et 5 (dans une transaction annulée)'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
SELECT 'Test', 'risk' || g, 'test.risk'|| g || '@exemple.fr', '0600000000', '1990-01-01', g
FROM generate_series(1, 5) AS g;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : risk level n''est pas entre 1 et 5 (ck_customers_risk_level)'
\echo '--- doit ÉCHOUER : risk level 0'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
VALUES ('Test', 'risk0', 'test.risk0@exemple.fr', '0600000000', '1990-01-01', 0);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;
\echo '--- doit ÉCHOUER : risk level 6'
BEGIN;
INSERT INTO core.customers (first_name, last_name, email, phone, birth_date, risk_level)
VALUES ('Test', 'risk6', 'test.risk0@exemple.fr', '0600000000', '1990-01-01', 6);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== E2 · Contraintes : solde valide ==='

\echo '--- doit RÉUSSIR : solde positif (dans une transaction annulée)'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'WITHDRAWAL', -10);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : solde négatif  (ck_accounts_balance)'
BEGIN;
UPDATE core.accounts SET balance = -10
WHERE account_id = 42;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== E2 · Contraintes : signe d’une écriture valide ==='

\echo '--- doit RÉUSSIR : signe d’une écriture cohérent avec son type  (ck_transactions_signe)'
\echo '--- doit RÉUSSIR : DEPOSIT'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'DEPOSIT', 10);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;
\echo '--- doit RÉUSSIR : TRANSFER_IN'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'TRANSFER_IN', 10);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;
\echo '--- doit RÉUSSIR : WITHDRAWAL'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'WITHDRAWAL', -10);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;
\echo '--- doit RÉUSSIR : TRANSFER_OUT'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'TRANSFER_OUT', -10);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;


\echo '--- doit ÉCHOUER : signe d’une écriture incohérent avec son type  (ck_transactions_signe)'
\echo '--- doit ÉCHOUER : DEPOSIT'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'DEPOSIT', -10);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;
\echo '--- doit ÉCHOUER : TRANSFER_IN'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'TRANSFER_IN', -10);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;
\echo '--- doit ÉCHOUER : WITHDRAWAL'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'WITHDRAWAL', 10);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;
\echo '--- doit ÉCHOUER : TRANSFER_OUT'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'TRANSFER_OUT', 10);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== E2 · Contraintes : montant de virement valide ==='

\echo '--- doit RÉUSSIR : virement positif et deux client différents (dans une transaction annulée)'
BEGIN;
INSERT INTO core.transfers (from_account_id, to_account_id, amount, label)
VALUES (42, 43, 10, 'Transfert positif de client 42 à 43');
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : virement négatif  (ck_transfers_amount)'
BEGIN;
INSERT INTO core.transfers (from_account_id, to_account_id, amount, label)
VALUES (42, 43, -10, 'Transfert négatif de client 42 à 43');
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : virement vers soi-même  (ck_transfers_comptes_differents)'
BEGIN;
INSERT INTO core.transfers (from_account_id, to_account_id, amount, label)
VALUES (42, 42, 10, 'Transfert vers soi-même');
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== E3 · Droits : 9 Tests totaux ==='
\echo '=== E3 · Droits : Lecture de droit par comptes ==='

\echo '--- doit RÉUSSIR : l''analyste lit les comptes'
BEGIN;
SET ROLE analyste_alice;
SELECT 1 FROM core.accounts LIMIT 1;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : l''analyste ne lit pas les audits'
BEGIN;
SET ROLE analyste_alice;
SELECT 1 FROM audit.audit_log LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : l''analyste ne lit pas les clients'
BEGIN;
SET ROLE analyste_alice;
SELECT 1 FROM core.customers LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : le support lit les comptes'
BEGIN;
SET ROLE support_bob;
SELECT 1 FROM core.accounts LIMIT 1;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : le support ne lit pas les alertes au fraude'
BEGIN;
SET ROLE support_bob;
SELECT 1 FROM core.fraud_alerts LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : le support ne lit pas les clients'
BEGIN;
SET ROLE support_bob;
SELECT 1 FROM core.customers LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : l''auditeur lit les audits'
BEGIN;
SET ROLE auditeur_chloe;
SELECT 1 FROM audit.audit_log LIMIT 1;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : l''auditeur ne lit pas les clients'
BEGIN;
SET ROLE auditeur_chloe;
SELECT 1 FROM core.customers LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : l''application ne lit pas les comptes'
BEGIN;
SET ROLE app_novabank;
SELECT 1 FROM core.accounts LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;


\echo '=== E4 · Vues : 6 Tests totaux ==='
\echo '=== E4 · Vues : Lecture et insertions de données via les vues ==='
\echo '--- doit RÉUSSIR : le support a accès à sa vue (v_customers_support)'
BEGIN;
SET ROLE support_bob;
SELECT * FROM core.v_customers_support LIMIT 1;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : le support n''a pas accès à la vue de l''analyste (mv_nb_tx_mois_type)'
BEGIN;
SET ROLE support_bob;
SELECT * FROM core.mv_nb_tx_mois_type LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : l''analyste a accès à sa vue (mv_nb_tx_mois_type)'
BEGIN;
SET ROLE analyste_alice;
SELECT * FROM core.mv_nb_tx_mois_type LIMIT 1;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : l''analyste n''a pas accès à la vue du support (v_customers_support)'
BEGIN;
SET ROLE analyste_alice;
SELECT * FROM core.v_customers_support LIMIT 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : la vue peux modifier le status d''un comptes (v_comptes_ouverts)'
BEGIN;
UPDATE core.v_comptes_ouverts SET status = 'FROZEN' WHERE account_id = 42;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : la vue ne peux fermer un comptes (v_comptes_ouverts)'
BEGIN;
UPDATE core.v_comptes_ouverts SET status = 'CLOSED' WHERE account_id = 42;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== E6 · Triggers : 10 Tests totaux ==='
\echo '=== E6 · Triggers : Triggers sur le ''Grand livre immuable'', la solde, les fraudes et l''audit ==='

\echo '--- doit RÉUSSIR : ON passe un compte à FROZEN puis ACTIVE, et on vérifie si c''est bien audité (trg_accounts_after_audit)'
BEGIN;
UPDATE core.accounts SET status = 'FROZEN' WHERE account_id = 1;
UPDATE core.accounts SET status = 'ACTIVE' WHERE account_id = 1;
SELECT 1 / count(*) FROM audit.audit_log
WHERE table_name = 'core.accounts'
  AND (new_data->>'account_id')::bigint = 1
  AND changed_at = now();
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : modifier autre chose que le statut ne crée PAS de ligne d''audit (trg_accounts_after_audit)'
BEGIN;
-- une modification qui ne touche pas au statut : le trigger d'audit ne doit pas se déclencher
UPDATE core.accounts SET balance = balance WHERE account_id = 1;
-- compte les lignes d'audit du compte 1 créées PENDANT ce test (changed_at = now())
-- division inversée : erreur si ce compte n'est PAS égal à 0
SELECT 1 / (count(*) = 0)::int
FROM audit.audit_log
WHERE table_name = 'core.accounts'
  AND (new_data->>'account_id')::bigint = 1
  AND changed_at = now();
    \if :ERROR
    \echo 'RESULTAT: KO'
    \else
    \echo 'RESULTAT: OK'
    \endif
ROLLBACK;

\echo '--- doit ÉCHOUER : On ne modifie pas les transactions (trg_transactions_before_update_delete)'
BEGIN;
UPDATE core.transactions SET amount = 1 WHERE tx_id = 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : On ne supprime pas les transactions (trg_transactions_before_update_delete)'
BEGIN;
DELETE FROM core.transactions WHERE tx_id = 1;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : On ne supprimes pas toutes les données (trg_transactions_before_truncate)'
BEGIN;
TRUNCATE core.transactions CASCADE;
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : Un retrait qui passe (trg_transactions_before_insert_solde)'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'WITHDRAWAL', -10)
RETURNING balance_after;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : Un retrait qui rendrait le solde négatif (trg_transactions_before_insert_solde)'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount)
VALUES (42, 'WITHDRAWAL', -999999);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : Un retrait d''au moins 5000 créé une fraud_alert BIG_WITHDRAWAL (trg_transactions_after_insert_fraude)'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'WITHDRAWAL', -5000);
-- erreur « division by zero » s'il n'y a AUCUNE alerte : le test affiche alors KO
SELECT 1 / count(*) FROM core.fraud_alerts
WHERE account_id = 42 AND rule_code = 'BIG_WITHDRAWAL';
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : 4 virements émis en moins de 10min ne créé pas de fraud_alert RAPID_TRANSFERS (trg_transactions_after_insert_fraude)'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
SELECT 1 / (count(*) = 0)::int FROM core.fraud_alerts
WHERE account_id = 42 AND rule_code = 'RAPID_TRANSFERS';
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit RÉUSSIR : 5 virements émis en moins de 10min créé une fraud_alert RAPID_TRANSFERS (trg_transactions_after_insert_fraude)'
BEGIN;
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'TRANSFER_OUT', -10);
SELECT 1 / count(*) FROM core.fraud_alerts
WHERE account_id = 42 AND rule_code = 'RAPID_TRANSFERS';
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '=== E7 · Procédures : 10 Tests totaux ==='
\echo '=== E7 · Procédures : Ouverture, virement et relvé par app_novabank ==='
\echo '--- Ouverture de compte'
\echo '--- doit RÉUSSIR : le client 1 a un KYC VERIFIED (sp_ouvrir_compte)'
BEGIN;
SET ROLE app_novabank;
CALL core.sp_ouvrir_compte(1, 'SAVINGS', 500, NULL);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : le client 2 a un KYC REJECTED'
BEGIN;
SET ROLE app_novabank;
CALL core.sp_ouvrir_compte(2, 'SAVINGS', 500, NULL);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : client inconnu'
BEGIN;
SET ROLE app_novabank;
CALL core.sp_ouvrir_compte(999999, 'SAVINGS', 500, NULL);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : dépôt nul'
BEGIN;
SET ROLE app_novabank;
CALL core.sp_ouvrir_compte(1, 'SAVINGS', 0, NULL);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- Virement'
\echo '--- doit RÉUSSIR : Un virement de client 42 vers 43 de 50€ (sp_virement)'
BEGIN;
SET ROLE app_novabank;
CALL core.sp_virement(42, 43, 50, 'Test de virement', NULL);
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : solde insuffisant'
BEGIN;
SET ROLE app_novabank;
CALL core.sp_virement(42, 43, 999999, 'Trop gros', NULL);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : même compte'
BEGIN;
SET ROLE app_novabank;
CALL core.sp_virement(42, 42, 50, 'Moi-même', NULL);
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;


\echo '--- Relevé'
\echo '--- doit RÉUSSIR : le relevé du compte 42 sur deux ans (fn_releve)'
BEGIN;
SET ROLE app_novabank;
SELECT 1 / count(*) FROM core.fn_releve(42, '2024-01-01', '2026-12-31');
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : dates dans le désordre'
BEGIN;
SET ROLE app_novabank;
SELECT * FROM core.fn_releve(42, '2026-12-31', '2026-01-01');
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '--- doit ÉCHOUER : compte inconnu'
BEGIN;
SET ROLE app_novabank;
SELECT * FROM core.fn_releve(999999, '2026-01-01', '2026-12-31');
\if :ERROR
\echo 'RESULTAT: OK'
\else
\echo 'RESULTAT: KO'
\endif
ROLLBACK;

\echo '=== Cohérence : 1 Tests total ==='
\echo '--- doit RÉUSSIR : compte les incohérences de compte'
SELECT 1 / (count(*) = 0)::int
FROM core.accounts AS a
         JOIN (SELECT account_id, sum(amount) AS total
               FROM core.transactions GROUP BY account_id) AS s
              ON s.account_id = a.account_id
WHERE a.balance <> s.total;
\if :ERROR
\echo 'RESULTAT: KO'
\else
\echo 'RESULTAT: OK'
\endif

\echo '=== Fin des tests ==='
