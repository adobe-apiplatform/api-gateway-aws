# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 4)-1;

my $pwd = cwd();
my $aws_client_id = "replace-me";
my $aws_secret = "replace-me";

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path 'src/lua/?.lua;;';
    lua_package_cpath 'src/lua/?.so;;';
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test GenerateDataKey with Generic AwsService
--- http_config eval: $::HttpConfig
--- config
        location /test-signature {
            # stg:  :
            set $aws_access_key AKIAILORHBFMVEP2LLDA;
            set $aws_secret_key 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;
            set $aws_region us-east-1;
            set $aws_service kms;

            #resolver 8.8.8.8;
            resolver 10.8.4.247;

            content_by_lua '

                local host = ngx.var.aws_service .."." .. ngx.var.aws_region .. ".amazonaws.com"

                local o = {
                    KeyId   =  "alias/GW-CACHE-MK",
                    KeySpec = "AES_256",
                    --NumberOfBytes = 128
                }

                local path = "/"

                local AwsService = require "api-gateway.aws.AwsService"

                local service = AwsService:new({
                    aws_service = ngx.var.aws_service,
                    aws_region = ngx.var.aws_region,
                    aws_secret_key = ngx.var.aws_secret_key,
                    aws_access_key = ngx.var.aws_access_key
                })
                local ok, code, headers, status, body  = service:performAction("ListAliases", {}, path, ngx.var.request_method, true, 120000 )
                ok, code, headers, status, body  = service:performAction("GenerateDataKey", o, path, ngx.var.request_method, true, 120000 )

                ngx.say(status)
                ngx.say(body)

                local cjson = require"cjson"
                local cipher = cjson.decode(body)
                local blob = cipher["GenerateDataKeyResponse"]["GenerateDataKeyResult"]["CiphertextBlob"]
                local blob = "CiBqGtLctbehq6wBcoXkGroAGoExTJTHN75gf8bc15CNcBKnAQEBAwB4ahrS3LW3oausAXKF5Bq6ABqBMUyUxze+YH/G3NeQjXAAAAB+MHwGCSqGSIb3DQEHBqBvMG0CAQAwaAYJKoZIhvcNAQcBMB4GCWCGSAFlAwQBLjARBAxCWQz4VAlKxYYtnQACARCAO/519dhWwSzweyXMjRWz/gElI2DM8lJu6WVPhF3tB/MwEfGB87stexHaHhxqQsx8uhtmp8PqXZ+Iu6LX"
                ngx.say("BLOB:" .. blob)
                ok, code, headers, status, body  = service:performAction("Decrypt", {CiphertextBlob=blob}, path, "POST", true, 120000 )

                ngx.say(status)
                ngx.say(body)
            ';
        }
--- more_headers
X-Test: test
--- request
GET /test-signature?Action=GenerateDataKey
--- response_body_like eval
[".*PublishResult.*ResponseMetadata.*"]
--- error_code: 200
--- no_error_log
[error]



