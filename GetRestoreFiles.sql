USE [master]
GO

/****** Object:  StoredProcedure [dbo].[GetRestoreFiles]    Script Date: 7/11/2016 11:27:28 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[GetRestoreFiles]
	@db_name SYSNAME = NULL, 
	@stopat DATETIME = NULL
AS
	IF OBJECT_ID('tempdb..#backupset') IS NOT NULL
	BEGIN

		DROP TABLE #backupset;

	END

	--DECLARE @db_name              sysname ,@restore_to_datetime  datetime 


	--select @db_name = N'testdb'

	IF @stopat IS NULL
	BEGIN

		select @stopat = GETDATE();

	END



	declare @server_name nvarchar(512)
	set @server_name = cast(serverproperty(N'Servername') as nvarchar(512))
			


	DECLARE 
	  @first_full_backupset_id      INTEGER,
	  @first_full_backup_startdate  DATETIME,
		@count_entries					INTEGER,
		@in_restore_plan				BIT,
		@last_backupset_type			CHAR(1),
		@last_backupset_id				INTEGER,
		@last_backupset_family_guid		UNIQUEIDENTIFIER,
		@last_backupset_diff_base_guid	UNIQUEIDENTIFIER,
		@last_backupset_recovery_fork_guid	UNIQUEIDENTIFIER,
		@full_backupset_id				INTEGER,
		@full_backupset_start_date		DATETIME,
		@full_backupset_recovery_fork_guid	UNIQUEIDENTIFIER,
	
	
		@loop_var						BIT,
		@loop_backup_set_id				INTEGER,
		@loop_start_date				DATETIME,
	  @count_unique_fork_guid INTEGER,
	
		@t1_backup_set_id				INTEGER,
		@t1_type						CHAR(1),
		@t1_backup_start_date			DATETIME,
		@t1_first_recovery_fork_guid	UNIQUEIDENTIFIER,
		@t1_last_recovery_fork_guid		UNIQUEIDENTIFIER,
		@t1_first_lsn					NUMERIC(25, 0),
		@t1_last_lsn					NUMERIC(25, 0),
		@t1_checkpoint_lsn				NUMERIC(25, 0),
		@t1_database_backup_lsn			NUMERIC(25, 0),
		@t1_fork_point_lsn				NUMERIC(25, 0),
		@t1_backup_set_uuid				UNIQUEIDENTIFIER,
		@t1_database_guid				UNIQUEIDENTIFIER,
		@t1_diff_base_guid				UNIQUEIDENTIFIER,
	
		@t2_backup_set_id				INTEGER,
		@t2_type						CHAR(1),
		@t2_backup_start_date			DATETIME,
		@t2_first_recovery_fork_guid	UNIQUEIDENTIFIER,
		@t2_last_recovery_fork_guid		UNIQUEIDENTIFIER,
		@t2_first_lsn					NUMERIC(25, 0),
		@t2_last_lsn					NUMERIC(25, 0),
		@t2_checkpoint_lsn				NUMERIC(25, 0),
		@t2_database_backup_lsn			NUMERIC(25, 0),
		@t2_fork_point_lsn				NUMERIC(25, 0),
		@t2_backup_set_uuid				UNIQUEIDENTIFIER,
		@t2_database_guid				UNIQUEIDENTIFIER,
		@t2_diff_base_guid				UNIQUEIDENTIFIER
    

	CREATE TABLE #backupset(
		backup_set_id					INTEGER				NOT NULL,
		is_in_restore_plan				BIT					NOT NULL,
		backup_start_date				DATETIME			NOT NULL,
		type						    CHAR(1)				NOT NULL,
		database_name				    NVARCHAR(256)		NOT NULL,
		database_guid				    UNIQUEIDENTIFIER	,
		family_guid						UNIQUEIDENTIFIER	,
		first_recovery_fork_guid		UNIQUEIDENTIFIER	,
		last_recovery_fork_guid			UNIQUEIDENTIFIER	,
		first_lsn					    NUMERIC(25, 0)		,
		last_lsn					    NUMERIC(25, 0)		,
		checkpoint_lsn					NUMERIC(25, 0)		,
		database_backup_lsn				NUMERIC(25, 0)		,
		fork_point_lsn					NUMERIC(25, 0)		,
		restore_till_lsn				NUMERIC(25, 0)		,
		backup_set_uuid					UNIQUEIDENTIFIER	,
		differential_base_guid			UNIQUEIDENTIFIER
	)
	/**********************************************************************/
	/* Identify the first                                                 */
	/**********************************************************************/
	SELECT @first_full_backupset_id = backupset_outer.backup_set_id
		  ,@first_full_backup_startdate = backupset_outer.backup_start_date
	  FROM msdb.dbo.backupset backupset_outer
	 WHERE backupset_outer.database_name = @db_name
	   AND backupset_outer.server_name = @server_name
	   AND backupset_outer.type = 'D' -- Full Database Backup   
	   AND backupset_outer.backup_start_date = (  SELECT MAX(backupset_inner.backup_start_date)
														FROM msdb.dbo.backupset backupset_inner
													   WHERE backupset_inner.database_name = backupset_outer.database_name
														 AND backupset_inner.server_name = @server_name
														 AND backupset_inner.type = backupset_outer.type 
														 AND backupset_inner.backup_start_date <= @stopat
														 AND backupset_inner.is_copy_only = 0 )
	   AND backupset_outer.is_copy_only = 0
	/*******************************************************************************************/
	/* Find the first full database backup needed in the restore plan and store its attributes */
	/* in #backupset work table                                                                */ 
	/*******************************************************************************************/
	INSERT #backupset(
	   backup_set_id             
	  ,is_in_restore_plan        
	  ,backup_start_date         
	  ,type                      
	  ,database_name
	  ,last_recovery_fork_guid
	)
	SELECT backup_set_id             
		  ,1                   --  The full database backup is always needed for the restore plan
		  ,backup_start_date         
		  ,type                      
		  ,database_name
		  ,last_recovery_fork_guid
	  FROM msdb.dbo.backupset
	 WHERE msdb.dbo.backupset.backup_set_id = @first_full_backupset_id
	 AND msdb.dbo.backupset.server_name = @server_name

	/***************************************************************/
	/* Find the log and differential backups that occurred after   */
	/* the full backup and store them in #backupset work table     */ 
	/***************************************************************/
	INSERT #backupset(
	   backup_set_id
	  ,is_in_restore_plan 
	  ,backup_start_date         
	  ,type                      
	  ,database_name
	  ,last_recovery_fork_guid
	)
	SELECT backup_set_id             
		  ,0
		  ,backup_start_date         
		  ,type                      
		  ,database_name
		  ,last_recovery_fork_guid
	  FROM msdb.dbo.backupset
	 WHERE msdb.dbo.backupset.database_name = @db_name
	   AND msdb.dbo.backupset.server_name = @server_name
	   AND msdb.dbo.backupset.type IN ('I', 'L')  -- Differential, Log backups
	   AND msdb.dbo.backupset.backup_start_date >= @first_full_backup_startdate
   
	/**********************************************************************************/
	/* identify and mark the backup logs that need to be included in the restore plan */
	/**********************************************************************************/
	UPDATE #backupset  
	   SET is_in_restore_plan = 1
	 WHERE #backupset.type = 'I'
	   AND #backupset.backup_start_date = (SELECT MAX(backupset_inner.backup_start_date)
											 FROM #backupset backupset_inner
											WHERE backupset_inner.type = #backupset.type
											AND backupset_inner.backup_start_date <= @stopat)
  
	/**************************************************************************************/
	/* Log backups that occurred after the different are always part of the restore plan. */
	/**************************************************************************************/
	UPDATE #backupset  
	   SET is_in_restore_plan = 1
	 WHERE #backupset.type = 'L'
	   AND #backupset.backup_start_date <= @stopat
	   AND #backupset.backup_start_date >= (SELECT backupset_inner.backup_start_date
											  FROM #backupset backupset_inner
											 WHERE backupset_inner.type = 'I'
											   AND backupset_inner.is_in_restore_plan = 1)
                                           
	/**************************************************************************************/
	/* If @stopat is greater than the last startdate of the last log backup, */
	/* include the next log backup in the restore plan                                    */
	/**************************************************************************************/
	UPDATE #backupset  
	   SET is_in_restore_plan = 1
	 WHERE #backupset.type = 'L'
	   AND #backupset.backup_start_date = (SELECT MIN(backupset_inner.backup_start_date)
											 FROM #backupset backupset_inner
											WHERE backupset_inner.type = 'L'
											  AND backupset_inner.backup_start_date > @stopat
											  AND backupset_inner.is_in_restore_plan = 0)
                                           
	/**************************************************************************************/
	/* If there are no differential backups, all log backups that occurred after the full */
	/* backup are needed in the restore plan.                                             */
	/**************************************************************************************/
	UPDATE #backupset  
	   SET is_in_restore_plan = 1
	 WHERE #backupset.type = 'L'
	   AND #backupset.backup_start_date <= @stopat
	   AND NOT EXISTS(SELECT *
						FROM #backupset backupset_inner
					   WHERE backupset_inner.type = 'I')
                   
    



	/**************************************************************************************/
	/* The above plan is based on backup_start_date which fails in case when the DB is    */
	/* restored to a previous state i.e forked. In which case we need to base it on lsn   */
	/* numbers. This forking condition can be checked by matching the                     */
	/* last_recovery_fork_guid of the backupset if it doesn't match, we need to change    */
	/* the plan.                                                                          */
	/**************************************************************************************/

	SELECT @count_unique_fork_guid = COUNT( DISTINCT last_recovery_fork_guid )
	  FROM #backupset

	IF @count_unique_fork_guid > 1
	BEGIN

	DELETE 
	FROM #backupset
	/**************************************************************************************/
	/* First we look for a T-Log backup taken after the given point-in-time to get the    */
	/* tail log, that can be used to restore to the exact point-in-time.                  */
	/**************************************************************************************/

	INSERT #backupset(
		backup_set_id,
		is_in_restore_plan,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid
	)
	SELECT TOP(1)
		backup_set_id,
		1,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid
                 
	  FROM msdb.dbo.backupset
	 WHERE msdb.dbo.backupset.database_name = @db_name
	   AND msdb.dbo.backupset.type IN ('D', 'L')
	   AND msdb.dbo.backupset.backup_start_date >= @stopat
	 ORDER BY msdb.dbo.backupset.backup_start_date ASC,
			  msdb.dbo.backupset.last_lsn ASC                                          
                                              
	SELECT @last_backupset_type = bset.type
	  FROM #backupset as bset
 
	IF @last_backupset_type = 'D' --Full
	BEGIN 
		DELETE FROM #backupset
	END

	/**********************************************************************/
	/* If no T-Log backup exits for after the time T, get the last backup */
	/**********************************************************************/                                          

	SELECT @count_entries = COUNT(bset.backup_set_id)
	  FROM #backupset as bset

	IF @count_entries < 1
	BEGIN

		INSERT #backupset(
			backup_set_id,
			is_in_restore_plan,
			backup_start_date,
			type,
			database_name,
			database_guid,
			family_guid,
			first_recovery_fork_guid,
			last_recovery_fork_guid,
			first_lsn,
			last_lsn,
			checkpoint_lsn,
			database_backup_lsn,
			fork_point_lsn,
			backup_set_uuid,
			differential_base_guid
	)
		SELECT TOP(1)
			backup_set_id,
			1,
			backup_start_date,
			type,
			database_name,
			database_guid,
			family_guid,
			first_recovery_fork_guid,
			last_recovery_fork_guid,
			first_lsn,
			last_lsn,
			checkpoint_lsn,
			database_backup_lsn,
			fork_point_lsn,
			backup_set_uuid,
			differential_base_guid

		 FROM msdb.dbo.backupset
		WHERE msdb.dbo.backupset.database_name = @db_name
		  AND msdb.dbo.backupset.backup_start_date <= @stopat
	 ORDER BY msdb.dbo.backupset.backup_start_date DESC,
			  msdb.dbo.backupset.last_lsn DESC 
	      
	END

	SELECT @last_backupset_type = bset.type,
		   @last_backupset_id = bset.backup_set_id,
		   @last_backupset_family_guid = bset.family_guid,
		   @last_backupset_diff_base_guid = bset.differential_base_guid,
		   @last_backupset_recovery_fork_guid = bset.last_recovery_fork_guid	   
	  FROM #backupset as bset
  
	/**************************************************************************************/
	/* If the selected backup is Full ('D') return.                                       */
	/**************************************************************************************/

	IF (@last_backupset_type = 'D')
	BEGIN
		GOTO done
	END 

	/**************************************************************************************/
	/* If the selected backup is Differential('I'),select the Diff-base backup(Full) also */
	/**************************************************************************************/
	IF (@last_backupset_type = 'I')
	BEGIN
	
		INSERT #backupset(
				backup_set_id,
				is_in_restore_plan,
				backup_start_date,
				type,
				database_name,
				database_guid,
				family_guid,
				first_recovery_fork_guid,
				last_recovery_fork_guid,
				first_lsn,
				last_lsn,
				checkpoint_lsn,
				database_backup_lsn,
				fork_point_lsn,
				backup_set_uuid,
				differential_base_guid
			)
			SELECT TOP(1)
				backup_set_id,
				1,
				backup_start_date,
				type,
				database_name,
				database_guid,
				family_guid,
				first_recovery_fork_guid,
				last_recovery_fork_guid,
				first_lsn,
				last_lsn,
				checkpoint_lsn,
				database_backup_lsn,
				fork_point_lsn,
				backup_set_uuid,
				differential_base_guid

			 FROM msdb.dbo.backupset
			WHERE msdb.dbo.backupset.backup_set_uuid = @last_backupset_diff_base_guid
			  AND msdb.dbo.backupset.family_guid = @last_backupset_family_guid
	
		GOTO done
	END

	SELECT @t1_type = bset.type,
		   @t1_backup_set_id = bset.backup_set_id,
		   @t1_backup_set_uuid = bset.backup_set_uuid,
		   @t1_backup_start_date = bset.backup_start_date,
		   @t1_diff_base_guid = bset.differential_base_guid,
		   @t1_last_recovery_fork_guid = bset.last_recovery_fork_guid,
		   @t1_first_recovery_fork_guid = bset.first_recovery_fork_guid,
		   @t1_database_guid = bset.database_guid,
		   @t1_first_lsn = bset.first_lsn,
		   @t1_last_lsn = bset.last_lsn,
		   @t1_checkpoint_lsn = bset.checkpoint_lsn,
		   @t1_database_backup_lsn = bset.database_backup_lsn,
		   @t1_fork_point_lsn = bset.fork_point_lsn	   
	 FROM #backupset as bset

	SET @loop_backup_set_id = @t1_backup_set_id
	SET @loop_start_date = @t1_backup_start_date

	/**************************************************************************************/
	/* This Loop iterates thru the backup with the same family_guid in reverse order and  */
	/* constructs the T-Log chain, until it finds the compatible Diff or Backup           */
	/**************************************************************************************/
	SET @loop_var = 1  
	WHILE ( @loop_var = 1 )
	BEGIN
	
		SELECT TOP(1)
			@t2_backup_set_id = backup_set_id,
			@t2_backup_set_uuid = backup_set_uuid,
			@t2_backup_start_date =	backup_start_date,
			@t2_type = type,
			@t2_first_recovery_fork_guid = first_recovery_fork_guid,
			@t2_last_recovery_fork_guid= last_recovery_fork_guid,
			@t2_database_guid = database_guid,
			@t2_first_lsn = first_lsn,
			@t2_last_lsn = last_lsn,
			@t2_checkpoint_lsn = checkpoint_lsn,
			@t2_database_backup_lsn = database_backup_lsn,
			@t2_fork_point_lsn= fork_point_lsn,
			@t2_diff_base_guid = differential_base_guid		

		 FROM msdb.dbo.backupset
		WHERE msdb.dbo.backupset.family_guid = @last_backupset_family_guid
		  AND msdb.dbo.backupset.backup_start_date <= @loop_start_date
		  AND msdb.dbo.backupset.backup_set_id < @loop_backup_set_id
	 ORDER BY msdb.dbo.backupset.backup_start_date DESC,
			  msdb.dbo.backupset.last_lsn DESC, 
			  msdb.dbo.backupset.backup_set_id DESC 
	      
		IF( @t2_backup_set_id IS NULL OR @t2_backup_set_id = @loop_backup_set_id) 
		BEGIN
			GOTO done
		END 
	
		IF( @t1_fork_point_lsn IS NULL )
		BEGIN
	
			IF (@t2_type = 'D' AND @t2_database_guid = @t1_database_guid AND @t2_first_lsn = @t1_first_lsn AND  @t2_last_recovery_fork_guid = @t1_first_recovery_fork_guid )
			BEGIN
				GOTO AddFullBackup
			END
		
			IF (@t2_type = 'I' AND @t2_database_guid = @t1_database_guid AND  @t2_last_recovery_fork_guid = @t1_first_recovery_fork_guid )
			BEGIN 
				GOTO AddDiffBackup
			END		
		
			IF (@t2_type = 'L' AND @t2_last_recovery_fork_guid = @t1_first_recovery_fork_guid AND @t2_last_lsn = @t1_first_lsn)
			BEGIN
				INSERT #backupset(
					backup_set_id,
					is_in_restore_plan,
					backup_start_date,
					type,
					database_name,
					database_guid,
					family_guid,
					first_recovery_fork_guid,
					last_recovery_fork_guid,
					first_lsn,
					last_lsn,
					checkpoint_lsn,
					database_backup_lsn,
					fork_point_lsn,
					backup_set_uuid,
					differential_base_guid
				)
				SELECT TOP(1)
					backup_set_id,
					1,
					backup_start_date,
					type,
					database_name,
					database_guid,
					family_guid,
					first_recovery_fork_guid,
					last_recovery_fork_guid,
					first_lsn,
					last_lsn,
					checkpoint_lsn,
					database_backup_lsn,
					fork_point_lsn,
					backup_set_uuid,
					differential_base_guid

				 FROM msdb.dbo.backupset
				WHERE msdb.dbo.backupset.backup_set_id = @t2_backup_set_id	
			 
				SET	@t1_type = @t2_type
				SET	@t1_backup_set_id = @t2_backup_set_id
				SET	@t1_backup_set_uuid = @t2_backup_set_uuid
				SET	@t1_backup_start_date = @t2_backup_start_date
				SET	@t1_diff_base_guid = @t2_diff_base_guid
				SET	@t1_last_recovery_fork_guid = @t2_last_recovery_fork_guid
				SET	@t1_first_recovery_fork_guid = @t2_first_recovery_fork_guid
				SET	@t1_database_guid = @t2_database_guid
				SET	@t1_first_lsn = @t2_first_lsn
				SET	@t1_last_lsn = @t2_last_lsn
				SET	@t1_checkpoint_lsn = @t2_checkpoint_lsn
				SET	@t1_database_backup_lsn = @t2_database_backup_lsn
				SET	@t1_fork_point_lsn = @t2_fork_point_lsn	   
			
			END
	
		END
		ELSE
		BEGIN

			IF (@t2_type = 'D' AND ((@t2_last_recovery_fork_guid = @t1_first_recovery_fork_guid AND @t2_last_lsn <= @t1_fork_point_lsn) 
					 OR @t2_last_recovery_fork_guid = @t1_last_recovery_fork_guid AND @t2_last_lsn > @t1_fork_point_lsn AND @t2_last_lsn < @t1_last_lsn))
			BEGIN
				GOTO AddFullBackup
			END
		
			IF (@t2_type = 'I' 
				AND ((@t2_last_recovery_fork_guid = @t1_first_recovery_fork_guid AND @t2_last_lsn <= @t1_fork_point_lsn) 
					 OR @t2_last_recovery_fork_guid = @t1_last_recovery_fork_guid AND @t2_last_lsn > @t1_fork_point_lsn AND @t2_last_lsn < @t1_last_lsn))
			BEGIN
				GOTO AddDiffBackup
			END
		
			IF (@t2_type = 'L' AND @t2_last_recovery_fork_guid = @t1_first_recovery_fork_guid AND @t2_last_lsn = @t1_first_lsn)
			BEGIN
				INSERT #backupset(
					backup_set_id,
					is_in_restore_plan,
					backup_start_date,
					type,
					database_name,
					database_guid,
					family_guid,
					first_recovery_fork_guid,
					last_recovery_fork_guid,
					first_lsn,
					last_lsn,
					checkpoint_lsn,
					database_backup_lsn,
					fork_point_lsn,
					backup_set_uuid,
					differential_base_guid
				)
				SELECT TOP(1)
					backup_set_id,
					1,
					backup_start_date,
					type,
					database_name,
					database_guid,
					family_guid,
					first_recovery_fork_guid,
					last_recovery_fork_guid,
					first_lsn,
					last_lsn,
					checkpoint_lsn,
					database_backup_lsn,
					fork_point_lsn,
					backup_set_uuid,
					differential_base_guid

				 FROM msdb.dbo.backupset
				WHERE msdb.dbo.backupset.backup_set_id = @t2_backup_set_id	
			
				SET	@t1_type = @t2_type
				SET	@t1_backup_set_id = @t2_backup_set_id
				SET	@t1_backup_set_uuid = @t2_backup_set_uuid
				SET	@t1_backup_start_date = @t2_backup_start_date
				SET	@t1_diff_base_guid = @t2_diff_base_guid
				SET	@t1_last_recovery_fork_guid = @t2_last_recovery_fork_guid
				SET	@t1_first_recovery_fork_guid = @t2_first_recovery_fork_guid
				SET	@t1_database_guid = @t2_database_guid
				SET	@t1_first_lsn = @t2_first_lsn
				SET	@t1_last_lsn = @t2_last_lsn
				SET	@t1_checkpoint_lsn = @t2_checkpoint_lsn
				SET	@t1_database_backup_lsn = @t2_database_backup_lsn
				SET	@t1_fork_point_lsn = @t2_fork_point_lsn	   
			
			END
		END
	
		SET @loop_backup_set_id = @t2_backup_set_id
		SET @loop_start_date = @t2_backup_start_date
	
	END

	AddFullBackup:
	INSERT #backupset(
		backup_set_id,
		is_in_restore_plan,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid
	)
	SELECT TOP(1)
		backup_set_id,
		1,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid

	 FROM msdb.dbo.backupset
	WHERE msdb.dbo.backupset.backup_set_id = @t2_backup_set_id	
	GOTO done

	AddDiffBackup:	
	INSERT #backupset(
		backup_set_id,
		is_in_restore_plan,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid
	)
	SELECT TOP(1)
		backup_set_id,
		1,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid

	 FROM msdb.dbo.backupset
	WHERE msdb.dbo.backupset.backup_set_id = @t2_backup_set_id

	INSERT #backupset(
		backup_set_id,
		is_in_restore_plan,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid
	)
	SELECT TOP(1)
		backup_set_id,
		1,
		backup_start_date,
		type,
		database_name,
		database_guid,
		family_guid,
		first_recovery_fork_guid,
		last_recovery_fork_guid,
		first_lsn,
		last_lsn,
		checkpoint_lsn,
		database_backup_lsn,
		fork_point_lsn,
		backup_set_uuid,
		differential_base_guid

	 FROM msdb.dbo.backupset
	WHERE msdb.dbo.backupset.backup_set_uuid = @t2_diff_base_guid
	  AND msdb.dbo.backupset.family_guid = @last_backupset_family_guid


	done:

	SELECT @count_entries = COUNT( bset.backup_set_id )
	  FROM #backupset AS bset
	 WHERE bset.type = 'D'

	/**************************************************************************************/
	/* If the backupset info in the msdb is incomplete then the restore_plan may be       */
	/* broken. In those cases just don't return anything.                                 */
	/**************************************************************************************/

	IF @count_entries < 1
	BEGIN
	  DELETE 
	  FROM #backupset
	END 


	END           
            
    


	SELECT
	bmf.physical_device_name, btmp.type
	FROM
	#backupset AS btmp
	INNER JOIN msdb.dbo.backupset AS bkps ON bkps.backup_set_id = btmp.backup_set_id
	INNER JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bkps.media_set_id
	WHERE btmp.is_in_restore_plan = 1
	ORDER BY
	bkps.[backup_finish_date] ASC,bkps.backup_set_id ASC;

				

GO


