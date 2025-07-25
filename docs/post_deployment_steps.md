# Post Deployment Steps:
These steps will help to check that the isolated environment was set up correctly.
Follow these steps to check the creation of the required private endpoints in the environment (when set to networkIsolation = true).

One way to check if the access is private to the hub is to launch the AI Foundry hub from the portal. 

![Image showing if network isolation is checked](../img/provisioning/checkNetworkIsolation3.png)

When a user that is not connected through the virtual network via an RDP approved connection will see the following screen in their browser. This is the intended behavior! 

![Image showing the virtual machine in the browser](../img/provisioning/checkNetworkIsolation4.png)

A more thorough check is to look for the networking settings and checking for private endpoints.
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
