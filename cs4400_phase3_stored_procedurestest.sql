-- CS4400: Introduction to Database Systems: Monday, July 1, 2024
-- Simple Cruise Management System Course Project Stored Procedures [TEMPLATE] (v0)
-- Views, Functions & Stored Procedures

/* This is a standard preamble for most of our scripts.  The intent is to establish
a consistent environment for the database behavior. */
set global transaction isolation level serializable;
set global SQL_MODE = 'ANSI,TRADITIONAL';
set names utf8mb4;
set SQL_SAFE_UPDATES = 0;

set @thisDatabase = 'cruise_tracking';
use cruise_tracking;
-- -----------------------------------------------------------------------------
-- stored procedures and views
-- -----------------------------------------------------------------------------
/* Standard Procedure: If one or more of the necessary conditions for a procedure to
be executed is false, then simply have the procedure halt execution without changing
the database state. Do NOT display any error messages, etc. */

-- [_] supporting functions, views and stored procedures
-- -----------------------------------------------------------------------------
/* Helpful library capabilities to simplify the implementation of the required
views and procedures. */
-- -----------------------------------------------------------------------------
drop function if exists leg_time;
delimiter //
create function leg_time (ip_distance integer, ip_speed integer)
	returns time reads sql data
begin
	declare total_time decimal(10,2);
    declare hours, minutes int default 0;
    set total_time = truncate(ip_distance / ip_speed, 2);
    set hours = floor(truncate(total_time, 0));
    set minutes = floor(truncate((total_time - hours) * 60, 0));
    return maketime(hours, minutes, 0);
end //
delimiter ;

-- [1] add_ship()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new ship.  A new ship must be sponsored
by an existing cruiseline, and must have a unique name for that cruiseline. 
A ship must also have a non-zero seat capacity and speed. A ship
might also have other factors depending on it's type, like paddles or some number
of lifeboats.  Finally, a ship must have a new and database-wide unique location
since it will be used to carry passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_ship;
delimiter //
create procedure add_ship (in ip_cruiselineID varchar(50), in ip_ship_name varchar(50),
	in ip_max_capacity integer, in ip_speed integer, in ip_locationID varchar(50),
    in ip_ship_type varchar(100), in ip_uses_paddles boolean, in ip_lifeboats integer)
sp_main: begin
    if ip_ship_name in (select ship_name from ship) then leave sp_main; end if;
    if ip_cruiselineID not in (select cruiselineID from cruiseline) then leave sp_main; end if;
    if ip_max_capacity = 0 then leave sp_main; end if;
    if ip_locationID in (select locationID from location) then leave sp_main; end if;
    insert into location values (ip_locationID);
    insert into ship values (ip_cruiselineID, ip_ship_name, ip_max_capacity, ip_speed, ip_locationID, ip_ship_type, 
    ip_uses_paddles, ip_lifeboats);
end //
delimiter ;

-- [2] add_port()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new port.  A new port must have a unique
identifier along with a new and database-wide unique location if it will be used
to support ship arrivals and departures.  A port may have a longer, more
descriptive name.  An airport must also have a city, state, and country designation. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_port;
delimiter //
create procedure add_port (in ip_portID char(3), in ip_port_name varchar(200),
    in ip_city varchar(100), in ip_state varchar(100), in ip_country char(3), in ip_locationID varchar(50))
sp_main: begin
	DECLARE v_locationCount INT;
	declare v_portCount int;
    -- Check if the portID is unique
    SELECT COUNT(*)
    INTO v_portCount
    FROM Ship_port
    WHERE portID = ip_portID;

    IF exists (select portID from ship_port where portID = ip_portID) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Port ID already exists.';
	ELSEIF exists (select locationID from location where locationID = ip_locationID) THEN
		SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Location ID already exists.';
	ELSE
		insert into location values (ip_locationID);
        insert into ship_port values (ip_portID, ip_port_name, ip_city, ip_state, ip_country, ip_locationID);
    END IF;

    -- Check if the locationID is unique
    SELECT COUNT(*)
    INTO v_locationCount
    FROM Ship_port
    WHERE locationID = ip_locationID;

