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
the [ngx_lua module](http://wiki.nginx.org/HttpLuaModule), [LuaJIT 2.0](http://luajit.org/luajit.html) and
[api-gateway-hmac](https://git.corp.adobe.com/adobe-apis/api-gateway-hmac) module.

### AWS V4 Signature
This library supports the latest AWS V4 signature which means you can use any of the latest AWS APIs without any problem.

### AwsService wrapper
`AwsService` is a generic Lua class to interact with any AWS API. All the actual implementations extend form this class.
 It's very straight forward to configure it:

 ```lua
 local service = AwsService:new({
         aws_service = "sns",
         aws_region = "us-east-1",
         aws_secret_key = "--replace--me",
         aws_access_key = "--replace--me",
         aws_debug = true,              -- print warn level messages on the nginx logs. useful for debugging
         aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS open
         aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
     })
 ```


Synopsis
========

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

## Build locally
 ```
sudo LUA_LIB_DIR=/usr/local/api-gateway/lualib make install
 ```

To execute the test issue the following command:
 ```
 make test
 ```

 If you want to run a single test, the following command helps:
 ```
 PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl/awsv4signature.t
 ```
 This command only executes the test `awsv4signature.t`.

[Back to TOC](#table-of-contents)
