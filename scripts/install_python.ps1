$url = 'https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe'
$output = "$env:TEMP\\python-installer.exe"
Invoke-WebRequest -Uri $url -OutFile $output;
Start-Process -FilePath $output -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1' -Wait;