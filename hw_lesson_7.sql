-- 1. Составьте список пользователей users, которые осуществили хотя бы один заказ orders в интернет магазине.

select * from users where id in (select user_id from orders);

-- 2. Выведите список товаров products и разделов catalogs, который соответствует товару.

select
	id,
	(select name from catalogs where id = catalog_id) as 'catalog',
	name,
	description,
	price	
from
	products;

/* 3. Пусть имеется таблица рейсов flights (id, from, to) и таблица городов cities (label,
name). Поля from, to и label содержат английские названия городов, поле name — русское.
Выведите список рейсов flights с русскими названиями городов. */

select
	id,
	(select name from cities where lable = `from`),
	(select name from cities where lable = `to`)
from flights;