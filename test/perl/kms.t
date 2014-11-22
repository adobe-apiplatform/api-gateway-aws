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


=== TEST 1: test GenerateDataKey
--- http_config eval: $::HttpConfig
--- config
        location /test-signature {
            # stg:  :
            set $aws_access_key AKIAIBF2BKMFXSCLCR4Q;
            set $aws_secret_key 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;
            set $aws_region us-east-1;
            set $aws_service kms;

            resolver 10.8.4.247;

            content_by_lua '

                local host = ngx.var.aws_service .."." .. ngx.var.aws_region .. ".amazonaws.com"

                local AWSV4S = require "api-gateway.aws.AwsV4Signature"
                local awsAuth =  AWSV4S:new({
                                   aws_region  = ngx.var.aws_region,
                                   aws_service = ngx.var.aws_service,
                                   aws_secret_key = ngx.var.aws_secret_key,
                                   aws_access_key = ngx.var.aws_access_key
                              })

                local requestbody = "Action=GenerateDataKey"

                local keyId = "arn:aws:kms:us-east-1:889681731264:key/8120770f-33a6-4613-b740-0e39ae15cc3f"

                requestbody = requestbody .. "&KeyId=" .. keyId  .. "&KeySpec=AES_256"

                local authorization = awsAuth:getAuthorizationHeader( ngx.var.request_method,
                                                                    "/",
                                                                    {}, -- ngx.req.get_uri_args()
                                                                    requestbody)

                local http = require "api-gateway.aws.httpclient.http"
                local hc = http:new()


                local ok, code, headers, status, body  = hc:request {
                        scheme = "https",
                        port = 443,
                        url = "/", -- .. "?" .. ngx.var.args,
                        host = host,
                        body = requestbody,
                        method = ngx.var.request_method,
                        headers = {
                                    Authorization = authorization,
                                    ["X-Amz-Date"] = awsAuth.aws_date,
                                    ["Content-Type"] = "application/x-www-form-urlencoded"
                                }
                }
                ngx.say(ok)
                ngx.say(code)
                ngx.say(status)
                ngx.say(body)
            ';
        }
--- more_headers
X-Test: test
--- request
POST /test-signature?Action=GenerateDataKey
--- response_body_like eval
[".*PublishResult.*ResponseMetadata.*"]
--- error_code: 200
--- no_error_log
[error]
