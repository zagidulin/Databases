delimiter //
 
drop trigger if exists logging_users//
create trigger logging_users after insert on users
for each row
begin
	insert into logs (table_name, primary_key_id, name) values
	('users', new.id, new.name);
end//

drop trigger if exists logging_catalogs//
create trigger logging_catalogs after insert on catalogs
for each row
begin
	insert into logs (table_name, primary_key_id, name) values
	('catalogs', new.id, new.name);
end//

drop trigger if exists logging_products//
create trigger logging_products after insert on products
for each row
begin
	insert into logs (table_name, primary_key_id, name) values
	('products', new.id, new.name);
end//

delimiter ;