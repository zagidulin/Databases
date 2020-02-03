/* задание 1.1. В базе данных shop и sample присутствуют одни и те же таблицы, учебной базы данных.
Переместите запись id = 1 из таблицы shop.users в таблицу sample.users. Используйте
транзакции. */

start transaction;

insert into sample.users
	select id, name from shop.users where id = 1;
	
commit;

/* задание 1.2 Создайте представление, которое выводит название name товарной позиции из таблицы
products и соответствующее название каталога name из таблицы catalogs. */

create or replace view prod as
	select
		p.name as product_name,
		c.name as catalog_name
	from products as p
	left join catalogs as c
	on p.catalog_id = c.id

/* задание 1.3  Пусть имеется таблица с календарным полем created_at. В ней размещены
разряженые календарные записи за август 2018 года '2018-08-01', '2016-08-04', '2018-08-16' и
2018-08-17. Составьте запрос, который выводит полный список дат за август, выставляя в
соседнем поле значение 1, если дата присутствует в исходном таблице и 0, если она
отсутствует.*/

drop table if exists dates;
create table dates (
id serial primary key,
created_at date);

insert into dates (created_at) values
('2018-08-01'),
('2018-08-04'),
('2018-08-16'),
('2018-08-17');


drop table if exists digits;
create table digits (value int);

insert into digits values
(0), (1), (2), (3), (4), (5), (6), (7), (8), (9),
(10), (11), (12), (13), (14), (15), (16), (17), (18), (19),
(20), (21), (22), (23), (24), (25), (26), (27), (28), (29), (30);


create or replace view overview (day, day_matched)
as
select
	date(date('2018.08.01') + interval digits.value DAY),
	if(dates.created_at is null, 0, 1)
from 
	digits
left join
	dates
on
	date(date('2018.08.01') + interval digits.value DAY) = dates.created_at;

select * from overview order by day;
	
/* 1.4 Пусть имеется любая таблица с календарным полем created_at. Создайте
запрос, который удаляет устаревшие записи из таблицы, оставляя только 5 самых свежих
записей. */


start transaction;

prepare deleting from 'delete from `profiles` order by created_at limit ?';
set @needless = (select count(*) - 5 from `profiles`);
execute deleting using @needless;

commit;

-- select * from `profiles_copy`;

/* 3.1 Создайте хранимую функцию hello(), которая будет возвращать приветствие, в зависимости от
текущего времени суток. С 6:00 до 12:00 функция должна возвращать фразу "Доброе утро", с
12:00 до 18:00 функция должна возвращать фразу "Добрый день", с 18:00 до 00:00 — "Добрый
вечер", с 00:00 до 6:00 — "Доброй ночи". */

drop function if exists hello;
create function hello()
returns varchar ( 30 ) not deterministic
begin
declare cur_hour int;
declare greeting varchar ( 30 );
	set cur_hour = hour(curtime());
	if cur_hour < 6 then
		set greeting = 'Доброй ночи!';
	elseif cur_hour < 12 then
		set greeting = 'Доброе утро!';
	elseif cur_hour < 18 then
		set greeting = 'Добрый день!';
	else
		set greeting = 'Добрый вечер!';
	end if;
return greeting;
end;

select hello();

SET GLOBAL log_bin_trust_function_creators = 1;

/* 3.2 В таблице products есть два текстовых поля: name с названием товара и description с его
описанием. Допустимо присутствие обоих полей или одно из них. Ситуация, когда оба поля
принимают неопределенное значение NULL неприемлема. Используя триггеры, добейтесь
того, чтобы одно из этих полей или оба поля были заполнены. При попытке присвоить полям
NULL-значение необходимо отменить операцию. */

drop trigger if exists check_products_insert;
create trigger check_products_insert before insert on products
for each row
begin
	if new.name is null and new.description is null then
		signal sqlstate '45000'
			SET MESSAGE_TEXT = 'Поле name или description должны содержать значение';
	end if;
end;


/* 3.2 Напишите хранимую функцию для вычисления произвольного числа Фибоначчи.
Числами Фибоначчи называется последовательность в которой число равно сумме двух
предыдущих чисел. Вызов функции FIBONACCI(10) должен возвращать число 55. */

drop function if exists fibonacci;
create function fibonacci (num INT)
returns int not deterministic
begin
	declare fib_1 int default 0;
	declare fib_2 int default 1;
	declare fib_res int;
	if num = 0 then
			set fib_res = fib_1;			
	elseif num = 1 then
			set fib_res = fib_2;			
	else
		set @counter = 2;
		while @counter <= num DO
			set fib_res = fib_1 + fib_2;
			set fib_1 = fib_2;
			set fib_2 = fib_res;
			set @counter = @counter + 1;
		end while;
	end if;
return fib_res;
end