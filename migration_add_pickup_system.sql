-- Migration SQL to add pickup system to existing telegram databases
-- Run this if you already have the telegrams table installed

-- Add the new columns
ALTER TABLE `telegrams` 
ADD COLUMN `fromPostOffice` TINYINT(1) NOT NULL DEFAULT '1' AFTER `birdstatus`,
ADD COLUMN `pickedUp` TINYINT(1) NOT NULL DEFAULT '0' AFTER `fromPostOffice`;

-- Mark all existing messages as picked up (so they show in inbox immediately)
UPDATE `telegrams` SET `pickedUp` = 1 WHERE `pickedUp` = 0;
