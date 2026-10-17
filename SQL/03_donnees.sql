-- Fichier de génération des données de la base pour la DB
-- Lancé avec l'user bank_owner :
-- psql -h 127.0.0.1 -U bank_owner -d bankdb < ~/SQL/03_donnees.sql
-- Verification : ```SELECT count(*) FROM core.customers;```


-- On met à vide toutes les tables remplies par ce fichier, et remet leurs compteurs à 1
TRUNCATE core.customers, core.accounts, core.transfers, core.transactions, core.fraud_alerts RESTART IDENTITY;

-- On utilise une seed pour avoir la même chose à chaque lancement du fichier
SELECT setseed(0.3);

-- Les clients : core.customers
INSERT INTO core.customers (first_name,
                            last_name,
                            email,
                            phone,
                            birth_date,
                            kyc_status,
                            risk_level,
                            created_at
)
SELECT
    -- 20 prénoms, au hasard parmi 20 (random(1,20), car les cases commencent à 1)
    (ARRAY['Emma', 'Lucas', 'Léa', 'Hugo', 'Chloé', 'Louis', 'Manon', 'Gabriel',
     'Camille', 'Arthur', 'Inès', 'Jules', 'Sarah', 'Nathan', 'Jade', 'Adam',
     'Louise', 'Raphaël', 'Alice', 'Mohamed'])[random(1,20)],
    -- 20 noms, au hasard parmi 20
    (ARRAY['Martin', 'Bernard', 'Dubois', 'Thomas', 'Robert', 'Richard', 'Petit',
    'Durand', 'Leroy', 'Moreau', 'Simon', 'Laurent', 'Lefebvre', 'Michel',
    'Garcia', 'David', 'Bertrand', 'Roux', 'Nguyen', 'Fontaine'])[random(1,20)],
    -- email unique, construit à partir du numéro de ligne g : client42@novabank.bk
    'client' || g || '@novabank.bk',
    -- téléphone : 06 si g pair, 07 sinon, suivi de g sur 8 chiffres (lpad complète avec des 0 à gauche)
    CASE WHEN g % 2 = 0 THEN '06' ELSE '07' END || lpad(g::text, 8, '0'),
    -- date de naissance au hasard entre 19 et 60 ans (date - entier = date, en jours)
    current_date - random(19 * 365, 60 * 365),
    -- statut KYC au hasard, converti du texte vers le type ENUM core.kyc_status
    (ARRAY['PENDING', 'VERIFIED', 'REJECTED'])[1 + floor(random() * 3)::int]::core.kyc_status,
    -- niveau de risque au hasard entre 1 et 5 (respecte ck_customers_risk_level)
    random(1, 5),
    -- inscription au hasard entre il y a 3 ans et il y a 2 ans
    now() - interval '2 years' - random() * interval '1 year'
FROM generate_series(1, 100000) AS g;

