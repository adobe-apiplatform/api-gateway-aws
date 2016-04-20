api-gateway-aws
===============

Lua module for AWS APIs . The missing AWS SDK from Nginx/Openresty.
Use it to proxy AWS APIs in a simple fashion, with any Http Client that you prefer.

Table of Contents
=================

* [Status](#status)
* [Description](#description)
* [Synopsis](#synopsis)
* [Developer Guide](#developer-guide)


Status
======

This library is considered production ready.

It needs a bit of love to support more AWS APIs as the list of APIs is small at the moment.
But even if not all AWS APIs are exposed via Lua class wrappers, you can still use any AWS API via a generic Lua wrapper `AwsService`.

Description
===========

This library requires an nginx build with OpenSSL,
the [ngx_lua module](http://wiki.nginx.org/HttpLuaModule), [LuaJIT 2.0](http://luajit.org/luajit.html),
[api-gateway-hmac](https://github.com/adobe-apiplatform/api-gateway-hmac) module, and
[lua-resty-http](https://github.com/pintsized/lua-resty-http) module.

### AWS Credentials Provider
Requests to AWS Services must supply valid credentials and this library provides a few credentials providers for signing AWS Requests.
`aws_credentials` config option specifies which provider to use. 

If no `aws_credentials` is provided then the library will try to find one using the following order:
 
1. if `aws_access_key` and `aws_secret_key` are provided then Basic Credentials Provider is used. 
2. Otherwise the IAM Credentials Provider is used. 
   
>INFO: This library supports the latest AWS V4 signature which means you can use any of the latest AWS APIs without any problem.



#### Basic Credentials
Basic credentials work with `secret_key` and `access_key`.
```lua
aws_credentials = {
    provider = "api-gateway.aws.AWSBasicCredentials",
    access_key = "replace-me",
    secret_key = "replace-me"
}
```
>INFO: For better security inside the AWS environment use IAM or STS credentials.

#### IAM Credentials
This is probably the most popular credentials provider to be used inside the AWS environment. 
To learn more about IAM Credentials see [IAM Roles for Amazon EC2](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html).

This credentials provider discovers automatically the `IAM Role` associated to the EC2 instance retrieving its credentials and caching them.
  This is a more secure method for signing AWS requests as credentials are short lived and the NGINX configuration doesn't need to maintain any `access_key` or `secret_key` nor worry about rotating the keys. 

```lua
aws_credentials = {
    provider = "api-gateway.aws.AWSIAMCredentials",
    shared_cache_dict = "my_dict"    -- the name of a shared dictionary used for caching IAM Credentials
}
```

#### STS Credentials
AWS Security Token Service(STS) provides a great way to get limited-privilege credentials for accessing AWS Services.
 To learn more about STS Credentials see [Getting Temporary Credentials with STS](http://docs.aws.amazon.com/AWSSdkDocsJava/latest/DeveloperGuide/prog-services-sts.html) and the [STS](#sts) section bellow.
```lua
aws_credentials = {
    provider = "api-gateway.aws.AWSSTSCredentials",
    role_ARN = "arn:aws:iam::111111:role/assumed_role_kinesis", -- ARN of the role to assume
    role_session_name = "kinesis-session",                      -- a name for this session
    shared_cache_dict = "shared_cache"                          -- shared dict for caching the credentials
}    
```
Unlike IAM Credentials that exposes a single IAM Role for each EC2 instance, STS Credentials allows an EC2 instance to assume multiple roles each with its own access policy.

This credentials provider uses [SecurityTokenService](src/lua/api-gateway/aws/sts/SecurityTokenService.lua) for making requests to STS and SecurityTokenService uses the IAM Credentials provider for making the call.
 It is strongly recommended to provide the `shared_cache_dict` in order to improve performance. The temporary credentials obtained from STS are stored in the `shared_cache_dict` for up to 60 minutes.

### AwsService wrapper
[AwsService](src/lua/api-gateway/aws/AwsService.lua) is a generic Lua class to interact with any AWS API. The actual implementations extend this class.
 Its configuration is straight forward:
 
```lua
local service = AwsService:new({
     aws_service = "sns",
     aws_region = "us-east-1",
     aws_credentials = {
        provider = "api-gateway.aws.AWSIAMCredentials",
        shared_cache_dict = "my_dict" -- the name of a shared dictionary used for caching IAM Credentials
     }
     aws_debug = true,              -- print warn level messages on the nginx logs. useful for debugging
     aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS open
     aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
})
```


Synopsis
========
### Kinesis

```lua

    local KinesisService = require "api-gateway.aws.kinesis.KinesisService"
    local service = KinesisService:new({
        aws_region = ngx.var.aws_region,
        aws_secret_key = ngx.var.aws_secret_key,
        aws_access_key = ngx.var.aws_access_key
    })
    
    -- CreateStream
    local response = service:createStream("test-stream")

    -- ListStreams
    local streams  = service:listStreams()

    -- PutRecord
    local response = service:putRecord("test-stream","test-message", "partitionKey")
    
    -- PutRecords
    local records = {
       {
          Data = "test-data-1",
          PartitionKey = "partitionKey-1"
       },
       {
          Data = "test-data-2",
          PartitionKey = "partitionKey-2"
       }
    }
    local response = service:putRecords("test-stream", records)

```

### Lambda

```lua

    local LambdaService = require "api-gateway.aws.lambda.LambdaService"

    local service = LambdaService:new({
        aws_region = ngx.var.aws_region,
        aws_debug = true,              -- print warn level messages on the nginx logs
        aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS alive
        aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
    })

    --Invoke function
    local payload = {
                        key1 = "value-1",
                        key2 = "value-2"
                    }
    local functionName = "hello-world-test"
    local invokeResult, code, headers, status, body  = service:invoke(functionName, payload)
    ngx.say("EXECUTION RESULT:" .. tostring(body))

    --Invoke a Lambda function from another AWS account
    functionName = "arn:aws:lambda:us-east-1:123123123123123:function:hello-world"
    invokeResult, code, headers, status, body  = service:invoke(functionName, payload)
    ngx.say("EXECUTION RESULT FROM ANOTHER AWS ACCOUNT:" .. tostring(body))

```

Note that in order to call a Lambda function cross AWS Accounts you need to have the correct policies in place.
Let's say an EC2 node in the account `789789789789789` with a role `webserver` needs to call a lambda function defined in another AWS account `123123123123123`.

1. Create a new Lambda function in account `123123123123123`, i.e `hello-world-lambda-fn`

2. Make sure that the `webserver` role in account `789789789789789` can call Lambda functions from other AWS accounts.
   Create a new role policy for `webserver`:

```javascript
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1437070759000",
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": [
                "arn:aws:lambda:*:*:*:*"
            ]
        }
    ]
}
```

3. Go to the other AWS Account `123123123123123` where you want to invoke the Lambda function and using AWS CLI add a new policy for your lambda function

```bash
$ aws lambda add-permission   \
   --function-name hello-world-lambda-fn \
   --statement-id stmt-lambda-Id-456 \
   --action "lambda:InvokeFunction"  \
   --principal arn:aws:iam::789789789789789:role/webserver
   --region us-east-1
# should yield
{
    "Statement": "{\"Action\":[\"lambda:InvokeFunction\"],\"Resource\":\"arn:aws:lambda:us-east-1:123123123123123:function:hello-world-lambda-fn\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::789789789789789:role/webserver\"},\"Sid\":\"stmt-lambda-Id-456\"}"
}
```
You have to make sure that the user you're adding the permissions with does have the rights to `lambda:AddPermission` and `lambda:GetPolicy`.

To verify you have the policy added you can execute:

```bash
aws lambda get-policy --function-name hello-world-lambda-fn --region=us-east-1
```

### SNS

```lua

    local SnsService = require "api-gateway.aws.sns.SnsService"
    local service = SnsService:new({
        aws_region = ngx.var.aws_region,
        aws_secret_key = ngx.var.aws_secret_key,
        aws_access_key = ngx.var.aws_access_key
    })

    -- ListTopics
    local list  = service:listTopics()
    local topicArn = list.ListTopicsResponse.ListTopicsResult.Topics[1].TopicArn

    -- Publish
    local response = service:publish("test-subject","test-message", topicArn)
    local messageId = response.PublishResponse.PublishResult.MessageId

```

### KMS

```lua

       local KmsService = require "api-gateway.aws.kms.KmsService"

       local service = KmsService:new({
           aws_region = ngx.var.aws_region,
           aws_secret_key = ngx.var.aws_secret_key,
           aws_access_key = ngx.var.aws_access_key
       })

       -- search for aliases
       local list  = service:listAliases()

       -- pick the first alias
       local KeyId = list.Aliases[1].AliasName

       -- generate a data key
       local cipher = service:generateDataKey(KeyId, "AES_256")
       local blob = cipher.CiphertextBlob
       local blob_text = cipher.Plaintext

       -- encrypt a text
       local encryptResult = service:encrypt(KeyId, blob_text)

       -- decrypt
       local decryptResult = service:decrypt(encryptResult.CiphertextBlob)

```

### STS

The AWS Security Token Service (STS) provides access to temporary, limited-privilege credentials for AWS Identity and IAM users. 
This can be useful for communicating with a a third party AWS account, without having access to some long-term credentials. (ex. IAM user's access key).

The [SecurityTokenService](src/lua/api-gateway/aws/sts/SecurityTokenService.lua) is a AWS STS API wrapper and it provides support for the `AssumeRole` requests. It can be used as follows:

```lua

       local SecuriyTokenService = require "api-gateway.aws.sts.SecuriyTokenService"

       local service = SecuriyTokenService:new({
           aws_region = ngx.var.aws_region,
           aws_secret_key = ngx.var.aws_secret_key,
           aws_access_key = ngx.var.aws_access_key
       })
       
       local response, code, headers, status, body = sts:assumeRole(role_ARN,
                role_session_name,
                policy,
                security_credentials_timeout,
                external_id)       
```

These are the steps that need to be followed in order to be able to generate temporary credentials:
 
Let's say that the AWS account `A` needs to send records to a Kinesis stream in account `B`.

* Create a role in account `B` that grants permission to write to Kinesis and update the `Trust Relationship` as follows:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{A-account-number}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}    
```
* The role from account `A` should be set to allow `sts:AssumeRole` actions pointing to the `B` account:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "sts:AssumeRole",
    "Resource": "arn:aws:iam::{B-account-number}:role/*"
  }]
}    
```

* Call AWS STS AssumeRole API to obtain temporary credentials.
```lua 
       local response, code, headers, status, body = sts:assumeRole(role_ARN,
                role_session_name,
                policy,
                security_credentials_timeout,
                external_id)       
```

>INFO: For more information on how to configure the accounts see [How to Use an External ID When Granting Access to Your AWS Resources to a Third Party](http://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html).

[Back to TOC](#table-of-contents)

Developer guide
===============

## Install the api-gateway first
 Since this module is running inside the `api-gateway`, make sure the api-gateway binary is installed under `/usr/local/sbin`.
 You should have 2 binaries in there: `api-gateway` and `nginx`, the latter being only a symbolik link.

## Update git submodules
```
git submodule update --init --recursive
```

## Running the tests
The tests are based on the `test-nginx` library.
This library is added a git submodule under `test/resources/test-nginx/` folder, from `https://github.com/agentzh/test-nginx`.

Test files are located in `test/perl`.
The other libraries such as `Redis`, `test-nginx` are located in `test/resources/`.
Other files used when running the test are also located in `test/resources`.

To execute the test issue the following command:

 ```bash
 TEST_NGINX_AWS_CLIENT_ID="--change--me" TEST_NGINX_AWS_SECRET="--change-me--" make test
 ```

 If you want to run a single test, the following command helps:
 ```
 TEST_NGINX_AWS_CLIENT_ID="--change--me" TEST_NGINX_AWS_SECRET="--change-me--"  \
 PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl/awsv4signature.t
 ```
 This command only executes the test `awsv4signature.t`.

## Build locally
 ```
sudo LUA_LIB_DIR=/usr/local/api-gateway/lualib make install
 ```

[Back to TOC](#table-of-contents)
