DROP DATABASE IF EXISTS soccer;
CREATE DATABASE soccer;
USE soccer;

-- 1 ТАБЛИЦА пользователей
DROP TABLE IF EXISTS players;
CREATE TABLE players (
	id SERIAL PRIMARY KEY,
    firstname VARCHAR(50),
    lastname VARCHAR(50),
    email VARCHAR(120) UNIQUE,
    phone BIGINT UNSIGNED UNIQUE NOT NULL,
    INDEX players_phone_idx(phone),
    INDEX players_firstname_lastname_idx(firstname, lastname)
);

-- 2 ТАБЛИЦА профили игроков/пользователей
DROP TABLE IF EXISTS profiles;
CREATE TABLE profiles (
	player_id SERIAL PRIMARY KEY,
    homeland VARCHAR(50),
    native_language VARCHAR(50),
    birthday DATE,
	-- photo_id BIGINT UNSIGNED NULL,
    created_at DATETIME DEFAULT NOW(),
    FOREIGN KEY (player_id) REFERENCES players(id) ON UPDATE CASCADE ON DELETE RESTRICT
    -- FOREIGN KEY (photo_id) REFERENCES media(id)
);

-- 3 ТАБЛИЦА списки площадок
DROP TABLE IF EXISTS stadiums;
CREATE TABLE stadiums (
	id INT AUTO_INCREMENT UNIQUE PRIMARY KEY,
    address VARCHAR(50),
    photo_path VARCHAR(255) NOT NULL,
    max_players TINYINT UNSIGNED NOT NULL -- max количество игроков на поле
);


-- 4 ТАБЛИЦА со ценами участия 
DROP TABLE IF EXISTS tariffs;
CREATE TABLE tariffs (
    stadium_id INT,
    tarif_starts TIME NOT NULL,
    tarif_ends TIME NOT NULL,
    price DOUBLE(3,2) NOT NULL,
    FOREIGN KEY (stadium_id) REFERENCES stadiums(id),
    INDEX (stadium_id)
);


-- 5 ТАБЛИЦА с расписанием предстоящих игр (оно же предложение игр)
DROP TABLE IF EXISTS match_offer;
CREATE TABLE match_offer (
    id SERIAL PRIMARY KEY,
    stadium_id INT,
    start_time DATETIME NOT NULL,
    places TINYINT UNSIGNED, -- осталось дсотупных для записи мест
    FOREIGN KEY (stadium_id) REFERENCES stadiums(id),
    INDEX (stadium_id),
    INDEX (start_time)
);

-- ТРИГГЕР для автопроставления количества доступных мест на игру при изначальном заведении игры в расписании
delimiter //
 
DROP TRIGGER IF EXISTS places_available//
CREATE TRIGGER places_available BEFORE INSERT ON match_offer
FOR EACH ROW
BEGIN
	DECLARE available tinyint;
	SET available = (SELECT max_players FROM stadiums WHERE id = new.stadium_id); 
	SET new.places = COALESCE(new.places, available); 
END//

delimiter ;


-- 6 ТАБЛИЦА с играми и игроками, которые на них записались:
DROP TABLE IF EXISTS matches_players;
CREATE TABLE matches_players (
	match_id BIGINT UNSIGNED NOT NULL,
	player_id BIGINT UNSIGNED NOT NULL,
	-- INDEX (stadium_id), -- использовать при необходимости
	-- INDEX (matchtime), -- использовать при необходимости
	INDEX (match_id),
	INDEX (player_id),
	FOREIGN KEY (match_id) REFERENCES match_offer(id) ON UPDATE CASCADE ON DELETE CASCADE
	-- FOREIGN KEY (player_id) REFERENCES players(id) ON UPDATE CASCADE ON DELETE CASCADE    
);


-- 7 ТАБЛИЦА для хранения архивной информации о прошедших играх (заполняется ч/з хранимую процедуру)

CREATE TABLE IF NOT EXISTS match_history (
	match_time DATETIME,
	stad_addr VARCHAR(50),
	player_name VARCHAR(50),
	player_id BIGINT
) engine=archive DEFAULT charset=utf8;


-- 8 ТАБЛИЦА с типами медиафайлов
DROP TABLE IF EXISTS media_types;
CREATE TABLE media_types(
	id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    created_at DATETIME DEFAULT NOW()
);


