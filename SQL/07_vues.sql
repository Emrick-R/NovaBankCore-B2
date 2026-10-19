-- Fichier de création des vues avec leurs fonctions pour la db
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/07_vues.sql


-- arrête le fichier à la première erreur, au lieu d'exécuter la suite sur des données incomplètes
\set ON_ERROR_STOP on

-- Masque un email : garde la première lettre et le domaine (c*******@novabank.bk)
CREATE OR REPLACE FUNCTION core.fn_masquer_email(p_email text) RETURNS text
    LANGUAGE sql IMMUTABLE AS $$
    SELECT
        left(p_email, 1) -- première lettre du string
        || repeat('*', strpos(p_email, '@')-2)  --  une étoile par caractère caché : ceux entre la 1re lettre et le @
        || substr(p_email, strpos(p_email, '@')) -- enlève tout ce qui est avant le @ du string
$$;
-- Vérification en tant que bank owner:
-- SELECT core.fn_masquer_email('client42@novabank.bk');   -- attendu : c*******@novabank.bk


-- grp_support entier, masquée, ou absente
-- customer_id	entier
-- first_name	entier
-- last_name	masquée M. pour Martin left(last_name, 1) || '.'
-- email	masquée	client42@novabank.bk  →  c*******@novabank.bk left(email, 1) || repeat('*', strpos(email, '@')-2) || substr(email, strpos(email, '@'))
-- phone	masquée	0600000042 → ......42 repeat('*', 8) || right(phone, 2)
-- birth_date	masquée 1989 extract(year from birth_date)
-- kyc_status	entier
-- risk_level	absente

-- Vue des clients pour le support : identifie un client sans exposer ses données personnelles
CREATE OR REPLACE VIEW core.v_customers_support
    WITH (security_barrier = true) AS
    SELECT
        customer_id,
        first_name,
        left(last_name, 1) || '.'         AS last_name,
        core.fn_masquer_email(email) AS email,
        repeat('*', 8) || right(phone, 2) AS phone,
        extract(year from birth_date)     AS birth_year,
        kyc_status
    FROM core.customers;

-- On donne les droits au grp_support de lire la vue et d'exécuter la fonction pour le masque des mails
GRANT SELECT ON core.v_customers_support TO grp_support;
GRANT EXECUTE ON FUNCTION core.fn_masquer_email(text) TO grp_support;

-- Vérifications en tant que postgres :
-- SET ROLE support_bob;
-- SELECT * FROM core.v_customers_support LIMIT 5;   -- doit marcher, données masquées
-- SELECT * FROM core.customers LIMIT 1;             -- toujours refusé
-- RESET ROLE;

-- Vue des comptes ouverts : identifie un compte 'ACTIVE' ou 'FROZEN' sans le montant
-- Si l'user change le status en CLOSED il aura une erreur.
CREATE OR REPLACE VIEW core.v_comptes_ouverts
    WITH (security_barrier = true) AS
    SELECT
        account_id,
        customer_id,
        iban,
        account_type,
        status,
        opened_at
    FROM core.accounts
    WHERE status IN ('ACTIVE', 'FROZEN')
    WITH LOCAL CHECK OPTION;

-- Vérifications en tant que bank_owner :
-- -- accepté : le compte reste dans la vue (et l'audit le note)
-- UPDATE core.v_comptes_ouverts SET status = 'FROZEN' WHERE account_id = 2;
-- -- refusé : le compte sortirait de la vue
-- UPDATE core.v_comptes_ouverts SET status = 'CLOSED' WHERE account_id = 2;
-- -- remise en état
-- UPDATE core.v_comptes_ouverts SET status = 'ACTIVE' WHERE account_id = 2;


-- Vue nombre d'écritures par mois par type, mv_ pour materialized view
CREATE MATERIALIZED VIEW IF NOT EXISTS core.mv_nb_tx_mois_type AS
       SELECT
           COUNT(*) AS nb_tx,
           date_trunc('month', created_at) AS date,
           tx_type,
           sum(amount) AS montant_total
       FROM core.transactions
       GROUP BY date, tx_type;

-- index unique sur (mois, type) : exigé par REFRESH MATERIALIZED VIEW CONCURRENTLY,
-- qui s'en sert pour comparer l'ancien et le nouveau résultat ligne par ligne
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_transactions_mois_type ON core.mv_nb_tx_mois_type (date, tx_type);

-- On donne le droit au grp_analyste d'utiliser la vue
GRANT SELECT ON core.mv_nb_tx_mois_type TO grp_analyste;

-- Vérification en tant que bank_owner :
-- -- 1. le nombre de dépôts du mois en cours, d'après la vue
-- SELECT * FROM core.mv_nb_tx_mois_type
-- WHERE tx_type = 'DEPOSIT' ORDER BY date DESC LIMIT 1;
--
-- -- 2. un nouveau dépôt de 100 € sur le compte 42
-- INSERT INTO core.transactions (account_id, tx_type, amount) VALUES (42, 'DEPOSIT', 100);
--
-- -- 3. la vue n'a pas changé : elle est figée
-- SELECT * FROM core.mv_nb_tx_mois_type
-- WHERE tx_type = 'DEPOSIT' ORDER BY date DESC LIMIT 1;
--
-- -- 4. on la recalcule, sans bloquer les lecteurs
-- REFRESH MATERIALIZED VIEW CONCURRENTLY core.mv_nb_tx_mois_type;
--
-- -- 5. maintenant, le dépôt apparaît : un de plus, 100 € de plus
-- SELECT * FROM core.mv_nb_tx_mois_type
-- WHERE tx_type = 'DEPOSIT' ORDER BY date DESC LIMIT 1;