END//
delimiter ;


-- [3] add_person()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new person.  A new person must reference a unique
identifier along with a database-wide unique location used to determine where the
person is currently located: either at a port, on a ship, or both, at any given
time.  A person must have a first name, and might also have a last name.

A person can hold a crew role or a passenger role (exclusively).  As crew,
a person must have a tax identifier to receive pay, and an experience level.  As a
passenger, a person will have some amount of rewards miles, along with a
certain amount of funds needed to purchase cruise packages. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_person;
delimiter //
create procedure add_person (in ip_personID varchar(50), in ip_first_name varchar(100),
    in ip_last_name varchar(100), in ip_locationID varchar(50), in ip_taxID varchar(50),
    in ip_experience integer, in ip_miles integer, in ip_funds integer)
sp_main: begin
	if ip_personID in (select personID from person) then leave sp_main; end if;
    if ip_locationID not in (select locationID from location) then leave sp_main; end if;
    insert into person (personID, first_name, last_name) values (ip_personID, ip_first_name, ip_last_name);
    insert into person_occupies (personID, locationID) values (ip_personID, ip_locationID);
    if ip_taxID is not NULL then insert into crew(personID, taxID, experience, assigned_to)
    values (ip_personID, ip_taxID, ip_experience, NULL); end if;
    if ip_taxID is NULL then insert into passenger(personID, miles, funds)
    values (ip_personID, ip_miles, ip_funds); end if;
end //
delimiter ;

-- [4] grant_or_revoke_crew_license()
-- -----------------------------------------------------------------------------
/* This stored procedure inverts the status of a crew member's license.  If the license
doesn't exist, it must be created; and, if it already exists, then it must be removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists grant_or_revoke_crew_license;
delimiter //
create procedure grant_or_revoke_crew_license (in ip_personID varchar(50), in ip_license varchar(100))
sp_main: begin
declare license_count int default 0;
declare crew_exists int default 0;
if ip_personID is not null and ip_license is not null then
select count(*) into crew_exists from crew where personID = ip_personID;
if crew_exists > 0 then select count(*) into license_count from licenses
where personID = ip_personID and license = ip_license;
if license_count > 0 then delete from licenses where personID = ip_personID and license = ip_license;
else insert into licenses (personID, license) values (ip_personID, ip_license);
end if;
end if;
end if;	
end //
delimiter ;

-- [5] offer_cruise()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new cruise.  The cruise can be defined before
a ship has been assigned for support, but it must have a valid route.  And
the ship, if designated, must not be in use by another cruise.  The cruise
can be started at any valid location along the route except for the final stop,
and it will begin docked.  You must also include when the cruise will
depart along with its cost. */
-- -----------------------------------------------------------------------------
drop procedure if exists offer_cruise;
delimiter //
create procedure offer_cruise (in ip_cruiseID varchar(50), in ip_routeID varchar(50),
    in ip_support_cruiseline varchar(50), in ip_support_ship_name varchar(50), in ip_progress integer,
    in ip_next_time time, in ip_cost integer) 
sp_main: begin
    declare totallegs INT;
    declare ship_status varchar(50);
    declare locationofship varchar(50);
    declare progress INT;
	if ip_routeID not in (select routeID from route) then leave sp_main; end if;
    if ip_support_ship_name is not NUll and ip_support_ship_name in (select support_ship_name from cruise) then leave sp_main; end if;
    select count(*) from route_path where route_path.routeID = ip_routeID into totallegs;
    select locationID from ship where ip_support_ship_name = ship.ship_name into locationofship;
    if locationofship not in (select locationID from location) or totallegs = ip_progress then leave sp_main; end if; # count of rows in route_path with same route_ID = ip_progress
	set ship_status = 'docked';
    insert into cruise values (ip_cruiseID, ip_routeID, ip_support_cruiseline, ip_support_ship_name, ip_progress, ship_status, ip_next_time, ip_cost);
end //
delimiter ;