-- 9 ТАБЛИЦА для хранения медиафалов (фото площадок, фото/видео с игр):
DROP TABLE IF EXISTS media;
CREATE TABLE media(
	id SERIAL PRIMARY KEY,
    media_type_id BIGINT UNSIGNED NOT NULL,
    match_id BIGINT UNSIGNED NOT NULL,
  	body TEXT,
    filename VARCHAR(255),
    `SIZE` INT,
	location VARCHAR(255) COMMENT 'Путь к файлу', 
    created_at DATETIME DEFAULT NOW(),
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
	INDEX (match_id),
    FOREIGN KEY (match_id) REFERENCES match_offer(id),
    FOREIGN KEY (media_type_id) REFERENCES media_types(id)
);


-- 10 ТАБЛИЦА с комментариями к фото/видео с игр
DROP TABLE IF EXISTS comments;
CREATE TABLE comments(
	id SERIAL PRIMARY KEY,
    player_id BIGINT UNSIGNED NOT NULL,
    media_id BIGINT UNSIGNED NOT NULL,
    comment_text TEXT,
    created_at DATETIME DEFAULT NOW(),
    FOREIGN KEY (player_id) REFERENCES players(id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (media_id) REFERENCES media(id)
);

-- 11 

CREATE TABLE IF NOT EXISTS logs (
	created_at DATETIME DEFAULT current_timestamp,
	player_id INT,
	player_lastname VARCHAR(50),
	player_phone BIGINT
) engine=archive default charset=utf8;


delimiter //

DROP TRIGGER IF EXISTS logging//
CREATE TRIGGER logging AFTER INSERT ON players
FOR EACH ROW
BEGIN
	DECLARE p_id INT;
	DECLARE l_name VARCHAR(50);
	DECLARE ph_num BIGINT;
	SET p_id = new.id;
	SET l_name = new.lastname;
	SET ph_num = new.phone;
	insert into logs (player_id, player_lastname, player_phone) values
	(p_id, l_name, ph_num);
end//

delimiter ;

-- ФУНКЦИЯ для подсчета свободных для записи мест при заданных № площадки и № предложения игр
delimiter //

DROP FUNCTION IF EXISTS free_places//
CREATE FUNCTION free_places(location tinyint, m_num bigint)
RETURNS tinyint NOT DETERMINISTIC
BEGIN
	DECLARE reg_pl, pl_left tinyint;
	SET reg_pl = (SELECT count(*) FROM matches_players WHERE match_id = m_num);
	SET pl_left = (SELECT max_players FROM stadiums WHERE id = location) - reg_pl;
	RETURN pl_left;
END//

delimiter ;

-- ТРИГГЕРЫ для измеения количества доступных мест при записи на игру или отмене записи 

delimiter //
 
DROP TRIGGER IF EXISTS register_to_match//
CREATE TRIGGER register_to_match AFTER INSERT ON matches_players
FOR EACH ROW
BEGIN
	DECLARE loc, places_left tinyint;
	SET loc = (SELECT stadium_id FROM match_offer WHERE id = new.match_id);
	SET places_left = (SELECT free_places(loc, new.match_id)); 
	UPDATE match_offer SET places = places_left WHERE id = new.match_id; 
END//

DROP TRIGGER IF EXISTS unregister_from_match//
CREATE TRIGGER unregister_from_match AFTER DELETE ON matches_players
FOR EACH ROW
BEGIN
	DECLARE loc, places_left tinyint;
	SET loc = (SELECT stadium_id FROM match_offer WHERE id = old.match_id);
	SET places_left = (SELECT free_places(loc, old.match_id)); 
	update match_offer SET places = places_left WHERE id = old.match_id; 
END//

delimiter ;


-- ТРИГГЕР для запрета пользователю записи на игру, время начала которой протеворичит предыдущим его записям 

delimiter //
 
DROP TRIGGER IF EXISTS reg_checking//
CREATE TRIGGER reg_checking before insert on matches_players
FOR EACH ROW
BEGIN
	DECLARE new_time, exist_time datetime;
	DECLARE is_end INT DEFAULT 0;
	DECLARE curmatch CURSOR FOR SELECT start_time FROM match_offer WHERE id IN (SELECT match_id FROM matches_players WHERE player_id = new.player_id);
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET is_end = 1;
	set new_time = (SELECT start_time FROM match_offer WHERE id = new.match_id);
	OPEN curmatch;
	cycle: LOOP
		FETCH curmatch INTO exist_time;
		IF is_end THEN 
			LEAVE cycle;
		ELSEIF new_time BETWEEN exist_time - INTERVAL 4 HOUR AND exist_time + INTERVAL 4 HOUR THEN
			SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT = 'Время матча противоречит другим Вашим записям';
		END IF;
	END LOOP cycle;
	CLOSE curmatch;
END //

delimiter ;


/* ПРОЦЕДУРА для переноса данных в архивную таблицу и удаления соответствующих
старых данных из используемых "оперативных" таблиц, т.к. хранение в них старых сведений не имеет смысла */
DELIMITER //
 
DROP PROCEDURE IF EXISTS saving_to_history//
CREATE PROCEDURE saving_to_history ()
BEGIN
	INSERT INTO match_history
		SELECT
			m.start_time,
			s.address,
			p.firstname,
			p.id
		FROM
			matches_players as mp 
		LEFT JOIN 
			match_offer AS m
		ON
			m.id = mp.match_id
		LEFT JOIN 
			stadiums AS s
		ON
			s.id = m.stadium_id
		LEFT JOIN
			players AS p
		ON
			p.id = mp.player_id
		WHERE m.start_time < NOW() - interval 4 week;
	DELETE FROM match_offer WHERE start_time < NOW() - interval 4 week;
END//

DELIMITER ;


-- ПРЕДСТАВЛЕНИЕ для отражения времени начала в ближайшие 10 дней игр и стоимости участия:

CREATE OR REPLACE VIEW schedule AS
SELECT
	s.address,
	DATE_FORMAT(m.start_time, '%d %M, %H:%i') AS `beginning time`,
	t.price,
	m.places as places_left
FROM
	stadiums AS s
RIGHT JOIN 
	match_offer AS m
ON
	s.id = m.stadium_id
LEFT JOIN 
	tariffs AS t
ON
	m.stadium_id = t.stadium_id AND TIME_FORMAT(m.start_time, '%H:%s:%S') >= t.tarif_starts
	AND TIME_FORMAT(m.start_time, '%H:%s:%S') <= t.tarif_ends
WHERE m.start_time BETWEEN NOW() AND NOW() + INTERVAL 10 DAY;


-- ПРЕДСТАВЛЕНИЕ, отображающее список предстоящих игр (с указанием площадки и времени) и игроков (имя, фамилия) записавшихся на них

CREATE OR REPLACE VIEW squads AS
SELECT
	m.start_time,
	s.address,
	p.firstname,
	p.lastname
FROM
	matches_players as mp 
LEFT JOIN 
	match_offer AS m
ON
	m.id = mp.match_id
LEFT JOIN 
	stadiums AS s
ON
	s.id = m.stadium_id
LEFT JOIN
	players AS p
ON
	p.id = mp.player_id
WHERE m.start_time > NOW();


INSERT INTO players (id, firstname, lastname, email, phone) VALUES
('1','Аdam', 'Givagala','Givagala87@yahoo.com','3519374071'),
('2','Elfrieda','Orn','lottie15@example.com','3517498180'),
('3','Kenton','Funk','effie.feest@example.org','3517498181'),
('4','Ewell','McCullough','mjenkins@example.org','3517498182'),
('5','Korbin','O\'Keefe','yazmin79@example.org','3517498184'),
('6','Devan','Christiansen','reilly.taylor@example.org','3517498185'),
('7','Vivienne','McDermott','guido79@example.org','3517498186'),
('8','Selmer','Altenwerth','klocko.laurine@example.net','3517498187'),
('9','Lisa','Wolf','berta33@example.net','3517498188'),
('10','Christina','Friesen','kevin47@example.org','3517498189'),
('11','Martina','Hegmann','alexandre96@example.org','3517498190'),
('12','Judson','Labadie','evelyn.beatty@example.com','3517498191'),
('13','Delbert','Rice','colton10@example.net','3517498192'),
('14','Collin','Lubowitz','gsporer@example.net','3517498193'),
('15','Monica','Crona','calista.pagac@example.org','3517498194'),
('16','Shanna','Krajcik','kon@example.org','3517498195'),
('17','Carmela','Keebler','cole.lilla@example.net','3517498196'),
('18','Justina','Spencer','bridgette.christiansen@example.net','3517498197'),
('19','Margaret','Kuhic','swaniawski.arthur@example.com','3517498198'),
('20','Brett','Goyette','maxwell.lehner@example.org','3517498199'),
('21','Bell','Braun','hegmann.heaven@example.net','3511498181'),
('22','Audrey','Boyer','phyllis.weissnat@example.net','3512498181'),
('23','Michel','Upton','pearlie57@example.net','3510498181'),
('24','Maye','Carroll','helmer.gottlieb@example.org','3513498181'),
('25','Clemens','Konopelski','casandra53@example.com','3514498181'),
('26','Dan','Ortiz','liliane.gottlieb@example.org','3515498181'),
('27','Jakob','Nader','maximus16@example.net','3516498181'),
('28','Marc','O\'Reilly','dharris@example.com','3518498181'),
('29','Rosalyn','Johnston','enos.effertz@example.org','3519498181'),
('30','Reed','Bosco','powlowski.golda@example.net','3511098181'),
('31','Quincy','Mitchell','vanessa95@example.net','3511198181'),
('32','Lorenzo','Sawayn','thaddeus.watsica@example.com','3511298181'),
('33','Cristobal','Kohler','rokuneva@example.com','3511398181'),
('34','Hildegard','Carroll','josefa.kautzer@example.com','3511598181'),
('35','Jerrell','Durgan','zglover@example.com','3511698181'),
('36','Caleb','Osinski','swaniawski.onie@example.org','3511798181'),
('37','Noah','Predovic','isabella.kuphal@example.net','3511898181'),
('38','Xander','Swaniawski','dcasper@example.net','3511998181'),
('39','Giovani','Monahan','jbartell@example.com','3511408181'),
('40','Madeline','Gusikowski','rvonrueden@example.net','3511418181'),
('41','Darren','Boyle','brant14@example.net','3511428181'),
('42','Madisyn','Wolf','hilll.dedric@example.com','3511438181'),
('43','Kenny','Morissette','swift.oswaldo@example.net','3517774345'),
('44','Alfonso','Kozey','brennon19@example.com','3511448181'),
('45','Brook','Rodriguez','tremblay.meagan@example.org','3512323932'),
('46','Felicity','Bayer','mathilde36@example.com','3511458181'),
('47','Noel','Pagac','fae62@example.net','3511468181'),
('48','Tommie','Harber','gleichner.paige@example.com','3511478181'),
('49','Keira','Schinner','virgie.mcdermott@example.com','3519362772'),
('50','Madaline','Bogan','cayla12@example.org','3511488181'),
('51','Fidel','Cole','Cole@example.com','3517101408'),
('52','Lorenzo','Brown','Brown@example.com','3511101408'),
('53','Cristobal','Black','Black@example.com','3511111408'),
('54','Hildegard','Gray','Gray@example.com','3511121408'),
('55','Jerrell','Donovan','Donovan@example.com','3511131408'),
('56','Leonel','Osinski','Osinski@example.org','3511141408'),
('57','Predrag','Predovic','Predovic@example.net','3511151408'),
('58','Isaak','Swaniawski','Swaniawski@example.net','3511161408'),
('59','Giovani','Newton','Newton@example.com','3511171408'),
('60','Ernst','Gusikowski','Gusikowski@example.net','3511181408'),
('61','Darren','Aranofski','Aranofski@example.net','3511191408'),
('62','Artem','Novak','Novak@example.com','3511101418'),
('63','Kenny','Moses','Moses@example.net','3511101428'),
('64','Kirill','Petrov','Petrov19@example.com','3511101438'),
('65','Brook','Rodriguez','Rodriguezzz@example.org','3511101448'),
('66','James','Bond','bond.james@example.com','3511101458'),
('67','Oliver','Kahn','fael83@example.net','3511101468'),
('68','Tommie','Hilfiger','tommy.gun@example.com','3511101478'),
('69','Keir','Schmidt','virgie@example.com','3511101488'),
('70','Carlos','Gonsales','cayla72@example.org','3511101498'),
('71','Fidel','Castro','castro_f@example.com','3511127503');


INSERT INTO profiles (player_id, homeland, native_language, birthday) VALUES
('1','germany','german','1978-01-18'),
('2','portugal','portugal','1994-11-06'),
('3','portugal','portugal','1985-11-27'),
('4','france','french','1994-04-12'),
('5','spain','spanish','1986-07-05'),
('6','spain','spanish','1981-06-20'),
('7','portugal','portugal','1987-06-21'),
('8','russia','russian','1978-08-18'),
('9','france','french','1991-09-29'),
('10','brazil','portugal','1980-03-17'),
('11','spain','spanish','1981-08-22'),
('12','russia','russian','1995-08-04'),
('13','brazil','portugal','1988-02-12'),
('14','france','french','1986-03-13'),
('15','spain','spanish','1983-08-13'),
('16','portugal','portugal','1989-09-08'),
('17','portugal','portugal','1992-10-29'),
('18','portugal','portugal','1981-08-22'),
('19','france','french','1983-08-17'),
('20','brazil','portugal','1988-02-11'),
('21','brazil','portugal','1982-09-21'),
('22','russia','russian','1987-03-15'),
('23','spain','spanish','1991-10-15'),
('24','portugal','portugal','1994-06-23'),
('25','portugal','portugal','1982-11-21'),
('26','brazil','portugal','1995-06-07'),
('27','spain','spanish','1992-03-18'),
('28','portugal','portugal','1983-06-16'),
('29','france','french','1988-02-09'),
('30','portugal','portugal','1977-03-09'),
('31','portugal','portugal','1978-01-31'),
('32','brazil','portugal','1995-11-19'),
('33','portugal','portugal','1991-11-21'),
('34','china','chinese','1981-08-17'),
('35','brazil','portugal','1991-07-07'),
('36','germany','german','1977-11-04'),
('37','spain','spanish','1984-11-25'),
('38','russia','russian','1990-04-29'),
('39','france','french','1979-09-18'),
('40','brazil','portugal','1986-10-03'),
('41','germany','german','1987-04-11'),
('42','portugal','portugal','1981-02-20'),
('43','brazil','portugal','1979-05-18'),
('44','england','russian','1987-09-01'),
('45','portugal','portugal','1985-04-02'),
('46','germany','german','1984-01-04'),
('47','spain','spanish','1992-08-24'),
('48','portugal','portugal','1992-12-01'),
('49','ukrain','russian','1984-10-23'),
('50','england','english','1984-01-17'),
('51','spain','spanish','1988-06-20'),
('52','spain','spanish','1986-09-23'),
('53','ukrain','russian','1982-08-02'),
('54','france','french','1993-09-21'),
('55','portugal','portugal','1984-07-07'),
('56','portugal','portugal','1984-10-13'),
('57','spain','spanish','1987-10-31'),
('58','italy','italian','2003-06-03'),
('59','spain','spanish','2015-11-19'),
('60','germany','german','1981-02-06'),
('61','portugal','portugal','1972-07-02'),
('62','russia','russian','1986-12-19'),
('63','russia','russian','1978-12-23'),
('64','russia','russian','1980-10-31'),
('65','germany','german','1981-10-15'),
('66','germany','german','1983-10-20'),
('67','spain','spanish','1990-01-23'),
('68','brazil','portugal','1992-04-29'),
('69','portugal','portugal','1987-02-12'),
('70','germany','german','1987-05-04'),
('71','brazil','portugal','1993-10-23');

INSERT INTO stadiums (address, photo_path, max_players) VALUES
('Rua Francisco de Oliveira, 1','a/b/c/stadium_1','16'),
('Avenida da Ilha da Madeira, 8', 'a/b/c/stadium_2', '14'),
('Rua Silva e Albuquerque, 29', 'a/b/c/stadium_3', '14'),
('Praça José Afonso, 13', 'a/b/c/stadium_4', '12'),
('Rua de São Pedro de Alcântara, 65', 'a/b/c/stadium_5', '12');


INSERT INTO tariffs (stadium_id, tarif_starts, tarif_ends, price) VALUES
	('1', '14:00:00', '17:59:59', '2.50'),
	('1', '18:00:00', '19:59:59', '3.00'),
	('1', '20:00:00', '23:59:59', '5.00'),
	('2', '14:00:00', '17:59:59', '3.00'),
	('2', '18:00:00', '19:59:59', '3.50'),
	('2', '20:00:00', '23:59:59', '4.50'),
	('3', '12:30:00', '18:29:59', '2.80'),
	('3', '18:30:00', '20:29:59', '3.50'),
	('3', '20:30:00', '00:29:59', '4.50'),
	('4', '13:30:00', '17:29:59', '3.00'),
	('4', '17:30:00', '21:29:59', '4.00'),
	('4', '21:30:00', '23:29:59', '3.50'),
	('5', '13:30:00', '17:29:59', '3.50'),
	('5', '17:30:00', '21:29:59', '4.50'),
	('5', '21:30:00', '23:29:59', '4.00');

INSERT INTO match_offer (stadium_id, start_time) VALUES 
(3,'2020-01-15 18:30:00')
,(2,'2020-01-15 20:00:00')
,(1,'2020-01-17 18:00:00')
,(1,'2020-01-17 20:00:00')
,(2,'2020-01-19 18:00:00')
,(2,'2020-01-20 20:00:00')
,(3,'2020-01-23 18:30:00')
,(3,'2020-01-23 20:30:00')
,(4,'2020-01-25 19:30:00')
,(5,'2020-01-25 21:30:00')
,(5,'2020-01-28 19:30:00')
,(4,'2020-01-28 21:30:00')
,(3,'2020-01-30 18:30:00')
,(2,'2020-01-30 20:00:00')
,(1,'2020-02-01 18:00:00')
,(1,'2020-02-01 20:00:00')
,(2,'2020-02-02 18:00:00')
,(2,'2020-02-02 20:00:00')
,(3,'2020-02-03 18:30:00')
,(3,'2020-02-03 20:30:00')
,(4,'2020-02-04 19:30:00')
,(5,'2020-02-04 21:30:00')
,(5,'2020-02-05 19:30:00')
,(4,'2020-02-05 21:30:00')
,(3,'2020-02-06 18:30:00')
,(2,'2020-02-06 20:00:00')
,(1,'2020-02-07 18:00:00')
,(1,'2020-02-07 20:00:00')
,(2,'2020-02-08 18:00:00')
,(2,'2020-02-10 20:00:00')
,(3,'2020-02-12 18:30:00')
,(3,'2020-02-12 20:30:00')
,(4,'2020-02-14 19:30:00')
,(5,'2020-02-15 21:30:00')
,(5,'2020-02-17 19:30:00')
,(4,'2020-02-17 21:30:00')
,(3,'2020-02-19 18:30:00')
,(2,'2020-02-20 20:00:00')
,(1,'2020-02-22 18:00:00')
,(1,'2020-02-22 20:00:00')
,(2,'2020-02-24 18:00:00')
,(2,'2020-02-25 20:00:00')
,(3,'2020-02-26 18:30:00')
,(3,'2020-02-26 20:30:00')
,(4,'2020-02-27 19:30:00')
,(5,'2020-02-27 21:30:00')
,(5,'2020-02-28 19:30:00')
,(4,'2020-02-28 21:30:00')
,(3,'2020-02-29 18:30:00')
,(2,'2020-02-29 20:00:00')
,(1, '2020-03-01 18:00:00')
,(1, '2020-03-01 20:00:00')
,(2, '2020-03-02 18:00:00')
,(2, '2020-03-03 20:00:00')
,(3, '2020-03-04 18:30:00')
,(3, '2020-03-04 20:30:00')
,(4, '2020-03-05 19:30:00')
,(5, '2020-03-05 21:30:00')
,(4, '2020-03-06 21:30:00')
,(5, '2020-03-06 19:30:00')
,(3, '2020-03-07 18:30:00')
,(2, '2020-03-07 20:00:00')
,(1, '2020-03-08 18:00:00')
,(1, '2020-03-08 20:00:00')
,(2, '2020-03-09 18:00:00')
,(2, '2020-03-10 20:00:00')
,(3, '2020-03-11 18:30:00')
,(3, '2020-03-11 20:30:00')
,(4, '2020-03-12 19:30:00')
,(5, '2020-03-12 21:30:00')
,(4, '2020-03-13 21:30:00')
,(5, '2020-03-13 19:30:00')
,(3, '2020-03-14 18:30:00')
,(2, '2020-03-14 20:00:00');


INSERT INTO matches_players (match_id,player_id) VALUES 
(1,1)
,(1,3)
,(1,5)
,(1,7)
,(1,9)
,(1,11)
,(1,13)
,(1,15)
,(1,17)
,(1,19)
,(1,21)
,(1,23)
,(1,25)
,(1,27)
,(2,29)
,(2,31)
,(2,2)
,(2,4)
,(2,6)
,(2,8)
,(2,10)
,(2,12)
,(2,14)
,(2,16)
,(2,18)
,(2,20)
,(2,22)
,(2,24)
,(3,71)
,(3,69)
,(3,67)
,(3,65)
,(3,63)
,(3,61)
,(3,59)
,(3,57)
,(3,55)
,(3,53)
,(3,70)
,(3,68)
,(3,66)
,(3,64)
,(3,62)
,(3,60)
,(4,58)
,(4,56)
,(4,54)
,(4,52)
,(4,50)
,(4,48)
,(4,46)
,(4,44)
,(4,42)
,(4,40)
,(4,33)
,(4,35)
,(4,37)
,(4,39)
,(4,41)
,(4,43)
,(5,45)
,(5,47)
,(5,49)
,(5,51)
,(5,53)
,(5,2)
,(5,4)
,(5,6)
,(5,26)
,(5,28)
,(5,30)
,(5,32)
,(5,34)
,(5,36)
,(6,38)
,(6,1)
,(6,3)
,(6,5)
,(6,7)
,(6,9)
,(6,11)
,(6,13)
,(6,15)
,(6,17)
,(6,8)
,(6,10)
,(6,12)
,(6,14)
,(7,16)
,(7,18) 
,(7,20)
,(7,22)
,(7,24)
,(7,71)
,(7,69)
,(7,67)
,(7,65)
,(7,63)
,(7,61)
,(7,59) 
,(7,57)
,(7,55)
,(8,1)
,(8,3)
,(8,5)
,(8,7)
,(8,9)
,(8,11)
,(8,13)
,(8,15)
,(8,17)
,(8,19)
,(8,21)
,(8,23)
,(8,25)
,(8,27)
,(9,71)
,(9,69)
,(9,67)
,(9,65)
,(9,63)
,(9,61)
,(9,59)
,(9,57)
,(9,55)
,(9,53)
,(9,70)
,(9,68)
,(10,54)
,(10,52)
,(10,50)
,(10,48)
,(10,46)
,(10,44)
,(10,42)
,(10,40)
,(10,33)
,(10,35)
,(10,37)
,(10,39)
,(11,26)
,(11,28)
,(11,30)
,(11,32)
,(11,34)
,(11,36)
,(11,38)
,(11,1)
,(11,3)
,(11,5)
,(11,7)
,(11,9)
,(12,49)
,(12,51)
,(12,53)
,(12,2)
,(12,4)
,(12,6)
,(12,13)
,(12,15)
,(12,17)
,(12,8)
,(12,10)
,(12,12)
,(13,1)
,(13,3)
,(13,5)
,(13,7)
,(13,9)
,(13,11)
,(13,13)
,(13,15)
,(13,17)
,(13,19)
,(13,21)
,(13,23)
,(13,25)
,(13,27)
,(14,29)
,(14,31)
,(14,2)
,(14,4)
,(14,6)
,(14,8)
,(14,10)
,(14,12)
,(14,14)
,(14,16)
,(14,18)
,(14,20)
,(14,22)
,(14,24)
,(15,71)
,(15,69)
,(15,67)
,(15,65)
,(15,63)
,(15,61)
,(15,59)
,(15,57)
,(15,55)
,(15,53)
,(15,70)
,(15,68)
,(15,66)
,(15,64)
,(15,62)
,(15,60)
,(16,58)
,(16,56)
,(16,54)
,(16,52)
,(16,50)
,(16,48)
,(16,46)
,(16,44)
,(16,42)
,(16,40)
,(16,33)
,(16,35)
,(16,37)
,(16,39)
,(16,41)
,(16,43)
,(17,45)
,(17,47)
,(17,49)
,(17,51)
,(17,53)
,(17,2)
,(17,4)
,(17,6)
,(17,26)
,(17,28)
,(17,30)
,(17,32)
,(17,34)
,(17,36)
,(18,38)
,(18,1)
,(18,3)
,(18,5)
,(18,7)
,(18,9)
,(18,11)
,(18,13)
,(18,15)
,(18,17)
,(18,8)
,(18,10)
,(18,12)
,(18,14)
,(19,16)
,(19,18)
,(19,20)
,(19,22)
,(19,24)
,(19,71)
,(19,69)
,(19,67)
,(19,65)
,(19,63)
,(19,61)
,(19,59)
,(19,57)
,(19,55)
,(20,1)
,(20,3)
,(20,5)
,(20,7)
,(20,9)
,(20,11)
,(20,13)
,(20,15)
,(20,17)
,(20,19)
,(20,21)
,(20,23)
,(20,25)
,(20,27)
,(21,71)
,(21,69)
,(21,67)
,(21,65)
,(21,63)
,(21,61)
,(21,59)
,(21,57)
,(21,55)
,(21,53)
,(21,70)
,(21,68)
,(22,54)
,(22,52)
,(22,50)
,(22,48)
,(22,46)
,(22,44)
,(22,42)
,(22,40)
,(22,33)
,(22,35)
,(22,37)
,(22,39)
,(23,26)
,(23,28)
,(23,30)
,(23,32)
,(23,34)
,(23,36)
,(23,38)
,(23,1)
,(23,3)
,(23,5)
,(23,7)
,(23,9)
,(24,49)
,(24,51)
,(24,53)
,(24,2)
,(24,4)
,(24,6)
,(24,13)
,(24,15)
,(24,17)
,(24,8)
,(24,10)
,(24,12)
,(25,1)
,(25,3)
,(25,5)
,(25,7)
,(25,9)
,(25,11)
,(25,13)
,(25,15)
,(25,17)
,(25,19)
,(25,21)
,(25,23)
,(25,25)
,(25,27)
,(26,29)
,(26,31)
,(26,2)
,(26,4)
,(26,6)
,(26,8)
,(26,10)
,(26,12)
,(26,14)
,(26,16)
,(26,18)
,(26,20)
,(26,22)
,(26,24)
,(27,71)
,(27,69)
,(27,67)
,(27,65)
,(27,63)
,(27,61)
,(27,59)
,(27,57)
,(27,55)
,(27,53)
,(27,70)
,(27,68)
,(27,66)
,(27,64)
,(27,62)
,(27,60)
,(28,58)
,(28,56)
,(28,54)
,(28,52)
,(28,50)
,(28,48)
,(28,46)
,(28,44)
,(28,42)
,(28,40)
,(28,33)
,(28,35)
,(28,37)
,(28,39)
,(28,41)
,(28,43)
,(29,45)
,(29,47)
,(29,49)
,(29,51)
,(29,53)
,(29,2)
,(29,4)
,(29,6)
,(29,26)
,(29,28)
,(29,30)
,(29,32)
,(29,34)
,(29,36)
,(30,38)
,(30,1)
,(30,3)
,(30,9)
,(30,11)
,(30,13)
,(30,15)
,(30,17)
,(30,8)
,(30,10)
,(30,14)
,(31,18)
,(31,20)
,(31,22)
,(31,24)
,(31,67)
,(31,65)
,(31,63)
,(31,61)
,(31,59)
,(31,55)
,(32,1)
,(32,11)
,(32,13)
,(32,15)
,(32,17)
,(32,19)
,(32,21)
,(32,27)
,(33,71)
,(33,69)
,(33,67)
,(33,57)
,(33,55)
,(33,53)
,(34,46)
,(34,42)
,(34,40)
,(34,33)
,(34,35)
,(34,37)
,(35,26)
,(35,28)
,(35,30)
,(35,9)
,(36,13)
,(36,10)
,(36,12)
,(37,10)
,(38,12)
,(39,1)
,(40,3);

SELECT * FROM schedule;
SELECT * FROM squads;

-- ЗАПРОС для подсчета количества зарегистрированных пользователей из разных стран
SELECT homeland, count(*) AS total FROM profiles
GROUP BY homeland ORDER BY total DESC;

-- ЗАПРОС частоты записи игроками на игры за последние 3 недели
SELECT
	mp.player_id,
	p.lastname,
	count(*) AS times
FROM matches_players AS mp
LEFT JOIN
	players AS p
ON
	p.id = mp.player_id
LEFT join
	match_offer AS m
ON
	mp.match_id = m.id
WHERE m.start_time BETWEEN NOW() - INTERVAL 2 WEEK AND NOW() 
GROUP BY mp.player_id ORDER BY count(*) DESC;

-- ЗАПРОС id 10 игроков, которые за последние три недели принимали участие в матчах с заданным игроком и частоты "пересечений"
select player_id, count(*) from matches_players where match_id in
(select match_id from matches_players where player_id = 17) and
match_id in (select id from match_offer where start_time between NOW() - interval 3 week and NOW())
group by player_id order by count(*) desc limit 10;


