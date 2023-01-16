# esp-terraform-ecs-fargate
[![workflow](https://github.com/nlykkei/esp-terraform-ecs-fargate/actions/workflows/app.yml/badge.svg)](https://github.com/nlykkei/esp-terraform-ecs-fargate/actions/workflows/app.yml)&nbsp;&nbsp;[![workflow](https://github.com/nlykkei/esp-terraform-ecs-fargate/actions/workflows/api.yml/badge.svg)](https://github.com/nlykkei/esp-terraform-ecs-fargate/actions/workflows/api.yml)

This projects deploys a web applicaton and API on AWS ECS Fargate with automatic scaling, service discovery, and monitoring.

The web application supports Azure AD OIDC authentication for retrieving ID token (user's identity) and access token (API claim).

## Architecture 
![image](https://user-images.githubusercontent.com/14088508/212656573-0cbc4c2c-b560-4c5a-9711-b8056edb456f.png)

## CI/CD
- Run integration tests
- Build Docker image
- Publish it to private ECR
- Update ECS Service (by editing task image)
