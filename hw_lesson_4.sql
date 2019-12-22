select distinct firstname
from users
order by firstname desc;

update `profiles`
set
	is_active = 1
where
	birthday>DATE_SUB(CURDATE(),Interval 18 YEAR);
	
delete from messages
where created_at>curdate();