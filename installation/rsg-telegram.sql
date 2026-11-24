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
    `batch` VARCHAR(40) NULL DEFAULT NULL,
    `has_attachment` TINYINT(1) NOT NULL DEFAULT 0,
    `attachment` TEXT NULL DEFAULT NULL,
    `anonymous` TINYINT(1) NOT NULL DEFAULT 0,
    `silenced` TINYINT(1) NOT NULL DEFAULT 0,
    `kind` VARCHAR(20) NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    INDEX `idx_citizenid` (`citizenid`),
    INDEX `idx_sender` (`sender_citizenid`),
    INDEX `idx_inbox` (`citizenid`, `sent_at`)
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

CREATE TABLE IF NOT EXISTS `rsg_telegram_blocks` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `blocked_citizenid` VARCHAR(50) NOT NULL,
    `blocked_name` VARCHAR(100) NOT NULL,
    `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `anonymous` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_block` (`citizenid`, `blocked_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_telegram_settings` (
    `citizenid` VARCHAR(50) NOT NULL,
    `unlisted` TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `rsg_telegram_mailboxes` (
    `id` INT(11) NOT NULL AUTO_INCREMENT,
    `label` VARCHAR(64) NULL DEFAULT NULL,
    `x` DOUBLE NOT NULL,
    `y` DOUBLE NOT NULL,
    `z` DOUBLE NOT NULL,
    `heading` DOUBLE NOT NULL DEFAULT 0,
    `created_by` VARCHAR(50) NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
