### GitHub Codespaces

You can run this solution using GitHub Codespaces. The button will open a web-based VS Code instance in your browser:

1. Open the solution accelerator (this may take several minutes):

    [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production)
2. Accept the default values on the create Codespaces page
3. Open a terminal window if it is not already open
4. Continue with the [deploying steps](#deploying)


# Steps to Provision Network Isolated environment using GitHub Codespaces using AZD CLI

1. Navigate to the repo
2. Click the code button
3. Click the Codespaces tab
4. Click "Create Codespaces on main"

   ![Image showing Codespaces in the browser](../img/provisioning/codespaces.png)

   This step will create the codespaces environment for you and launch a web based VS Code session.
5. In the terminal window (usually below by default) you can select the layout of the window in the upper right corner.

   ![Image showing VS Code terminal](../img/provisioning/vscode_terminal.png)

6. Log into your Azure subscription by leveraging the “azd auth login” command. Type the command “azd auth login”. It will display a code to copy and paste into the authorization window that will appear when you hit the enter button.

   ![Image showing the entering of the command 'azd auth' in the terminal of VS Code](../img/provisioning/azdauthcommandline.png)

   ![image showing the authorization window opening in the browser](../img/provisioning/azdauthpopup.png)

   ![Image showing the password prompt for azure](../img/provisioning/enterpassword.png)

   **Prompting for MFA**

   ![Image showing the pop up window in the web browser for azd auth](../img/provisioning/azdauthpopup.png)

7. Repeat the same process in #6 using the “az login” command. The [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/what-is-azure-cli?view=azure-cli-latest) is used to validate available AI model quota.
     ![image showing theaz login in the vs code terminal](../img/provisioning/az_login.png)  

8. Return to the codespaces window now. In the terminal window, begin by initializing the environment by typing the command “azd init”

   ![image showing the initial screen in the vs code terminal](../img/provisioning/azd_init_terminal.png)

9. Enter the name for your environment

   ![aImage showing entering a new environment name](../img/provisioning/enter_evn_name.png)

10. Now start the deployment of the infrastructure by typing the command “azd up”

    ![image showing the terminal in vs code](../img/provisioning/azd_provision_terminal.png)

    This step will allow you to choose from the subscriptions you have available, based on the account you logged in with in the login step. Next it will prompt you for the region to deploy the resources into as well as any additional Azure resources to be provisioned and configured.

        **Be sure to remember the vm password. This will be used in a later step. You are still required to log into Azure once you connect through the virtual machine.


11. The automated model quota check will run, and will check if the location selected will have the necessary quota for the AI Models that are listed in the parameters file prior to deploying any resources. If the location selected has sufficient quota for the models you plan to deploy, the provisioning will begin without notification.

    ![image showing model quota pre-provision pass](../img/provisioning/preprovision_success.png)

    If the location selected does not have the available quota for the models selected in your parameters, there will be a message back to the user, prior to any provisioning of resources. This will allow the developer to change the location of the provisiong and try again. Note that in our example, Italy North had capacity for gpt-4o but not for text-embedding-ada-002. This terminated the entire provisioning, because both models could not be deployed due to a quota issue.

12. After completeing the required paramters that you were prompted for, and a successful model quota validation, the provisioning of resources will run and deploy the Network Isolated AI Foundry development portal and dependent resources in about 20 minutes.


# Post Deployment Steps:
These steps will help to check that the isolated environment was set up correctly.
Follow these steps to check the creation of the required private endpoints in the environment (when set to networkIsolation = true).

One way to check if the access is private to the hub is to launch the AI Foundry hub from the portal. 

![Image showing if network isolation is checked](../img/provisioning/checkNetworkIsolation3.png)

When a user that is not connected through the virtual network via an RDP approved connection will see the following screen in their browser. This is the intended behavior! 

![Image showing the virtual machine in the browser](../img/provisioning/checkNetworkIsolation4.png)

A more thourough check is to look for the networking settings and checking for private end points.

1. Go to the Azure Portal and select your Azure AI hub that was just created.

2.	Click on Settings and then Networking.

    ![Image showing the Azure Portal for AI Foundry Hub and the settings blade](../img/provisioning/checkNetworkIsolation1.png)

3.	Open the Workspace managed outbound access tab.

    ![Image showing the Azure Portal for AI Foundry Hub and the Workspace managed outbound access tab](../img/provisioning/checkNetworkIsolation2.png)

    Here, you will find the private endpoints that are connected to the resources within the hub managed virtual network. Ensure that these private endpoints are active.
    The hub should show that Public access is ‘disabled’.

## Connecting to the isolated network via RDP
1.	Navigate to the resource group where the isolated AI Foundry was deployed to and select the virtual machine.

    ![Image showing the Azure Portal for the virtual machine](../img/provisioning/checkNetworkIsolation5.png)

2.	Be sure that the Virtual Machine is running. If not, start the VM.

    ![Image showing the Azure Portal VM and the start/stop button](../img/provisioning/checkNetworkIsolation6.png)

3.	Select “Bastion” under the ‘Connect’ heading in the VM resource.

    ![Image showing the bastion blade selected](../img/provisioning/checkNetworkIsolation7.png)

4.	Supply the username and the password you created as environment variables and press the connect button.

    ![Image showing the screen to enter the VM Admin info and the connect to bastion button](../img/provisioning/checkNetworkIsolation8.png)

5.	Your virtual machine will launch and you will see a different screen.

    ![Image showing the opening of the Virtual machine in another browser tab](../img/provisioning/checkNetworkIsolation9.png)

6.	Launch Edge browser and navigate to your AI Foundry Hub. https://ai.azure.com Sign in using your credentials.


7.	You are challenged by MFA to connect.

    ![Image showing the Multi Factor Authentication popup](../img/provisioning/checkNetworkIsolation10.png)

8.	You will now be able to view the Foundry Hub which is contained in an isolated network.

    ![Image showing the Azure Foundry AI Hub with a private bubble icon](../img/provisioning/checkNetworkIsolation11.png)

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
