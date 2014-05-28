### Licensed to the Apache Software Foundation (ASF) under one or more
### contributor license agreements.  See the NOTICE file distributed with
### this work for additional information regarding copyright ownership.
### The ASF licenses this file to You under the Apache License, Version 2.0
### (the "License"); you may not use this file except in compliance with
### the License.  You may obtain a copy of the License at
###
###     http://www.apache.org/licenses/LICENSE-2.0
###
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.

###
### A set of basic PowerShell routines that can be used to install and
### manage Hadoop services on a single node. For use-case see install.ps1.
###

###
### Global variables
###
$ScriptDir = Resolve-Path (Split-Path $MyInvocation.MyCommand.Path)
$FinalName = "mahout-@mahout.version@"

###############################################################################
###
### Installs Mahout
###
### Arguments:
###     component: Component to be installed, it can be "mahout"
###     nodeInstallRoot: Target install folder (for example "C:\Hadoop")
###     serviceCredential: Credential object used for service creation
###     role: Space separated list of roles that should be installed.
###           (only "mahout" allowed for now)
###
###############################################################################
function Install(
        [String]
        [Parameter( Position=0, Mandatory=$true )]
        $component,
        [String]
        [Parameter( Position=1, Mandatory=$true )]
        $nodeInstallRoot,
        [System.Management.Automation.PSCredential]
        [Parameter( Position=2, Mandatory=$false )]
        $serviceCredential,
        [String]
        [Parameter( Position=3, Mandatory=$false )]
        $role
        )
{
    if ( $component -eq "mahout" )
    {
        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"
        Write-Log "Checking the JAVA Installation."
        if( -not (Test-Path $ENV:JAVA_HOME\bin\java.exe))
        {
            Write-Log "JAVA_HOME not set properly; $ENV:JAVA_HOME\bin\java.exe does not exist" "Failure"
            throw "Install: JAVA_HOME not set properly; $ENV:JAVA_HOME\bin\java.exe does not exist."
        }

        Write-Log "Checking the Hadoop Installation."
        if( -not (Test-Path $ENV:HADOOP_HOME\bin\hadoop.cmd))
        {

            Write-Log "HADOOP_HOME not set properly; $ENV:HADOOP_HOME\bin\hadoop.cmd does not exist" "Failure"
            throw "Install: HADOOP_HOME not set properly; $ENV:HADOOP_HOME\bin\hadoop.cmd does not exist."
        }

        ### $installToDir: the directory that contains the appliation, after unzipping
        $installToDir = Join-Path "$nodeInstallRoot" "$FinalName"

        ###
        ###  Unzip Mahout distribution from compressed archive
        ###
       Write-Log "Extracting $FinalName to $ENV:HADOOP_NODE_INSTALL_ROOT"
       if ( Test-Path ENV:UNZIP_CMD )
       {
            ### Use external unzip command if given
            $unzipExpr = $ENV:UNZIP_CMD.Replace("@SRC", "`"$HDP_RESOURCES_DIR\$FinalName.zip`"")
            $unzipExpr = $unzipExpr.Replace("@DEST", "`"$nodeInstallRoot`"")
            ### We ignore the error code of the unzip command for now to be
            ### consistent with prior behavior.
            Invoke-Ps $unzipExpr
        }
       else
       {
            $shellApplication = new-object -com shell.application
            $zipPackage = $shellApplication.NameSpace("$HDP_RESOURCES_DIR\$FinalName.zip")
            $destinationFolder = $shellApplication.NameSpace($nodeInstallRoot)
            $destinationFolder.CopyHere($zipPackage.Items(), 20)
        }
        ###
        ### Setting environment variables
        ###
        $nodeInstallRoot = $ENV:HADOOP_NODE_INSTALL_ROOT
        $mahoutInstallToDir = Join-Path $nodeInstallRoot "$FinalName"
        Write-Log "Setting MAHOUT_HOME at machine scope"
        [Environment]::SetEnvironmentVariable( "MAHOUT_HOME", "$mahoutInstallToDir", [EnvironmentVariableTarget]::Machine )
    }
    else
    {
        throw "Install: Unsupported compoment argument."
    }
}

###############################################################################
###
### Uninstalls Mahout component.
###
### Arguments:
###     component: Component to be uninstalled, it can be only "mahout" for now
###     nodeInstallRoot: Install folder (for example "C:\Hadoop")
###
###############################################################################
function Uninstall(
        [String]
        [Parameter( Position=0, Mandatory=$true )]
        $component,
        [String]
        [Parameter( Position=1, Mandatory=$true )]
        $nodeInstallRoot
        )
{
    if ( $component -eq "mahout" )
    {

        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"

        ### $installToDir: the directory that contains the application, after unzipping
        $installToDir = Join-Path "$nodeInstallRoot" "$FinalName"
        Write-Log "installToDir: $installToDir"


        ###
        ### Delete the Mahout directory
        ###
        Write-Log "Deleting $installToDir"
        $cmd = "rd /s /q `"$installToDir`""
        Invoke-Cmd $cmd
    }
    else
    {
        throw "Uninstall: Unsupported component argument."
    }
}

###############################################################################
###
### Alters the configuration of the component.
###
### Arguments:
###     component: Component to be configured, e.g "mahout"
###     nodeInstallRoot: Target install folder (for example "C:\Hadoop")
###     serviceCredential: Credential object used for service creation
###     configs: Configuration that should be applied.
###              For example, @{"mahout.jar" = "C:\Hadoop\mahout\mahout.jar"}
###              for details.
###     aclAllFolders: If true, all folders defined in config file will be ACLed
###                    If false, only the folders listed in $configs will be ACLed.
###
###############################################################################
function Configure(
        [String]
        [Parameter( Position=0, Mandatory=$true )]
        $component,
        [String]
        [Parameter( Position=1, Mandatory=$true )]
        $nodeInstallRoot,
        [System.Management.Automation.PSCredential]
        [Parameter( Position=2, Mandatory=$true )]
        $serviceCredential,
        [hashtable]
        [parameter( Position=3 )]
        $configs = @{},
        [bool]
        [parameter( Position=4 )]
        $aclAllFolders = $True
        )
{
    if ( $component -eq "mahout" )
    {
        $HDP_INSTALL_PATH, $HDP_RESOURCES_DIR = Initialize-InstallationEnv $scriptDir "$FinalName.winpkg.log"

        ### $installToDir: the directory that contains the application, after unzipping
        $installToDir = Join-Path "$nodeInstallRoot" "$FinalName"
        $installToBin = Join-Path "$installToDir" "bin"
        Write-Log "installToDir: $installToDir"

        if( -not (Test-Path $installToDir ))
        {
            throw "Configure: Install mahout before configuring it"
        }

    }
    else
    {
        throw "Configure: Unsupported compoment argument."
    }
}

###############################################################################
###
### Start component services.
###
### Arguments:
###     component: Component name
###     roles: List of space separated service to start
###
###############################################################################
function StartService(
        [String]
        [Parameter( Position=0, Mandatory=$true )]
        $component,
        [String]
        [Parameter( Position=1, Mandatory=$true )]
        $roles
        )
{
    Write-Log "Starting `"$component`" `"$roles`" services"

    if ( $component -eq "mahout" )
    {
        ### Verify that roles are in the supported set
        CheckRole $roles @("mahout")

        foreach ( $role in $roles.Split(" ") )
        {
            Write-Log "Starting $role service"
            Start-Service $role
        }
    }
    else
    {
        throw "StartService: Unsupported compoment argument."
    }
}

###############################################################################
###
### Stop component services.
###
### Arguments:
###     component: Component name
###     roles: List of space separated service to stop
###
###############################################################################
function StopService(
        [String]
        [Parameter( Position=0, Mandatory=$true )]
        $component,
        [String]
        [Parameter( Position=1, Mandatory=$true )]
        $roles
        )
{
    Write-Log "Stopping `"$component`" `"$roles`" services"

        if ( $component -eq "mahout" )
        {
### Verify that roles are in the supported set
            CheckRole $roles @("mahout")
                foreach ( $role in $roles.Split(" ") )
                {
                    try
                    {
                        Write-Log "Stopping $role "
                            if (Get-Service "$role" -ErrorAction SilentlyContinue)
                            {
                                Write-Log "Service $role exists, stopping it"
                                    Stop-Service $role
                            }
                            else
                            {
                                Write-Log "Service $role does not exist, moving to next"
                            }
                    }
                    catch [Exception]
                    {
                        Write-Host "Can't stop service $role"
                    }
                }
        }
        else
        {
            throw "StartService: Unsupported compoment argument."
        }
}


### Helper routing that converts a $null object to nothing. Otherwise, iterating over
### a $null object with foreach results in a loop with one $null element.
function empty-null($obj)
{
    if ($obj -ne $null) { $obj }
}

### Checks if the given space separated roles are in the given array of
### supported roles.
function CheckRole(
        [string]
        [parameter( Position=0, Mandatory=$true )]
        $roles,
        [array]
        [parameter( Position=1, Mandatory=$true )]
        $supportedRoles
        )
{
    foreach ( $role in $roles.Split(" ") )
    {
        if ( -not ( $supportedRoles -contains $role ) )
        {
            throw "CheckRole: Passed in role `"$role`" is outside of the supported set `"$supportedRoles`""
        }
    }
}

### Creates and configures the service.
function CreateAndConfigureHadoopService(
        [String]
        [Parameter( Position=0, Mandatory=$true )]
        $service,
        [String]
        [Parameter( Position=1, Mandatory=$true )]
        $hdpResourcesDir,
        [String]
        [Parameter( Position=2, Mandatory=$true )]
        $serviceBinDir,
        [System.Management.Automation.PSCredential]
        [Parameter( Position=3, Mandatory=$true )]
        $serviceCredential
        )
{
    if ( -not ( Get-Service "$service" -ErrorAction SilentlyContinue ) )
    {
        Write-Log "Creating service `"$service`" as $serviceBinDir\$service.exe"
        $xcopyServiceHost_cmd = "copy /Y `"$hdpResourcesDir\serviceHost.exe`" `"$serviceBinDir\$service.exe`""
        Invoke-CmdChk $xcopyServiceHost_cmd

        #HadoopServiceHost.exe will write to this log but does not create it
        #Creating the event log needs to be done from an elevated process, so we do it here
        if( -not ([Diagnostics.EventLog]::SourceExists( "$service" )))
        {
            [Diagnostics.EventLog]::CreateEventSource( "$service", "" )
        }

        Write-Log "Adding service $service"
        $s = New-Service -Name "$service" -BinaryPathName "$serviceBinDir\$service.exe" -Credential $serviceCredential -DisplayName "Apache Hadoop $service"
        if ( $s -eq $null )
        {
            throw "CreateAndConfigureHadoopService: Service `"$service`" creation failed"
        }

        $cmd="$ENV:WINDIR\system32\sc.exe failure $service reset= 30 actions= restart/5000"
        Invoke-CmdChk $cmd

        $cmd="$ENV:WINDIR\system32\sc.exe config $service start= demand"
        Invoke-CmdChk $cmd

        Set-ServiceAcl $service
    }
    else
    {
        Write-Log "Service `"$service`" already exists, Removing `"$service`""
        StopAndDeleteHadoopService $service
        CreateAndConfigureHadoopService $service $hdpResourcesDir $serviceBinDir $serviceCredential
    }
}

### Stops and deletes the Hadoop service.
function StopAndDeleteHadoopService(
        [String]
        [Parameter( Position=0, Mandatory=$true )]
        $service
        )
{
    Write-Log "Stopping $service"
        $s = Get-Service $service -ErrorAction SilentlyContinue

        if( $s -ne $null )
        {
            Stop-Service $service
            $cmd = "sc.exe delete $service"
            Invoke-Cmd $cmd
        }
}

### Returns the value of the given propertyName from the given xml file.
###
### Arguments:
###     xmlFileName: Xml file full path
###     propertyName: Name of the property to retrieve
function FindXmlPropertyValue(
        [string]
        [parameter( Position=0, Mandatory=$true )]
        $xmlFileName,
        [string]
        [parameter( Position=1, Mandatory=$true )]
        $propertyName)
{
    $value = $null

    if ( Test-Path $xmlFileName )
    {
        $xml = [xml] (Get-Content $xmlFileName)
            $xml.SelectNodes('/configuration/property') | ? { $_.name -eq $propertyName } | % { $value = $_.value }
        $xml.ReleasePath
    }

    $value
}

### Helper routine that updates the given fileName XML file with the given
### key/value configuration values. The XML file is expected to be in the
### Hadoop format. For example:
### <configuration>
###   <property>
###     <name.../><value.../>
###   </property>
### </configuration>
function UpdateXmlConfig(
        [string]
        [parameter( Position=0, Mandatory=$true )]
        $fileName,
        [hashtable]
        [parameter( Position=1 )]
        $config = @{} )
{
    $xml = [xml] (Get-Content $fileName)

    foreach( $key in empty-null $config.Keys )
    {
        $value = $config[$key]
        $found = $False
        $xml.SelectNodes('/configuration/property') | ? { $_.name -eq $key } | % { $_.value = $value; $found = $True }
        if ( -not $found )
        {
            $newItem = $xml.CreateElement("property")
            $newItem.AppendChild($xml.CreateElement("name")) | Out-Null
            $newItem.AppendChild($xml.CreateElement("value")) | Out-Null
            $newItem.name = $key
            $newItem.value = $value
            $xml["configuration"].AppendChild($newItem) | Out-Null
        }
    }

    $xml.Save($fileName)
    $xml.ReleasePath
}

###
### Public API
###
Export-ModuleMember -Function Install
Export-ModuleMember -Function Uninstall
Export-ModuleMember -Function Configure
Export-ModuleMember -Function StartService
Export-ModuleMember -Function StopService
### Private API
Export-ModuleMember -Function UpdateXmlConfig
