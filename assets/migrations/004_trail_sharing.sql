-- Trails saved from other people ('bookmarked' source) keep who made them.
-- author_pubkey is the creator's public key (hex), author_npub the same as npub1…,
-- author_d_tag the trail's id on Nostr; together pubkey + d_tag identify the original.
ALTER TABLE trails ADD COLUMN author_pubkey TEXT;
ALTER TABLE trails ADD COLUMN author_npub TEXT;
ALTER TABLE trails ADD COLUMN author_name TEXT;
ALTER TABLE trails ADD COLUMN author_d_tag TEXT;
ALTER TABLE trails ADD COLUMN author_event_id TEXT;

-- Our own trails that were published: when, and the Nostr event that carries them.
ALTER TABLE trails ADD COLUMN shared_at TEXT;
ALTER TABLE trails ADD COLUMN shared_event_id TEXT;
