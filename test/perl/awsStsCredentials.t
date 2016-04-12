# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use strict;
use warnings;
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

# try to read the nameservers used by the system resolver:
my @nameservers;
if (open my $in, "/etc/resolv.conf") {
    while (<$in>) {
        if (/^\s*nameserver\s+(\d+(?:\.\d+){3})(?:\s+|$)/) {
            push @nameservers, $1;
            if (@nameservers > 10) {
                last;
            }
        }
    }
    close $in;
}

if (!@nameservers) {
    # default to Google's open DNS servers
    push @nameservers, "8.8.8.8", "8.8.4.4";
}


warn "Using nameservers: \n@nameservers\n";

our $HttpConfig = <<_EOC_;
    # lua_package_path "$pwd/scripts/?.lua;;";
    lua_package_path 'src/lua/?.lua;/usr/local/lib/lua/?.lua;;';

    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    lua_shared_dict shared_cache 1m;
    resolver @nameservers;

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;

    # define a virtual server for proxying STS requests to the /sts-mock location defined by each test
    server {
        listen 80;
        location / {
            proxy_pass http://127.0.0.1:\$TEST_NGINX_PORT/sts-mock;
        }
    }
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test an API call with STS Credentials obtained using IAM Credentials
--- http_config eval: $::HttpConfig
--- config
        error_log ../awsStsCredentials_test1_error.log debug;

        # mock IAM
        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        # mock IAM
        location = /latest/meta-data/iam/security-credentials/test-iam-user {
            set_by_lua $expiration '
                            local offset = os.time() - os.time(os.date("!*t"))
                            return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 10)
                        ';
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "iam_access_key_id",
                          "SecretAccessKey" : "iam_secret",
                          "Token" : "iam_security_token",
                          "Expiration" : "$expiration"
                        }';
        }

        # mock STS
        location = /sts-mock {
            set_by_lua $expiration '
                            local offset = os.time() - os.time(os.date("!*t"))
                            return os.time() + math.abs(offset) + 10
                            ';
            return 200 '
{
	"AssumeRoleResponse": {
		"AssumeRoleResult": {
                "AssumedRoleUser": {
                    "AssumedRoleId": "AROA3XFRBF535PLBIFPI4:s3-access-example",
                    "Arn": "arn:aws:sts::123456789012:assumed-role/xaccounts3access/s3-access-example"
                },
                "Credentials": {
                    "SecretAccessKey": "secret-access-key",
                    "SessionToken": "security-token",
                    "Expiration": $expiration,
                    "AccessKeyId": "access-key-id"
                }
            }
     }
}
            ';
        }


        location /test {
            set $aws_region us-east-1;
            content_by_lua '
                local cjson = require "cjson"
                local KinesisService = require "api-gateway.aws.kinesis.KinesisService"
                local SecurityTokenService = require "api-gateway.aws.sts.SecurityTokenService"
                -- mock the AWS endpoint
                SecurityTokenService.getAWSHost = function(self)
                    return "127.0.0.1"
                end
                local _performAction = SecurityTokenService.performAction
                SecurityTokenService.performAction = function(self, actionName, arguments, path, http_method, useSSL, timeout, contentType, extra_headers)
                    -- force useSSL to false
                    return _performAction(self, actionName, arguments, path, http_method, false, timeout, contentType, extra_headers)
                end

                local service = KinesisService:new({
                    aws_region = ngx.var.aws_region,
                    aws_credentials = {
                        provider = "api-gateway.aws.AWSSTSCredentials",
                        role_ARN = "arn:aws:iam::111111:role/assumed_role_kinesis",
                        role_session_name = "kinesis-session",
                        shared_cache_dict = "shared_cache",

                        -- the remaining options are useful only for this test
                        security_credentials_host = "127.0.0.1",
                        security_credentials_port = $TEST_NGINX_PORT,
                        iam_security_credentials_host = "127.0.0.1",
                        iam_security_credentials_port = $TEST_NGINX_PORT,
                        aws_debug = true
                    },
                    aws_debug = true,
                    aws_conn_keepalive = 60000,
                    aws_conn_pool = 100
                })

                local data = "testas"
                local partitionKey = "partition"
                local json_response, code, headers, status, body = service:putRecord("test-stream", data, partitionKey)

                local kCreds = service:getCredentials()
                assert(kCreds.aws_access_key == "access-key-id", "aws_access_key expected to be [access-key-id] but found:" .. tostring(kCreds.aws_access_key))
                assert(kCreds.aws_secret_key == "secret-access-key", "aws_secret_key expected to be [secret-access-key] but found:" .. tostring(kCreds.aws_secret_key))
                assert(kCreds.token == "security-token", "token expected to be [security-token] but found:" .. tostring(kCreds.token))

                -- check that both the IAM and STS credentials are stored in cache
                local d = ngx.shared.shared_cache
                local iam = d:get("iam_credentials")
                iam = cjson.decode(iam)
                ngx.print("iam_access_key=" .. tostring(iam.AccessKeyId) .. ";")

                local sts = d:get("sts_arn:aws:iam::111111:role/assumed_role_kinesis_kinesis-session")
                sts = cjson.decode(sts)
                ngx.print("sts_access_key=" .. tostring(sts.AccessKeyId) .. ";")

                ngx.sleep(5)
                -- make another request - this time using cached credentials
                local data = "testas"
                local partitionKey = "partition"
                local json_response, code, headers, status, body = service:putRecord("test-stream", data, partitionKey)

                ngx.sleep(6) -- allow time for the cached credentials to expire

                iam = d:get("iam_credentials")
                if (iam == nil) then
                    ngx.print("iam_expired_correctly;")
                else
                    ngx.print("iam_did_not_expire_correctly;")
                end

                local sts = d:get("sts_arn:aws:iam::111111:role/assumed_role_kinesis_kinesis-session")
                if (sts == nil) then
                    ngx.print("sts_expired_correctly;")
                else
                    ngx.print("sts_did_not_expire_correctly;")
                end
            ';
        }
--- timeout: 70
--- request
GET /test
--- response_body_like eval
["iam_access_key=iam_access_key_id;sts_access_key=access-key-id;iam_expired_correctly;sts_expired_correctly;"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test