-- [6] cruise_arriving()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a cruise arriving at the next port
along its route.  The status should be updated, and the next_time for the cruise 
should be moved 8 hours into the future to allow for the passengers to disembark 
and sight-see for the next leg of travel.  Also, the crew of the cruise should receive 
increased experience, and the passengers should have their rewards miles updated. 
Everyone on the cruise must also have their locations updated to include the port of 
arrival as one of their locations, (as per the scenario description, a person's location 
when the ship docks includes the ship they are on, and the port they are docked at). */
-- -----------------------------------------------------------------------------
drop procedure if exists cruise_arriving;
delimiter //
create procedure cruise_arriving (in ip_cruiseID varchar(50))
sp_main: begin
	
	declare nextPortID varchar(50);
    declare currentlegID varchar(50);
    declare distance int;
	
    update cruise set ship_status = 'docked', next_time = DATE_ADD(next_time, interval 8 hour)  
    where cruiseID = ip_cruiseID;
	
    update crew set experience = experience + 1 where ip_cruiseID = assigned_to;
    select leg.legID, leg.distance into currentlegID, distance from cruise join route_path on cruise.routeID = route_path.routeID join leg on leg.legID = route_path.legID 
    where cruiseID = ip_cruiseID 
    and sequence = (select progress from cruise where cruiseID = ip_cruiseID);
    
	update passenger set miles = miles + distance 
    where personID in (select personID from passenger_books where cruiseID = ip_cruiseID);
    
    select ship_port.locationID into nextPortID from leg join ship_port on arrival = portID where legID = currentlegID;
    
    if nextPortID is null then leave sp_main; end if;

	insert into person_occupies (personID, locationID) select personID, nextPortID from passenger_books where cruiseID = ip_cruiseID;
    
    insert into person_occupies (personID, locationID) select personID, nextPortID from crew where assigned_to = ip_cruiseID;
end //
delimiter ;


-- [7] cruise_departing()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a cruise departing from its current
port towards the next port along its route.  The time for the next leg of
the cruise must be calculated based on the distance and the speed of the ship. The progress
of the ship must also be incremented on a successful departure, and the status must be updated.
We must also ensure that everyone, (crew and passengers), are back on board. 
If the cruise cannot depart because of missing people, then the cruise must be delayed 
for 30 minutes. You must also update the locations of all the people on that cruise,
so that their location is no longer connected to the port the cruise departed from, 
(as per the scenario description, a person's location when the ship sets sails only includes 
the ship they are on and not the port of departure). */
-- -----------------------------------------------------------------------------
drop procedure if exists cruise_departing;
delimiter //
create procedure cruise_departing (in ip_cruiseID varchar(50))
sp_main: begin

declare travelTime decimal(5, 2);
declare currentPort varchar(50);
declare nextPort varchar(50);
declare shipDistance decimal(5, 2);
declare shipSpeed decimal(5, 2);
declare missingCrewCount int;
declare missingPassengerCount int;
declare thisShipID varchar(50);

select departure, arrival, distance, speed into currentPort, nextPort, shipDistance, shipSpeed
from cruise join route_path on cruise.routeID = route_path.routeID and sequence = progress
join leg on route_path.legID = leg.legID
join ship on support_ship_name = ship_name
where cruiseID = ip_cruiseID;

select locationID into thisShipID from ship 
join cruise on support_ship_name = ship_name 
where cruiseID = ip_cruiseID;

# time calculated to get there based on distance and speed
set travelTime = shipDistance / shipSpeed;
update cruise set next_time = DATE_ADD(next_time, interval travelTime hour);

# progress incremeted when departed
update cruise set progress = progress + 1 where cruiseID = ip_cruiseID;

# status updated to sailing
update cruise set ship_status = 'sailing' where cruiseID = ip_cruiseID;

# ensure all crew and passengers have location on ship
select count(*) into missingCrewCount from crew where assigned_to = ip_cruiseID 
and personID not in (select personID from person_occupies where locationID = thisShipID);

