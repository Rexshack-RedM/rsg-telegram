ALTER TABLE `telegrams` ADD `recipient` VARCHAR(64) NOT NULL  AFTER `citizenid`;
ALTER TABLE `telegrams` ADD `birdstatus` TINYINT(2) NOT NULL DEFAULT '0' AFTER `status`;