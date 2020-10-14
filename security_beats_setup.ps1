param (
    [string]$stack_version = $(throw "-stack_version is required."),
    [string]$cloud_id,
    [string]$password,
    [string]$user_password
)

$install_dir = "C:\Elastic"
$credentials_file_path = "C:\Users\Administrator\Desktop\cluster.txt"
$beat_config_repository_uri = "https://raw.githubusercontent.com/nich07as/elastic-security-workshop/master/"

Write-Output "*** Security Workshop Setup ***`n"

#Update Elastic Cloud Plan based on command line parameters
$cloud_id = $es_cloud_id
$password = $es_cloud_password
$user_password = $es_analyst_password
$kibana_url = $es_kibana_endpoint
$elasticsearch_url = $es_elasticsearch_endpoint

#Create Credentials File
New-Item -Force $credentials_file_path | Out-Null
Add-Content $credentials_file_path "Kibana URL: https://$kibana_url"
Add-Content $credentials_file_path "Elasticsearch URL: https://$elasticsearch_url"
Add-Content $credentials_file_path "Cloud ID: $cloud_id"
Add-Content $credentials_file_path "Username: analyst"
Add-Content $credentials_file_path "Password: $user_password"

#Uninstall all Elastic Beats already installed
$app = Get-WmiObject -Class Win32_Product -Filter ("Vendor = 'Elastic'")
if ($null -ne $app) {
    Write-Output "Uninstalling exising Elastic Beats..."
    $app.Uninstall() | Out-Null
}

#Configure Beats
function ElasticBeatSetup ([string]$beat_name)
{
    Write-Output "`n*** Setting up $beat_name ****"
    $beat_install_folder = "C:\Program Files\Elastic\Beats\$stack_version\$beat_name"
    $beat_exe_path = "$beat_install_folder\$beat_name.exe"
    $beat_config_path = "C:\ProgramData\Elastic\Beats\$beat_name\$beat_name.yml"
    $beat_data_path = "C:\ProgramData\Elastic\Beats\$beat_name\data"
    $beat_config_file = "$beat_config_repository_url/$beatname.yml"
    $beat_artifact_uri = "https://artifacts.elastic.co/downloads/beats/$beat_name/$beat_name-$stack_version-windows-x86_64.msi"
    $log_file_path = "$install_dir\$beat_name.log"

    Write-Output "Installing $beat_name..."
    Invoke-WebRequest -Uri "$beat_artifact_uri" -OutFile "$install_dir\$beat_name-$stack_version-windows-x86_64.msi"
    $MSIArguments = @(
        "/i"
        "$install_dir\$beat_name-$stack_version-windows-x86_64.msi"
        "/qn"
        "/norestart"
        "/L"
        $log_file_path
    )
    Start-Process msiexec.exe -Wait -ArgumentList $MSIArguments -NoNewWindow

    #Download Beat configuration file
    Invoke-WebRequest -Uri "$beat_config_repository_uri/$beat_name.yml" -OutFile $beat_config_path

    # Create Beat Keystore and add CLOUD_ID and ES_PWD keys to it
    $params = $('-c', $beat_config_path, 'keystore','create','--force')
    & $beat_exe_path @params
    $params = $('-c', $beat_config_path, 'keystore','add','CLOUD_ID','--stdin','--force','-path.data', $beat_data_path)
    Write-Output $cloud_id | & $beat_exe_path @params
    $params = $('-c', $beat_config_path, 'keystore','add','ES_PWD','--stdin','--force','-path.data', $beat_data_path)
    Write-Output $password | & $beat_exe_path @params
    
    # Run Beat Setup
    Write-Output "Running $beat_name setup..."
    $params = $('-c', $beat_config_path, 'setup', '-path.data', $beat_data_path)
    & $beat_exe_path @params

    Write-Output "Starting $beat_name Service"
    Start-Service -Name $beat_name
}
ElasticBeatSetup("winlogbeat");
ElasticBeatSetup("packetbeat");
ElasticBeatSetup("metricbeat");

Write-Output "`nSetup complete!"
