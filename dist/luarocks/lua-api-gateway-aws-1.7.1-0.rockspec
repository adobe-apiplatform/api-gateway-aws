package = "lua-api-gateway-aws"
version = "1.7.1-0"
source = {
   url = "git://github.com/adobe-apiplatform/api-gateway-aws",
   tag = "1.7.1"
}
description = {
   summary = "AWS SDK for NGINX with Lua",
   detailed = [[
Lua module for AWS APIs . The missing AWS SDK from Nginx/Openresty.
Use it to proxy AWS APIs in a simple fashion, with any Http Client that you prefer.]],
   homepage = "https://github.com/adobe-apiplatform/api-gateway-aws",
   license = "Apache 2.0"
}
dependencies = {
  "lua >= 5.1",
  "lua-api-gateway-hmac",
  "lua-resty-http"
}
build = {
   type = "builtin",
   modules = {
      ["api-gateway.aws.AWSBasicCredentials"] = "src/lua/api-gateway/aws/AWSBasicCredentials.lua",
      ["api-gateway.aws.AWSIAMCredentials"] = "src/lua/api-gateway/aws/AWSIAMCredentials.lua",
      ["api-gateway.aws.AWSSTSCredentials"] = "src/lua/api-gateway/aws/AWSSTSCredentials.lua",
      ["api-gateway.aws.AwsDateConverter"] = "src/lua/api-gateway/aws/AwsDateConverter.lua",
      ["api-gateway.aws.AwsService"] = "src/lua/api-gateway/aws/AwsService.lua",
      ["api-gateway.aws.AwsV4Signature"] = "src/lua/api-gateway/aws/AwsV4Signature.lua",
      ["api-gateway.aws.httpclient.http"] = "src/lua/api-gateway/aws/httpclient/http.lua",
      ["api-gateway.aws.httpclient.restyhttp"] = "src/lua/api-gateway/aws/httpclient/restyhttp.lua",
      ["api-gateway.aws.httpclient.url"] = "src/lua/api-gateway/aws/httpclient/url.lua",
      ["api-gateway.aws.kinesis.KinesisService"] = "src/lua/api-gateway/aws/kinesis/KinesisService.lua",
      ["api-gateway.aws.kms.KmsService"] = "src/lua/api-gateway/aws/kms/KmsService.lua",
      ["api-gateway.aws.lambda.LambdaService"] = "src/lua/api-gateway/aws/lambda/LambdaService.lua",
      ["api-gateway.aws.sns.SnsService"] = "src/lua/api-gateway/aws/sns/SnsService.lua",
      ["api-gateway.aws.sts.SecurityTokenService"] = "src/lua/api-gateway/aws/sts/SecurityTokenService.lua"
   }
}
