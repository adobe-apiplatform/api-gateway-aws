--[[
  Copyright 2016 Adobe Systems Incorporated. All rights reserved.

  This file is licensed to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR RESPRESENTATIONS OF ANY KIND, either express or implied.  See the License for the specific language governing permissions and limitations under the License.
  ]]

--
-- STS Credentials provider
-- User: ddascal
-- Date: 19/03/16
-- Time: 21:26
--
local SecurityTokenService = require "api-gateway.aws.sts.SecurityTokenService"
local cacheCls = require "api-gateway.cache.cache"

local _M = {}


local IAM_DEFAULT_SECURITY_CREDENTIALS_HOST = "169.254.169.254" -- used by IAM
local IAM_DEFAULT_SECURITY_CREDENTIALS_PORT = "80" -- used by IAM
local IAM_DEFAULT_SECURITY_CREDENTIALS_URL = "/latest/meta-data/iam/security-credentials/" -- used by IAM

---
-- default expiration for the STS token
local DEFAULT_TOKEN_EXPIRATION = 60 * 60 * 1 -- in seconds

-- configure cache Manager for IAM crendentials
local stsCache = cacheCls:new()

local function initStsCache(shared_cache_dict)
    local localCache = require "api-gateway.cache.store.localCache":new({
        dict = shared_cache_dict,
        ttl = function (value)
            local value_o = cjson.decode(value)
            local expiryTimeUTC = value.ExpireAtTimestamp or awsDate.convertDateStringToTimestamp(value_o.ExpireAt, true)
            local expiryTimeInSeconds = expiryTimeUTC - os.time()
            return math.min(DEFAULT_TOKEN_EXPIRATION, expiryTimeInSeconds)
        end
    })

    stsCache:addStore(localCache)
end

---
-- @param o Init object
-- o.role_ARN                       -- required. The Amazon Resource Name (ARN) of the role to assume.
-- o.role_session_name              -- required. An identifier for the assumed role session.
-- o.policy                         -- optional. An IAM policy in JSON format.
-- o.security_credentials_timeout   -- optional. specifies when the token should expire. Defaults to 1 hour.
-- o.external_id                    -- optional. A unique identifier used by third parties
-- o.iam_user                       -- optional. iam_user. if not defined it'll be auto-discovered
-- o.security_credentials_host      -- optional. AWS Host to read IAM credentials from. Defaults to "169.254.169.254"
-- o.security_credentials_port      -- optional. AWS Port to read IAM credentials. Defaults to 80.
-- o.security_credentials_url       -- optional. AWS URI to read IAM credentials. Defaults to "/latest/meta-data/iam/security-credentials/"
-- o.shared_cache_dict              -- optional. For performance improvements the credentials may be stored in a share dict.
--
function _M:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    if (o ~= nil) then
        -- config options specific to STS
        self.security_credentials_timeout = o.security_credentials_timeout or DEFAULT_TOKEN_EXPIRATION
        self.role_ARN = o.role_ARN
        self.role_session_name = o.role_session_name
        self.policy = o.policy
        self.external_id = o.external_id

        -- config options specific to IAM User
        self.iam_user = o.iam_user
        self.iam_security_credentials_host = o.iam_security_credentials_host or IAM_DEFAULT_SECURITY_CREDENTIALS_HOST
        self.iam_security_credentials_port = o.iam_security_credentials_port or IAM_DEFAULT_SECURITY_CREDENTIALS_PORT
        self.iam_security_credentials_url = o.iam_security_credentials_url or IAM_DEFAULT_SECURITY_CREDENTIALS_URL

        -- config options for static AWS Credetials
        self.aws_region = o.aws_region or "us-east-1"
        self.aws_secret_key = o.aws_secret_key
        self.aws_access_key = o.aws_access_key

        -- shared dict used to cache STS and IAM credentials
        self.shared_cache_dict = o.shared_cache_dict
    end
    return o
end

function _M:getCredentialsFromSTS()
    local sts = SecurityTokenService:new({
        security_credentials_host = self.security_credentials_host,
        security_credentials_port = self.security_credentials_port,
        aws_region = "us-east-1",
        aws_conn_keepalive = 60000, -- how long to keep the sockets used for AWS alive
        aws_conn_pool = 10 -- the connection pool size for sockets used to connect to AWS
    })
    local response, code, headers, status, body = sts:assumeRole(self.role_ARN,
        self.role_session_name,
        self.policy,
        self.security_credentials_timeout,
        self.external_id)

end

function _M:getSecurityCredentials()
    --1. try to read it from the local cache

    --2. get credentials from SecurityTokenService
end

return _M