select count(*) into missingPassengerCount from passenger_books 
join person_occupies on passenger_books.personID = person_occupies.personID 
where passenger_books.cruiseID = ip_cruiseID and passenger_books.personID not in (select personID from person_occupies where locationID = thisShipID);

if missingCrewCount + missingPassengerCount > 0 then
	update cruise set next_time = DATE_ADD(next_time, interval 0.5 hour);
end if;

# delete person location from the port -- only location is the ship
delete from person_occupies where locationID in (select locationID from ship_port where portID = currentPort) and personID in (select personID from person_occupies where locationID = currentPort);

end //
delimiter ;
-- [8] person_boards()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the location for people, (crew and passengers), 
getting on a in-progress cruise at its current port.  The person must be at the same port as the cruise,
and that person must either have booked that cruise as a passenger or been assigned
to it as a crew member. The person's location cannot already be assigned to the ship
they are boarding. After running the procedure, the person will still be assigned to the port location, 
but they will also be assigned to the ship location. */
-- -----------------------------------------------------------------------------
drop procedure if exists person_boards;
delimiter //
create procedure person_boards (in ip_personID varchar(50), in ip_cruiseID varchar(50))
sp_main: begin
	declare ship_location varchar(50);
    select ship.locationID into ship_location from ship join cruise on cruiselineID = support_cruiseline 
    and ship_name = support_ship_name where cruise.cruiseID = ip_cruiseID;
	if (select locationID from person_occupies where personID = ip_personID) like '%ship%'
    then leave sp_main; end if;
    if (select locationID from person_occupies where personID = ip_personID) !=
    (select locationID from ship_port join leg on portID = departure natural join route_path
    natural join cruise where cruiseID = ip_cruiseID and route_path.sequence = cruise.progress)
    then leave sp_main; end if;
	if (ip_personID, ip_cruiseID) not in (select personID, cruiseID from passenger_books) then leave sp_main; end if;
    if (ip_personID, ip_cruiseID) not in (select personID, assigned_to from crew) then leave sp_main; end if;
    if (ip_personID, ship_location) in (select personID, locationID from person_occupies) then leave sp_main; end if;
    insert into person_occupies (personID, locationID) values (ip_personID, ship_location);
end //
delimiter ;

-- [9] person_disembarks()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the location for people, (crew and passengers), , 
getting off a cruise at its current port.  The person must be on the ship supporting 
the cruise, and the cruise must be docked at a port. The person should no longer be
assigned to the ship location, and they will only be assigned to the port location. */
-- -----------------------------------------------------------------------------
drop procedure if exists person_disembarks;
delimiter //
create procedure person_disembarks (in ip_personID varchar(50), in ip_cruiseID varchar(50))
sp_main: begin
	# make sure status of ship is docked
    if (select ship_status from cruise where cruiseID = ip_cruiseID) = 'docked' then
	if ip_personID in (select personID from crew join cruise on assigned_to = cruise.cruiseID join ship on support_ship_name = ship_name) then
			delete from person_occupies where personID = ip_personID and locationID like 'ship%';
	elseif ip_personID in (select personID from passenger_books join cruise on passenger_books.cruiseID = cruise.cruiseID join
        ship on support_ship_name = ship_name) then
			delete from person_occupies where personID = ip_personID and locationID like 'ship%';
	end if;
end if;

end //
delimiter ;

-- [10] assign_crew()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a crew member as part of the cruise crew for a given
cruise.  The crew member being assigned must have a license for that type of ship,
and must be at the same location as the cruise's first port. Also, the cruise must not 
already be in progress. Also, a crew member can only support one cruise (i.e. one ship) at a time. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_crew;
delimiter //
create procedure assign_crew (in ip_cruiseID varchar(50), ip_personID varchar(50))
sp_main: begin

end //
delimiter ;

