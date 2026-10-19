-- Fichier de création des indexes pour la db
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/08_index.sql


-- arrête le fichier à la première erreur, au lieu d'exécuter la suite sur des données incomplètes
\set ON_ERROR_STOP on

-- Index pour :
-- Le relevé d’un compte, trié par date
CREATE INDEX IF NOT EXISTS idx_transactions_account_id_created_at ON core.transactions (account_id, created_at);
-- Vérification en tant que bank_owner:
-- -- avant : Parallel Seq Scan, ~10 000 pages, 171 ms ; après : Bitmap Index Scan, 7 pages, 0,05 ms
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM core.transactions
-- WHERE account_id = 42
-- ORDER BY created_at;

-- Une recherche de client par email, insensible à la casse
CREATE INDEX IF NOT EXISTS idx_customers_lower_email ON core.customers (lower(email));
--Vérification en tant que bank_owner :
-- -- avant : Seq Scan, ~1 300 pages, 98 ms ; après : Index scan, 4 pages, 0.061 ms
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM core.customers
-- WHERE lower(email) = lower('CLIENT42@NovaBank.bk');

-- Les comptes gelés, une petite minorité
CREATE INDEX IF NOT EXISTS idx_accounts_frozen ON core.accounts (account_id) WHERE status = 'FROZEN';
--Vérification en tant que bank_owner :
-- -- avant : Seq Scan, ~196 000 lignes jetées, ~4 740 pages, 251 ms ; après : Index scan, ~2 025 pages, 24.649 ms
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM core.accounts WHERE status = 'FROZEN';

---- Expérience : l'index inutile (créé puis supprimé, NON conservé)
-- Question du guide : un index sur une colonne à très peu de valeurs différentes sert-il ?
-- CREATE INDEX idx_accounts_status_complet ON core.accounts (status);
-- ANALYZE core.accounts;
--
-- -- 1. tailles : partiel (comptes gelés) = 104 kB ; complet (tous les comptes) = 1 368 kB, 13 fois plus
-- SELECT pg_size_pretty(pg_relation_size('core.idx_accounts_frozen'))         AS partiel,
--        pg_size_pretty(pg_relation_size('core.idx_accounts_status_complet')) AS complet;
--
-- -- 2. recherche des comptes actifs (98 % de la table) : PostgreSQL IGNORE l'index complet
-- --    résultat : Seq Scan, 196 014 lignes, ~32 ms
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT * FROM core.accounts WHERE status = 'ACTIVE';
--
-- -- Conclusion : pour 98 % des lignes, lire l'index puis sauter vers presque chaque page
-- -- coûte plus cher que lire la table d'un bout à l'autre. L'index complet prend de la place
-- -- et ralentit les écritures sans jamais servir : on le supprime.
-- -- Seul l'index PARTIEL sur la valeur rare (FROZEN) est utile.
---- DROP INDEX core.idx_accounts_status_complet;

-- Une somme sur un mois
-- On utilise un BRIN (Block Range INdex), il note, pour chaque paquet de pages de la table, la date la plus petite
-- et la plus grande qu’il contient.
CREATE INDEX IF NOT EXISTS idx_transactions_brin_date ON core.transactions USING brin (created_at);
--Vérification en tant que bank_owner :
-- -- avant : Seq Scan, ~934 000 lignes jetées, ~9 940 pages, 170 ms ;
-- -- après : Bitmap Index Scan & Bitmap Heap Scan, 776 pages : 8 pour l’index, 768 pour la table, 61 ms
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT sum(amount) FROM core.transactions
-- WHERE created_at >= '2026-03-01' AND created_at < '2026-04-01';


--Vérifications sur tous les indexes:
-- SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS taille
-- FROM pg_stat_user_indexes
-- WHERE schemaname = 'core'
-- ORDER BY indexrelname;