-- MySQL dump 10.13  Distrib 8.0.45, for Win64 (x86_64)
--
-- Host: localhost    Database: election_db
-- ------------------------------------------------------
-- Server version	8.0.45

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `app_config`
--

DROP TABLE IF EXISTS `app_config`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `app_config` (
  `key` varchar(100) NOT NULL,
  `value` text,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `app_config`
--

LOCK TABLES `app_config` WRITE;
/*!40000 ALTER TABLE `app_config` DISABLE KEYS */;
INSERT INTO `app_config` VALUES ('allowStaffLogin','true','2026-04-03 11:12:07'),('electionDate','15 Apr 2026','2026-04-03 11:12:07'),('electionYear','2026','2026-04-03 11:12:07'),('forcePasswordReset','false','2026-04-03 11:12:07'),('maintenanceMode','false','2026-04-03 11:12:07'),('phase','Phase 1','2026-04-03 11:12:07'),('state','Uttar Pradesh','2026-04-03 11:12:07');
/*!40000 ALTER TABLE `app_config` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `duty_assignments`
--

DROP TABLE IF EXISTS `duty_assignments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `duty_assignments` (
  `id` int NOT NULL AUTO_INCREMENT,
  `staff_id` int NOT NULL,
  `sthal_id` int NOT NULL,
  `bus_no` varchar(50) DEFAULT '',
  `assigned_by` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_staff_sthal` (`staff_id`,`sthal_id`),
  KEY `sthal_id` (`sthal_id`),
  KEY `assigned_by` (`assigned_by`),
  CONSTRAINT `duty_assignments_ibfk_1` FOREIGN KEY (`staff_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `duty_assignments_ibfk_2` FOREIGN KEY (`sthal_id`) REFERENCES `matdan_sthal` (`id`) ON DELETE CASCADE,
  CONSTRAINT `duty_assignments_ibfk_3` FOREIGN KEY (`assigned_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `duty_assignments`
--

LOCK TABLES `duty_assignments` WRITE;
/*!40000 ALTER TABLE `duty_assignments` DISABLE KEYS */;
/*!40000 ALTER TABLE `duty_assignments` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `gram_panchayats`
--

DROP TABLE IF EXISTS `gram_panchayats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `gram_panchayats` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(200) NOT NULL,
  `address` text,
  `sector_id` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `sector_id` (`sector_id`),
  CONSTRAINT `gram_panchayats_ibfk_1` FOREIGN KEY (`sector_id`) REFERENCES `sectors` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `gram_panchayats`
--

LOCK TABLES `gram_panchayats` WRITE;
/*!40000 ALTER TABLE `gram_panchayats` DISABLE KEYS */;
INSERT INTO `gram_panchayats` VALUES (1,'surja','surja',1,'2026-04-03 11:28:45');
/*!40000 ALTER TABLE `gram_panchayats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `kshetra_officers`
--

DROP TABLE IF EXISTS `kshetra_officers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `kshetra_officers` (
  `id` int NOT NULL AUTO_INCREMENT,
  `super_zone_id` int NOT NULL,
  `user_id` int DEFAULT NULL,
  `name` varchar(150) NOT NULL DEFAULT '',
  `pno` varchar(50) DEFAULT '',
  `mobile` varchar(15) DEFAULT '',
  `user_rank` varchar(100) DEFAULT '',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `super_zone_id` (`super_zone_id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `kshetra_officers_ibfk_1` FOREIGN KEY (`super_zone_id`) REFERENCES `super_zones` (`id`) ON DELETE CASCADE,
  CONSTRAINT `kshetra_officers_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `kshetra_officers`
--

LOCK TABLES `kshetra_officers` WRITE;
/*!40000 ALTER TABLE `kshetra_officers` DISABLE KEYS */;
INSERT INTO `kshetra_officers` VALUES (1,2,NULL,'kshetradhikari','001','94679797','kshetradhikari','2026-04-03 11:16:11');
/*!40000 ALTER TABLE `kshetra_officers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `matdan_kendra`
--

DROP TABLE IF EXISTS `matdan_kendra`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `matdan_kendra` (
  `id` int NOT NULL AUTO_INCREMENT,
  `room_number` varchar(50) NOT NULL,
  `matdan_sthal_id` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `matdan_sthal_id` (`matdan_sthal_id`),
  CONSTRAINT `matdan_kendra_ibfk_1` FOREIGN KEY (`matdan_sthal_id`) REFERENCES `matdan_sthal` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `matdan_kendra`
--

LOCK TABLES `matdan_kendra` WRITE;
/*!40000 ALTER TABLE `matdan_kendra` DISABLE KEYS */;
INSERT INTO `matdan_kendra` VALUES (2,'3',1,'2026-04-03 11:35:11');
/*!40000 ALTER TABLE `matdan_kendra` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `matdan_sthal`
--

DROP TABLE IF EXISTS `matdan_sthal`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `matdan_sthal` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(250) NOT NULL,
  `address` text,
  `gram_panchayat_id` int NOT NULL,
  `thana` varchar(150) DEFAULT '',
  `center_type` enum('A','B','C') NOT NULL DEFAULT 'C',
  `bus_no` varchar(50) DEFAULT '',
  `latitude` decimal(10,7) DEFAULT NULL,
  `longitude` decimal(10,7) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `gram_panchayat_id` (`gram_panchayat_id`),
  CONSTRAINT `matdan_sthal_ibfk_1` FOREIGN KEY (`gram_panchayat_id`) REFERENCES `gram_panchayats` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `matdan_sthal`
--

LOCK TABLES `matdan_sthal` WRITE;
/*!40000 ALTER TABLE `matdan_sthal` DISABLE KEYS */;
INSERT INTO `matdan_sthal` VALUES (1,'prathmik pathshala surja','surja',1,'bagpat','B','1',NULL,NULL,'2026-04-03 11:32:53');
/*!40000 ALTER TABLE `matdan_sthal` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `sector_officers`
--

DROP TABLE IF EXISTS `sector_officers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `sector_officers` (
  `id` int NOT NULL AUTO_INCREMENT,
  `sector_id` int NOT NULL,
  `user_id` int DEFAULT NULL,
  `name` varchar(150) NOT NULL DEFAULT '',
  `pno` varchar(50) DEFAULT '',
  `mobile` varchar(15) DEFAULT '',
  `user_rank` varchar(100) DEFAULT '',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `sector_id` (`sector_id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `sector_officers_ibfk_1` FOREIGN KEY (`sector_id`) REFERENCES `sectors` (`id`) ON DELETE CASCADE,
  CONSTRAINT `sector_officers_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `sector_officers`
--

LOCK TABLES `sector_officers` WRITE;
/*!40000 ALTER TABLE `sector_officers` DISABLE KEYS */;
INSERT INTO `sector_officers` VALUES (1,1,NULL,'Rajveer','0q827','976464767','Home gard','2026-04-03 11:18:34');
/*!40000 ALTER TABLE `sector_officers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `sectors`
--

DROP TABLE IF EXISTS `sectors`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `sectors` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `zone_id` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `zone_id` (`zone_id`),
  CONSTRAINT `sectors_ibfk_1` FOREIGN KEY (`zone_id`) REFERENCES `zones` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `sectors`
--

LOCK TABLES `sectors` WRITE;
/*!40000 ALTER TABLE `sectors` DISABLE KEYS */;
INSERT INTO `sectors` VALUES (1,'sector 1',1,'2026-04-03 11:18:34');
/*!40000 ALTER TABLE `sectors` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `super_zones`
--

DROP TABLE IF EXISTS `super_zones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `super_zones` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `district` varchar(100) DEFAULT '',
  `block` varchar(100) DEFAULT '',
  `admin_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `admin_id` (`admin_id`),
  CONSTRAINT `super_zones_ibfk_1` FOREIGN KEY (`admin_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `super_zones`
--

LOCK TABLES `super_zones` WRITE;
/*!40000 ALTER TABLE `super_zones` DISABLE KEYS */;
INSERT INTO `super_zones` VALUES (2,'Bagpat super zone 1','Bagpat','Bagpat',3,'2026-04-03 11:16:11');
/*!40000 ALTER TABLE `super_zones` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `system_logs`
--

DROP TABLE IF EXISTS `system_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `system_logs` (
  `id` int NOT NULL AUTO_INCREMENT,
  `level` enum('INFO','WARN','ERROR') NOT NULL DEFAULT 'INFO',
  `message` text NOT NULL,
  `module` varchar(80) NOT NULL,
  `time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `system_logs`
--

LOCK TABLES `system_logs` WRITE;
/*!40000 ALTER TABLE `system_logs` DISABLE KEYS */;
/*!40000 ALTER TABLE `system_logs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(150) NOT NULL,
  `username` varchar(100) NOT NULL,
  `password` varchar(255) NOT NULL,
  `mobile` varchar(15) DEFAULT '',
  `role` enum('master','super_admin','admin','staff') NOT NULL DEFAULT 'staff',
  `district` varchar(100) DEFAULT '',
  `thana` varchar(100) DEFAULT '',
  `pno` varchar(50) DEFAULT NULL,
  `user_rank` varchar(100) DEFAULT '',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_by` int DEFAULT NULL,
  `assigned_by` int DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `pno` (`pno`),
  KEY `created_by` (`created_by`),
  KEY `assigned_by` (`assigned_by`),
  CONSTRAINT `users_ibfk_1` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `users_ibfk_2` FOREIGN KEY (`assigned_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES (1,'Master Admin','master','scrypt:32768:8:1$eiMW8BCU2pb3ssVh$5ba163e561684383fd66cc4385a016844f6e2020aeb9c9ea1d6895cb385adc52cfd790077a4f451d5f6221e6cb74f9026c2b4d84c8b320835ee1ea296a310cf6','','master','','',NULL,'',1,NULL,NULL,'2026-04-03 11:12:07','2026-04-03 11:12:07'),(2,'Super Admin','super','scrypt:32768:8:1$y0U3Fxpi2K40g8vA$e317055abeeb5e62bb03208cc2672e37d47ad330e49e198a528d66813f4e5449d641d4ae804f71c3ccf8fd810dd9146c5d5dbaf6226d8012cebc2741e42eb9fd','','super_admin','','',NULL,'',1,NULL,NULL,'2026-04-03 11:12:08','2026-04-03 11:12:08'),(3,'satya','satya','scrypt:32768:8:1$yPiE9WoUJN17TOke$624c3bf82ba3e64556044d35e5688e532678dca0fb09e023b3a48ccd24c86182c777fb13d8e52fb2931c525511fd2a469b14729a29561027c161779ccb31a233','','admin','Baghpat','',NULL,'',1,2,NULL,'2026-04-03 11:15:33','2026-04-03 11:15:33'),(4,'Aditya','001','scrypt:32768:8:1$hNPGToFGag9Gg9KP$9ef096ceb58589602e04068dd1b4aad25aec4c6f3dc1e216018974683e0248148227694440bac0c3311e2f85853633e21ffb84ff90453bd1233d215d74549f73','94349767','staff','bagpat','bagpat','001','',1,3,NULL,'2026-04-03 11:36:19','2026-04-03 11:36:19'),(5,'ghajag','bajaj','scrypt:32768:8:1$zcmMCeYgmgGpvfJU$d35987635a4dd62c0c805408a0d92dc06b7a460d9c3bea83c06449e44c09c899353aa7bd9c68b64c587957b3907f076e6a36033191270a117ebf0be9931e66f0','946494944','staff','Baghpat','vahaha','bajaj','',1,3,NULL,'2026-04-03 11:47:04','2026-04-03 11:47:04');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `zonal_officers`
--

DROP TABLE IF EXISTS `zonal_officers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `zonal_officers` (
  `id` int NOT NULL AUTO_INCREMENT,
  `zone_id` int NOT NULL,
  `user_id` int DEFAULT NULL,
  `name` varchar(150) NOT NULL DEFAULT '',
  `pno` varchar(50) DEFAULT '',
  `mobile` varchar(15) DEFAULT '',
  `user_rank` varchar(100) DEFAULT '',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `zone_id` (`zone_id`),
  KEY `user_id` (`user_id`),
  CONSTRAINT `zonal_officers_ibfk_1` FOREIGN KEY (`zone_id`) REFERENCES `zones` (`id`) ON DELETE CASCADE,
  CONSTRAINT `zonal_officers_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `zonal_officers`
--

LOCK TABLES `zonal_officers` WRITE;
/*!40000 ALTER TABLE `zonal_officers` DISABLE KEYS */;
INSERT INTO `zonal_officers` VALUES (1,1,NULL,'nirakshak','0002','66464949744','nirakshak','2026-04-03 11:17:22');
/*!40000 ALTER TABLE `zonal_officers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `zones`
--

DROP TABLE IF EXISTS `zones`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `zones` (
  `id` int NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `hq_address` text,
  `super_zone_id` int NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `super_zone_id` (`super_zone_id`),
  CONSTRAINT `zones_ibfk_1` FOREIGN KEY (`super_zone_id`) REFERENCES `super_zones` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `zones`
--

LOCK TABLES `zones` WRITE;
/*!40000 ALTER TABLE `zones` DISABLE KEYS */;
INSERT INTO `zones` VALUES (1,'Zone 1','dhanora',2,'2026-04-03 11:17:22');
/*!40000 ALTER TABLE `zones` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-04-03 12:56:27
