api-gateway-aws
===============

Lua module for AWS APIs . The missing AWS SDK from Nginx/Openresty

Table of Contents
=================

* [Status](#status)
* [Description](#description)
* [Synopsis](#synopsis)
* [Developer Guide](#developer-guide)


Status
======

This library is considered production ready.

Description
===========

This library requires an nginx build with OpenSSL,
the [ngx_lua module](http://wiki.nginx.org/HttpLuaModule), [LuaJIT 2.0](http://luajit.org/luajit.html) and
[api-gateway-hmac](https://git.corp.adobe.com/adobe-apis/api-gateway-hmac) module.


Synopsis
========
```lua
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
