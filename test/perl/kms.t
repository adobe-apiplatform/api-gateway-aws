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


=== TEST 1: test GenerateDataKey with Generic AwsService
--- http_config eval: $::HttpConfig
--- config
        location /test-signature {
            # stg:  :
            set $aws_access_key AKIAILOR777HBFMVEP2LLDA;
            set $aws_secret_key H6i7wSYrtQPWL/523+L8g5lZmWWugMoAz4JnJJfLLb;
            set $aws_region us-east-1;
            set $aws_service kms;

            content_by_lua '
                local KmsService = require "api-gateway.aws.kms.KmsService"

                local service = KmsService:new({
                    aws_region = ngx.var.aws_region,
                    aws_secret_key = ngx.var.aws_secret_key,
                    aws_access_key = ngx.var.aws_access_key,
                    aws_debug = true,              -- print warn level messages on the nginx logs
                    aws_conn_keepalive = 60000,    -- how long to keep the sockets used for AWS alive
                    aws_conn_pool = 100            -- the connection pool size for sockets used to connect to AWS
                })

                -- search for aliases
                local list  = service:listAliases()

                -- pick the first alias
                local KeyId = list.Aliases[1].AliasName
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
GET /test-signature?Action=GenerateDataKey
--- response_body_like eval
[".*KEY\\sALIAS\\:.*BLOB\\:.*"]
--- error_code: 200
--- no_error_log
[error]