-- [11] recycle_crew()
-- -----------------------------------------------------------------------------
/* This stored procedure releases the crew assignments for a given cruise. The
cruise must have ended, and all passengers must have disembarked. */
-- -----------------------------------------------------------------------------
drop procedure if exists recycle_crew;
delimiter //
create procedure recycle_crew (in ip_cruiseID varchar(50))
sp_main: begin
	if (select ship_status from cruise where cruiseID = ip_cruiseID) = 'docked' and
	(select progress from cruise where cruiseID = ip_cruiseID) = 
    (select max(sequence) from route_path where route_path.routeID = 
    (select routeID from cruise where cruise.cruiseID = ip_cruiseID)) and
    (select count(*) from person_occupies join passenger on person_occupies.personID = passenger.personID
	where locationID = (select locationID from ship join cruise on support_cruiseline = cruiselineID and
    support_ship_name = ship_name where cruiseID = ip_cruiseID)) = 0 then
    update crew set assigned_to = NULL where assigned_to = ip_cruiseID; end if;
end //
delimiter ;

-- [12] retire_cruise()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a cruise that has ended from the system.  The
cruise must be docked, and either be at the start its route, or at the
end of its route.  And the cruise must be empty - no crew or passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists retire_cruise;
delimiter //
create procedure retire_cruise (in ip_cruiseID varchar(50))
sp_main: begin
    declare cruiseStatus varchar(100);
    declare cruiseProgress int;
    declare totalLegs int;
    declare onboardCrewCount int;
    declare onboardPassengerCount int;
    select ship_status, progress into cruiseStatus, cruiseProgress from cruise
    where cruiseID = ip_cruiseID;
    if cruiseStatus = 'docked' then select count(*) into totalLegs from route_path rp
        join cruise c on rp.routeID = c.routeID
        where c.cruiseID = ip_cruiseID;
        if cruiseProgress = 0 or cruiseProgress = totalLegs then select count(*) into onboardCrewCount from crew
            where assigned_to = ip_cruiseID;
            select count(*) into onboardPassengerCount from passenger_books where cruiseID = ip_cruiseID;
            if onboardCrewCount = 0 and onboardPassengerCount = 0 then
                delete from cruise where cruiseID = ip_cruiseID;
            end if;
        end if;
    end if;
end //
delimiter ;

-- [13] cruises_at_sea()
-- -----------------------------------------------------------------------------
/* This view describes where cruises that are currently sailing are located. */
-- -----------------------------------------------------------------------------
create or replace view cruises_at_sea (departing_from, arriving_at, num_cruises,
	cruise_list, earliest_arrival, latest_arrival, ship_list) as
select departure as departing_from, arrival as arriving_at, count(distinct cruise.cruiseID)
as num_cruises, group_concat(distinct cruise.cruiseID order by cruise.cruiseID separator ','),
min(next_time), max(next_time), group_concat(distinct
ship.locationID) from cruise join route_path on cruise.routeID = route_path.routeID and route_path.sequence
= cruise.progress join leg on route_path.legID = leg.legID join ship on 
cruise.support_cruiseline = ship.cruiselineID and cruise.support_ship_name = 
ship.ship_name where cruise.ship_status = 'sailing' group by departure,arrival;


-- [14] cruises_docked()
-- -----------------------------------------------------------------------------
/* This view describes where cruises that are currently docked are located. */
-- -----------------------------------------------------------------------------
create or replace view cruises_docked(departing_from, num_cruises, cruise_list, earliest_departure, 
latest_departure, ship_list) AS

select 
    departure as departing_from, 
    count(distinct cruise.cruiseID) as num_cruises,
    GROUP_CONCAT(distinct cruise.cruiseID order by cruise.cruiseID SEPARATOR ',') as cruise_list,
    min(next_time) as earliest_departure,
    max(next_time) as latest_departure,
    GROUP_CONCAT(distinct ship.locationID) as ship_list
from 
    cruise 
join 
    route_path on cruise.routeID = route_path.routeID 
    and route_path.sequence = cruise.progress + 1
join 
    leg on route_path.legID = leg.legID 
join 
    ship on cruise.support_cruiseline = ship.cruiselineID 
    and cruise.support_ship_name = ship.ship_name
where 
    cruise.ship_status = 'docked'
group by 
    departure;

