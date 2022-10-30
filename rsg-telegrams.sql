CREATE TABLE `telegrams` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(255) NOT NULL,
  `sender` varchar(255) NOT NULL,
  `sendername` varchar(255) NOT NULL,
  `subject` varchar(255) NOT NULL,
  `sentDate` varchar(25) NOT NULL,
  `message` varchar(455) NOT NULL,
  `status` varchar(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;