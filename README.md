<!---------------------[  Mô tả  ]------------------<recommended> phần bên dưới------------------>

# Triển khai Ứng dụng AI của bạn vào Môi trường Production

**Lưu ý:** Với bất kỳ giải pháp AI nào bạn tạo bằng các mẫu này, bạn có trách nhiệm đánh giá tất cả các rủi ro liên quan và tuân thủ tất cả các luật và tiêu chuẩn an toàn hiện hành. Tìm hiểu thêm trong tài liệu minh bạch cho [Agent Service](https://learn.microsoft.com/en-us/azure/ai-foundry/responsible-ai/agents/transparency-note) và [Agent Framework](https://github.com/microsoft/agent-framework/blob/main/TRANSPARENCY_FAQ.md).

## Tổng quan

<span style="font-size: 3em;">🚀</span> **Mới: Cập nhật triển khai để phù hợp với bản phát hành Foundry tại Build 2025!**
Bản cập nhật mới này đã được thử nghiệm thành công ở khu vực EastUS2.
Đây là giải pháp nền tảng để triển khai tài khoản AI Foundry ([Cognitive Services accountKind = 'AIServices'](https://review.learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts?branch=main&pivots=deployment-language-bicep)) và dự án ([cognitiveServices/projects](https://review.learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts/projects?branch=main&pivots=deployment-language-bicep)) vào môi trường cô lập (vNet) trong Azure. Các tính năng được triển khai tuân theo Well-Architected Framework [WAF](https://learn.microsoft.com/en-us/azure/well-architected/) của Microsoft để thiết lập cơ sở hạ tầng cô lập cho AI Foundry, nhằm hỗ trợ chuyển đổi từ trạng thái Proof of Concept sang ứng dụng sẵn sàng cho production.

Mẫu này tận dụng Azure Verified Modules (AVM) và Azure Developer CLI (AZD) để cung cấp cơ sở hạ tầng tuân thủ WAF cho phát triển ứng dụng AI. Cơ sở hạ tầng này bao gồm các thành phần AI Foundry, mạng ảo (VNET), private endpoints, Key Vault, tài khoản lưu trữ và các tài nguyên tùy chọn tuân thủ WAF bổ sung (như AI Search, Cosmos DB và SQL Server) có thể được tận dụng với các dự án phát triển trên Foundry.

Triển khai sau đây tự động hóa cấu hình được khuyến nghị của chúng tôi để bảo vệ dữ liệu và tài nguyên của bạn; sử dụng kiểm soát truy cập dựa trên vai trò Microsoft Entra ID, mạng được quản lý và private endpoints. Chúng tôi khuyến nghị vô hiệu hóa truy cập mạng công khai cho tài nguyên Azure OpenAI, tài nguyên Azure AI Search và tài khoản lưu trữ (điều này sẽ xảy ra khi triển khai các dịch vụ tùy chọn đó trong quy trình làm việc này). Việc sử dụng mạng đã chọn với quy tắc IP không được hỗ trợ vì địa chỉ IP của các dịch vụ là động.

Repository này sẽ tự động hóa:
1. Cấu hình mạng ảo, private endpoints và dịch vụ private link để cô lập tài nguyên kết nối với tài khoản và dự án một cách an toàn. [Secure Data Playground](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/secure-data-playground)
2. Triển khai và cấu hình cô lập mạng của tài khoản Azure AI Foundry và tài nguyên phụ của dự án trong mạng ảo, với tất cả các dịch vụ được cấu hình phía sau private endpoints. 



## Kiến trúc
Sơ đồ dưới đây minh họa các khả năng được bao gồm trong mẫu.

![Network Isolation Infrastructure](./img/Architecture/FDParch.png)

| Bước trong Sơ đồ      | Mô tả     |
| ------------- | ------------- |
| 1 | Người dùng tenant sử dụng Microsoft Entra ID và xác thực đa yếu tố để đăng nhập vào máy ảo jumpbox |
| 2 | Người dùng và khối lượng công việc trong mạng ảo của khách hàng có thể sử dụng private endpoints để truy cập tài nguyên được quản lý và hub workspace|
| 3 | Mạng ảo được quản lý bởi workspace sẽ tự động được tạo cho bạn khi bạn cấu hình cô lập mạng được quản lý sang một trong các chế độ sau: <br> Allow Internet Outbound <br> Allow Only Approved Outbound|
| 4 | Online endpoint được bảo mật bằng xác thực Microsoft Entra ID. Ứng dụng khách phải lấy token bảo mật từ tenant Microsoft Entra ID trước khi gọi prompt flow được lưu trữ bởi triển khai được quản lý và có sẵn thông qua online endpoint|
| 5 | API Management tạo ra các API gateway nhất quán, hiện đại cho các dịch vụ backend hiện có. Trong kiến trúc này, API Management được sử dụng ở chế độ hoàn toàn riêng tư để giảm tải các vấn đề xuyên suốt từ mã API và lưu trữ.|

## Tính năng

### Giải pháp này cho phép làm gì? 
- Triển khai tài khoản và dự án AI Foundry tận dụng các bản cập nhật AI Foundry mới nhất được công bố tại Build 2025, vào mạng ảo với tất cả các dịch vụ phụ thuộc được kết nối thông qua private endpoints. 

- Cấu hình AI Foundry, tuân thủ các phương pháp hay nhất được nêu trong Well Architected Framework.

- Cung cấp khả năng [thêm các dịch vụ Azure bổ sung trong quá trình triển khai](docs/add_additional_services.md), được cấu hình để kết nối thông qua cô lập nhằm làm phong phú dự án AI của bạn.
    (AI Search, API Management, CosmosDB, Azure SQL DB)

-  <span style="font-size: 3em;">🚀</span> **Mới**: 
Cung cấp khả năng [bắt đầu với một Azure AI Project hiện có](docs/transfer_project_connections.md) sẽ cung cấp các tài nguyên Azure phụ thuộc dựa trên các kết nối đã thiết lập của Project trong AI Foundry.


## Điều kiện tiên quyết và các bước cấp cao

1. Có quyền truy cập vào subscription Azure và tài khoản Entra ID với quyền Contributor.
2. Xác nhận subscription mà bạn đang triển khai có [Vai trò và Phạm vi Bắt buộc](docs/Required_roles_scopes_resources.md).
3. Giải pháp đảm bảo truy cập an toàn vào VNET riêng tư thông qua VM jump-box với Azure Bastion. Theo mặc định, Bastion không yêu cầu quy tắc NSG đầu vào cho lưu lượng mạng. Tuy nhiên, nếu môi trường của bạn thực thi các quy tắc chính sách cụ thể, bạn có thể giải quyết các vấn đề truy cập bằng cách nhập địa chỉ IP của máy của bạn vào tham số `allowedIpAddress` khi được nhắc trong quá trình triển khai. Nếu không chỉ định, tất cả địa chỉ IP được phép kết nối với Azure Bastion. 
4. Nếu triển khai từ [môi trường cục bộ](docs/local_environment_steps.md) của bạn, cài đặt [Azure CLI (AZ)](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) và [Azure Developer CLI (AZD)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd?tabs=winget-windows%2Cbrew-mac%2Cscript-linux&pivots=os-windows).
5. Nếu triển khai qua [GitHub Codespaces](docs/github_code_spaces_steps.md) - yêu cầu người dùng ở trên gói GitHub Team hoặc Enterprise Cloud.
6. Nếu tận dụng [GitHub Actions](docs/github_actions_steps.md).
7. Tùy chọn [bao gồm một ứng dụng chat AI mẫu](/docs/sample_app_setup.md) với triển khai.

### Kiểm tra Khả dụng Hạn ngạch Azure OpenAI  

Để đảm bảo đủ hạn ngạch có sẵn trong subscription của bạn, vui lòng làm theo **[hướng dẫn kiểm tra hạn ngạch](./docs/quota_check.md)** trước khi triển khai giải pháp.

### Các Dịch vụ Được Kích hoạt Kích hoạt

Để biết tài liệu bổ sung về các dịch vụ được kích hoạt mặc định của solution accelerator này, vui lòng xem:

1. [Azure Open AI Service](https://learn.microsoft.com/en-us/azure/ai-services/openai/)
2. [Azure AI Search](https://learn.microsoft.com/en-us/azure/search/)
3. [Azure AI hub](https://learn.microsoft.com/en-us/azure/ai-foundry/)
4. [Azure AI project](https://learn.microsoft.com/en-us/azure/ai-foundry/)
5. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/)
6. [Azure Virtual Machines](https://learn.microsoft.com/en-us/azure/virtual-machines/)
7. [Azure Storage](https://learn.microsoft.com/en-us/azure/storage/)
8. [Azure Virtual Network](https://learn.microsoft.com/en-us/azure/virtual-network/)
9. [Azure Key vault](https://learn.microsoft.com/en-us/azure/key-vault/)
10. [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/)
11. [Azure Log Analytics](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview)
12. [Azure Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)

## Bắt đầu

<h2><img src="./img/Documentation/quickDeploy.png" width="64">
<br/>
TRIỂN KHAI NHANH
</h2>

| [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production) |
|---|---|
[Các bước triển khai với GitHub Codespaces](docs/github_code_spaces_steps.md)| [Các bước triển khai với Dev Container](docs/Dev_ContainerSteps.md)


## Kết nối và xác thực quyền truy cập vào môi trường mới 
Làm theo các bước sau triển khai [Các Bước Sau Triển Khai](docs/github_code_spaces_steps.md) để kết nối với môi trường cô lập.

## Triển khai Ứng dụng Mẫu với môi trường mới
Tùy chọn bao gồm một [ứng dụng chat AI mẫu](/docs/sample_app_setup.md) để giới thiệu một ứng dụng AI production được triển khai vào môi trường an toàn.

## Triển khai ứng dụng của bạn trong môi trường cô lập
- Tận dụng tài liệu Microsoft Learn để cung cấp một app service instance trong mạng an toàn của bạn [Cấu hình Web App](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/on-your-data-configuration#azure-ai-foundry-portal)
- Làm theo các hướng dẫn này để [Thêm dữ liệu của bạn và chat với nó trong AI Foundry playground](https://learn.microsoft.com/en-us/azure/ai-foundry/tutorials/deploy-chat-web-app#add-your-data-and-try-the-chat-model-again)


## Hướng dẫn

### Khả dụng theo Khu vực

Theo mặc định, mẫu này sử dụng các mô hình AI có thể không có sẵn ở tất cả các khu vực Azure. Vui lòng làm theo [hướng dẫn kiểm tra hạn ngạch](./docs/quota_check.md) trước khi triển khai giải pháp. Ngoài ra, kiểm tra [khả dụng khu vực cập nhật](https://learn.microsoft.com/azure/ai-services/openai/concepts/models#standard-deployment-model-availability) và chọn một khu vực trong quá trình triển khai cho phù hợp.

### Chi phí

Bạn có thể ước tính chi phí của kiến trúc dự án này với [máy tính giá của Azure](https://azure.microsoft.com/pricing/calculator/)


### Hướng dẫn Bảo mật

Mẫu này tận dụng [Managed Identity](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview) giữa các dịch vụ để loại bỏ nhu cầu các nhà phát triển phải quản lý các thông tin xác thực này. Ứng dụng có thể sử dụng managed identities để lấy token Microsoft Entra mà không cần quản lý bất kỳ thông tin xác thực nào.

Để đảm bảo tiếp tục các phương pháp hay nhất trong repository của riêng bạn, chúng tôi khuyến nghị bất kỳ ai tạo giải pháp dựa trên các mẫu của chúng tôi đảm bảo rằng cài đặt [Github secret scanning](https://docs.github.com/code-security/secret-scanning/about-secret-scanning) được bật.

Bạn có thể muốn xem xét các biện pháp bảo mật bổ sung, chẳng hạn như:
- Bật Microsoft Defender for Cloud để [bảo mật tài nguyên Azure của bạn](https://learn.microsoft.com/azure/defender-for-cloud/),
>#### Thông báo Bảo mật Quan trọng
>Mẫu này, mã ứng dụng và cấu hình mà nó chứa, đã được xây dựng để giới thiệu các dịch vụ và công cụ cụ thể của Microsoft Azure. Chúng tôi khuyến cáo mạnh mẽ khách hàng của chúng tôi không đưa mã này vào môi trường production của họ mà không triển khai hoặc kích hoạt các tính năng bảo mật bổ sung.
>
>Để biết danh sách đầy đủ hơn về các phương pháp hay nhất và khuyến nghị bảo mật cho Ứng dụng Thông minh, [truy cập tài liệu chính thức của chúng tôi](https://learn.microsoft.com/en-us/azure/ai-foundry/).

## Tài nguyên

- [Tài liệu Azure AI Foundry](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Tài liệu Azure Well Architecture Framework](https://learn.microsoft.com/en-us/azure/well-architected/)
- [Azure OpenAI Service - Tài liệu, quickstarts, tham chiếu API - Azure AI services | Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/use-your-data)
- [Tài liệu Azure AI Content Understanding](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/)
---

## Tuyên bố từ chối trách nhiệm

Trong phạm vi Phần mềm bao gồm các thành phần hoặc mã được sử dụng trong hoặc bắt nguồn từ các sản phẩm hoặc dịch vụ của Microsoft, bao gồm nhưng không giới hạn ở Microsoft Azure Services (gọi chung là "Sản phẩm và Dịch vụ của Microsoft"), bạn cũng phải tuân thủ Điều khoản Sản phẩm áp dụng cho các Sản phẩm và Dịch vụ của Microsoft đó. Bạn thừa nhận và đồng ý rằng giấy phép quản lý Phần mềm không cấp cho bạn giấy phép hoặc quyền khác để sử dụng Sản phẩm và Dịch vụ của Microsoft. Không có gì trong giấy phép hoặc file ReadMe này sẽ thay thế, sửa đổi, chấm dứt hoặc thay đổi bất kỳ điều khoản nào trong Điều khoản Sản phẩm đối với bất kỳ Sản phẩm và Dịch vụ của Microsoft nào.ất kỳ Sản phẩm và Dịch vụ của Microsoft nào. 

Bạn cũng phải tuân thủ tất cả các luật xuất khẩu trong nước và quốc tế áp dụng cho Phần mềm, bao gồm các hạn chế về điểm đến, người dùng cuối và mục đích sử dụng cuối. Để biết thêm thông tin về các hạn chế xuất khẩu, hãy truy cập https://aka.ms/exporting.

Bạn thừa nhận rằng Phần mềm và Sản phẩm và Dịch vụ của Microsoft (1) không được thiết kế, dự định hoặc cung cấp như một thiết bị y tế, và (2) không được thiết kế hoặc dự định để thay thế cho lời khuyên, chẩn đoán, điều trị hoặc phán đoán y tế chuyên nghiệp và không nên được sử dụng để thay thế hoặc như một sự thay thế cho lời khuyên, chẩn đoán, điều trị hoặc phán đoán y tế chuyên nghiệp. Khách hàng hoàn toàn chịu trách nhiệm hiển thị và/hoặc lấy các sự đồng ý, cảnh báo, tuyên bố từ chối trách nhiệm và xác nhận thích hợp cho người dùng cuối của việc triển khai Dịch vụ Trực tuyến của Khách hàng.

You acknowledge the Software is not subject to SOC 1 and SOC 2 compliance audits. No Microsoft technology, nor any of its component technologies, including the Software, is intended or made available as a substitute for the professional advice, opinion, or judgement of a certified financial services professional. Do not use the Software to replace, substitute, or provide professional financial advice or judgment.  

BY ACCESSING OR USING THE SOFTWARE, YOU ACKNOWLEDGE THAT THE SOFTWARE IS NOT DESIGNED OR INTENDED TO SUPPORT ANY USE IN WHICH A SERVICE INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE COULD RESULT IN THE DEATH OR SERIOUS BODILY INJURY OF ANY PERSON OR IN PHYSICAL OR ENVIRONMENTAL DAMAGE (COLLECTIVELY, “HIGH-RISK USE”), AND THAT YOU WILL ENSURE THAT, IN THE EVENT OF ANY INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE, THE SAFETY OF PEOPLE, PROPERTY, AND THE ENVIRONMENT ARE NOT REDUCED BELOW A LEVEL THAT IS REASONABLY, APPROPRIATE, AND LEGAL, WHETHER IN GENERAL OR IN A SPECIFIC INDUSTRY. BY ACCESSING THE SOFTWARE, YOU FURTHER ACKNOWLEDGE THAT YOUR HIGH-RISK USE OF THE SOFTWARE IS AT YOUR OWN RISK.  

* Data Collection. The software may collect information about you and your use of the software and send it to Microsoft. Microsoft may use this information to provide services and improve our products and services. You may turn off the telemetry as described in the repository. There are also some features in the software that may enable you and Microsoft to collect data from users of your applications. If you use these features, you must comply with applicable law, including providing appropriate notices to users of your applications together with a copy of Microsoft’s privacy statement. Our privacy statement is located at https://go.microsoft.com/fwlink/?LinkID=824704. You can learn more about data collection and use in the help documentation and our privacy statement. Your use of the software operates as your consent to these practices.
