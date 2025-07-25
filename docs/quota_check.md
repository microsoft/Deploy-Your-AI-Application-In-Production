# Check Quota Availability Before Deployment

Before deploying the accelerator, **ensure sufficient quota availability** for the required model.
> **We recommend increasing the capacity to 100k tokens for optimal performance.**

## Login if you have not done so already
```
az login
```

## 📌 Default Models & Capacities:
```
gpt-4o:30, gpt-4o-mini:30, gpt-4:30, text-embedding-ada-002:80
```
## 📌 Default Regions:
```
eastus, uksouth, eastus2, northcentralus, swedencentral, westus, westus2, southcentralus, canadacentral
```
## Usage Scenarios:
- No parameters passed → Default models and capacities will be checked in default regions.
- Only model(s) provided → The script will check for those models in the default regions.
- Only region(s) provided → The script will check default models in the specified regions.
- Both models and regions provided → The script will check those models in the specified regions.
- `--verbose` passed → Enables detailed logging output for debugging and traceability.
  
## **Input Formats**
> Use the --models, --regions, and --verbose options for parameter handling:

✔️ Run without parameters to check default models & regions without verbose logging:
   ```
  ./quota_check.sh
   ```
✔️ Enable verbose logging:
   ```
  ./quota_check.sh --verbose
   ```
✔️ Check specific model(s) in default regions:
  ```
  ./quota_check.sh --models gpt-4o:30,text-embedding-ada-002:80
  ```
✔️ Check default models in specific region(s):
  ```
./quota_check.sh --regions eastus,westus
  ```
✔️ Passing Both models and regions:  
  ```
  ./quota_check.sh --models gpt-4o:30 --regions eastus,westus2
  ```
✔️ All parameters combined:
  ```
 ./quota_check.sh --models gpt-4:30,text-embedding-ada-002:80 --regions eastus,westus --verbose
  ```

## **Sample Output**
The final table lists regions with available quota. You can select any of these regions for deployment.

![quota-check-output](../img/Documentation/quota-check-output.png)

---
## **If using Azure Portal and Cloud Shell**

1. Navigate to the [Azure Portal](https://portal.azure.com).
2. Click on **Azure Cloud Shell** in the top right navigation menu.
3. Run the appropriate command based on your requirement:  

   **To check quota for the deployment**  

    ```sh
    curl -L -o quota_check.sh "https://raw.githubusercontent.com/microsoft/Deploy-Your-AI-Application-In-Production/main/scripts/quota_check.sh"
    chmod +x quota_check.sh
    ./quota_check.sh
    ```
    - Refer to [Input Formats](#input-formats) for detailed commands.
      
## **If using VS Code or Codespaces**
1. Open the terminal in VS Code or Codespaces.
2. If you're using VS Code, click the dropdown on the right side of the terminal window, and select `Git Bash`.
   ![git_bash](../img/provisioning/git_bash.png)
3. Navigate to the `scripts` folder where the script files are located and make the script as executable:
   ```sh
    cd scripts
    chmod +x quota_check.sh
    ```
4. Run the appropriate script based on your requirement:  

   **To check quota for the deployment**  

    ```sh
    ./quota_check.sh
    ```
   - Refer to [Input Formats](#input-formats) for detailed commands.