-- [15] people_at_sea()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently at sea are located. */
-- -----------------------------------------------------------------------------
create or replace view people_at_sea (departing_from, arriving_at, num_ships, ship_list, cruise_list, 
    earliest_arrival, latest_arrival, num_crew, num_passengers, num_people, person_list) as
select leg.departure as departing_from, leg.arrival as arriving_at, count(distinct ship.locationID) as num_ships,
    GROUP_CONCAT(distinct ship.locationID separator ',') as ship_list, GROUP_CONCAT(distinct cruise.cruiseID separator ',') as cruise_list,
    min(cruise.next_time) as earliest_arrival, max(cruise.next_time) as latest_arrival,
    count(distinct crew.personID) as num_crew, count(distinct passenger.personID) as num_passengers,
    count(distinct person_occupies.personID) as num_people,
    GROUP_CONCAT(distinct person_occupies.personID order by cast(substring(person_occupies.personID,2) as unsigned)) as person_list
from cruise join ship on cruise.support_cruiseline = ship.cruiselineID and cruise.support_ship_name = ship.ship_name 
    join route_path on cruise.routeID = route_path.routeID and route_path.sequence = cruise.progress 
    join leg on route_path.legID = leg.legID join person_occupies on ship.locationID = person_occupies.locationID 
    left join crew on person_occupies.personID = crew.personID and crew.assigned_to = cruise.cruiseID 
    left join passenger on person_occupies.personID = passenger.personID and passenger.personID in (select passenger_books.personID from passenger_books where passenger_books.cruiseID = cruise.cruiseID) 
where cruise.ship_status = 'sailing'
group by leg.departure, leg.arrival;


-- [16] people_docked()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently docked are located. */
-- -----------------------------------------------------------------------------
create or replace view people_docked (departing_from, ship_port, port_name,
	city, state, country, num_crew, num_passengers, num_people, person_list) as
select portID, ship_port.locationID, port_name, city, state, country, count(distinct crew.personID), count( distinct passenger.personID),count(person_occupies.personID),
GROUP_CONCAT(distinct person_occupies.personID order by cast(substring(person_occupies.personID,2) as unsigned )  separator ',') from ship_port join person_occupies 
on person_occupies.locationID = ship_port.locationID left join crew on crew.personID = person_occupies.personID left join passenger on passenger.personID = 
person_occupies.personID join cruise  on crew.assigned_to = cruise.cruiseID or passenger.personID in (select passenger_books.personID from passenger_books where
cruiseID = cruise.cruiseID) join route_path on cruise.routeID = route_path.routeID and route_path.sequence  = cruise.progress + 1 join leg on route_path.legID 
= leg.legID and leg.departure = portID  where cruise.ship_status = 'docked' group by portID, ship_port.locationID, port_name, city, state, country;


-- [17] route_summary()
-- -----------------------------------------------------------------------------
/* This view describes how the routes are being utilized by different cruises. */
-- -----------------------------------------------------------------------------
create or replace view route_summary (route, num_legs, leg_sequence, route_length,
	num_cruises, cruise_list, port_sequence) as
select routeId, count(*), GROUP_CONCAT(route_path.legID order by route_path.sequence SEPARATOR ','), sum((select distance from leg where leg.legID=route_path.legID)), (select count(*) from cruise where cruise.routeID=route_path.routeID), (select GROUP_CONCAT(cruiseId SEPARATOR ',') from cruise where cruise.routeID=route_path.routeID), (select GROUP_CONCAT(CONCAT(departure,'->',arrival) order by sequence SEPARATOR ',')) from route_path join leg on leg.legID=route_path.legID group by routeId ;

-- [18] alternative_ports()
-- -----------------------------------------------------------------------------
/* This view displays ports that share the same country. */
-- -----------------------------------------------------------------------------
create or replace view alternative_ports (country, num_ports,
	port_code_list, port_name_list) as
select ship_port.country as country, count(*), group_concat(portID order by portID asc SEPARATOR
','), group_concat(port_name order by portID asc SEPARATOR ',') from ship_port group by country;
