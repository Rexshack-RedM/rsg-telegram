CREATE TABLE IF NOT EXISTS `rsg_telegrams` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `recipient_name` VARCHAR(100) NOT NULL,
    `sender_citizenid` VARCHAR(50) NOT NULL,
    `sender_name` VARCHAR(100) NOT NULL,
    `subject` VARCHAR(100) NOT NULL,
    `message` TEXT NOT NULL,
    `is_read` TINYINT(1) NOT NULL DEFAULT 0,
    `sent_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_telegram_contacts` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `contact_citizenid` VARCHAR(50) NOT NULL,
    `contact_name` VARCHAR(100) NOT NULL,
    `nickname` VARCHAR(50) NULL DEFAULT NULL,
    `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_contact` (`citizenid`, `contact_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
