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

    client_body_temp_path /tmp/;
    proxy_temp_path /tmp/;
    fastcgi_temp_path /tmp/;
_EOC_

#no_diff();
no_long_string();
run_tests();

__DATA__

#
#=== TEST 1: test GenerateDataKey with given Credentials
#--- http_config eval: $::HttpConfig
#--- config
#        error_log ../kms_test1_error.log debug;
#
#        location /test-signature {
#            set $aws_access_key $TEST_NGINX_AWS_CLIENT_ID;
#            set $aws_secret_key $TEST_NGINX_AWS_SECRET;
#            set $aws_region us-east-1;
#            set $aws_service kms;
#
#            content_by_lua '
#                local KmsService = require "api-gateway.aws.kms.KmsService"
#
#                local service = KmsService:new({
#                    aws_region = ngx.var.aws_region,
#                    aws_secret_key = ngx.var.aws_secret_key,
#                    aws_access_key = ngx.var.aws_access_key,
#                    aws_debug = true,              -- print warn level messages on the nginx logs
#                    aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS alive
#                    aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
#                })
#
#                -- search for aliases
#                local list  = service:listAliases()
#                assert(list ~= nil, "ListAliases should return at least 1 key")
#
#                -- pick the first alias
#                local KeyId = list.Aliases[1].AliasName
#                ngx.say("KEY-ALIAS:" .. tostring(KeyId))
#
#                -- generate a data key
#                local cipher = service:generateDataKey(KeyId, "AES_256")
#                local blob = cipher.CiphertextBlob
#                local blob_text = cipher.Plaintext
#                ngx.say("BLOB:" .. blob)
#
#                local decoded = service:decrypt(blob)
#                if decoded.Plaintext ~= blob_text then
#                    error( "KMS Error: [" .. blob_text .. "] does not match [" .. decoded.Plaintext .. "]" )
#                end
#
#                -- encrypt a text
#                local encryptResult = service:encrypt(KeyId, blob_text)
#                local decryptResult = service:decrypt(encryptResult.CiphertextBlob)
#
#                if decryptResult.Plaintext ~= blob_text then
#                    error( "KMS Encrypt/Decrypt Error: [" .. blob_text .. "] does not match [" .. decryptResult.Plaintext .. "]" )
#                end
#            ';
#        }
#
#--- request
#GET /test-signature?Action=GenerateDataKey
#--- response_body_like eval
#[".*KEY-ALIAS\\:.*BLOB\\:.*"]
#--- error_code: 200
#--- no_error_log
#[error]
#--- more_headers
#X-Test: test

# the next test is commented b/c you need IAM Credentials
# to run it, connect to an EC2 node, and run curl http://169.254.169.254//latest/meta-data/iam/security-credentials/<iam-user>
# then use AccessKeyId, SecretAccessKey and Token into the TEST command, like the following cmd :
#
#$ TEST_NGINX_AWS_CLIENT_ID="<AccessKeyId>"
#       TEST_NGINX_AWS_SECRET="<SecretAccessKey>" \
#       TEST_NGINX_AWS_TOKEN="<Token>" \
#       PATH=/usr/local/sbin:$PATH \
#       TEST_NGINX_SERVROOT=`pwd`/target/servroot \
#       TEST_NGINX_PORT=1989 \
#       prove -I ./test/resources/test-nginx/lib -r ./test/perl/kms.t
#
#
=== TEST 2: test with IAM User. DO NOT PROVIDE ANY CREDENTIALS AND LET KMS FIGURE IT OUT AUTOMATICALLY USING IAM ROLES
--- http_config eval: $::HttpConfig
--- config
        error_log ../kms_test2_error.log debug;

        location = /latest/meta-data/iam/security-credentials/ {
            return 200 'test-iam-user';
        }

        location = /latest/meta-data/iam/security-credentials/test-iam-user {
            return 200 '{
                          "Code" : "Success",
                          "LastUpdated" : "2014-11-03T01:56:20Z",
                          "Type" : "AWS-HMAC",
                          "AccessKeyId" : "$TEST_NGINX_AWS_CLIENT_ID",
                          "SecretAccessKey" : "$TEST_NGINX_AWS_SECRET",
                          "Token" : "$TEST_NGINX_AWS_SECURITY_TOKEN",
                          "Expiration" : "2014-11-03T08:07:52Z"
                        }';
        }
        location /test-with-iam {
            #set $aws_access_key $TEST_NGINX_AWS_CLIENT_ID;
            #set $aws_secret_key $TEST_NGINX_AWS_SECRET;
            set $aws_region us-east-1;
            set $aws_service kms;

            content_by_lua '
                local KmsService = require "api-gateway.aws.kms.KmsService"

                local service = KmsService:new({
                    security_credentials_host = "127.0.0.1",
                    security_credentials_port = $TEST_NGINX_PORT,
                    aws_region = ngx.var.aws_region,
                    aws_debug = true,              -- print warn level messages on the nginx logs
                    aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS alive
                    aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
                })

                -- search for aliases
                local list  = service:listAliases()
                assert(list ~= nil, "ListAliases should return at least 1 key")

                -- pick the first alias
                local KeyId = list.Aliases[1].AliasName
                ngx.say("KEY-ALIAS:" .. tostring(KeyId))

                local KeyId = "alias/GW-CACHE-MK"
                ngx.say("KEY ALIAS:" .. tostring(KeyId))

                -- generate a data key
                local cipher = service:generateDataKey(KeyId, "AES_256")
                local blob = cipher.CiphertextBlob
                local blob_text = cipher.Plaintext
                ngx.say("BLOB:" .. blob)

                local decoded = service:decrypt(blob)
                if decoded.Plaintext ~= blob_text then
                    error( "KMS Error: [" .. blob_text .. "] does not match [" .. decoded.Plaintext .. "]" )
                end

                -- encrypt a text
                local encryptResult = service:encrypt(KeyId, blob_text)
                local decryptResult = service:decrypt(encryptResult.CiphertextBlob)

                if decryptResult.Plaintext ~= blob_text then
                    error( "KMS Encrypt/Decrypt Error: [" .. blob_text .. "] does not match [" .. decryptResult.Plaintext .. "]" )
                end
            ';
        }
--- more_headers
X-Test: test
--- request
GET /test-with-iam
--- response_body_like eval
[".*KEY\\sALIAS\\:.*BLOB\\:.*"]
--- error_code: 200
--- no_error_log
[error]



