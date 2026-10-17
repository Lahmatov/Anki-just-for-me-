-- Облачные копии по изучаемым языкам (P-67): у каждого языка своя база в
-- приложении, и копии одного языка не должны вытеснять копии другого.
-- Всё, что было до языков, — английское.
ALTER TABLE backups ADD COLUMN language TEXT NOT NULL DEFAULT 'en';
CREATE INDEX backups_owner_language ON backups(owner, language, created_at);
