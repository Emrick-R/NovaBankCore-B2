-- Fichier de création des triggers de la db
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/06_triggers.sql


-- arrête le fichier à la première erreur, au lieu d'exécuter la suite sur des données incomplètes
\set ON_ERROR_STOP on

-- Fonction de l'historique de la transaction (grand livre) :
-- Elle revoit une EXCEPTION avec la commande interdite
CREATE OR REPLACE FUNCTION core.fn_interdit() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
        RAISE EXCEPTION 'Le grand livre est immuable: % interdit sur core.transactions', TG_OP;   -- le % est remplacé par la valeur de TG_OP
        RETURN NULL;
    END;
$$;

-- Triggers de l'historique de la transaction :
-- trigger avant une UPDATE ou DELETE sur core.transactions qui appel core.fn_interdit
CREATE OR REPLACE TRIGGER trg_transactions_before_update_delete
    BEFORE UPDATE OR DELETE ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_interdit();

-- trigger avant un TRUNCATE sur core.transactions qui appel core.fn_interdit
CREATE OR REPLACE TRIGGER trg_transactions_before_truncate
    BEFORE TRUNCATE ON core.transactions
    FOR EACH STATEMENT EXECUTE FUNCTION core.fn_interdit();

-- Verifications en tant que bank_owner:
-- UPDATE core.transactions SET amount = 1 WHERE tx_id = 1;   -- doit être refusé
-- DELETE FROM core.transactions WHERE tx_id = 1;             -- doit être refusé
-- BEGIN;                                                     -- ouvre une transaction : rien n'est définitif
-- TRUNCATE core.transactions CASCADE;                        -- doit être refusé par TON trigger
-- ROLLBACK;                                                  -- annule tout ce qui s'est passé depuis BEGIN
-- SELECT count(*) FROM core.transactions;                    -- toujours 1 000 000


-- Fonction d'audit générique :
-- Note dans audit.audit_log chaque changement important, quelle que soit la table qui l'a déclenchée
CREATE OR REPLACE FUNCTION core.fn_audit() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
        INSERT INTO audit.audit_log (table_name, operation, old_data, new_data)
        VALUES (
                   TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,     -- la table touchée
                   TG_OP,                 -- INSERT, UPDATE ou DELETE
                   to_jsonb(OLD),     -- (NULL pour un INSERT)
                   to_jsonb(NEW)      -- (NULL pour un DELETE)
               );
        -- db_user (qui) et changed_at (quand) : remplis par leurs valeurs par défaut
        RETURN NULL;           -- trigger AFTER : la valeur renvoyée est ignorée
    END;
$$;

-- Triggers d'audit générique :
-- Clients : tout changement est audité
CREATE OR REPLACE TRIGGER trg_customers_after_audit
    AFTER INSERT OR UPDATE OR DELETE ON core.customers
    FOR EACH ROW EXECUTE FUNCTION core.fn_audit();

-- Comptes : seulement quand le statut change (gel, fermeture)
CREATE OR REPLACE TRIGGER trg_accounts_after_audit
    AFTER UPDATE ON core.accounts
    FOR EACH ROW
    WHEN (NEW.status IS DISTINCT FROM OLD.status)
    EXECUTE FUNCTION core.fn_audit();

-- Alertes de fraude : quand une alerte est modifiée (changement de statut)
CREATE OR REPLACE TRIGGER trg_fraud_alerts_after_audit
    AFTER UPDATE ON core.fraud_alerts
    FOR EACH ROW EXECUTE FUNCTION core.fn_audit();

-- -- Verifications en tant que bank_owner:
-- -- 1. un changement de statut : doit être audité
-- UPDATE core.accounts SET status = 'FROZEN' WHERE account_id = 1;
-- -- 2. un retour en arrière : doit être audité aussi
-- UPDATE core.accounts SET status = 'ACTIVE' WHERE account_id = 1;
-- -- 3. un changement qui ne touche pas le statut : ne doit PAS être audité
-- UPDATE core.accounts SET balance = balance WHERE account_id = 1;
--
-- -- ce que contient le journal
-- SELECT log_id, table_name, operation, old_data->>'status' AS avant,
--     new_data->>'status' AS apres, db_user, changed_at
-- FROM audit.audit_log
-- ORDER BY log_id;

