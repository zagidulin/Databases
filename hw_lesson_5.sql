/*1-е задание Операторы, фильтрация, сортировка и ограничение */
UPDATE users
SET
  created_at = now()
WHERE
  created_at is NULL;
	
UPDATE users
SET
  updated_at = now()
WHERE
  updated_at is NULL;


/*2-е задание Операторы, фильтрация, сортировка и ограничение */
CREATE DATABASE hw_5;
USE hw_5;

DROP TABLE IF EXISTS users;
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) COMMENT 'Имя покупателя',
  birthday_at DATE COMMENT 'Дата рождения',
  created_at VARCHAR(50),
  updated_at VARCHAR(50)
) COMMENT = 'Покупатели';

INSERT INTO users (name, birthday_at, created_at, updated_at) VALUES
  ('Геннадий', '1990-10-05', '20.10.2017 8:10', '20.11.2018 8:10'),
  ('Наталья', '1984-11-12', '20.10.2017 8:10', '20.12.2018 8:10'),
  ('Александр', '1985-05-20', '20.10.2017 8:10', '20.01.2019 8:10');
  
CREATE TABLE tmp_users
SELECT
  id,
  name,
  birthday_at,
  created_at,
  updated_at
FROM
  users;

DELETE FROM users;

ALTER TABLE users
MODIFY created_at DATETIME;

ALTER TABLE users
MODIFY updated_at DATETIME;

INSERT INTO users
SELECT
  id,
  name,
  birthday_at,
  str_to_date(created_at, "%d.%m.%Y %h:%i"),
  str_to_date(updated_at, "%d.%m.%Y %h:%i")
FROM tmp_users;

DROP TABLE tmp_users;

/*3-е задание Операторы, фильтрация, сортировка и ограничение */
DROP TABLE IF EXISTS storehouses_products;
CREATE TABLE storehouses_products (
  id SERIAL PRIMARY KEY,
  storehouse_id INT UNSIGNED,
  product_id INT UNSIGNED,
  value INT UNSIGNED COMMENT 'Запас товарной позиции на складе',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) COMMENT = 'Запасы на складе';

INSERT INTO storehouses_products (id, storehouse_id,  product_id, value) VALUES
  ('1', '1', '1', '30'),
  ('2', '1', '2', '0'),
  ('3', '1', '3', '999'),
  ('4', '1', '4', '73'),
  ('5', '3', '5', '3'),
  ('6', '2', '6', '0'),
  ('7', '1', '7', '12');

SELECT * FROM storehouses_products
ORDER BY IF(value = 0, 1, 0), value;


/*1-е задание Агрегация данных */
SELECT AVG(TIMESTAMPDIFF(YEAR, birthday_at, CURDATE())) FROM users;


/*2-е задание Агрегация данных */
SELECT WEEKDAY(CONCAT('2020-', SUBSTRING(birthday_at, 6, 10))) FROM users;
