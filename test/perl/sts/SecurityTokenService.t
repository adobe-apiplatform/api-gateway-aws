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

plan tests => repeat_each() * (blocks())+2;

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

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;

    # lua_package_cpath 'src/lua/?.so;;';
    init_by_lua '
        local v = require "jit.v"
        v.on("$Test::Nginx::Util::ErrLogFile")
        require "resty.core"
    ';
    lua_shared_dict shared_cache 1m;
    resolver @nameservers;

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


=== TEST 1: test response of the SecurityTokenService
--- http_config eval: $::HttpConfig
--- config

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
                          "AccessKeyId" : "TEST_NGINX_AWS_CLIENT_ID",
                          "SecretAccessKey" : "TEST_NGINX_AWS_SECRET",
                          "Token" : "TEST_NGINX_AWS_SECURITY_TOKEN",
                          "Expiration" : "$expiration"
                        }';
        }

        location = /sts-mock {
            return 200 '
{
	"AssumeRoleResponse": {
		"AssumeRoleResult": {
                "AssumedRoleUser": {
                    "AssumedRoleId": "AROA3XFRBF535PLBIFPI4:s3-access-example",
                    "Arn": "arn:aws:sts::123456789012:assumed-role/xaccounts3access/s3-access-example"
                },
                "Credentials": {
                    "SecretAccessKey": "9drTJvcXLB89EXAMPLELB8923FB892xMFI",
                    "SessionToken": "AQoXdzELDDY//////////wEaoAK1wvxJY12r2IrDFT2IvAzTCn3zHoZ7YNtpiQLF0MqZye/qwjzP2iEXAMPLEbw/m3hsj8VBTkPORGvr9jM5sgP+w9IZWZnU+LWhmg+a5fDi2oTGUYcdg9uexQ4mtCHIHfi4citgqZTgco40Yqr4lIlo4V2b2Dyauk0eYFNebHtYlFVgAUj+7Indz3LU0aTWk1WKIjHmmMCIoTkyYp/k7kUG7moeEYKSitwQIi6Gjn+nyzM+PtoA3685ixzv0R7i5rjQi0YE0lf1oeie3bDiNHncmzosRM6SFiPzSvp6h/32xQuZsjcypmwsPSDtTPYcs0+YN/8BRi2/IcrxSpnWEXAMPLEXSDFTAQAM6Dl9zR0tXoybnlrZIwMLlMi1Kcgo5OytwU=",
                    "Expiration": "2016-03-15T00:05:07Z",
                    "AccessKeyId": "ASIAJEXAMPLEXEG2JICEA"
                }
            }
     }
}
            ';
        }

        location /test {
            content_by_lua '
                local SecurityTokenService = require "api-gateway.aws.sts.SecurityTokenService"
                local sts = SecurityTokenService:new({
                    security_credentials_host = "127.0.0.1",
                    security_credentials_port = $TEST_NGINX_PORT,
                    aws_region = "us-east-1",
                    aws_debug = true,              -- print warn level messages on the nginx logs
                    aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS alive
                    aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
                })
                sts.getAWSHost = function(self)
                    return "127.0.0.1"
                end

                sts.performAction = function(self, actionName, arguments, path, http_method, useSSL, timeout, contentType, extra_headers)
                    -- force useSSL to false
                    return SecurityTokenService.performAction(self, actionName, arguments, path, http_method, false, timeout, contentType, extra_headers)
                end

                local response, code, headers, status, body = sts:assumeRole("", "", nil, nil, nil)
                ngx.say(":" .. tostring(response.AssumeRoleResponse.AssumeRoleResult.Credentials.AccessKeyId))
            ';
        }
--- request
GET /test
--- response_body_like eval
["ASIAJEXAMPLEXEG2JICEA"]
--- error_code: 200
--- no_error_log
[error]
--- more_headers
X-Test: test