-- задание 1. Смог реализовать только с помощью временной дополнительной таблицы.

drop table if exists talks_temp;
create table talks_temp
	select from_user_id as 'user_id', count(*) as 'total_messages' FROM messages WHERE to_user_id = 1 and from_user_id in (
		SELECT target_user_id FROM friend_requests WHERE (initiator_user_id = 1) AND status='approved')	or from_user_id in (
		SELECT initiator_user_id FROM friend_requests WHERE (target_user_id = 1) AND status='approved') group by from_user_id
	union all
	select to_user_id as 'user_id', count(*) as 'total_messages' FROM messages WHERE from_user_id = 1 and to_user_id in (
		SELECT target_user_id FROM friend_requests WHERE (initiator_user_id = 1) AND status='approved')	or to_user_id in (
		SELECT initiator_user_id FROM friend_requests WHERE (target_user_id = 1) AND status='approved')
	group by to_user_id;

select user_id, sum(total_messages) as total_messages from talks_temp group by user_id order by total_messages desc limit 1;



-- задание 2
-- Подсчитать общее количество лайков, которые получили пользователи младше 10 лет.


select count(*) from likes where media_id in (
	select id from media where user_id in (
		select user_id from profiles where birthday>DATE_SUB(CURDATE(),Interval 10 YEAR)
));

-- задание 3. Определить кто больше поставил лайков (всего) - мужчины или женщины?

select
	(select count(*) as female_likes from likes where user_id in (select user_id from profiles where gender='f')) as female_likes,
	(select count(*) as male_likes from likes where user_id in (select user_id from profiles where gender='m')) as male_likes
;

