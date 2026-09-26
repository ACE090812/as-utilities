CREATE TABLE IF NOT EXISTS `as_util_meters` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `type` ENUM('electric','gas') NOT NULL,
  `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
  `heading` FLOAT NOT NULL DEFAULT 0,
  `smart` TINYINT(1) NOT NULL DEFAULT 0,
  `state` VARCHAR(16) NOT NULL DEFAULT 'ok',
  `fault` VARCHAR(16) NULL DEFAULT NULL,
  `reading` DOUBLE NOT NULL DEFAULT 0,
  `tampered_at` INT NULL DEFAULT NULL,
  `created_by` VARCHAR(64) NULL,
  PRIMARY KEY (`id`)
);

CREATE TABLE IF NOT EXISTS `as_util_engineers` (
  `citizenid` VARCHAR(64) NOT NULL,
  `xp` INT NOT NULL DEFAULT 0,
  `jobs_done` INT NOT NULL DEFAULT 0,
  `earned` INT NOT NULL DEFAULT 0,
  PRIMARY KEY (`citizenid`)
);

-- job sheets (log only)
CREATE TABLE IF NOT EXISTS `as_util_jobs` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `kind` VARCHAR(16) NOT NULL,
  `meters` VARCHAR(255) NOT NULL,
  `crew` TEXT NOT NULL,
  `outcome` VARCHAR(64) NULL,
  `pay` INT NOT NULL DEFAULT 0,
  `late` TINYINT(1) NOT NULL DEFAULT 0,
  `reporter` VARCHAR(64) NULL,
  `created_at` INT NOT NULL,
  `claimed_at` INT NULL,
  `finished_at` INT NULL,
  PRIMARY KEY (`id`),
  KEY `finished_at` (`finished_at`)
);
