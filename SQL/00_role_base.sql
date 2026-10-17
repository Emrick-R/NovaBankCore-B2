-- 1er fichier de création de la db
-- À lancer en tant que postgres, on crée la db, le rôle de l'owner et la base

CREATE ROLE bank_owner LOGIN;
-- Dans l'invite de commande de psql en tant que postgres, on créer le mdp de l'owner:
-- \password bank_owner

CREATE DATABASE bankdb OWNER bank_owner;
