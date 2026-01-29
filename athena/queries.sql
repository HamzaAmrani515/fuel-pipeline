-- 1) voir si curated a des lignes
SELECT * FROM curated LIMIT 100;

-- 2)
SELECT count(*) FROM curated;

-- 3)
SELECT * FROM curated WHERE ville = 'Paris' LIMIT 50;
