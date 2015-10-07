#  Running this unit test:
# TEST_NGINX_AWS_SECRET=${AWS_SECRET_ACCESS_KEY} TEST_NGINX_AWS_CLIENT_ID=${AWS_ACCESS_KEY_ID} TEST_NGINX_AWS_SECURITY_TOKEN=${AWS_SECURITY_TOKEN} PATH=/usr/local/sbin:$PATH TEST_NGINX_SERVROOT=`pwd`/target/servroot TEST_NGINX_PORT=1989 prove -I ./test/resources/test-nginx/lib -r ./test/perl/lambda.t

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
    lua_package_path 'src/lua/?.lua;;';
    lua_package_cpath 'src/lua/?.so;;';
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    resolver @nameservers;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__


=== TEST 1: test that we can call an existing lambda function
--- http_config eval: $::HttpConfig
--- config
        error_log ../lambda_test1_error.log debug;

        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        location = /latest/meta-data/iam/security-credentials/test-iam-user {
            set_by_lua $expiration '
                            local offset = os.time() - os.time(os.date("!*t"))
                            return os.date("%Y-%m-%dT%H:%M:%SZ", os.time() + math.abs(offset) + 20)
                        ';
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "$TEST_NGINX_AWS_CLIENT_ID",
                          "SecretAccessKey" : "$TEST_NGINX_AWS_SECRET",
                          "Token" : "$TEST_NGINX_AWS_SECURITY_TOKEN",
                          "Expiration" : "$expiration"
                        }';
        }

        location /test {
            set $aws_access_key $TEST_NGINX_AWS_CLIENT_ID;
            set $aws_secret_key $TEST_NGINX_AWS_SECRET;
            set $aws_region us-east-1;
            set $aws_service kms;

            content_by_lua '
                ngx.say("NOTE: THIS TEST EXPECTS THE hello-world-test FUNCTION TO EXIST, ACCEPTING {key1:k1,key2:k2} AS PAYLOAD")
                local LambdaService = require "api-gateway.aws.lambda.LambdaService"
                local cjson = require "cjson"

                local service = LambdaService:new({
                    security_credentials_host = "127.0.0.1",
                    security_credentials_port = $TEST_NGINX_PORT,
                    aws_region = ngx.var.aws_region,
                    aws_debug = true,              -- print warn level messages on the nginx logs
                    aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS alive
                    aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
                })

                -- TODO: find a function that starts with hello-world
                local functionName = "hello-world-test"
                local result, code, headers, status, body = service:listFunctions()

                if ( result.Functions == nil ) then
                   ngx.say("EXECUTION RESULT: no function named <hello-world> found. Please define one from the hello-world blueprint when executing this test")
                   ngx.log(ngx.DEBUG, "No functions defined. Response body=", tostring(body))
                end

                local functs = result.Functions
                for key,value in pairs(functs) do
                    functionName = tostring(value.FunctionName)
                    if ( string.find(functionName, "hello") ~= nil ) then
                        break
                    end
                end

                ngx.say("INVOKING FUNCTION:" .. tostring(functionName))

                -- invoke the hello-world function
                local payload = {
                    key1 = "value-1",
                    key2 = "value-2"
                }
                local invokeResult, code, headers, status, body  = service:invoke(functionName, payload)
                ngx.say("EXECUTION RESULT:" .. tostring(body))

                -- TODO: delete the hello-world function

            ';
        }
--- timeout: 70
--- request
GET /test
--- response_body_like eval
[".*INVOKING FUNCTION\\:.*hello.*EXECUTION RESULT\\:.*"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test