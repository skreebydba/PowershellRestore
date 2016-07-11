if (Get-Command Get-RelocateFile -ErrorAction SilentlyContinue)
{
    Remove-Item -Path Function:\Get-RelocateFile;
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
