<#
.SYNOPSIS
  Check Boundaries Device UI
.DESCRIPTION
  Simple GUI to determine if a device is within an SCCM boundary based on its IP or hostname. 
  Indicates assigned site systems.
.NOTES
  Version:        1.0
  Author:         Letalys
  Creation Date:  27/02/2023
  Purpose/Change: Initial script development
#>

$MainCode = {
    #region Variables
    $CCMServer = "<Your SCCM Server>"
    $CCMDrive = "<Your Site Code>"
    $DomainName = "<Your Domain>"
    #endregion Variables

    #Region Import SCCM Module
    try {
        Write-Host -ForegroundColor Yellow (Get-Module -Name ConfigurationManager).Version
        Write-Host -ForegroundColor Yellow (Get-Module -Name ConfigurationManager).Path

	    Import-module "C:\Program Files (x86)\Microsoft Endpoint Manager\bin\ConfigurationManager\ConfigurationManager.psd1"

	    New-PSDrive -Name "$CCMDrive" -PSProvider "CMSite" -Root "$CCMServer" -Description "Site Primaire" | Out-Null
	    Set-Location -Path "$($CCMDrive):"

    }catch{
	    Write-Host "Script:" $PSCommandPath
	    Write-Host "Path:" $ScriptLocation
	    write-Error $Error[0]
	    exit
    }
    #endregion Import SCCM Module
    #region Fonctions
    Function IsIpAddressInRange {
        param(
                [string] $ipAddress,
                [string] $fromAddress,
                [string] $toAddress
            )
        
            $ip = [system.net.ipaddress]::Parse($ipAddress).GetAddressBytes()
            [array]::Reverse($ip)
            $ip = [system.BitConverter]::ToUInt32($ip, 0)
        
            $from = [system.net.ipaddress]::Parse($fromAddress).GetAddressBytes()
            [array]::Reverse($from)
            $from = [system.BitConverter]::ToUInt32($from, 0)
        
            $to = [system.net.ipaddress]::Parse($toAddress).GetAddressBytes()
            [array]::Reverse($to)
            $to = [system.BitConverter]::ToUInt32($to, 0)
        
            $from -le $ip -and $ip -le $to
        }
    #endregion

    #region XAML Loader
    [xml]$XAML = [IO.File]::ReadAllText(".\UI\CheckDeviceBoundaries.UI.xml",[Text.Encoding]::GetEncoding(65001))
    #endregion

    #region XAML UI Load
    #Creation of a Thread-Safe synchronization HashTable, allows to retrieve objects and properties by any RunSpace (Execution space)
    $syncHash = [hashtable]::Synchronized(@{})

    #Load XAML and Add to Hashtable
    $XAMLReader=(New-Object System.Xml.XmlNodeReader $XAML)
    $syncHash.Window=[Windows.Markup.XamlReader]::Load($XAMLReader)
    #endregion XAML Loader

    #region XAML Events
    $syncHash.Window.FindName("FormUI").Add_ContentRendered({
        $syncHash.Window.FindName("TXT_SearchByDevice").IsEnabled =$True
        $syncHash.Window.FindName("TXT_SearchByDevice").Focus
        $syncHash.Window.FindName("TXT_SearchByIP").IsEnabled =$false
        $syncHash.Window.FindName("LBL_State").content = $Null
        $syncHash.Window.FindName("LBL_BoundName").content = $null
        $syncHash.Window.FindName("LBL_BoundRange").content = $null
        $syncHash.Window.FindName("LBX_BoundSystem").ItemsSource = $null
    })

    $syncHash.Window.FindName("RB_SearchByDevice").add_Checked({
        $syncHash.Window.FindName("TXT_SearchByDevice").IsEnabled =$True
        $syncHash.Window.FindName("TXT_SearchByDevice").Focus
        $syncHash.Window.FindName("TXT_SearchByIP").IsEnabled =$false
    })

    $syncHash.Window.FindName("RB_SearchByIP").add_Checked({
        $syncHash.Window.FindName("TXT_SearchByIP").IsEnabled =$True
        $syncHash.Window.FindName("TXT_SearchByIP").Focus
        $syncHash.Window.FindName("TXT_SearchByDevice").IsEnabled =$false
    })

    $syncHash.Window.FindName("B_Search").add_Click({
        $syncHash.Window.FindName("LBL_BoundName").Content = $null
        $syncHash.Window.FindName("LBL_BoundRange").Content = $null
        $syncHash.Window.FindName("LBX_BoundSystem").ItemsSource = $null
        
        $CurrentSearch = $null
        $CurrentIPResult = $null
        $ResultDNS = $null

        Switch($true){
            $syncHash.Window.FindName("RB_SearchByDevice").IsChecked {
                $syncHash.Window.FindName("TXT_SearchByIP").Text = $null    
                
                $ResultDNS = Resolve-DnsName -Name $syncHash.Window.FindName("TXT_SearchByDevice").Text -Type A -ErrorAction SilentlyContinue | Select-Object Name, IPAddress 
                
                if($ResultDNS -ne $null){
                    if($ResultDNS.IPAddress.Count -gt 1){
                        $CurrentIPResult = $ResultDNS.IPAddress[0]
                    }else{
                        $CurrentIPResult = $ResultDNS.IPAddress
                    }
    
                    $syncHash.Window.FindName("TXT_SearchByIP").Text = $CurrentIPResult
                    $TestState = Test-Connection $syncHash.Window.FindName("TXT_SearchByIP").Text -Count 1 -ErrorAction SilentlyContinue
    
                    if($TestState -ne $null){
                        $syncHash.Window.FindName("$LBL_State").Content = "Connected"
                        $syncHash.Window.FindName("$LBL_State").Foreground = "#FF0FA94A"
                    }else{
                        $syncHash.Window.FindName("$LBL_State").Content = "Disconnected"
                        $syncHash.Window.FindName("$LBL_State").Foreground = "#FFD2082D"
                    }
                }else{
                    $syncHash.Window.FindName("TXT_SearchByIP").Text = "Not Found"
                }
            }
    
    
            $syncHash.Window.FindName("RB_SearchByIP").IsChecked {
                $syncHash.Window.FindName("TXT_SearchByDevice").Text = $null
                $CurrentSearch = $syncHash.Window.FindName("TXT_SearchByIP").Text
    
                $ResultDNS = Resolve-DnsName $CurrentSearch | Select-Object NameHost 
    
                if($ResultDNS -ne $null){
                    $syncHash.Window.FindName("TXT_SearchByDevice").Text = $ResultDNS.NameHost.Replace(".$DomainName",$null)
    
                    $TestState = Test-Connection $syncHash.Window.FindName("TXT_SearchByIP").Text -Count 1 -ErrorAction SilentlyContinue
    
                    if($TestState -ne $null){
                        $syncHash.Window.FindName("LBL_State").Content = "Connected"
                        $syncHash.Window.FindName("LBL_State").Foreground = "#FF0FA94A"
                    }else{
                        $syncHash.Window.FindName("LBL_State").Content = "Disconnected"
                        $syncHash.Window.FindName("LBL_State").Foreground = "#FFD2082D"
                    }
                }else{
                    $syncHash.Window.FindName("TXT_SearchByDevice").Text = "Not found"
                }
            }
        }
    
        $BoundariesList = Get-CMBoundary
        $BoundaryFound = $false
            Foreach($b in $BoundariesList){
                $IpRange1 = $($b.Value -Split "-")[0]
                $IpRange2 = $($b.Value -Split "-")[1]
    
                If((IsIpAddressInRange $($syncHash.Window.FindName("TXT_SearchByIP").Text) $IpRange1 $IpRange2) -eq $true){
                    $syncHash.Window.FindName("LBL_BoundName").Content = $b.DisplayName
                    $syncHash.Window.FindName("LBL_BoundRange").Content = $b.Value
                    $syncHash.Window.FindName("LBX_BoundSystem").ItemsSource = $b.SiteSystems
                    $BoundaryFound = $true
                    break
                } 
            }
            if($BoundaryFound -eq $false){
                $LBL_BoundName.Content = "No associated boudary"
                $LBL_BoundRange.Content = $null
                $LBX_BoundSystem.ItemsSource = $null
            }
    })
    #endregion XAML Events

    $syncHash.Window.ShowDialog()
    $Runspace.Close()
    $Runspace.Dispose()
}

#region Main Runspace
$PSInstanceMain = [powershell]::Create()
$PSInstanceMain.AddScript($MainCode)

$PSInstanceMain.Runspace = $Runspace
$Job = $PSInstanceMain.BeginInvoke()

 # Wait Job Completed
 while (-not $Job.IsCompleted) {
    Start-Sleep -Seconds 1
 }

$PSInstanceMain.EndInvoke($Job)
#endregion