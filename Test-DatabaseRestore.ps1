if (Get-Command Test-DatabaseRestore -ErrorAction SilentlyContinue)
{
    Remove-Item -Path Function:\Test-DatabaseRestore;
}

function Test-DatabaseRestore {
<#
.SYNOPSIS
For the database input, restores the most recent FULL backup, all DIFF backup since the most recent FULL, and all LOG backups
since the most recent DIFF 
.DESCRIPTION
This function identifies the most recent FULL backup file for a database, any DIFF backup files that have been generated since the 
last FULL backup for that database, and any LOG backup files since the most recent DIFF
It then runs the Restore-SQLDatabase cmdlet for each file, setting the -norecovery flag for each file except the last one which runs
WITH RECOVERY
.EXAMPLE
Test-DatabaseRestore -databasename YourDatabase -backupinstance YourBackupInstance -restoreinstance YourRestoreInstance -noexec 0
Description
-----------
This example will identify the valid backup files for YourDatabase on YourBackupInstance and restore those files to YourRestoreInstance
.EXAMPLE
Test-DatabaseRestore -databasename YourDatabase -backupinstance YourBackupInstance -restoreinstance YourRestoreInstance -restorepath C:\YourRestorePath -noexec 0
Description
-----------
This example will identify the valid backup files for YourDatabase on YourBackupInstance and restore those files to YourRestoreInstance
If -backupinstance and -restoreinstance are not equal, all backup files will be copied to C:\YourRestorePath on YourRestoreInstance
.EXAMPLE
Test-DatabaseRestore -databasename YourDatabase -backupinstance YourBackupInstance -restoreinstance YourRestoreInstance -restorepath C:\YourRestorePath -stopatdate "2016-06-05 12:59:31" -noexec 0
Description
-----------
This example will identify the valid backup files for YourDatabase on YourBackupInstance before "2016-06-05 12:59:31" and copy those files to C:\YourRestorePath on YourRestoreInstance
The -stopatdate value will be used in the last log restore
.EXAMPLE
Test-DatabaseRestore -databasename YourDatabase -backupinstance YourBackupInstance -restoreinstance YourRestoreInstance -restorepath C:\YourRestorePath -stopatdate "2016-06-05 12:59:31" -noexec 0
Description
-----------
This example will identify the valid backup files for YourDatabase on YourBackupInstance before "2016-06-05 12:59:31" and copy those files to C:\YourRestorePath on YourRestoreInstance
The -stopatdate value will be used in the last log restore
.EXAMPLE
Test-DatabaseRestore -databasename YourDatabase -backupinstance YourBackupInstance -restoreinstance YourRestoreInstance -restorepath C:\YourRestorePath -noexec 1
Description
-----------
This example will identify the valid backup files for YourDatabase on YourBackupInstance and copy those files to C:\YourRestorePath on YourRestoreInstance
The Restore-SqlDatabase commands will be generated and written to file C:\YourRestorePath\restore.sql
.PARAMETER databasename
The database to test restores for
#>
[CmdletBinding()]
param
(
[Parameter(Mandatory=$True,
Position = 1,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='What database do you want to test restores for?')]
[Alias('database')]
[string]$databasename,

[Parameter(Mandatory=$True,
Position = 2,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='What instance do you want to query for the backup file list?')]
[Alias('backupinst')]
[string]$backupinstance,

[Parameter(Mandatory=$True,
Position = 3,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='What instance do you want to restore the backups to?')]
[Alias('restoreinst')]
[string]$restoreinstance,

[Parameter(Mandatory=$True,
Position = 4,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='What path do you want to copy the backup files to?')]
[Alias('rp')]
[string]$restorepath,

[Parameter(Mandatory=$False,
Position = 5,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='What is the stop at date you want to use for your restores?')]
[Alias('stopat')]
[string]$stopatdate,

    [Parameter(Mandatory=$True,
Position = 6,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='Set to 1 if you want to execute the database restore.  Otherwise ')]
[Alias('dontrun')]
[string]$noexec 
)

process {

    cls;

    $rfl = $null;

    <# The $noexec parm must be set to 0 to execute the restore commands #>
    if ($noexec -gt 1)
    {
        "The `$noexec parm was set to {0}. `$noexec must be set to 0 to execute the restore commands. Rerun your call to Test-DatabaseRestore." -f $noexec;
        $noexec = 1;
    }

    <# A restore path is required if the backup instance and restore instance are not the same #>
    if (($backupinstance -ne $restoreinstance) -and (!$restorepath))
    {
        Throw "You have entered backup instance {0} and restore instance {1}.  Because the instances are different, a restorepath muct be specified." -f $restoreinstance, $backupinstance;
    }
    <#
    [string]$setsingle = "ALTER DATABASE $databasename SET SINGLE_USER WITH ROLLBACK IMMEDIATE";
    if($noexec -eq 1)
    {
        Write-Output "Invoke-Sqlcmd -Query '$setsingle' -Database 'master' -ServerInstance $restoreinstance;"
    }
    else
    {
        Invoke-Sqlcmd -Query "$setsingle" -Database "master" -ServerInstance $restoreinstance;
    }#>

    <# If a `$stopatadte value has been passed in, pass it to the stored procedure #> 
    if (!$stopatdate)
    {
        [string]$querystring = "EXEC master.dbo.GetRestoreFiles @db_name = '$databasename'";
    } 
    else
    {
        [string]$querystring = "EXEC master.dbo.GetRestoreFiles @db_name = '$databasename', @stopat = '$stopatdate'";
    }

    #$querystring;

    <# Execute the stored procedure and pass the result set to variable `$filelist #>
    $filelist = @(Invoke-Sqlcmd -Query $querystring -ServerInstance $backupinstance -database "master")

    $filelist;

    <# If no files are returned, throw an error #>
    if ($filelist.Length -eq 0)
    {
        Throw "No valid backup files exist for database {0}.  If you have provided a `$stopatdate, rerun Test-DatabaseRestore without the @stopatdate value and set @noexec to 1 to see the list of valid backup files." -f $databasename
    }
        
    <# Initialize the loop counter and loop limit #>
    if($filelist.Length)
    {
        $filecount = 0;
        $filelimit = ($filelist.Length - 1)
        $array = 1;
    }
    else
    {
        $filecount = 0;
        $filelimit = 1;
        $array = 0;
    }
    if ($restoreinstance.Contains("\"))
    {
        $restoreserver = $restoreinstance.Substring(0,($restoreinstance.IndexOf("\")));
    }
    else
    {
        $restoreserver = $restoreinstance;
    }

    if ($backupinstance.Contains("\"))
    {
        $backupserver = $backupinstance.Substring(0,($backupinstance.IndexOf("\")));
    }
    else
    {
        $backupserver = $backupinstance;
    }

    $restoreunc = "\\" + $restoreserver + "\" + $restorepath.Replace(":","$");

    $exists = Test-Path $restoreunc;

    if ($exists -eq $false)
    {
        Throw "The restore path provided {0} does not exist.  Please validate the restore path and resubmit." -f $restorepath;
    }

    $outfile = $restoreunc +"\restore.ps1";
    
    if (Test-Path $outfile)
    {
        Remove-Item $outfile;
    }
    
    $restoredate = Get-Date -Format MM_dd_yyyy_HH_mm_ss;

    $durationfile = $restoreunc + "\" + $databasename + "_" + $restoredate + "_duration.txt";

    $surationfile;

    if (Test-Path $durationfile)
    {
        Remove-Item $durationfile;
    }
    
    $totalts = New-TimeSpan -Start $(Get-Date) -End $(Get-Date);

    <# Loop through each backup file and build Restore-SqlDatabase commands #>
    while($filecount -le $filelimit)
    {
        $filelimit;
        if($array -eq 0)
        {
            $file = $filelist.physical_device_name;
            $type = $filelist[$filecount].type;
            $filecount = 2;
        }
        else
        {
            $file = $filelist[$filecount].physical_device_name;
            $type = $filelist[$filecount].type;
        }
        $backupunc = "\\" + $backupserver + "\" + $file.Replace(":","$")

        <# If the backup instance is not the same as the restore instance, get the RelocateFile for the restore instance #>
        if ($backupinstance -ne $restoreinstance)
        {
            <# Copy backup files to the restore instance and set the backup file to the new location #>
            Copy-Item $backupunc -Destination $restoreunc;
            $file = $restorepath + "\" + $file.Substring(($file.LastIndexOf("\") + 1),($file.Length - (($file.LastIndexOf("\") + 1))));       

            if ($type -eq "D")
                {
                    $rfl = Get-RelocateFile -databasename $databasename -restoreinstance $restoreinstance -backupfile $file;
                    $rfl;               
                }
                else
                {
                    $rfl = $null
                }           
        }

        <# If it is not the last file, use the -Noreplace flag #>
        if ($filecount -lt $filelimit)
        {
            <# If `$noexec is 1, write the commands out #>
            if ($noexec -eq 1)
            {
                <# If it is a log backup, set the -RestoreAction Log flag #>
                if ($type -eq "L")
                {
                    Write-Output "Restore-SqlDatabase -ServerInstance  '$restoreinstance'  -database $databasename -RestoreAction Log -BackupFile $file -ReplaceDatabase -NoRecovery;" | Out-File -FilePath $outfile -Append
                }
                else
                {
                    <# If it is a FULL backup and a RelocateFile parm exists, set the -RelocateFile parm #>
                    if(($type -eq "D") -and ($rfl))
                    {
                        Write-Output "Restore-SqlDatabase -ServerInstance  '$restoreinstance'  -database $databasename -BackupFile $file -RelocateFile $rfl -ReplaceDatabase -NoRecovery;"  | Out-File -FilePath $outfile -Append
                    }
                    else
                    {
                        Write-Output "Restore-SqlDatabase -ServerInstance  '$restoreinstance'  -database $databasename -BackupFile $file -ReplaceDatabase -NoRecovery;"  | Out-File -FilePath $outfile -Append
                    }
                }
            }
            <# If the `$noexec flag is not set, execute the Restore-SqlDatabase commands #>
            else
            {
                <# If it is a LOG backup, use the -RestoreAction Log parm #>
                if ($type -eq "L")
                {

                    $restorestart = Get-Date;

                    Restore-SqlDatabase -ServerInstance $restoreinstance  -database $databasename -RestoreAction Log -BackupFile $file -ReplaceDatabase -NoRecovery;

                    $restoreend = Get-Date;

                    $restoreduration = New-TimeSpan -Start $restorestart -End $restoreend;

                    $logdur = "Log Duration " + $restoreduration.Hours.ToString("00") + ":" + $restoreduration.Minutes.ToString("00") + ":" +  $restoreduration.Seconds.ToString("00") + "." +  $restoreduration.Milliseconds.ToString("000");

                    $file | Out-File $durationfile -Append;

                    $logdur | Out-File $durationfile -Append;

                    $totalts = $restoreduration + $totalts;

                    #$totaldur = "Total Duration " + $totalts.Hours.ToString("00") + ":" + $totalts.Minutes.ToString("00") + ":" +  $totalts.Seconds.ToString("00") + "." +  $totalts.Milliseconds.ToString("000");

                    #$totaldur;


                }
                else
                {

                    <# If it is a FULL backup and a RestoreFile parm exists, use the -RestoreLocation parm #>
                    if(($type -eq "D") -and ($rfl))
                    {

                        $restorestart = Get-Date;

                        Restore-SqlDatabase -ServerInstance  $restoreinstance  -database $databasename -BackupFile $file -RelocateFile $rfl -ReplaceDatabase -NoRecovery;

                        $restoreend = Get-Date;

                        $restoreduration = New-TimeSpan -Start $restorestart -End $restoreend;

                        $fulldur = "Full Duration " + $restoreduration.Hours.ToString("00") + ":" + $restoreduration.Minutes.ToString("00") + ":" +  $restoreduration.Seconds.ToString("00") + "." +  $restoreduration.Milliseconds.ToString("000");
                        
                        $file | Out-File $durationfile -Append;

                        $fulldur | Out-File $durationfile -Append;

                        $totalts = $restoreduration + $totalts;

                        $totaldur = "Total Duration: " + $totalts.Hours.ToString("00") + ":" + $totalts.Minutes.ToString("00") + ":" +  $totalts.Seconds.ToString("00") + "." +  $totalts.Milliseconds.ToString("000");

                        $totaldur;

                    }
                    else
                    {
                        
                        $restorestart = Get-Date;

                        Restore-SqlDatabase -ServerInstance  $restoreinstance  -database $databasename -BackupFile $file -ReplaceDatabase -NoRecovery;

                        $restoreend = Get-Date;

                        $restoreduration = New-TimeSpan -Start $restorestart -End $restoreend;

                        $diffdur = "Diff Duration " + $restoreduration.Hours.ToString("00") + ":" + $restoreduration.Minutes.ToString("00") + ":" +  $restoreduration.Seconds.ToString("00") + "." +  $restoreduration.Milliseconds.ToString("000");

                        $file | Out-File $durationfile -Append;

                        $diffdur | Out-File $durationfile -Append;

                        $totalts = $restoreduration + $totalts;

                        $totaldur = "Total Duration: " + $totalts.Hours.ToString("00") + ":" + $totalts.Minutes.ToString("00") + ":" +  $totalts.Seconds.ToString("00") + "." +  $totalts.Milliseconds.ToString("000");

                        $totaldur;


                    }
                }
                    
            }
        }
        <# If it is the last backup file in the list, do not use the -Norecovery flag #>
        else
        {
            #Write-Output "Recovery"
            <# If `$noexec is 1, write the commands out #>
            if ($noexec -eq 1)
            {
                <# If it is a log backup, set the -RestoreAction Log flag #>
                if ($type -eq "L")
                {
                    if($stopatdate)
                    {
                        Write-Output "Restore-SqlDatabase -ServerInstance  '$restoreinstance'  -database $databasename -RestoreAction Log -BackupFile $file -ReplaceDatabase -ToPointInTime '$stopatdate';" | Out-File -FilePath $outfile -Append;
                    }
                    else
                    {
                        Write-Output "Restore-SqlDatabase -ServerInstance  '$restoreinstance'  -database $databasename -RestoreAction Log -BackupFile $file -ReplaceDatabase;" | Out-File -FilePath $outfile -Append;
                    }

                }
                else
                {
                    <# If it is a FULL backup and a RestoreFile parm exists, use the -RestoreLocation parm #>
                    if(($type -eq "D") -and ($rfl))
                    {
                        Write-Output "Restore-SqlDatabase -ServerInstance  '$restoreinstance'  -database $databasename -BackupFile $file -RelocateFile $rfl -ReplaceDatabase;"  | Out-File -FilePath $outfile -Append
                    }
                    else
                    {
                        Write-Output "Restore-SqlDatabase -ServerInstance  '$restoreinstance'  -database $databasename -BackupFile $file -ReplaceDatabase;"  | Out-File -FilePath $outfile -Append
                    }
                }
            }
            <# If the `$noexec flag is not set, execute the Restore-SqlDatabase commands #>
            else
            {
                <# If it is a LOG backup, use the -RestoreAction Log parm #>
                if ($type -eq "L")
                {
                    if($stopatdate)
                    {
                        Restore-SqlDatabase -ServerInstance  $restoreinstance  -database $databasename -RestoreAction Log -BackupFile $file -ReplaceDatabase -ToPointInTime "$stopatdate";
                    }
                    else
                    {
                        
                        $restorestart = Get-Date;

                        Restore-SqlDatabase -ServerInstance  $restoreinstance  -database $databasename -RestoreAction Log -BackupFile $file -ReplaceDatabase;
                        
                        $restoreend = Get-Date;

                        $restoreduration = New-TimeSpan -Start $restorestart -End $restoreend;

                        $logdur = "Log Duration " + $restoreduration.Hours.ToString("00") + ":" + $restoreduration.Minutes.ToString("00") + ":" +  $restoreduration.Seconds.ToString("00") + "." +  $restoreduration.Milliseconds.ToString("000");
                        
                        $file | Out-File $durationfile -Append;

                        $logdur | Out-File $durationfile -Append;
                        
                        $totalts = $restoreduration + $totalts;

                        $totaldur = "Total Duration " + $totalts.Hours.ToString("00") + ":" + $totalts.Minutes.ToString("00") + ":" +  $totalts.Seconds.ToString("00") + "." +  $totalts.Milliseconds.ToString("000");

                        $totaldur;

                    }
                }
                <# If it is a FULL backup and a RestoreFile parm exists, use the -RestoreLocation parm #>
                else
                {
                    if(($type -eq "D") -and ($rfl))
                    {

                        $restorestart = Get-Date;

                        Restore-SqlDatabase -ServerInstance  $restoreinstance  -database $databasename -BackupFile $file -RelocateFile $rfl -ReplaceDatabase;

                        $restoreend = Get-Date;

                        $restoreduration = New-TimeSpan -Start $restorestart -End $restoreend;

                        $totalts = $restoreduration + $totalts;

                        #$totaldur = "Full Duration " + $totalts.Hours.ToString("00") + ":" + $totalts.Minutes.ToString("00") + ":" +  $totalts.Seconds.ToString("00") + "." +  $totalts.Milliseconds.ToString("000");

                        #$totaldur;
                    }
                    else
                    {

                        $restorestart = Get-Date;

                        Restore-SqlDatabase -ServerInstance  $restoreinstance  -database $databasename -BackupFile $file -ReplaceDatabase;

                        $restoreend = Get-Date;

                        $restoreduration = New-TimeSpan -Start $restorestart -End $restoreend;

                        $totalts = $restoreduration + $totalts;

                        #$totaldur = "Diff Duration " + $totalts.Hours.ToString("00") + ":" + $totalts.Minutes.ToString("00") + ":" +  $totalts.Seconds.ToString("00") + "." +  $totalts.Milliseconds.ToString("000");

                        #$totaldur;
                    }
                }
                    
            }

        }

        $filecount += 1;

    }  

    $finaltotaldur = "Total Duration " + $totalts.Hours.ToString("00") + ":" + $totalts.Minutes.ToString("00") + ":" +  $totalts.Seconds.ToString("00") + "." +  $totalts.Milliseconds.ToString("000");   
    $finaltotaldur | Out-File $durationfile -Append;

}
}
function Get-RelocateFile {
<#
.SYNOPSIS
Builds the RelocateFile parm for Restore-SQLDatabase

.DESCRIPTION
This cmdlet identifies the default data and log file locations for a SQL instance and uses that information
to build the RelocateFile parameter for the REstore-SQLDatabase cmdlet

.EXAMPLE
Get-RelocateFile -databasename YourDatabaseName -restoreinstance TheInstanceYouAreRestoringTo -backupfile YourBackupFile

.PARAMETER databasename
The database to test restores for

.PARAMETER restoreinstance
The instance you will be restoring to 

.PARAMETER backup file
The backup file you are restoring

#>
[CmdletBinding()]
param
(
[Parameter(Mandatory=$True,
Position = 1,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='What database do you want to test restores for?')]
[Alias('database')]
[string]$databasename,

[Parameter(Mandatory=$True,
Position = 1,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='What instance do you want to restore the backups to?')]
[Alias('restoreinst')]
[string]$restoreinstance,

    [Parameter(Mandatory=$False,
ValueFromPipeline=$True,
ValueFromPipelineByPropertyName=$True,
    HelpMessage='Set to 1 if you want to execute the database restore.  Otherwise ')]
[Alias('bfile')]
[string]$backupfile 
)

process {
        
    <#
    The code in this function has been modified from the code at 
    https://www.simple-talk.com/sql/backup-and-recovery/backup-and-restore-sql-server-with-the-sql-server-2012-powershell-cmdlets/
    Many thanks to Allen White for making it generally available
    #>

    cls;

    # Connect to the specified instance
    $srv = new-object ('Microsoft.SqlServer.Management.Smo.Server') $restoreinstance;

 

    # Get the default file and log locations

    # (If DefaultFile and DefaultLog are empty, use the MasterDBPath and MasterDBLogPath values)

    $fileloc = $srv.Settings.DefaultFile

    $logloc = $srv.Settings.DefaultLog

    if ($fileloc.Length -eq 0) {

        $fileloc = $srv.Information.MasterDBPath

        }

    if ($logloc.Length -eq 0) {

        $logloc = $srv.Information.MasterDBLogPath

        }

    #$fileloc;
    #$logloc;
 

    # $backupfile and $databasename are passed in as mandatory parameters

    # Build the physical file names for the database copy

    $dbfile = $fileloc + $databasename + '_Data.mdf'

    $logfile = $logloc + $databasename + '_Log.ldf'

 

    # Use the backup file name to create the backup device

    $bdi = new-object ('Microsoft.SqlServer.Management.Smo.BackupDeviceItem') ($backupfile, 'File')

 

    # Create the new restore object, set the database name and add the backup device

    $rs = new-object('Microsoft.SqlServer.Management.Smo.Restore')

    $rs.Database = $databasename

    $rs.Devices.Add($bdi)

    # Get the file list info from the backup file

    $fl = $rs.ReadFileList($srv)

    $rfl = @()

    foreach ($fil in $fl) {

        $rsfile = new-object('Microsoft.SqlServer.Management.Smo.RelocateFile')

        $rsfile.LogicalFileName = $fil.LogicalName

        if ($fil.Type -eq 'D') {

            $rsfile.PhysicalFileName = $dbfile

            }

        else {

            $rsfile.PhysicalFileName = $logfile

            }

        $rfl += $rsfile

        }
        
    return $rfl;
        

 
    #Restore the database

    #Restore-SqlDatabase -ServerInstance ".\instance2" -Database $databasename -BackupFile $bckfile -RelocateFile $rfl -ReplaceDatabase;

    }  
}
