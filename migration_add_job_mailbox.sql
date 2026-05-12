-- Migration SQL to add job mailbox support to existing telegram databases
-- Run this once before starting the updated resource on an existing database.

-- Adds the mailbox discriminator when updating from the official schema.
SET @sql = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE `telegrams` ADD COLUMN `mailbox` VARCHAR(20) NOT NULL DEFAULT ''personal'' AFTER `pickedUp`',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'telegrams'
      AND COLUMN_NAME = 'mailbox'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Renames the earlier businessTarget column if a test database already used the old wording.
SET @sql = (
    SELECT IF(
        EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'telegrams'
              AND COLUMN_NAME = 'businessTarget'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'telegrams'
              AND COLUMN_NAME = 'jobTarget'
        ),
        'ALTER TABLE `telegrams` CHANGE COLUMN `businessTarget` `jobTarget` VARCHAR(50) DEFAULT NULL',
        'SELECT 1'
    )
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Adds jobTarget when updating directly from the official schema.
SET @sql = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE `telegrams` ADD COLUMN `jobTarget` VARCHAR(50) DEFAULT NULL AFTER `mailbox`',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'telegrams'
      AND COLUMN_NAME = 'jobTarget'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Keeps all historical telegrams in the original personal inbox.
UPDATE `telegrams` SET `mailbox` = 'personal' WHERE `mailbox` IS NULL OR `mailbox` = '';