-- Fonction du solde : pour chaque nouvelle écriture, calcule balance_after,
-- refuse si le compte passerait sous 0, et met à jour le solde du compte
CREATE OR REPLACE FUNCTION core.fn_solde() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE
        v_ancien  numeric(14,2);   -- solde AVANT cette écriture
        v_nouveau numeric(14,2);   -- solde APRÈS cette écriture
    BEGIN
        -- 1. lecture du solde actuel ET on verrouille la ligne du compte : on évite les doubles écriture simultanée
        SELECT balance INTO v_ancien
            FROM core.accounts
            WHERE account_id = NEW.account_id
            FOR UPDATE;

        -- 2. calcule du nouveau solde : ancien + montant à déduire ou ajouter (+ -/+)
        v_nouveau := v_ancien + NEW.amount;

        -- 3. refus si le compte < 0
        IF v_nouveau < 0 THEN
            RAISE EXCEPTION 'Solde insuffisant sur le compte % : % + % < 0', NEW.account_id, v_ancien, NEW.amount;
        END IF;

        -- 4. le nouveau solde pour archivage dans le Grand livre
        NEW.balance_after := v_nouveau;

        -- 5. actualisation du compte avec le nouveau montant
        UPDATE core.accounts
            SET balance = v_nouveau
            WHERE account_id = NEW.account_id;

        -- BEFORE : on renvoie la ligne (modifiée) pour qu'elle soit écrite
        RETURN NEW;
    END;
$$;

-- Trigger avant les transactions
CREATE OR REPLACE TRIGGER trg_transactions_before_insert_solde
    BEFORE INSERT ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_solde();

-- Verifications en tant que bank_owner :
-- -- solde actuel du compte 42
-- SELECT balance FROM core.accounts WHERE account_id = 42;
--
-- -- 1. un retrait qui passe : balance_after est calculé par le trigger, pas fourni
-- INSERT INTO core.transactions (account_id, tx_type, amount)
-- VALUES (42, 'WITHDRAWAL', -10)
-- RETURNING tx_id, amount, balance_after;
-- -- le solde du compte doit avoir baissé de 10
-- SELECT balance FROM core.accounts WHERE account_id = 42;
--
-- -- 2. un retrait qui rendrait le solde négatif : doit être refusé
-- INSERT INTO core.transactions (account_id, tx_type, amount)
-- VALUES (42, 'WITHDRAWAL', -999999);
-- -- attendu : ERROR: Solde insuffisant sur le compte 42 : … + -999999.00 < 0
--
-- -- 3. cohérence : le solde du compte = le balance_after de sa dernière écriture
-- SELECT a.balance, t.balance_after
-- FROM core.accounts AS a
-- JOIN core.transactions AS t ON t.account_id = a.account_id
-- WHERE a.account_id = 42
-- ORDER BY t.created_at DESC, t.tx_id DESC
-- LIMIT 1;
-- -- attendu : les deux colonnes égales

-- Fonction de fraude : après chaque écriture, crée une alerte si elle est suspecte
CREATE OR REPLACE FUNCTION core.fn_fraude() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE
        v_nb_virements int;   -- nombre de virements émis par ce compte dans les 10 dernières minutes
    BEGIN
        -- Règle 1 : retrait de 5 000 ou plus (montant négatif, option B)
        IF NEW.amount <= -5000 AND NEW.tx_type = 'WITHDRAWAL' THEN
            INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
            VALUES (NEW.account_id, NEW.tx_id, 'BIG_WITHDRAWAL'::core.rule_code);
        END IF;

        -- Règle 2 : 5 virements émis ou plus en 10 minutes
        IF NEW.tx_type = 'TRANSFER_OUT' THEN
            SELECT count(*) INTO v_nb_virements
                FROM core.transactions
                WHERE account_id = NEW.account_id
                  AND tx_type = 'TRANSFER_OUT'
                  AND created_at > NEW.created_at - interval '10 minutes';

            IF v_nb_virements >= 5 THEN
                INSERT INTO core.fraud_alerts (account_id, tx_id, rule_code)
                VALUES (NEW.account_id, NEW.tx_id, 'RAPID_TRANSFERS'::core.rule_code);
            END IF;
        END IF;

        RETURN NULL;   -- AFTER : la valeur renvoyée est ignorée
    END;
$$;

-- Trigger après une transaction
CREATE OR REPLACE TRIGGER trg_transactions_after_insert_fraude
    AFTER INSERT ON core.transactions
    FOR EACH ROW EXECUTE FUNCTION core.fn_fraude();

-- Verifications en tant que bank_owner :
-- BEGIN;
--
-- -- Règle 1 : un retrait de 5 000 → doit créer une alerte BIG_WITHDRAWAL
-- INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'WITHDRAWAL', -5000);
--
-- -- Règle 2 : 5 virements émis par le compte 43 → l'alerte RAPID_TRANSFERS au 5e
-- INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (43, 'TRANSFER_OUT', -10);
-- INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (43, 'TRANSFER_OUT', -10);
-- INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (43, 'TRANSFER_OUT', -10);
-- INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (43, 'TRANSFER_OUT', -10);
-- INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (43, 'TRANSFER_OUT', -10);
--
-- -- ce que contiennent les alertes, AVANT d'annuler
-- SELECT alert_id, account_id, tx_id, rule_code, status FROM core.fraud_alerts;
--
-- ROLLBACK;   -- annule les écritures de test et leurs alertes